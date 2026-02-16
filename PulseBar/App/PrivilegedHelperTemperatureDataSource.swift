import Foundation
import Darwin
import PulseBarCore

actor PrivilegedHelperLauncher {
    private var lastLaunchAttempt = Date.distantPast
    private let launchCooldownSeconds: TimeInterval
    private let socketReadyTimeoutSeconds: TimeInterval

    init(
        launchCooldownSeconds: TimeInterval = 20,
        socketReadyTimeoutSeconds: TimeInterval = 8
    ) {
        self.launchCooldownSeconds = launchCooldownSeconds
        self.socketReadyTimeoutSeconds = socketReadyTimeoutSeconds
    }

    func ensureRunning(socketPath: String) async throws {
        if canConnect(to: socketPath) {
            return
        }

        let now = Date()
        if now.timeIntervalSince(lastLaunchAttempt) < launchCooldownSeconds {
            throw ProviderError.unavailable("Privileged helper is not available yet")
        }

        lastLaunchAttempt = now

        let helperPath = try resolveHelperPath()
        try launchPrivilegedHelper(helperPath: helperPath, socketPath: socketPath)
        try await waitUntilReachable(socketPath: socketPath)
    }

    private func waitUntilReachable(socketPath: String) async throws {
        let deadline = Date().addingTimeInterval(socketReadyTimeoutSeconds)
        while Date() < deadline {
            if canConnect(to: socketPath) {
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        throw ProviderError.unavailable("Privileged helper did not become reachable")
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

    private func launchPrivilegedHelper(helperPath: String, socketPath: String) throws {
        let shellCommand = "\(helperPath.shellEscaped()) --socket \(socketPath.shellEscaped()) >/tmp/pulsebar_priv_helper.log 2>&1 &"
        let appleScript = "do shell script \"\(shellCommand.appleScriptEscaped())\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ProviderError.unavailable("Failed to request privileged helper launch: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stdErr = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if stdErr.lowercased().contains("user canceled") {
                throw ProviderError.unavailable("Administrator authorization was cancelled")
            }
            if stdErr.isEmpty {
                throw ProviderError.unavailable("Privileged helper launch failed")
            }
            throw ProviderError.unavailable(stdErr)
        }
    }

    private func canConnect(to socketPath: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

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
}

struct PrivilegedHelperTemperatureDataSource: TemperatureDataSource {
    private let socketPath: String
    private let launcher: PrivilegedHelperLauncher

    init(
        socketPath: String = "/tmp/pulsebar-temp.sock",
        launcher: PrivilegedHelperLauncher = PrivilegedHelperLauncher()
    ) {
        self.socketPath = socketPath
        self.launcher = launcher
    }

    func readTemperatures() async throws -> PowermetricsTemperatureReading {
        try await launcher.ensureRunning(socketPath: socketPath)

        let request = PrivilegedTemperatureRequest(command: .sample)
        let response = try sendRequest(request, socketPath: socketPath)

        guard response.ok else {
            throw ProviderError.unavailable(response.error ?? "Privileged helper returned an unknown failure")
        }
        guard let reading = response.reading else {
            throw ProviderError.parsingFailed("Privileged helper returned an empty reading")
        }
        return reading
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

        let responseData = try readLine(from: fd, maxBytes: 16 * 1024)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PrivilegedTemperatureResponse.self, from: responseData)
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

        var byte: UInt8 = 0
        while collected.count < maxBytes {
            let count = read(fd, &byte, 1)
            if count == 0 {
                break
            }
            if count < 0 {
                throw ProviderError.unavailable("Failed reading from privileged helper socket")
            }
            if byte == 10 {
                break
            }
            collected.append(byte)
        }

        guard !collected.isEmpty else {
            throw ProviderError.parsingFailed("Privileged helper returned an empty response")
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
