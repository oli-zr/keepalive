// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "KeepAlive",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KeepAlive",
            path: "Sources/KeepAlive",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(
            name: "KeepAliveTests",
            dependencies: ["KeepAlive"],
            path: "Tests/KeepAliveTests"
        ),
    ]
)
