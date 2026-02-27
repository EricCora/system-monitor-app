import Foundation
import IOKit

public actor DiskProvider: MetricProvider {
    public nonisolated let providerID = "disk"

    private var previousByteSnapshot: (timestamp: Date, readBytes: UInt64, writeBytes: UInt64)?
    private var cachedSMARTStatus: (timestamp: Date, statusCode: Double)?
    private let smartStatusCacheTTL: TimeInterval = 300

    public init() {}

    public func sample(at date: Date) async throws -> [MetricSample] {
        let freeBytes = readFreeSpaceBytes()
        let smartStatusCode = readSMARTStatusCode(now: date)

        var samples: [MetricSample] = [
            MetricSample(metricID: .diskFreeBytes, timestamp: date, value: freeBytes, unit: .bytes),
            MetricSample(metricID: .diskSMARTStatusCode, timestamp: date, value: smartStatusCode, unit: .scalar)
        ]

        if let throughput = try? readReadWriteThroughput(at: date) {
            samples.append(
                MetricSample(
                    metricID: .diskReadBytesPerSec,
                    timestamp: date,
                    value: throughput.readBytesPerSecond,
                    unit: .bytesPerSecond
                )
            )
            samples.append(
                MetricSample(
                    metricID: .diskWriteBytesPerSec,
                    timestamp: date,
                    value: throughput.writeBytesPerSecond,
                    unit: .bytesPerSecond
                )
            )
            samples.append(
                MetricSample(
                    metricID: .diskThroughputBytesPerSec,
                    timestamp: date,
                    value: throughput.readBytesPerSecond + throughput.writeBytesPerSecond,
                    unit: .bytesPerSecond
                )
            )
            return samples
        }

        let combinedThroughputBytesPerSec = (try? readCombinedThroughputBytesPerSecond()) ?? 0
        samples.append(
            MetricSample(
                metricID: .diskThroughputBytesPerSec,
                timestamp: date,
                value: combinedThroughputBytesPerSec,
                unit: .bytesPerSecond
            )
        )
        return samples
    }

    private func readFreeSpaceBytes() -> Double {
        let rootURL = URL(fileURLWithPath: "/")

        if let values = try? rootURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) {
            if let important = values.volumeAvailableCapacityForImportantUsage {
                return Double(important)
            }
            if let fallback = values.volumeAvailableCapacity {
                return Double(fallback)
            }
        }

        return 0
    }

    private func readReadWriteThroughput(at date: Date) throws -> (readBytesPerSecond: Double, writeBytesPerSecond: Double) {
        let totals = try readIOKitByteTotals()
        guard let previous = previousByteSnapshot else {
            previousByteSnapshot = (date, totals.readBytes, totals.writeBytes)
            return (0, 0)
        }

        previousByteSnapshot = (date, totals.readBytes, totals.writeBytes)

        let elapsed = max(0.001, date.timeIntervalSince(previous.timestamp))
        let readRate = Double(totals.readBytes &- previous.readBytes) / elapsed
        let writeRate = Double(totals.writeBytes &- previous.writeBytes) / elapsed
        return (readRate, writeRate)
    }

    private func readIOKitByteTotals() throws -> (readBytes: UInt64, writeBytes: UInt64) {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
        guard result == KERN_SUCCESS else {
            throw ProviderError.unavailable("IOKit disk statistics unavailable")
        }

        defer { IOObjectRelease(iterator) }

        var totalReadBytes: UInt64 = 0
        var totalWriteBytes: UInt64 = 0
        var foundAny = false

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            guard let property = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue(),
            let stats = property as? [String: Any],
            let parsed = Self.parseIOKitStatistics(stats) else {
                continue
            }

            totalReadBytes &+= parsed.readBytes
            totalWriteBytes &+= parsed.writeBytes
            foundAny = true
        }

        guard foundAny else {
            throw ProviderError.parsingFailed("No IOBlockStorageDriver statistics dictionaries found")
        }

        return (totalReadBytes, totalWriteBytes)
    }

    static func parseIOKitStatistics(_ statistics: [String: Any]) -> (readBytes: UInt64, writeBytes: UInt64)? {
        guard let readBytes = parseByteCounter(statistics["Bytes (Read)"]),
              let writeBytes = parseByteCounter(statistics["Bytes (Write)"]) else {
            return nil
        }
        return (readBytes, writeBytes)
    }

    static func parseByteCounter(_ value: Any?) -> UInt64? {
        switch value {
        case let number as NSNumber:
            return number.uint64Value
        case let intValue as Int:
            return UInt64(max(0, intValue))
        case let uint64Value as UInt64:
            return uint64Value
        case let doubleValue as Double:
            return UInt64(max(0, doubleValue))
        case let stringValue as String:
            return UInt64(stringValue)
        default:
            return nil
        }
    }

    private func readSMARTStatusCode(now: Date) -> Double {
        if let cachedSMARTStatus, now.timeIntervalSince(cachedSMARTStatus.timestamp) < smartStatusCacheTTL {
            return cachedSMARTStatus.statusCode
        }

        let statusCode = (try? fetchSMARTStatusCode()) ?? -2
        cachedSMARTStatus = (now, statusCode)
        return statusCode
    }

    private func fetchSMARTStatusCode() throws -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "/"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ProviderError.unavailable("diskutil exited with status \(process.terminationStatus)")
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ProviderError.parsingFailed("Unable to decode diskutil output")
        }

        return Self.parseSMARTStatusCode(from: output)
    }

    static func parseSMARTStatusCode(from diskutilOutput: String) -> Double {
        let lines = diskutilOutput.split(whereSeparator: \.isNewline)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.localizedCaseInsensitiveContains("SMART Status:") else { continue }
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { return -2 }
            let statusText = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if statusText.contains("verified") {
                return 1
            }
            if statusText.contains("failing") {
                return -1
            }
            if statusText.contains("not supported") {
                return 0
            }
            return -2
        }
        return -2
    }

    private func readCombinedThroughputBytesPerSecond() throws -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/iostat")
        process.arguments = ["-d", "-K", "-c", "2"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ProviderError.unavailable("iostat exited with status \(process.terminationStatus)")
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ProviderError.parsingFailed("Unable to decode iostat output")
        }

        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let numericLines = lines.filter { line in
            line.range(of: #"^[0-9\s\.]+$"#, options: .regularExpression) != nil
        }

        guard let latestDataLine = numericLines.last else {
            throw ProviderError.parsingFailed("No numeric iostat line found")
        }

        let values = latestDataLine
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .compactMap { Double($0) }

        guard values.count >= 3 else {
            throw ProviderError.parsingFailed("Unexpected iostat column count")
        }

        var combinedMBPerSecond = 0.0
        var index = 2
        while index < values.count {
            combinedMBPerSecond += values[index]
            index += 3
        }

        return combinedMBPerSecond * 1_000_000.0
    }
}
