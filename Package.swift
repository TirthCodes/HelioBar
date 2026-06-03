// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HelioBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HelioBar", targets: ["HelioBar"]),
    ],
    dependencies: [
        .package(path: "HelioCore"),
    ],
    targets: [
        .executableTarget(
            name: "HelioBar",
            dependencies: ["HelioCore"],
            path: "HelioBarApp",
            exclude: ["Resources"],
            sources: [
                "HelioBarApp.swift",
                "AppModel.swift",
                "HeartRateMonitor.swift",
                "Views",
            ]
        ),
    ]
)
