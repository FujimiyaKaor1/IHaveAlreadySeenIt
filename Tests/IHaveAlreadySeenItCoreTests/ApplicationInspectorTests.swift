import Foundation
import IHaveAlreadySeenItCore
import Testing

@Suite struct ApplicationInspectorTests {
    @Test
    func testComputesStandardSHA256Digest() {
        let digest = SHA256Digest.hex(of: Data("abc".utf8))
        #expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test
    func testInspectsLocalWeChatStyleAppBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHaveAlreadySeenItTests-\(UUID().uuidString)", isDirectory: true)
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
        #expect(report.bundleIdentifier == "com.tencent.xinWeChat")
        #expect(report.version == expectedVersion)
        #expect(report.build == "34371")
        #expect(report.signatureScan.isSafeToPatch)
        #expect(report.injection.architectures == Set([.arm64, .x86_64]))
        #expect(report.injection.slicesContainingDylib.isEmpty)
    }

    @Test
    func testRejectsUnexpectedBundleIdentifier() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHaveAlreadySeenItTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Fake.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "example.fake"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        do {
            _ = try ApplicationInspector().inspect(appURL: root.appendingPathComponent("Fake.app"))
            Issue.record("expected an unexpected bundle identifier error")
        } catch {
            #expect(error as? ApplicationInspectionError == .unexpectedBundleIdentifier("example.fake"))
        }
    }

    @Test
    func testRejectsMissingAppBundle() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Missing-IHaveAlreadySeenIt-\(UUID().uuidString).app")
        do {
            _ = try ApplicationInspector().inspect(appURL: missing)
            Issue.record("expected an app-not-found error")
        } catch {
            #expect(error as? ApplicationInspectionError == .appNotFound(missing.path))
        }
    }

    @Test
    func testRejectsUnsafeExecutableName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHaveAlreadySeenItTests-\(UUID().uuidString)", isDirectory: true)
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

        do {
            _ = try ApplicationInspector().inspect(appURL: app)
            Issue.record("expected an invalid executable name error")
        } catch {
            #expect(error as? ApplicationInspectionError == .invalidExecutableName)
        }
    }

    @Test
    func testRejectsMissingExecutable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHaveAlreadySeenItTests-\(UUID().uuidString)", isDirectory: true)
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

        do {
            _ = try ApplicationInspector().inspect(appURL: app)
            Issue.record("expected an executable-not-found error")
        } catch {
            #expect(error as? ApplicationInspectionError == .executableNotFound(missing.path))
        }
    }
}
