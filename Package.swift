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
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "PulseBarPrivilegedHelper",
            dependencies: ["PulseBarCore"],
            path: "PulseBarHelper"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["PulseBarCore"],
            path: "Tests/CoreTests"
        )
    ]
)
