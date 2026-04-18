import Foundation

enum Formatters {
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: Int64(value))
    }

    static func shortBytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        formatter.isAdaptive = true
        formatter.includesActualByteCount = false
        return formatter.string(fromByteCount: Int64(value))
    }

    static func minutesSince(_ date: Date?) -> String {
        guard let date else { return "未追蹤" }
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 {
            return "剛剛"
        }
        if minutes < 60 {
            return "\(minutes) 分鐘前"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) 小時前"
        }
        return "\(hours / 24) 天前"
    }
}
