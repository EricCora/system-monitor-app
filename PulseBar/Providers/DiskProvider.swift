import Foundation

public struct DiskProvider: MetricProvider {
    public let providerID = "disk"

    public init() {}

    public func sample(at date: Date) async throws -> [MetricSample] {
        let freeBytes = readFreeSpaceBytes()
        let throughputBytesPerSec = (try? readCombinedThroughputBytesPerSecond()) ?? 0

        return [
            MetricSample(metricID: .diskFreeBytes, timestamp: date, value: freeBytes, unit: .bytes),
            MetricSample(
                metricID: .diskThroughputBytesPerSec,
                timestamp: date,
                value: throughputBytesPerSec,
                unit: .bytesPerSecond
            )
        ]
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
