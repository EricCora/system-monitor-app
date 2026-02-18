import Foundation
import Darwin
import PulseBarCore

@main
struct PulseBarPrivilegedHelperMain {
    static func main() async {
        let config = Configuration.parse(arguments: CommandLine.arguments)
        let server = PrivilegedTemperatureServer(socketPath: config.socketPath)

        do {
            try await server.run()
        } catch {
            fputs("PulseBarPrivilegedHelper fatal error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private struct Configuration {
    let socketPath: String

    static func parse(arguments: [String]) -> Configuration {
        var socketPath = "/tmp/pulsebar-temp.sock"

        var index = 1
        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--socket":
                if index + 1 < arguments.count {
                    socketPath = arguments[index + 1]
                    index += 2
                } else {
                    index += 1
                }
            default:
                index += 1
            }
        }

        return Configuration(socketPath: socketPath)
    }
}

private final class PrivilegedTemperatureServer {
    private let socketPath: String
    private let dataSource = CompositeTemperatureDataSource(
        primary: IOHIDTemperatureDataSource(),
        fallback: PowermetricsTemperatureDataSource()
    )
    private var listenFD: Int32 = -1

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func run() async throws {
        listenFD = try setupSocket(path: socketPath)
        defer { cleanupSocket(path: socketPath) }

        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR {
                    continue
                }
                try await Task.sleep(nanoseconds: 200_000_000)
                continue
            }

            await handle(clientFD: clientFD)
        }
    }

    private func handle(clientFD: Int32) async {
        disableSigPipe(on: clientFD)
        defer { close(clientFD) }

        guard let line = readLine(from: clientFD, maxBytes: 16 * 1024) else {
            // Connectivity probes may connect and close without sending payload.
            // Treat this as a no-op to avoid writing to a closed socket.
            return
        }

        let decoder = JSONDecoder()
        guard let request = try? decoder.decode(PrivilegedTemperatureRequest.self, from: line) else {
            write(response: .failure("Unable to decode request"), to: clientFD)
            return
        }

        switch request.command {
        case .sample:
            do {
                let reading = try await dataSource.readTemperatures()
                write(response: .success(reading, source: reading.source ?? "unknown"), to: clientFD)
            } catch {
                write(response: .failure(error.localizedDescription), to: clientFD)
            }
        }
    }

    private func setupSocket(path: String) throws -> Int32 {
        _ = unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "PulseBarHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create socket"])
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let utf8Path = path.utf8CString
        let maxPath = MemoryLayout.size(ofValue: address.sun_path)
        guard utf8Path.count <= maxPath else {
            close(fd)
            throw NSError(domain: "PulseBarHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Socket path too long"])
        }

        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: CChar.self, repeating: 0)
            _ = utf8Path.withUnsafeBufferPointer { pathBuffer in
                memcpy(buffer.baseAddress, pathBuffer.baseAddress, utf8Path.count)
            }
        }

        let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + utf8Path.count)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, addressLength) }
        }

        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw NSError(domain: "PulseBarHelper", code: 3, userInfo: [NSLocalizedDescriptionKey: "bind failed: \(message)"])
        }

        _ = chmod(path, 0o666)

        guard listen(fd, 8) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw NSError(domain: "PulseBarHelper", code: 4, userInfo: [NSLocalizedDescriptionKey: "listen failed: \(message)"])
        }

        return fd
    }

    private func cleanupSocket(path: String) {
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        _ = unlink(path)
    }

    private func readLine(from fd: Int32, maxBytes: Int) -> Data? {
        var collected = Data()
        collected.reserveCapacity(2048)

        var byte: UInt8 = 0
        while collected.count < maxBytes {
            let count = read(fd, &byte, 1)
            if count == 0 {
                break
            }
            if count < 0 {
                return nil
            }
            if byte == 10 {
                break
            }
            collected.append(byte)
        }

        guard !collected.isEmpty else { return nil }
        return collected
    }

    private func write(response: PrivilegedTemperatureResponse, to fd: Int32) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard var payload = try? encoder.encode(response) else {
            return
        }
        payload.append(0x0A)

        payload.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < rawBuffer.count {
                let result = Darwin.write(fd, base.advanced(by: sent), rawBuffer.count - sent)
                if result <= 0 {
                    break
                }
                sent += result
            }
        }
    }

    private func disableSigPipe(on fd: Int32) {
        var one: Int32 = 1
        _ = withUnsafePointer(to: &one) { pointer in
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, pointer, socklen_t(MemoryLayout<Int32>.size))
        }
    }
}
