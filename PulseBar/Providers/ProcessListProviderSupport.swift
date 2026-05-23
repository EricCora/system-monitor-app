import Foundation

public enum ProcessListProviderSupport {
    public static func cpuProcessOutput() throws -> String {
        try runPSOutput(arguments: ["-axo", "pid=,%cpu=,comm="])
    }

    public static func memoryProcessOutput() throws -> String {
        try runPSOutput(arguments: ["-axo", "pid=,rss=,comm="])
    }

    public static func runPSOutput(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = errorOutput?.isEmpty == false
                ? errorOutput!
                : "ps exited with status \(process.terminationStatus)"
            throw ProviderError.unavailable(message)
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw ProviderError.parsingFailed("Unable to decode ps output")
        }
        return output
    }

    static func parseLegacyCPULine(_ trimmed: String) -> (name: String, value: Double)? {
        guard let cpuStart = trimmed.firstIndex(where: { !$0.isWhitespace }) else {
            return nil
        }
        guard let splitIndex = trimmed[cpuStart...].firstIndex(where: \.isWhitespace) else {
            return nil
        }

        let cpuToken = String(trimmed[cpuStart..<splitIndex])
            .replacingOccurrences(of: ",", with: ".")
        guard let cpuPercent = Double(cpuToken), cpuPercent >= 0 else {
            return nil
        }

        let nameToken = trimmed[splitIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nameToken.isEmpty else { return nil }
        return (nameToken, cpuPercent)
    }
}
