// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HelioCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HelioCore", targets: ["HelioCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "HelioCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "HelioCoreTests", dependencies: ["HelioCore"]),
    ]
)
