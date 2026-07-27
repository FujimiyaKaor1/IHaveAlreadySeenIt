import Foundation
import WeChatGuardCore

func runApplicationInspectorTests() throws {
    try test("computes a standard SHA-256 digest") {
        let digest = SHA256Digest.hex(of: Data("abc".utf8))
        try expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    try test("inspects a local WeChat-style app bundle") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeChatGuardTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("WeChat.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleExecutable": "WeChat",
            "CFBundleIdentifier": "com.tencent.xinWeChat",
            "CFBundleShortVersionString": "4.1.7",
            "CFBundleVersion": "34371",
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        let executableData = MachOFixture.universalBinary(includePatterns: true)
        try executableData.write(to: macOS.appendingPathComponent("WeChat"))

        let report = try ApplicationInspector().inspect(appURL: app)
        let expectedVersion = try Version("4.1.7")
        try expect(report.bundleIdentifier == "com.tencent.xinWeChat")
        try expect(report.version == expectedVersion)
        try expect(report.build == "34371")
        try expect(report.signatureScan.isSafeToPatch)
        try expect(report.injection.architectures == Set([.arm64, .x86_64]))
        try expect(report.injection.slicesContainingDylib.isEmpty)
    }

    try test("rejects an unexpected bundle identifier") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeChatGuardTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Fake.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "example.fake"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        try expectThrows(ApplicationInspectionError.unexpectedBundleIdentifier("example.fake")) {
            try ApplicationInspector().inspect(appURL: root.appendingPathComponent("Fake.app"))
        }
    }

    try test("rejects a missing app bundle") {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Missing-WeChatGuard-\(UUID().uuidString).app")
        try expectThrows(ApplicationInspectionError.appNotFound(missing.path)) {
            try ApplicationInspector().inspect(appURL: missing)
        }
    }

    try test("rejects an unsafe executable name") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeChatGuardTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("WeChat.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.tencent.xinWeChat",
            "CFBundleExecutable": "../Other",
            "CFBundleShortVersionString": "4.1.7",
            "CFBundleVersion": "34371",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        try expectThrows(ApplicationInspectionError.invalidExecutableName) {
            try ApplicationInspector().inspect(appURL: app)
        }
    }

    try test("rejects a missing executable") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeChatGuardTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("WeChat.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.tencent.xinWeChat",
            "CFBundleExecutable": "WeChat",
            "CFBundleShortVersionString": "4.1.7",
            "CFBundleVersion": "34371",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        let missing = contents.appendingPathComponent("MacOS/WeChat")

        try expectThrows(ApplicationInspectionError.executableNotFound(missing.path)) {
            try ApplicationInspector().inspect(appURL: app)
        }
    }
}
