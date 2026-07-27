// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WeChatGuard",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WeChatGuardCore", targets: ["WeChatGuardCore"]),
        .executable(name: "wechatguard", targets: ["wechatguard"]),
    ],
    targets: [
        .target(name: "WeChatGuardCore"),
        .executableTarget(
            name: "wechatguard",
            dependencies: ["WeChatGuardCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "wechatguard-tests",
            dependencies: ["WeChatGuardCore"],
            path: "Tests/WeChatGuardCoreTests"
        ),
    ]
)
