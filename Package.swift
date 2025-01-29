// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ResticMac",
    platforms: [
        .macOS(.v13)  // Targeting macOS 13 (Ventura) for wider compatibility
    ],
    products: [
        .executable(
            name: "ResticMac",
            targets: ["ResticMac"]
        ),
    ],
    dependencies: [
        // Shell command execution
        .package(url: "https://github.com/kareman/SwiftShell.git", from: "5.1.0"),
        // Logging
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.3"),
        // KeychainAccess for secure password storage
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "ResticMac",
            dependencies: [
                "SwiftShell",
                .product(name: "Logging", package: "swift-log"),
                "KeychainAccess"
            ],
            path: "Sources/ResticMac",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ResticMacTests",
            dependencies: [
                "ResticMac",
                "SwiftShell",
                .product(name: "Logging", package: "swift-log"),
                "KeychainAccess"
            ],
            path: "Tests/ResticMacTests"
        ),
    ]
)