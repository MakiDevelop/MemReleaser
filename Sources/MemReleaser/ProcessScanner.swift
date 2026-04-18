import Darwin
import Foundation

enum ProcessScanner {
    private struct Aggregate {
        var totalResident: UInt64 = 0
        var processCount = 0
        var executablePath: String?
    }

    static func scan(
        runningApps: [RunningAppDescriptor],
        recentActivity: [String: Date],
        frontmostKey: String?,
        currentProcessID: Int32
    ) -> [AppMemoryUsage] {
        let descriptors = runningApps.reduce(into: [String: RunningAppDescriptor]()) { partialResult, descriptor in
            let key = descriptor.appKey
            guard let existing = partialResult[key] else {
                partialResult[key] = descriptor
                return
            }

            if shouldReplace(existing: existing, with: descriptor) {
                partialResult[key] = descriptor
            }
        }
        let pids = allPIDs()
        var grouped: [String: Aggregate] = [:]

        for pid in pids where pid > 0 && pid != currentProcessID {
            guard let executablePath = executablePath(for: pid) else { continue }
            guard let residentBytes = residentBytes(for: pid), residentBytes > 0 else { continue }

            let key = groupKey(for: executablePath)
            var aggregate = grouped[key, default: Aggregate()]
            aggregate.totalResident += residentBytes
            aggregate.processCount += 1
            aggregate.executablePath = aggregate.executablePath ?? executablePath
            grouped[key] = aggregate
        }

        let apps = grouped.compactMap { key, aggregate in
            let descriptor = descriptors[key]
            let category = category(for: key, descriptor: descriptor)
            let displayName = descriptor?.localizedName ?? readableName(for: key)
            let isSystemCritical = isSystemCritical(key: key, descriptor: descriptor)
            let canTerminate = descriptor?.bundlePath != nil && !isSystemCritical

            return AppMemoryUsage(
                key: key,
                stableIdentifier: descriptor?.bundleIdentifier ?? descriptor?.bundlePath ?? key,
                displayName: displayName,
                residentBytes: aggregate.totalResident,
                processCount: aggregate.processCount,
                bundleIdentifier: descriptor?.bundleIdentifier,
                bundlePath: descriptor?.bundlePath,
                executablePath: aggregate.executablePath,
                isFrontmost: key == frontmostKey,
                isHidden: descriptor?.isHidden ?? false,
                lastActiveAt: recentActivity[key],
                category: category,
                workloadKind: workloadKind(for: key, descriptor: descriptor, category: category),
                canTerminate: canTerminate,
                isSystemCritical: isSystemCritical
            )
        }

        return apps.sorted { lhs, rhs in
            lhs.residentBytes > rhs.residentBytes
        }
    }

    static func groupKey(for executablePath: String) -> String {
        if let range = executablePath.range(of: ".app") {
            return String(executablePath[..<range.upperBound])
        }
        return executablePath
    }

    private static func category(for key: String, descriptor: RunningAppDescriptor?) -> AppMemoryUsage.Category {
        if key.hasPrefix("/System/") {
            return .system
        }
        if descriptor?.bundlePath != nil || key.hasSuffix(".app") {
            return .application
        }
        return .commandLine
    }

    private static func readableName(for key: String) -> String {
        let url = URL(fileURLWithPath: key)
        if key.hasSuffix(".app") {
            return url.deletingPathExtension().lastPathComponent
        }
        return url.lastPathComponent
    }

    private static func shouldReplace(existing: RunningAppDescriptor, with incoming: RunningAppDescriptor) -> Bool {
        if existing.isRegularApp != incoming.isRegularApp {
            return incoming.isRegularApp
        }
        if existing.bundleIdentifier == nil && incoming.bundleIdentifier != nil {
            return true
        }
        if existing.localizedName == nil && incoming.localizedName != nil {
            return true
        }
        return incoming.processIdentifier < existing.processIdentifier
    }

    private static func workloadKind(
        for key: String,
        descriptor: RunningAppDescriptor?,
        category: AppMemoryUsage.Category
    ) -> WorkloadKind {
        if category == .system {
            return .system
        }

        let haystack = [key, descriptor?.bundleIdentifier, descriptor?.localizedName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if haystack.contains("chrome")
            || haystack.contains("brave")
            || haystack.contains("safari")
            || haystack.contains("arc")
            || haystack.contains("firefox")
            || haystack.contains("edge")
        {
            return .browser
        }

        if haystack.contains("virtualmachine")
            || haystack.contains("docker")
            || haystack.contains("orbstack")
            || haystack.contains("parallels")
            || haystack.contains("vmware")
            || haystack.contains("utm")
            || haystack.contains("qemu")
        {
            return .virtualMachine
        }

        if haystack.contains("xcode")
            || haystack.contains("cursor")
            || haystack.contains("visual studio code")
            || haystack.contains("code.app")
            || haystack.contains("claude")
            || haystack.contains("simulator")
        {
            return .developerTool
        }

        if haystack.contains("line")
            || haystack.contains("slack")
            || haystack.contains("discord")
            || haystack.contains("teams")
            || haystack.contains("zoom")
            || haystack.contains("telegram")
        {
            return .communication
        }

        if haystack.contains("terminal")
            || haystack.contains("iterm")
            || haystack.contains("warp")
            || haystack.contains("ghostty")
            || haystack.contains("kitty")
            || category == .commandLine
        {
            return .terminal
        }

        return .unknown
    }

    private static func isSystemCritical(key: String, descriptor: RunningAppDescriptor?) -> Bool {
        if key.hasPrefix("/System/Library/CoreServices/Finder.app") {
            return true
        }
        let blockedBundleIdentifiers: Set<String> = [
            "com.apple.dock",
            "com.apple.finder",
            "com.apple.loginwindow",
            "com.apple.WindowManager",
            "com.apple.controlcenter",
        ]

        if let bundleIdentifier = descriptor?.bundleIdentifier, blockedBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }
        return key.hasPrefix("/System/")
    }

    private static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }

        let capacity = Int(count)
        let pointer = UnsafeMutablePointer<Int32>.allocate(capacity: capacity)
        defer { pointer.deallocate() }

        let bufferSize = Int32(capacity * MemoryLayout<Int32>.stride)
        let actualCount = proc_listallpids(pointer, bufferSize)
        guard actualCount > 0 else { return [] }
        let validCount = Int(actualCount)
        return Array(UnsafeBufferPointer(start: pointer, count: validCount))
    }

    private static func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN * 4))
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func residentBytes(for pid: Int32) -> UInt64? {
        var info = proc_taskallinfo()
        let size = MemoryLayout<proc_taskallinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, pointer, Int32(size))
        }

        guard result == size else { return nil }
        return UInt64(info.ptinfo.pti_resident_size)
    }
}

private extension RunningAppDescriptor {
    var appKey: String {
        bundlePath ?? executablePath ?? "pid:\(processIdentifier)"
    }
}
