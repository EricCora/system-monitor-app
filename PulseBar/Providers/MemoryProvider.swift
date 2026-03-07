import Foundation
import Darwin
import Darwin.Mach

public struct MemoryVMStatsSnapshot: Sendable, Equatable {
    public let pageSizeBytes: Double
    public let totalMemoryBytes: Double
    public let freePages: UInt64
    public let activePages: UInt64
    public let inactivePages: UInt64
    public let wiredPages: UInt64
    public let compressedPages: UInt64
    public let cachePages: UInt64
    public let pageIns: UInt64
    public let pageOuts: UInt64

    public init(
        pageSizeBytes: Double,
        totalMemoryBytes: Double,
        freePages: UInt64,
        activePages: UInt64,
        inactivePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        cachePages: UInt64,
        pageIns: UInt64,
        pageOuts: UInt64
    ) {
        self.pageSizeBytes = pageSizeBytes
        self.totalMemoryBytes = totalMemoryBytes
        self.freePages = freePages
        self.activePages = activePages
        self.inactivePages = inactivePages
        self.wiredPages = wiredPages
        self.compressedPages = compressedPages
        self.cachePages = cachePages
        self.pageIns = pageIns
        self.pageOuts = pageOuts
    }
}

public struct MemorySwapUsageSnapshot: Sendable, Equatable {
    public let totalBytes: Double
    public let usedBytes: Double

    public init(totalBytes: Double, usedBytes: Double) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
    }
}

public actor MemoryProvider: MetricProvider {
    public nonisolated let providerID = "memory"

    public typealias VMStatsReader = @Sendable () throws -> MemoryVMStatsSnapshot
    public typealias SwapUsageReader = @Sendable () -> MemorySwapUsageSnapshot?

    private let vmStatsReader: VMStatsReader
    private let swapUsageReader: SwapUsageReader
    private var previousPagingCounters: (timestamp: Date, pageIns: UInt64, pageOuts: UInt64)?

    public init(
        vmStatsReader: @escaping VMStatsReader = { try MemoryProvider.readVMStatsSnapshot() },
        swapUsageReader: @escaping SwapUsageReader = { MemoryProvider.readSwapUsageSnapshot() }
    ) {
        self.vmStatsReader = vmStatsReader
        self.swapUsageReader = swapUsageReader
    }

    public func sample(at date: Date) async throws -> [MetricSample] {
        let vmStats = try vmStatsReader()
        let swapUsage = swapUsageReader()

        let pageSize = vmStats.pageSizeBytes
        let activeBytes = max(0, Double(vmStats.activePages) * pageSize)
        let inactiveBytes = max(0, Double(vmStats.inactivePages) * pageSize)
        let wiredBytes = max(0, Double(vmStats.wiredPages) * pageSize)
        let compressedBytes = max(0, Double(vmStats.compressedPages) * pageSize)
        let cacheBytes = max(0, Double(vmStats.cachePages) * pageSize)
        let freeBytes = max(0, Double(vmStats.freePages) * pageSize)
        let usedBytes = activeBytes + inactiveBytes + wiredBytes + compressedBytes
        let appBytes = max(0, activeBytes + inactiveBytes - cacheBytes)

        let pressurePercent: Double
        if vmStats.totalMemoryBytes > 0 {
            pressurePercent = min(max((usedBytes / vmStats.totalMemoryBytes) * 100.0, 0), 100)
        } else {
            pressurePercent = 0
        }

        let swapUsedBytes = max(0, swapUsage?.usedBytes ?? 0)
        let swapTotalBytes = max(swapUsedBytes, max(0, swapUsage?.totalBytes ?? 0))
        let pageRates = pageRateBytesPerSecond(current: vmStats, date: date)

        return [
            MetricSample(metricID: .memoryUsedBytes, timestamp: date, value: usedBytes, unit: .bytes),
            MetricSample(metricID: .memoryFreeBytes, timestamp: date, value: freeBytes, unit: .bytes),
            MetricSample(metricID: .memoryCompressedBytes, timestamp: date, value: compressedBytes, unit: .bytes),
            MetricSample(metricID: .memorySwapUsedBytes, timestamp: date, value: swapUsedBytes, unit: .bytes),
            MetricSample(metricID: .memorySwapTotalBytes, timestamp: date, value: swapTotalBytes, unit: .bytes),
            MetricSample(metricID: .memoryActiveBytes, timestamp: date, value: activeBytes, unit: .bytes),
            MetricSample(metricID: .memoryWiredBytes, timestamp: date, value: wiredBytes, unit: .bytes),
            MetricSample(metricID: .memoryCacheBytes, timestamp: date, value: cacheBytes, unit: .bytes),
            MetricSample(metricID: .memoryAppBytes, timestamp: date, value: appBytes, unit: .bytes),
            MetricSample(metricID: .memoryPressureLevel, timestamp: date, value: pressurePercent, unit: .percent),
            MetricSample(metricID: .memoryPageInsBytesPerSec, timestamp: date, value: pageRates.pageIns, unit: .bytesPerSecond),
            MetricSample(metricID: .memoryPageOutsBytesPerSec, timestamp: date, value: pageRates.pageOuts, unit: .bytesPerSecond)
        ]
    }

    private func pageRateBytesPerSecond(
        current: MemoryVMStatsSnapshot,
        date: Date
    ) -> (pageIns: Double, pageOuts: Double) {
        defer {
            previousPagingCounters = (timestamp: date, pageIns: current.pageIns, pageOuts: current.pageOuts)
        }

        guard let previousPagingCounters else {
            return (0, 0)
        }

        let elapsed = max(0.001, date.timeIntervalSince(previousPagingCounters.timestamp))
        let pageInsDelta = current.pageIns &- previousPagingCounters.pageIns
        let pageOutsDelta = current.pageOuts &- previousPagingCounters.pageOuts
        let pageSize = current.pageSizeBytes

        return (
            max(0, (Double(pageInsDelta) * pageSize) / elapsed),
            max(0, (Double(pageOutsDelta) * pageSize) / elapsed)
        )
    }

    public static func readVMStatsSnapshot() throws -> MemoryVMStatsSnapshot {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result: kern_return_t = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            throw ProviderError.unavailable("VM statistics unavailable")
        }

        let pageSize = Double(vm_kernel_page_size)
        let totalMemoryBytes = Double(ProcessInfo.processInfo.physicalMemory)

        return MemoryVMStatsSnapshot(
            pageSizeBytes: pageSize,
            totalMemoryBytes: totalMemoryBytes,
            freePages: UInt64(vmStats.free_count) &+ UInt64(vmStats.speculative_count),
            activePages: UInt64(vmStats.active_count),
            inactivePages: UInt64(vmStats.inactive_count),
            wiredPages: UInt64(vmStats.wire_count),
            compressedPages: UInt64(vmStats.compressor_page_count),
            cachePages: UInt64(vmStats.external_page_count),
            pageIns: UInt64(vmStats.pageins),
            pageOuts: UInt64(vmStats.pageouts)
        )
    }

    public static func readSwapUsageSnapshot() -> MemorySwapUsageSnapshot? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else {
            return nil
        }

        return MemorySwapUsageSnapshot(
            totalBytes: Double(usage.xsu_total),
            usedBytes: Double(usage.xsu_used)
        )
    }
}
