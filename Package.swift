// swift-tools-version: 6.0

import Foundation
import PackageDescription

let commandLineToolsFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let commandLineToolsDeveloperLibraries = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
let commandLineToolsTestingSettings: [SwiftSetting] = FileManager.default.fileExists(
    atPath: "\(commandLineToolsFrameworks)/Testing.framework"
) ? [.unsafeFlags(["-F", commandLineToolsFrameworks])] : []
let commandLineToolsTestingLinkerSettings: [LinkerSetting] = commandLineToolsTestingSettings.isEmpty
    ? []
    : [.unsafeFlags([
        "-F", commandLineToolsFrameworks,
        "-Xlinker", "-rpath",
        "-Xlinker", commandLineToolsFrameworks,
        "-Xlinker", "-rpath",
        "-Xlinker", commandLineToolsDeveloperLibraries,
    ])]

let package = Package(
    name: "IHaveAlreadySeenIt",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IHaveAlreadySeenItCore", targets: ["IHaveAlreadySeenItCore"]),
        .executable(name: "ihavealreadyseenit", targets: ["ihavealreadyseenit"]),
        .executable(name: "IHaveAlreadySeenItApp", targets: ["IHaveAlreadySeenItApp"]),
        .executable(
            name: "IHaveAlreadySeenItPrivilegedHelper",
            targets: ["IHaveAlreadySeenItPrivilegedHelper"]
        ),
        .executable(name: "ihavealreadyseenit-tests", targets: ["ihavealreadyseenit-tests"]),
    ],
    targets: [
        .target(name: "IHaveAlreadySeenItCore", resources: [.process("Resources")]),
        .executableTarget(
            name: "ihavealreadyseenit",
            dependencies: ["IHaveAlreadySeenItCore"]
        ),
        .executableTarget(
            name: "IHaveAlreadySeenItApp",
            dependencies: ["IHaveAlreadySeenItCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "IHaveAlreadySeenItPrivilegedHelper",
            dependencies: ["IHaveAlreadySeenItCore"]
        ),
        .target(
            name: "IHaveAlreadySeenItTestSuite",
            dependencies: ["IHaveAlreadySeenItCore"],
            path: "Tests/IHaveAlreadySeenItCoreTests",
            swiftSettings: commandLineToolsTestingSettings
        ),
        .executableTarget(
            name: "ihavealreadyseenit-tests",
            dependencies: ["IHaveAlreadySeenItTestSuite"],
            path: "Tests/TestRunner",
            swiftSettings: commandLineToolsTestingSettings,
            linkerSettings: commandLineToolsTestingLinkerSettings
        ),
        .testTarget(
            name: "IHaveAlreadySeenItCoreTests",
            dependencies: ["IHaveAlreadySeenItTestSuite"],
            path: "Tests/TestDiscovery",
            swiftSettings: commandLineToolsTestingSettings,
            linkerSettings: commandLineToolsTestingLinkerSettings
        ),
    ]
)
