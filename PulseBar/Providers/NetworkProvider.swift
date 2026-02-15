import Foundation
import Darwin

public actor NetworkProvider: MetricProvider {
    public nonisolated let providerID = "network"
    private var previousSnapshot: (timestamp: Date, inBytes: UInt64, outBytes: UInt64)?

    public init() {}

    public func sample(at date: Date) async throws -> [MetricSample] {
        let counters = try readCounters()

        let previous = previousSnapshot
        previousSnapshot = (date, counters.inBytes, counters.outBytes)

        guard let previous else {
            return [
                MetricSample(metricID: .networkInBytesPerSec, timestamp: date, value: 0, unit: .bytesPerSecond),
                MetricSample(metricID: .networkOutBytesPerSec, timestamp: date, value: 0, unit: .bytesPerSecond)
            ]
        }

        let elapsed = max(0.001, date.timeIntervalSince(previous.timestamp))
        let inDelta = counters.inBytes &- previous.inBytes
        let outDelta = counters.outBytes &- previous.outBytes

        let inboundRate = Double(inDelta) / elapsed
        let outboundRate = Double(outDelta) / elapsed

        return [
            MetricSample(metricID: .networkInBytesPerSec, timestamp: date, value: inboundRate, unit: .bytesPerSecond),
            MetricSample(metricID: .networkOutBytesPerSec, timestamp: date, value: outboundRate, unit: .bytesPerSecond)
        ]
    }

    private func readCounters() throws -> (inBytes: UInt64, outBytes: UInt64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let start = addrs else {
            throw ProviderError.unavailable("Unable to read network interfaces")
        }

        defer { freeifaddrs(start) }

        var inbound: UInt64 = 0
        var outbound: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = start
        while let iface = cursor {
            let flags = Int32(iface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp,
               !isLoopback,
               let addr = iface.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let dataPointer = iface.pointee.ifa_data {
                let networkData = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                inbound += UInt64(networkData.ifi_ibytes)
                outbound += UInt64(networkData.ifi_obytes)
            }

            cursor = iface.pointee.ifa_next
        }

        return (inbound, outbound)
    }
}
