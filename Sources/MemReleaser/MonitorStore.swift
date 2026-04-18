import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@MainActor
@Observable
final class MonitorStore {
    var snapshot = MemorySnapshot.placeholder
    var apps: [AppMemoryUsage] = []
    var suggestions: [AppSuggestion] = []
    var isRefreshing = false
    var lastError: String?
    var notificationsEnabled = false
    var autoReleaseOnCritical = false
    var statusMessage = "初始化中…"
    var ignoredKeys: Set<String> = []
    var launchAtLoginState = LaunchAtLoginState.unavailable
    var history: [MemoryTrendSample] = []
    var growthInsights: [AppGrowthInsight] = []
    var selfResidentBytes: UInt64 = 0
    var lastNotificationSentAt: Date?

    private var recentActivity: [String: Date] = [:]
    private var refreshTask: Task<Void, Never>?
    private var loopTask: Task<Void, Never>?
    private var lastNotifiedLevel: MemoryPressureLevel?
    private let autoReleaseMinimumIdleMinutes: TimeInterval = 30
    private var activationObserver: NSObjectProtocol?
    private var appMemoryHistory: [String: [AppMemoryPoint]] = [:]
    private let maxHistorySamples = 360
    private let growthWindow: TimeInterval = 15 * 60

    init() {
        notificationsEnabled = UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
        autoReleaseOnCritical = UserDefaults.standard.bool(forKey: Keys.autoReleaseOnCritical)
        ignoredKeys = Set(UserDefaults.standard.stringArray(forKey: Keys.ignoredAppIdentifiers) ?? [])
        refreshLaunchAtLoginState()
        seedCurrentFrontmostApp()
        observeAppActivations()
        loopTask = Task {
            await refreshNow()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await refreshNow()
            }
        }
    }

    func refreshNow() async {
        isRefreshing = true
        lastError = nil

        let recentActivitySnapshot = recentActivity
        let frontmostKey = currentFrontmostKey()
        let runningApps = currentRunningApps()
        let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)
        let notificationsEnabled = notificationsEnabled
        let autoReleaseOnCritical = autoReleaseOnCritical

        refreshTask?.cancel()
        refreshTask = Task {
            do {
                let snapshot = try SystemMemoryReader.read()
                let apps = ProcessScanner.scan(
                    runningApps: runningApps,
                    recentActivity: recentActivitySnapshot,
                    frontmostKey: frontmostKey,
                    currentProcessID: currentPID
                )
                let suggestions = SuggestionEngine.suggestions(
                    for: apps,
                    snapshot: snapshot,
                    ignoredKeys: ignoredKeys
                )
                let history = updatedHistory(with: snapshot)
                let growthInsights = updatedGrowthInsights(with: apps)
                let selfResidentBytes = ProcessScanner.residentBytesForProcess(currentPID) ?? 0

                await MainActor.run {
                    self.snapshot = snapshot
                    self.apps = apps
                    self.suggestions = suggestions
                    self.history = history
                    self.growthInsights = growthInsights
                    self.selfResidentBytes = selfResidentBytes
                    self.statusMessage = snapshot.level.subtitle
                    self.isRefreshing = false
                }

                if notificationsEnabled {
                    await notifyIfNeeded(for: snapshot, suggestions: suggestions)
                }

                if autoReleaseOnCritical && snapshot.level == .critical {
                    await MainActor.run {
                        self.releaseSuggestedApps(limit: 2, idleMinutesAtLeast: self.autoReleaseMinimumIdleMinutes)
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.statusMessage = "無法讀取系統記憶體資料"
                    self.isRefreshing = false
                }
            }
        }

        await refreshTask?.value
    }

    func toggleNotifications(_ enabled: Bool) {
        notificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.notificationsEnabled)

        guard enabled else { return }
        Task {
            let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            if granted != true {
                await MainActor.run {
                    self.notificationsEnabled = false
                    UserDefaults.standard.set(false, forKey: Keys.notificationsEnabled)
                    self.statusMessage = "通知權限未授權，改為只在 app 內提醒。"
                }
            }
        }
    }

    func toggleAutoRelease(_ enabled: Bool) {
        autoReleaseOnCritical = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.autoReleaseOnCritical)
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginState = LaunchAtLoginController.currentState()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            launchAtLoginState = try LaunchAtLoginController.setEnabled(enabled)
            statusMessage = launchAtLoginState.title
        } catch {
            launchAtLoginState = LaunchAtLoginController.currentState()
            lastError = "登入啟動設定失敗：\(error.localizedDescription)"
        }
    }

    func openLoginItemsSettings() {
        LaunchAtLoginController.openSystemSettings()
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "MemReleaser-diagnostics-\(exportFilenameTimestamp()).json"

        guard panel.runModal() == .OK, let url = panel.url else {
            statusMessage = "已取消匯出診斷。"
            return
        }

        let report = DiagnosticReport(
            exportedAt: .now,
            snapshot: .init(
                sampledAt: snapshot.sampledAt,
                level: snapshot.level.rawValue,
                physicalMemoryBytes: snapshot.physicalMemory,
                usedBytes: snapshot.usedBytes,
                availableBytes: snapshot.availableBytes,
                compressedBytes: snapshot.compressedBytes,
                swapUsedBytes: snapshot.swapUsedBytes,
                selfResidentBytes: selfResidentBytes
            ),
            launchAtLoginTitle: launchAtLoginState.title,
            ignoredAppIdentifiers: Array(ignoredKeys).sorted(),
            suggestions: suggestions.map {
                .init(
                    displayName: $0.app.displayName,
                    stableIdentifier: $0.app.stableIdentifier,
                    residentBytes: $0.app.residentBytes,
                    workloadKind: $0.app.workloadKind.rawValue,
                    recommendation: $0.recommendation
                )
            },
            growthApps: growthInsights.map {
                .init(
                    displayName: $0.displayName,
                    stableIdentifier: $0.stableIdentifier,
                    currentBytes: $0.currentBytes,
                    deltaBytes: $0.deltaBytes,
                    windowMinutes: $0.windowMinutes
                )
            },
            trend: history.map {
                .init(
                    timestamp: $0.timestamp,
                    availableBytes: $0.availableBytes,
                    swapUsedBytes: $0.swapUsedBytes,
                    compressedBytes: $0.compressedBytes,
                    level: $0.level.rawValue
                )
            }
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            try data.write(to: url, options: .atomic)
            statusMessage = "已匯出診斷到 \(url.lastPathComponent)"
        } catch {
            lastError = "匯出診斷失敗：\(error.localizedDescription)"
        }
    }

    func isIgnored(_ app: AppMemoryUsage) -> Bool {
        ignoredKeys.contains(app.stableIdentifier)
    }

    func toggleIgnore(_ app: AppMemoryUsage) {
        if ignoredKeys.contains(app.stableIdentifier) {
            ignoredKeys.remove(app.stableIdentifier)
            statusMessage = "已取消忽略 \(app.displayName)"
        } else {
            ignoredKeys.insert(app.stableIdentifier)
            statusMessage = "之後不再把 \(app.displayName) 排進建議清單"
        }

        UserDefaults.standard.set(Array(ignoredKeys).sorted(), forKey: Keys.ignoredAppIdentifiers)
        suggestions = SuggestionEngine.suggestions(for: apps, snapshot: snapshot, ignoredKeys: ignoredKeys)
    }

    var ignoredApps: [AppMemoryUsage] {
        apps.filter { ignoredKeys.contains($0.key) }
            .sorted { $0.residentBytes > $1.residentBytes }
    }

    func terminate(_ suggestion: AppSuggestion) {
        guard
            let bundlePath = suggestion.app.bundlePath,
            let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == bundlePath })
        else {
            statusMessage = "找不到可結束的 app：\(suggestion.app.displayName)"
            return
        }

        let terminated = runningApp.terminate()
        statusMessage = terminated
            ? "已請 \(suggestion.app.displayName) 正常結束，等下一輪採樣確認釋放量。"
            : "\(suggestion.app.displayName) 拒絕結束，可能有未存檔內容。"

        Task {
            try? await Task.sleep(for: .seconds(2))
            await refreshNow()
        }
    }

    func releaseSuggestedApps(limit: Int, idleMinutesAtLeast: TimeInterval) {
        let releasable = suggestions.filter { suggestion in
            guard suggestion.app.canTerminate, !suggestion.app.isFrontmost else { return false }
            guard let lastActiveAt = suggestion.app.lastActiveAt else { return suggestion.app.isHidden }
            return Date().timeIntervalSince(lastActiveAt) / 60 >= idleMinutesAtLeast
        }

        for suggestion in releasable.prefix(limit) {
            terminate(suggestion)
        }
    }

    private func observeAppActivations() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let runningApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else {
                return
            }

            let key = runningApp.bundleURL?.path ?? runningApp.executableURL?.path ?? "pid:\(runningApp.processIdentifier)"
            Task { @MainActor [weak self] in
                self?.recentActivity[key] = .now
            }
        }
    }

    private func seedCurrentFrontmostApp() {
        if let key = currentFrontmostKey() {
            recentActivity[key] = .now
        }
    }

    private func currentFrontmostKey() -> String? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        return frontmost?.bundleURL?.path ?? frontmost?.executableURL?.path
    }

    private func currentRunningApps() -> [RunningAppDescriptor] {
        NSWorkspace.shared.runningApplications.map { app in
            RunningAppDescriptor(
                processIdentifier: app.processIdentifier,
                bundlePath: app.bundleURL?.path,
                executablePath: app.executableURL?.path,
                bundleIdentifier: app.bundleIdentifier,
                localizedName: app.localizedName,
                isHidden: app.isHidden,
                isRegularApp: app.activationPolicy == .regular
            )
        }
    }

    private func notifyIfNeeded(for snapshot: MemorySnapshot, suggestions: [AppSuggestion]) async {
        let now = Date()
        if snapshot.level == .healthy {
            lastNotifiedLevel = .healthy
            return
        }

        guard NotificationPolicy.shouldNotify(
            previousLevel: lastNotifiedLevel,
            lastSentAt: lastNotificationSentAt,
            newLevel: snapshot.level,
            now: now
        ) else {
            return
        }
        lastNotifiedLevel = snapshot.level
        lastNotificationSentAt = now

        let content = UNMutableNotificationContent()
        content.title = snapshot.level == .critical ? "MemReleaser：記憶體接近卡死" : "MemReleaser：記憶體壓力上升"
        content.body = makeNotificationBody(snapshot: snapshot, suggestions: suggestions)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "MemReleaser.\(snapshot.level.rawValue)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    private func makeNotificationBody(snapshot: MemorySnapshot, suggestions: [AppSuggestion]) -> String {
        let topNames = suggestions.prefix(3).map(\.app.displayName).joined(separator: "、")
        let swap = Formatters.shortBytes(snapshot.swapUsedBytes)
        if topNames.isEmpty {
            return "Swap 已達 \(swap)，請手動收掉高佔用 app。"
        }
        return "Swap \(swap)。優先考慮：\(topNames)。"
    }

    private func updatedHistory(with snapshot: MemorySnapshot) -> [MemoryTrendSample] {
        var next = history
        next.append(
            MemoryTrendSample(
                timestamp: snapshot.sampledAt,
                availableBytes: snapshot.availableBytes,
                swapUsedBytes: snapshot.swapUsedBytes,
                compressedBytes: snapshot.compressedBytes,
                level: snapshot.level
            )
        )

        if next.count > maxHistorySamples {
            next.removeFirst(next.count - maxHistorySamples)
        }
        return next
    }

    private func updatedGrowthInsights(with apps: [AppMemoryUsage]) -> [AppGrowthInsight] {
        let now = Date()
        let cutoff = now.addingTimeInterval(-growthWindow)
        var nextHistory: [String: [AppMemoryPoint]] = [:]

        for app in apps {
            var points = appMemoryHistory[app.stableIdentifier] ?? []
            points.append(AppMemoryPoint(timestamp: now, residentBytes: app.residentBytes))
            points = points.filter { $0.timestamp >= cutoff }
            nextHistory[app.stableIdentifier] = points
        }

        appMemoryHistory = nextHistory

        return apps.compactMap { app in
            guard let points = nextHistory[app.stableIdentifier], let first = points.first else {
                return nil
            }

            let delta = Int64(app.residentBytes) - Int64(first.residentBytes)
            let windowMinutes = max(1, Int(now.timeIntervalSince(first.timestamp) / 60))
            guard windowMinutes >= 5 else { return nil }
            guard delta >= 512 * 1_024 * 1_024 else { return nil }
            guard app.residentBytes >= 1_024 * 1_024 * 1_024 else { return nil }

            return AppGrowthInsight(
                stableIdentifier: app.stableIdentifier,
                displayName: app.displayName,
                workloadKind: app.workloadKind,
                currentBytes: app.residentBytes,
                deltaBytes: delta,
                windowMinutes: windowMinutes
            )
        }
        .sorted { lhs, rhs in
            lhs.deltaBytes > rhs.deltaBytes
        }
        .prefix(5)
        .map { $0 }
    }

    private func exportFilenameTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }

    private enum Keys {
        static let notificationsEnabled = "notificationsEnabled"
        static let autoReleaseOnCritical = "autoReleaseOnCritical"
        static let ignoredAppIdentifiers = "ignoredAppIdentifiers"
    }
}
