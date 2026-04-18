import Foundation
import Testing
@testable import MemReleaser

@Test
func groupKeyAggregatesAppHelpersIntoOneApp() {
    let path = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
    #expect(ProcessScanner.groupKey(for: path) == "/Applications/Google Chrome.app")
}

@Test
func criticalPressureIsTriggeredByLowAvailability() {
    let level = SystemMemoryReader.evaluateLevel(
        physicalMemory: 48 * 1_024 * 1_024 * 1_024,
        availableBytes: 2 * 1_024 * 1_024 * 1_024,
        compressedBytes: 3 * 1_024 * 1_024 * 1_024,
        swapUsedBytes: 1 * 1_024 * 1_024 * 1_024
    )

    #expect(level == .critical)
}

@Test
func hiddenIdleAppsAreRankedAheadOfFrontmostApps() {
    let now = Date()
    let snapshot = MemorySnapshot(
        physicalMemory: 48 * 1_024 * 1_024 * 1_024,
        usedBytes: 40 * 1_024 * 1_024 * 1_024,
        freeBytes: 2 * 1_024 * 1_024 * 1_024,
        availableBytes: 4 * 1_024 * 1_024 * 1_024,
        compressedBytes: 6 * 1_024 * 1_024 * 1_024,
        wiredBytes: 4 * 1_024 * 1_024 * 1_024,
        appMemoryBytes: 32 * 1_024 * 1_024 * 1_024,
        cachedBytes: 3 * 1_024 * 1_024 * 1_024,
        swapUsedBytes: 4 * 1_024 * 1_024 * 1_024,
        level: .critical,
        sampledAt: now
    )

    let hiddenApp = AppMemoryUsage(
        key: "chrome",
        stableIdentifier: "com.google.Chrome",
        displayName: "Chrome",
        residentBytes: 8 * 1_024 * 1_024 * 1_024,
        processCount: 12,
        bundleIdentifier: "com.google.Chrome",
        bundlePath: "/Applications/Google Chrome.app",
        executablePath: nil,
        isFrontmost: false,
        isHidden: true,
        lastActiveAt: now.addingTimeInterval(-7200),
        category: .application,
        workloadKind: .browser,
        canTerminate: true,
        isSystemCritical: false
    )

    let frontmostApp = AppMemoryUsage(
        key: "xcode",
        stableIdentifier: "com.apple.dt.Xcode",
        displayName: "Xcode",
        residentBytes: 9 * 1_024 * 1_024 * 1_024,
        processCount: 6,
        bundleIdentifier: "com.apple.dt.Xcode",
        bundlePath: "/Applications/Xcode.app",
        executablePath: nil,
        isFrontmost: true,
        isHidden: false,
        lastActiveAt: now,
        category: .application,
        workloadKind: .developerTool,
        canTerminate: true,
        isSystemCritical: false
    )

    let suggestions = SuggestionEngine.suggestions(for: [frontmostApp, hiddenApp], snapshot: snapshot)
    #expect(suggestions.first?.app.displayName == "Chrome")
}

@Test
func ignoredAppsDoNotAppearInSuggestions() {
    let now = Date()
    let snapshot = MemorySnapshot(
        physicalMemory: 32 * 1_024 * 1_024 * 1_024,
        usedBytes: 24 * 1_024 * 1_024 * 1_024,
        freeBytes: 2 * 1_024 * 1_024 * 1_024,
        availableBytes: 5 * 1_024 * 1_024 * 1_024,
        compressedBytes: 2 * 1_024 * 1_024 * 1_024,
        wiredBytes: 3 * 1_024 * 1_024 * 1_024,
        appMemoryBytes: 18 * 1_024 * 1_024 * 1_024,
        cachedBytes: 2 * 1_024 * 1_024 * 1_024,
        swapUsedBytes: 1 * 1_024 * 1_024 * 1_024,
        level: .warning,
        sampledAt: now
    )

    let app = AppMemoryUsage(
        key: "brave",
        stableIdentifier: "com.brave.Browser",
        displayName: "Brave",
        residentBytes: 5 * 1_024 * 1_024 * 1_024,
        processCount: 10,
        bundleIdentifier: "com.brave.Browser",
        bundlePath: "/Applications/Brave Browser.app",
        executablePath: nil,
        isFrontmost: false,
        isHidden: true,
        lastActiveAt: now.addingTimeInterval(-3600),
        category: .application,
        workloadKind: .browser,
        canTerminate: true,
        isSystemCritical: false
    )

    let suggestions = SuggestionEngine.suggestions(for: [app], snapshot: snapshot, ignoredKeys: ["com.brave.Browser"])
    #expect(suggestions.isEmpty)
}

@Test
func notificationPolicyThrottlesRepeatedWarning() {
    let now = Date()

    #expect(
        NotificationPolicy.shouldNotify(
            previousLevel: .warning,
            lastSentAt: now.addingTimeInterval(-(10 * 60)),
            newLevel: .warning,
            now: now
        ) == false
    )

    #expect(
        NotificationPolicy.shouldNotify(
            previousLevel: .warning,
            lastSentAt: now.addingTimeInterval(-(31 * 60)),
            newLevel: .warning,
            now: now
        ) == true
    )

    #expect(
        NotificationPolicy.shouldNotify(
            previousLevel: .warning,
            lastSentAt: now.addingTimeInterval(-(2 * 60)),
            newLevel: .critical,
            now: now
        ) == true
    )
}
