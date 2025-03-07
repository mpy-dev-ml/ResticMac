// swift-tools-version: 5.9.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ResticMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ResticMac",
            targets: ["ResticMac"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/kareman/SwiftShell.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.3"),
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
            exclude: [
                "Views/_disabled",
                "Services/_disabled",
                "Views/CloudSettings",
                "Views/CloudTransfer",
                "Services/CloudError",
                "Services/CloudOptimizer"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("ForwardTrailingClosures"),
                .enableUpcomingFeature("ImplicitOpenExistentials"),
                .enableUpcomingFeature("StrictConcurrency")
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
            path: "Tests/ResticMacTests",
            exclude: [
                "CloudAnalytics"
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("ForwardTrailingClosures"),
                .enableUpcomingFeature("ImplicitOpenExistentials"),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)
