// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HelioBar",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "HelioBar", targets: ["HelioBar"]),
        .executable(name: "HelioBLEInspector", targets: ["HelioBLEInspector"]),
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
                "MenuBarIcon.swift",
                "UpdateChecker.swift",
                "Views",
            ]
        ),
        .executableTarget(
            name: "HelioBLEInspector",
            path: "Tools/HelioBLEInspector"
        ),
    ]
)
