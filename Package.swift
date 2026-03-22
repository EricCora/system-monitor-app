// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PulseBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PulseBarCore",
            targets: ["PulseBarCore"]
        ),
        .executable(
            name: "PulseBarApp",
            targets: ["PulseBarApp"]
        ),
        .executable(
            name: "PulseBarPrivilegedHelper",
            targets: ["PulseBarPrivilegedHelper"]
        )
    ],
    targets: [
        .target(
            name: "PulseBarSMCBridge",
            path: "PulseBarSMCBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "PulseBarCore",
            path: "PulseBar",
            exclude: [
                "App",
                "UI",
                "Resources"
            ],
            sources: [
                "Core",
                "Providers",
                "Alerts"
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "PulseBarApp",
            dependencies: ["PulseBarCore"],
            path: "PulseBar",
            exclude: [
                "Core",
                "Providers",
                "Alerts"
            ],
            sources: [
                "App",
                "UI"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("Charts"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "PulseBarPrivilegedHelper",
            dependencies: ["PulseBarCore", "PulseBarSMCBridge"],
            path: "PulseBarHelper",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["PulseBarCore"],
            path: "Tests/CoreTests"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["PulseBarApp"],
            path: "Tests/AppTests"
        )
    ]
)
