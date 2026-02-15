import Foundation
import Darwin
import Darwin.Mach

public actor CPUProvider: MetricProvider {
    public nonisolated let providerID = "cpu"
    private var previousTicks: [[UInt32]]?

    public init() {}

    public func sample(at date: Date) async throws -> [MetricSample] {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            throw ProviderError.unavailable("CPU load info unavailable")
        }

        defer {
            let byteCount = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), byteCount)
        }

        let currentTicks = extractTicks(cpuInfo: cpuInfo, cpuCount: Int(cpuCount))

        let previous = previousTicks
        previousTicks = currentTicks

        guard let previous, previous.count == currentTicks.count else {
            return bootstrapSamples(from: currentTicks, at: date)
        }

        var samples: [MetricSample] = []
        samples.reserveCapacity(currentTicks.count + 1)

        var totalCoreUsage = 0.0

        for (index, current) in currentTicks.enumerated() {
            let prior = previous[index]

            let userDelta = Double(current[0] &- prior[0])
            let systemDelta = Double(current[1] &- prior[1])
            let idleDelta = Double(current[2] &- prior[2])
            let niceDelta = Double(current[3] &- prior[3])

            let usedDelta = userDelta + systemDelta + niceDelta
            let totalDelta = usedDelta + idleDelta
            let usage = totalDelta > 0 ? (usedDelta / totalDelta) * 100.0 : 0.0
            totalCoreUsage += usage

            samples.append(
                MetricSample(
                    metricID: .cpuCorePercent(index),
                    timestamp: date,
                    value: usage,
                    unit: .percent
                )
            )
        }

        let overall = currentTicks.isEmpty ? 0.0 : totalCoreUsage / Double(currentTicks.count)
        samples.append(
            MetricSample(
                metricID: .cpuTotalPercent,
                timestamp: date,
                value: overall,
                unit: .percent
            )
        )

        return samples
    }

    private func extractTicks(cpuInfo: processor_info_array_t, cpuCount: Int) -> [[UInt32]] {
        var ticks: [[UInt32]] = []
        ticks.reserveCapacity(cpuCount)

        for cpuIndex in 0..<cpuCount {
            let base = cpuIndex * Int(CPU_STATE_MAX)
            let user = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)])
            ticks.append([user, system, idle, nice])
        }

        return ticks
    }

    private func bootstrapSamples(from ticks: [[UInt32]], at date: Date) -> [MetricSample] {
        var samples: [MetricSample] = []
        samples.reserveCapacity(ticks.count + 1)

        for index in ticks.indices {
            samples.append(
                MetricSample(
                    metricID: .cpuCorePercent(index),
                    timestamp: date,
                    value: 0,
                    unit: .percent
                )
            )
        }

        samples.append(
            MetricSample(
                metricID: .cpuTotalPercent,
                timestamp: date,
                value: 0,
                unit: .percent
            )
        )

        return samples
    }
}
