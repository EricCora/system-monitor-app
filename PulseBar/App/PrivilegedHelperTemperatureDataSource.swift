import Foundation
import Darwin
import PulseBarCore

actor PrivilegedHelperLauncher {
    private var lastLaunchAttempt = Date.distantPast
    private let launchCooldownSeconds: TimeInterval
    private let socketReadyTimeoutSeconds: TimeInterval
    private let connectionConfig: PrivilegedHelperConnectionConfig

    init(
        connectionConfig: PrivilegedHelperConnectionConfig = .default(expectedUID: Int32(getuid())),
        launchCooldownSeconds: TimeInterval = 20,
        socketReadyTimeoutSeconds: TimeInterval = 15
    ) {
        self.connectionConfig = connectionConfig
        self.launchCooldownSeconds = launchCooldownSeconds
        self.socketReadyTimeoutSeconds = socketReadyTimeoutSeconds
    }

    func ensureRunning() async throws {
        let socketPath = connectionConfig.socketPath
        if canConnect(to: socketPath) {
            return
        }

        let now = Date()
        if now.timeIntervalSince(lastLaunchAttempt) < launchCooldownSeconds {
            throw ProviderError.unavailable("Privileged helper is not available yet")
        }

        lastLaunchAttempt = now

        try ensureRuntimeDirectoryExists()
        let helperPath = try resolveHelperPath()
        try launchPrivilegedHelper(helperPath: helperPath)
        try await waitUntilReachable(socketPath: socketPath)
    }

    func isHelperReachable() -> Bool {
        canConnect(to: connectionConfig.socketPath)
    }

    private func waitUntilReachable(socketPath: String) async throws {
        let deadline = Date().addingTimeInterval(socketReadyTimeoutSeconds)
        while Date() < deadline {
            if canConnect(to: socketPath) {
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        let diagnostics = helperStartupDiagnostics(socketPath: socketPath)
        throw ProviderError.unavailable("Privileged helper did not become reachable (\(diagnostics))")
    }

    private func resolveHelperPath() throws -> String {
        let fileManager = FileManager.default
        let env = ProcessInfo.processInfo.environment

        let candidates: [String] = [
            env["PULSEBAR_PRIV_HELPER_PATH"],
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent("PulseBarPrivilegedHelper")
                .path,
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent(".build/debug/PulseBarPrivilegedHelper")
                .path
        ]
        .compactMap { $0 }

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        throw ProviderError.unavailable(
            "Privileged helper binary not found. Build PulseBarPrivilegedHelper target first."
        )
    }

    private func ensureRuntimeDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: connectionConfig.runtimeDirectoryPath),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func launchPrivilegedHelper(helperPath: String) throws {
        let cleanupAndLaunch = [
            "mkdir -p \(connectionConfig.runtimeDirectoryPath.shellEscaped())",
            "chmod 700 \(connectionConfig.runtimeDirectoryPath.shellEscaped())",
            "if [ -f \(connectionConfig.helperPIDPath.shellEscaped()) ]; then OLD_PID=$(cat \(connectionConfig.helperPIDPath.shellEscaped()) 2>/dev/null || true); if [ -n \"$OLD_PID\" ]; then kill \"$OLD_PID\" >/dev/null 2>&1 || true; fi; fi",
            "rm -f \(connectionConfig.socketPath.shellEscaped())",
            helperLaunchCommand(helperPath: helperPath)
        ].joined(separator: "; ")
        let shellCommand = cleanupAndLaunch
        let appleScript = "do shell script \"\(shellCommand.appleScriptEscaped())\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ProviderError.unavailable("Failed to request privileged helper launch: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stdOut = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stdErr = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let combined = "\(stdOut) \(stdErr)".trimmingCharacters(in: .whitespacesAndNewlines)
            let combinedLower = combined.lowercased()
            if combinedLower.contains("user canceled")
                || combinedLower.contains("user cancelled")
                || combinedLower.contains("cancelled")
                || combinedLower.contains("canceled")
                || combinedLower.contains("error -128") {
                throw ProviderError.unavailable("Administrator authorization was cancelled")
            }
            if combined.isEmpty {
                throw ProviderError.unavailable("Privileged helper launch failed (osascript exit \(process.terminationStatus))")
            }
            throw ProviderError.unavailable("Privileged helper launch failed (osascript exit \(process.terminationStatus)): \(combined)")
        }
    }

    private func helperLaunchCommand(helperPath: String) -> String {
        var command = "\(helperPath.shellEscaped()) --socket \(connectionConfig.socketPath.shellEscaped())"
        if let expectedUID = connectionConfig.expectedUID {
            command += " --expected-uid \(expectedUID)"
        }
        command += " >\(connectionConfig.helperLogPath.shellEscaped()) 2>&1 & echo $! >\(connectionConfig.helperPIDPath.shellEscaped())"
        return command
    }

    private func canConnect(to socketPath: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        disableSigPipeOnSocket(fd)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let utf8Path = socketPath.utf8CString
        let maxPath = MemoryLayout.size(ofValue: address.sun_path)
        guard utf8Path.count <= maxPath else { return false }

        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: CChar.self, repeating: 0)
            _ = utf8Path.withUnsafeBufferPointer { pathBuffer in
                memcpy(buffer.baseAddress, pathBuffer.baseAddress, utf8Path.count)
            }
        }

        let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + utf8Path.count)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, addressLength) }
        }
        return result == 0
    }

    private func helperStartupDiagnostics(socketPath: String) -> String {
        let fileManager = FileManager.default
        let socketExists = fileManager.fileExists(atPath: socketPath)
        var details: [String] = []
        details.append(socketExists ? "socket exists" : "socket missing")
        details.append(helperProcessState())

        if let logTail = readLogTail(path: connectionConfig.helperLogPath), !logTail.isEmpty {
            details.append("helper log: \(logTail)")
        } else {
            details.append("no helper log output")
        }

        return details.joined(separator: "; ")
    }

    private func helperProcessState() -> String {
        guard let data = FileManager.default.contents(atPath: connectionConfig.helperPIDPath),
              let pidString = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidString),
              pid > 0 else {
            return "pid missing"
        }

        let result = kill(pid, 0)
        if result == 0 || errno == EPERM {
            return "pid \(pid) active"
        }
        return "pid \(pid) not running"
    }

    private func readLogTail(path: String, maxLength: Int = 200) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " | ")
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxLength {
            return trimmed
        }
        return String(trimmed.suffix(maxLength))
    }

    private func disableSigPipeOnSocket(_ fd: Int32) {
        var one: Int32 = 1
        _ = withUnsafePointer(to: &one) { pointer in
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, pointer, socklen_t(MemoryLayout<Int32>.size))
        }
    }
}

struct PrivilegedHelperTemperatureDataSource: TemperatureDataSource {
    private let connectionConfig: PrivilegedHelperConnectionConfig
    private let launcher: PrivilegedHelperLauncher
    private let channelBackfillSource: TemperatureDataSource

    init(
        connectionConfig: PrivilegedHelperConnectionConfig = .default(expectedUID: Int32(getuid())),
        launcher: PrivilegedHelperLauncher? = nil,
        channelBackfillSource: TemperatureDataSource = IOHIDTemperatureDataSource()
    ) {
        self.connectionConfig = connectionConfig
        self.launcher = launcher ?? PrivilegedHelperLauncher(connectionConfig: connectionConfig)
        self.channelBackfillSource = channelBackfillSource
    }

    func isHelperReachableWithoutLaunching() async -> Bool {
        await launcher.isHelperReachable()
    }

    func readTemperatures() async throws -> PowermetricsTemperatureReading {
        try await launcher.ensureRunning()

        let request = PrivilegedTemperatureRequest(command: .sample)
        let response = try sendRequest(request, socketPath: connectionConfig.socketPath)

        guard response.ok else {
            throw ProviderError.unavailable(response.error ?? "Privileged helper returned an unknown failure")
        }
        guard let reading = response.reading else {
            throw ProviderError.parsingFailed("Privileged helper returned an empty reading")
        }
        return await backfillChannelsIfNeeded(reading)
    }

    private func backfillChannelsIfNeeded(_ reading: PowermetricsTemperatureReading) async -> PowermetricsTemperatureReading {
        guard reading.channels.isEmpty else {
            return reading
        }

        guard let fallback = try? await channelBackfillSource.readTemperatures(),
              !fallback.channels.isEmpty else {
            return reading
        }

        let primary = reading.primaryCelsius > 0 ? reading.primaryCelsius : fallback.primaryCelsius
        let max = max(reading.maxCelsius, fallback.maxCelsius)
        let source = reading.source ?? fallback.source ?? "iohid"
        let chain = mergedSourceChain(primary: reading.sourceChain, fallback: fallback.sourceChain)
        let diagnostics = mergedDiagnostics(primary: reading.sourceDiagnostics)

        return PowermetricsTemperatureReading(
            primaryCelsius: primary,
            maxCelsius: max,
            sensorCount: fallback.sensorCount,
            sensors: fallback.sensors,
            channels: fallback.channels,
            source: source,
            sourceChain: chain,
            sourceDiagnostics: diagnostics,
            fanTelemetryAvailable: reading.fanTelemetryAvailable,
            fanCount: reading.fanCount
        )
    }

    private func mergedSourceChain(primary: [String], fallback: [String]) -> [String] {
        var result: [String] = []
        for item in primary where !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !result.contains(item) {
                result.append(item)
            }
        }
        for item in fallback where !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !result.contains(item) {
                result.append(item)
            }
        }
        if !result.contains("app-iohid-backfill") {
            result.append("app-iohid-backfill")
        }
        return result
    }

    private func mergedDiagnostics(primary: [SensorSourceDiagnostic]) -> [SensorSourceDiagnostic] {
        var diagnostics = primary
        diagnostics.append(
            SensorSourceDiagnostic(
                source: "app-iohid-backfill",
                healthy: true,
                message: "Filled missing helper channels from direct IOHID probe"
            )
        )
        return diagnostics
    }

    private func sendRequest(
        _ request: PrivilegedTemperatureRequest,
        socketPath: String
    ) throws -> PrivilegedTemperatureResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ProviderError.unavailable("Unable to create helper client socket")
        }
        defer { close(fd) }
        disableSigPipe(on: fd)
        setSocketTimeout(fd: fd, seconds: 25)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let utf8Path = socketPath.utf8CString
        let maxPath = MemoryLayout.size(ofValue: address.sun_path)
        guard utf8Path.count <= maxPath else {
            throw ProviderError.unavailable("Helper socket path too long")
        }

        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: CChar.self, repeating: 0)
            _ = utf8Path.withUnsafeBufferPointer { pathBuffer in
                memcpy(buffer.baseAddress, pathBuffer.baseAddress, utf8Path.count)
            }
        }

        let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + utf8Path.count)
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, addressLength) }
        }
        guard connectResult == 0 else {
            throw ProviderError.unavailable("Unable to connect to privileged helper")
        }

        let encoder = JSONEncoder()
        var payload = try encoder.encode(request)
        payload.append(0x0A)
        try writeAll(payload, to: fd)

        let responseData = try readLine(from: fd, maxBytes: 256 * 1024)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PrivilegedTemperatureResponse.self, from: responseData)
    }

    private func disableSigPipe(on fd: Int32) {
        var one: Int32 = 1
        _ = withUnsafePointer(to: &one) { pointer in
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, pointer, socklen_t(MemoryLayout<Int32>.size))
        }
    }

    private func setSocketTimeout(fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) { ptr in
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
        }
        _ = withUnsafePointer(to: &timeout) { ptr in
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
        }
    }

    private func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < rawBuffer.count {
                let result = Darwin.write(fd, base.advanced(by: sent), rawBuffer.count - sent)
                if result <= 0 {
                    throw ProviderError.unavailable("Failed writing to privileged helper socket")
                }
                sent += result
            }
        }
    }

    private func readLine(from fd: Int32, maxBytes: Int) throws -> Data {
        var collected = Data()
        collected.reserveCapacity(2048)
        var reachedLimit = false

        var byte: UInt8 = 0
        while collected.count < maxBytes {
            let count = read(fd, &byte, 1)
            if count == 0 {
                break
            }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw ProviderError.unavailable("Privileged helper request timed out")
                }
                throw ProviderError.unavailable("Failed reading from privileged helper socket")
            }
            if byte == 10 {
                break
            }
            collected.append(byte)
        }

        if collected.count >= maxBytes {
            reachedLimit = true
        }

        guard !collected.isEmpty else {
            throw ProviderError.parsingFailed("Privileged helper returned an empty response")
        }
        if reachedLimit {
            throw ProviderError.unavailable("Privileged helper response exceeded read buffer limit")
        }
        return collected
    }
}

private extension String {
    func shellEscaped() -> String {
        let escaped = replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    func appleScriptEscaped() -> String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
