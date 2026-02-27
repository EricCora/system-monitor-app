import Foundation
import Darwin
import Darwin.Mach

public struct MemoryProvider: MetricProvider {
    public let providerID = "memory"

    public init() {}

    public func sample(at date: Date) async throws -> [MetricSample] {
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

        let freePages = Double(vmStats.free_count + vmStats.speculative_count)
        let activePages = Double(vmStats.active_count)
        let inactivePages = Double(vmStats.inactive_count)
        let wiredPages = Double(vmStats.wire_count)
        let compressedPages = Double(vmStats.compressor_page_count)

        let usedPages = activePages + inactivePages + wiredPages + compressedPages
        let usedBytes = usedPages * pageSize
        let freeBytes = max(0, freePages * pageSize)
        let compressedBytes = max(0, compressedPages * pageSize)
        let swapUsedBytes = readSwapUsedBytes() ?? 0

        let pressurePercent = totalMemoryBytes > 0
            ? min(max((usedBytes / totalMemoryBytes) * 100.0, 0), 100)
            : 0

        return [
            MetricSample(metricID: .memoryUsedBytes, timestamp: date, value: usedBytes, unit: .bytes),
            MetricSample(metricID: .memoryFreeBytes, timestamp: date, value: freeBytes, unit: .bytes),
            MetricSample(metricID: .memoryCompressedBytes, timestamp: date, value: compressedBytes, unit: .bytes),
            MetricSample(metricID: .memorySwapUsedBytes, timestamp: date, value: swapUsedBytes, unit: .bytes),
            MetricSample(metricID: .memoryPressureLevel, timestamp: date, value: pressurePercent, unit: .percent)
        ]
    }

    private func readSwapUsedBytes() -> Double? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else {
            return nil
        }
        return Double(usage.xsu_used)
    }
}
