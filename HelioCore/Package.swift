// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HelioCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HelioCore", targets: ["HelioCore"]),
    ],
    targets: [
        .target(name: "HelioCore"),
        .testTarget(name: "HelioCoreTests", dependencies: ["HelioCore"]),
    ]
)
