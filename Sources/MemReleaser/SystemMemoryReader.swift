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

        return makeSnapshot(
            statistics: statistics,
            pageSize: pageSize,
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            swapUsedBytes: readSwapUsage(),
            sampledAt: .now
        )
    }

    static func makeSnapshot(
        statistics: vm_statistics64,
        pageSize: vm_size_t,
        physicalMemory: UInt64,
        swapUsedBytes: UInt64,
        sampledAt: Date
    ) -> MemorySnapshot {
        let bytesPerPage = UInt64(pageSize)
        let freeBytes = UInt64(statistics.free_count) * bytesPerPage
        let speculativeBytes = UInt64(statistics.speculative_count) * bytesPerPage
        let wiredBytes = UInt64(statistics.wire_count) * bytesPerPage
        let purgeableBytes = UInt64(statistics.purgeable_count) * bytesPerPage
        let compressedBytes = UInt64(statistics.compressor_page_count) * bytesPerPage
        let appMemoryBytes = UInt64(statistics.internal_page_count) * bytesPerPage
        let fileBackedBytes = UInt64(statistics.external_page_count) * bytesPerPage

        let unusedBytes = freeBytes + speculativeBytes
        let cachedBytes = fileBackedBytes + purgeableBytes
        let usedBytes = appMemoryBytes + wiredBytes + compressedBytes
        let availableBytes = unusedBytes + cachedBytes

        return MemorySnapshot(
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
            sampledAt: sampledAt
        )
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
        let twoGiB: UInt64 = 2 * 1_024 * 1_024 * 1_024
        let eightGiB: UInt64 = 8 * 1_024 * 1_024 * 1_024

        if availableRatio < 0.08 || swapUsedBytes > eightGiB {
            return .critical
        }
        if availableRatio < 0.16 && compressedRatio > 0.18 {
            return .critical
        }
        if availableRatio < 0.16 || swapUsedBytes > twoGiB {
            return .warning
        }
        if availableRatio < 0.25 && compressedRatio > 0.18 {
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
