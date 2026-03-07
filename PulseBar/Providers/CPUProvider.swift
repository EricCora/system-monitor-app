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
        samples.reserveCapacity(currentTicks.count + 8)

        var totalCoreUsage = 0.0
        var totalUserDelta = 0.0
        var totalSystemDelta = 0.0
        var totalIdleDelta = 0.0
        var totalNiceDelta = 0.0

        for (index, current) in currentTicks.enumerated() {
            let prior = previous[index]

            let userDelta = Double(current[0] &- prior[0])
            let systemDelta = Double(current[1] &- prior[1])
            let idleDelta = Double(current[2] &- prior[2])
            let niceDelta = Double(current[3] &- prior[3])

            totalUserDelta += userDelta
            totalSystemDelta += systemDelta
            totalIdleDelta += idleDelta
            totalNiceDelta += niceDelta

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
        let totalDelta = totalUserDelta + totalSystemDelta + totalIdleDelta + totalNiceDelta
        let userPercent = totalDelta > 0 ? ((totalUserDelta + totalNiceDelta) / totalDelta) * 100.0 : 0.0
        let systemPercent = totalDelta > 0 ? (totalSystemDelta / totalDelta) * 100.0 : 0.0
        let idlePercent = totalDelta > 0 ? (totalIdleDelta / totalDelta) * 100.0 : 100.0

        samples.append(
            MetricSample(
                metricID: .cpuTotalPercent,
                timestamp: date,
                value: overall,
                unit: .percent
            )
        )
        samples.append(MetricSample(metricID: .cpuUserPercent, timestamp: date, value: userPercent, unit: .percent))
        samples.append(MetricSample(metricID: .cpuSystemPercent, timestamp: date, value: systemPercent, unit: .percent))
        samples.append(MetricSample(metricID: .cpuIdlePercent, timestamp: date, value: idlePercent, unit: .percent))

        var loadAverages = [Double](repeating: 0, count: 3)
        if getloadavg(&loadAverages, Int32(loadAverages.count)) == Int32(loadAverages.count) {
            samples.append(MetricSample(metricID: .cpuLoadAverage1, timestamp: date, value: loadAverages[0], unit: .scalar))
            samples.append(MetricSample(metricID: .cpuLoadAverage5, timestamp: date, value: loadAverages[1], unit: .scalar))
            samples.append(MetricSample(metricID: .cpuLoadAverage15, timestamp: date, value: loadAverages[2], unit: .scalar))
        }

        samples.append(
            MetricSample(
                metricID: .uptimeSeconds,
                timestamp: date,
                value: ProcessInfo.processInfo.systemUptime,
                unit: .seconds
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
        samples.reserveCapacity(ticks.count + 8)

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
        samples.append(MetricSample(metricID: .cpuUserPercent, timestamp: date, value: 0, unit: .percent))
        samples.append(MetricSample(metricID: .cpuSystemPercent, timestamp: date, value: 0, unit: .percent))
        samples.append(MetricSample(metricID: .cpuIdlePercent, timestamp: date, value: 100, unit: .percent))

        var loadAverages = [Double](repeating: 0, count: 3)
        if getloadavg(&loadAverages, Int32(loadAverages.count)) == Int32(loadAverages.count) {
            samples.append(MetricSample(metricID: .cpuLoadAverage1, timestamp: date, value: loadAverages[0], unit: .scalar))
            samples.append(MetricSample(metricID: .cpuLoadAverage5, timestamp: date, value: loadAverages[1], unit: .scalar))
            samples.append(MetricSample(metricID: .cpuLoadAverage15, timestamp: date, value: loadAverages[2], unit: .scalar))
        }
        samples.append(
            MetricSample(
                metricID: .uptimeSeconds,
                timestamp: date,
                value: ProcessInfo.processInfo.systemUptime,
                unit: .seconds
            )
        )

        return samples
    }
}
