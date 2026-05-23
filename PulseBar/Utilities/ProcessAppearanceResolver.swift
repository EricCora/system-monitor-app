import AppKit
import SwiftUI

enum ProcessAppearanceResolver {
    private static let iconCache = NSCache<NSString, NSImage>()

    static func icon(forExecutablePath path: String) -> NSImage? {
        guard path.hasPrefix("/") else { return nil }
        let key = path as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        iconCache.setObject(icon, forKey: key)
        return icon
    }

    @ViewBuilder
    static func iconView(forExecutablePath path: String, size: CGFloat = 16) -> some View {
        if let icon = icon(forExecutablePath: path) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "gearshape.fill")
                .font(.system(size: size - 2))
                .foregroundStyle(DashboardPalette.tertiaryText)
                .frame(width: size, height: size)
        }
    }

    static func helpText(executablePath: String, fallbackName: String) -> String {
        if executablePath.hasPrefix("/") {
            return executablePath
        }
        return fallbackName
    }
}
