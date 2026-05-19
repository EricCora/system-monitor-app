import Foundation
import Darwin

public actor NetworkProvider: MetricProvider {
    public nonisolated let providerID = "network"

    private struct Snapshot: Sendable {
        let timestamp: Date
        let totalInBytes: UInt64
        let totalOutBytes: UInt64
        let byInterface: [String: InterfaceCounters]
    }

    private struct InterfaceCounters: Sendable {
        let inBytes: UInt64
        let outBytes: UInt64
    }

    private var previousSnapshot: Snapshot?

    public init() {}

    public func sample(at date: Date) async throws -> [MetricSample] {
        let counters = try readCounters()
        let snapshot = Snapshot(
            timestamp: date,
            totalInBytes: counters.totalInBytes,
            totalOutBytes: counters.totalOutBytes,
            byInterface: counters.byInterface
        )

        let previous = previousSnapshot
        previousSnapshot = snapshot

        guard let previous else {
            return bootstrapSamples(timestamp: date, byInterface: counters.byInterface)
        }

        let elapsed = max(0.001, date.timeIntervalSince(previous.timestamp))

        let inboundRate = Self.bytesPerSecond(current: counters.totalInBytes, previous: previous.totalInBytes, elapsed: elapsed)
        let outboundRate = Self.bytesPerSecond(current: counters.totalOutBytes, previous: previous.totalOutBytes, elapsed: elapsed)

        var samples: [MetricSample] = [
            MetricSample(metricID: .networkInBytesPerSec, timestamp: date, value: inboundRate, unit: .bytesPerSecond),
            MetricSample(metricID: .networkOutBytesPerSec, timestamp: date, value: outboundRate, unit: .bytesPerSecond)
        ]

        for interface in counters.byInterface.keys.sorted() {
            let current = counters.byInterface[interface]
            let previousInterface = previous.byInterface[interface]

            let inboundRate = Self.bytesPerSecond(
                current: current?.inBytes ?? 0,
                previous: previousInterface?.inBytes ?? (current?.inBytes ?? 0),
                elapsed: elapsed
            )
            let outboundRate = Self.bytesPerSecond(
                current: current?.outBytes ?? 0,
                previous: previousInterface?.outBytes ?? (current?.outBytes ?? 0),
                elapsed: elapsed
            )

            samples.append(
                MetricSample(
                    metricID: .networkInterfaceInBytesPerSec(interface),
                    timestamp: date,
                    value: inboundRate,
                    unit: .bytesPerSecond
                )
            )
            samples.append(
                MetricSample(
                    metricID: .networkInterfaceOutBytesPerSec(interface),
                    timestamp: date,
                    value: outboundRate,
                    unit: .bytesPerSecond
                )
            )
        }

        return samples
    }

    static func bytesPerSecond(current: UInt64, previous: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }

    private func bootstrapSamples(
        timestamp: Date,
        byInterface: [String: InterfaceCounters]
    ) -> [MetricSample] {
        var samples: [MetricSample] = [
            MetricSample(metricID: .networkInBytesPerSec, timestamp: timestamp, value: 0, unit: .bytesPerSecond),
            MetricSample(metricID: .networkOutBytesPerSec, timestamp: timestamp, value: 0, unit: .bytesPerSecond)
        ]

        for interface in byInterface.keys.sorted() {
            samples.append(
                MetricSample(
                    metricID: .networkInterfaceInBytesPerSec(interface),
                    timestamp: timestamp,
                    value: 0,
                    unit: .bytesPerSecond
                )
            )
            samples.append(
                MetricSample(
                    metricID: .networkInterfaceOutBytesPerSec(interface),
                    timestamp: timestamp,
                    value: 0,
                    unit: .bytesPerSecond
                )
            )
        }

        return samples
    }

    private func readCounters() throws -> (
        totalInBytes: UInt64,
        totalOutBytes: UInt64,
        byInterface: [String: InterfaceCounters]
    ) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let start = addrs else {
            throw ProviderError.unavailable("Unable to read network interfaces")
        }

        defer { freeifaddrs(start) }

        var inbound: UInt64 = 0
        var outbound: UInt64 = 0
        var byInterface: [String: InterfaceCounters] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = start
        while let iface = cursor {
            let flags = Int32(iface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp,
               !isLoopback,
               let addr = iface.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let dataPointer = iface.pointee.ifa_data,
               let namePointer = iface.pointee.ifa_name {
                let name = String(cString: namePointer)
                let networkData = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                let inBytes = UInt64(networkData.ifi_ibytes)
                let outBytes = UInt64(networkData.ifi_obytes)

                inbound += inBytes
                outbound += outBytes
                byInterface[name] = InterfaceCounters(inBytes: inBytes, outBytes: outBytes)
            }

            cursor = iface.pointee.ifa_next
        }

        return (inbound, outbound, byInterface)
    }
}
