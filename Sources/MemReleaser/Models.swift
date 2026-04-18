import Foundation

enum MemoryPressureLevel: String, CaseIterable, Codable, Sendable {
    case healthy
    case warning
    case critical

    var title: String {
        switch self {
        case .healthy:
            "Healthy"
        case .warning:
            "Warning"
        case .critical:
            "Critical"
        }
    }

    var subtitle: String {
        switch self {
        case .healthy:
            "現在不是爆 RAM，但可以先收斂常駐 app。"
        case .warning:
            "記憶體壓力在上升，該先收掉重但閒置的 app。"
        case .critical:
            "已接近卡死區，應立刻釋放幾個高佔用 app。"
        }
    }

    var systemImage: String {
        switch self {
        case .healthy:
            "gauge.with.dots.needle.33percent"
        case .warning:
            "exclamationmark.triangle"
        case .critical:
            "flame"
        }
    }
}

struct MemorySnapshot: Sendable {
    var physicalMemory: UInt64
    var usedBytes: UInt64
    var freeBytes: UInt64
    var availableBytes: UInt64
    var compressedBytes: UInt64
    var wiredBytes: UInt64
    var appMemoryBytes: UInt64
    var cachedBytes: UInt64
    var swapUsedBytes: UInt64
    var level: MemoryPressureLevel
    var sampledAt: Date

    var usedRatio: Double {
        guard physicalMemory > 0 else { return 0 }
        return Double(usedBytes) / Double(physicalMemory)
    }

    var availableRatio: Double {
        guard physicalMemory > 0 else { return 0 }
        return Double(availableBytes) / Double(physicalMemory)
    }

    var compressedRatio: Double {
        guard physicalMemory > 0 else { return 0 }
        return Double(compressedBytes) / Double(physicalMemory)
    }

    static let placeholder = MemorySnapshot(
        physicalMemory: ProcessInfo.processInfo.physicalMemory,
        usedBytes: 0,
        freeBytes: 0,
        availableBytes: 0,
        compressedBytes: 0,
        wiredBytes: 0,
        appMemoryBytes: 0,
        cachedBytes: 0,
        swapUsedBytes: 0,
        level: .healthy,
        sampledAt: .now
    )
}

struct RunningAppDescriptor: Sendable {
    var processIdentifier: Int32
    var bundlePath: String?
    var executablePath: String?
    var bundleIdentifier: String?
    var localizedName: String?
    var isHidden: Bool
    var isRegularApp: Bool
}

enum WorkloadKind: String, CaseIterable, Sendable {
    case browser
    case virtualMachine
    case developerTool
    case communication
    case terminal
    case system
    case unknown

    var label: String {
        switch self {
        case .browser:
            "Browser"
        case .virtualMachine:
            "VM / Containers"
        case .developerTool:
            "Dev Tool"
        case .communication:
            "Communication"
        case .terminal:
            "Terminal / CLI"
        case .system:
            "System"
        case .unknown:
            "General"
        }
    }
}

struct AppMemoryUsage: Identifiable, Sendable {
    enum Category: String, Sendable {
        case application
        case commandLine
        case system
    }

    var id: String { key }
    var key: String
    var stableIdentifier: String
    var displayName: String
    var residentBytes: UInt64
    var processCount: Int
    var bundleIdentifier: String?
    var bundlePath: String?
    var executablePath: String?
    var isFrontmost: Bool
    var isHidden: Bool
    var lastActiveAt: Date?
    var category: Category
    var workloadKind: WorkloadKind
    var canTerminate: Bool
    var isSystemCritical: Bool
}

struct AppSuggestion: Identifiable, Sendable {
    var id: String { app.id }
    var app: AppMemoryUsage
    var score: Double
    var reasons: [String]
    var recommendation: String
}

struct MonitorSample: Sendable {
    var snapshot: MemorySnapshot
    var apps: [AppMemoryUsage]
    var suggestions: [AppSuggestion]
}

struct MemoryTrendSample: Identifiable, Sendable {
    var id: Date { timestamp }
    var timestamp: Date
    var availableBytes: UInt64
    var swapUsedBytes: UInt64
    var compressedBytes: UInt64
    var level: MemoryPressureLevel
}

struct AppMemoryPoint: Sendable {
    var timestamp: Date
    var residentBytes: UInt64
}

struct AppGrowthInsight: Identifiable, Sendable {
    var id: String { stableIdentifier }
    var stableIdentifier: String
    var displayName: String
    var workloadKind: WorkloadKind
    var currentBytes: UInt64
    var deltaBytes: Int64
    var windowMinutes: Int

    var deltaIsPositive: Bool {
        deltaBytes > 0
    }
}

enum NotificationPolicy {
    static func shouldNotify(
        previousLevel: MemoryPressureLevel?,
        lastSentAt: Date?,
        newLevel: MemoryPressureLevel,
        now: Date = .now
    ) -> Bool {
        guard newLevel != .healthy else { return false }

        if previousLevel != newLevel {
            return true
        }

        guard let lastSentAt else { return true }
        let cooldown: TimeInterval

        switch newLevel {
        case .warning:
            cooldown = 30 * 60
        case .critical:
            cooldown = 10 * 60
        case .healthy:
            cooldown = .infinity
        }

        return now.timeIntervalSince(lastSentAt) >= cooldown
    }
}

struct DiagnosticReport: Codable, Sendable {
    struct Snapshot: Codable, Sendable {
        var sampledAt: Date
        var level: String
        var physicalMemoryBytes: UInt64
        var usedBytes: UInt64
        var availableBytes: UInt64
        var compressedBytes: UInt64
        var swapUsedBytes: UInt64
        var selfResidentBytes: UInt64
    }

    struct SuggestedApp: Codable, Sendable {
        var displayName: String
        var stableIdentifier: String
        var residentBytes: UInt64
        var workloadKind: String
        var recommendation: String
    }

    struct GrowthApp: Codable, Sendable {
        var displayName: String
        var stableIdentifier: String
        var currentBytes: UInt64
        var deltaBytes: Int64
        var windowMinutes: Int
    }

    struct TrendPoint: Codable, Sendable {
        var timestamp: Date
        var availableBytes: UInt64
        var swapUsedBytes: UInt64
        var compressedBytes: UInt64
        var level: String
    }

    var exportedAt: Date
    var snapshot: Snapshot
    var launchAtLoginTitle: String
    var ignoredAppIdentifiers: [String]
    var suggestions: [SuggestedApp]
    var growthApps: [GrowthApp]
    var trend: [TrendPoint]
}

struct LaunchAtLoginState: Sendable {
    var isEnabled: Bool
    var isSupportedInCurrentBuild: Bool
    var needsApproval: Bool
    var title: String
    var detail: String

    static let unavailable = LaunchAtLoginState(
        isEnabled: false,
        isSupportedInCurrentBuild: false,
        needsApproval: false,
        title: "目前這份執行檔不支援登入啟動",
        detail: "請從 Xcode 產出的正式 .app 執行，`swift run` 或測試執行檔通常不會被系統當成可登錄的主 app。"
    )
}
