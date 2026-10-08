// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsageStatus",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexUsageStatus", targets: ["CodexUsageStatus"])
    ],
    targets: [
        .executableTarget(name: "CodexUsageStatus"),
        .testTarget(name: "CodexUsageStatusTests", dependencies: ["CodexUsageStatus"])
    ]
)
