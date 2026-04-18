import Darwin
import Foundation

enum SystemMemoryReader {
    enum ReaderError: Error {
        case hostPageSize
        case hostStatistics
    }

    static func read() throws -> MemorySnapshot {
        let host = mach_host_self()
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else {
            throw ReaderError.hostPageSize
        }

        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(host, HOST_VM_INFO64, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            throw ReaderError.hostStatistics
        }

        let bytesPerPage = UInt64(pageSize)
        let freeBytes = UInt64(statistics.free_count) * bytesPerPage
        let activeBytes = UInt64(statistics.active_count) * bytesPerPage
        let inactiveBytes = UInt64(statistics.inactive_count) * bytesPerPage
        let speculativeBytes = UInt64(statistics.speculative_count) * bytesPerPage
        let wiredBytes = UInt64(statistics.wire_count) * bytesPerPage
        let purgeableBytes = UInt64(statistics.purgeable_count) * bytesPerPage
        let compressedBytes = UInt64(statistics.compressor_page_count) * bytesPerPage

        let usedBytes = activeBytes + inactiveBytes + wiredBytes + compressedBytes
        let availableBytes = freeBytes + speculativeBytes + purgeableBytes
        let cachedBytes = inactiveBytes + speculativeBytes
        let appMemoryBytes = activeBytes + wiredBytes
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let swapUsedBytes = readSwapUsage()

        let snapshot = MemorySnapshot(
            physicalMemory: physicalMemory,
            usedBytes: min(usedBytes, physicalMemory),
            freeBytes: freeBytes,
            availableBytes: availableBytes,
            compressedBytes: compressedBytes,
            wiredBytes: wiredBytes,
            appMemoryBytes: appMemoryBytes,
            cachedBytes: cachedBytes,
            swapUsedBytes: swapUsedBytes,
            level: evaluateLevel(
                physicalMemory: physicalMemory,
                availableBytes: availableBytes,
                compressedBytes: compressedBytes,
                swapUsedBytes: swapUsedBytes
            ),
            sampledAt: .now
        )

        return snapshot
    }

    static func evaluateLevel(
        physicalMemory: UInt64,
        availableBytes: UInt64,
        compressedBytes: UInt64,
        swapUsedBytes: UInt64
    ) -> MemoryPressureLevel {
        guard physicalMemory > 0 else { return .healthy }
        let availableRatio = Double(availableBytes) / Double(physicalMemory)
        let compressedRatio = Double(compressedBytes) / Double(physicalMemory)

        if availableRatio < 0.08 || compressedRatio > 0.18 || swapUsedBytes > 8 * 1_024 * 1_024 * 1_024 {
            return .critical
        }
        if availableRatio < 0.16 || compressedRatio > 0.10 || swapUsedBytes > 2 * 1_024 * 1_024 * 1_024 {
            return .warning
        }
        return .healthy
    }

    private static func readSwapUsage() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return 0 }
        return usage.xsu_used
    }
}
