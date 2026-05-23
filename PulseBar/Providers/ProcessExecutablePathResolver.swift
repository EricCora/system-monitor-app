import Darwin
import Foundation

enum ProcessExecutablePathResolver {
    private static let maxPathLength = 4_096

    static func executablePath(pid: Int32, comm: String) -> String {
        let trimmed = comm.trimmingCharacters(in: .whitespacesAndNewlines)
        // Prefer ps `comm` when it already looks like a filesystem path (common on macOS).
        if trimmed.contains("/") {
            return trimmed
        }
        if pid > 0, let resolved = procPidPath(pid), !resolved.isEmpty {
            return resolved
        }
        return trimmed
    }

    private static func procPidPath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: maxPathLength)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
