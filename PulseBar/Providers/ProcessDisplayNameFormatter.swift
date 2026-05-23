import Foundation

enum ProcessDisplayNameFormatter {
    static func format(executablePath: String, fallback: String) -> String {
        let path = executablePath.isEmpty ? fallback : executablePath
        if let appName = bundleDisplayName(in: path) {
            return appName
        }

        let last = (path as NSString).lastPathComponent
        if !last.isEmpty, last != "/" {
            return last
        }
        return fallback
    }

    private static func bundleDisplayName(in path: String) -> String? {
        for component in path.split(separator: "/") {
            let segment = String(component)
            if segment.lowercased().hasSuffix(".app") {
                return String(segment.dropLast(4))
            }
        }
        return nil
    }
}
