import Foundation
import WeChatGuardCore

func runPatchPlannerTests() throws {
    try test("prepares an injectable executable after every safety gate passes") {
        let fixture = MachOFixture.universalBinary(includePatterns: true)
        let hash = SHA256Digest.hex(of: fixture)
        let rules = CompatibilityRules(rules: [
            CompatibilityRule(
                id: "test-rule",
                version: try Version("4.1.7"),
                build: "34371",
                executableSHA256: [hash]
            ),
        ])
        let app = try makeFixtureApp(executable: fixture)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let report = try ApplicationInspector(compatibilityRules: rules).inspect(appURL: app)

        let patched = try PatchPlanner.prepareExecutable(fixture, report: report)
        let inspection = try MachOEditor.inspect(
            patched,
            dylibPath: ApplicationInspector.defaultDylibPath
        )
        try expect(inspection.slicesContainingDylib == Set([.arm64, .x86_64]))
    }

    try test("refuses to patch an executable with an unknown hash") {
        let fixture = MachOFixture.universalBinary(includePatterns: true)
        let app = try makeFixtureApp(executable: fixture)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let report = try ApplicationInspector().inspect(appURL: app)

        try expectThrows(PatchPlanningError.unknownExecutableHash) {
            try PatchPlanner.prepareExecutable(fixture, report: report)
        }
    }

    try test("refuses to patch when signatures are missing") {
        let fixture = MachOFixture.universalBinary(includePatterns: false)
        let hash = SHA256Digest.hex(of: fixture)
        let rules = CompatibilityRules(rules: [
            CompatibilityRule(
                id: "test-rule",
                version: try Version("4.1.7"),
                build: "34371",
                executableSHA256: [hash]
            ),
        ])
        let app = try makeFixtureApp(executable: fixture)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let report = try ApplicationInspector(compatibilityRules: rules).inspect(appURL: app)

        try expectThrows(PatchPlanningError.unsafeSignatureMatches) {
            try PatchPlanner.prepareExecutable(fixture, report: report)
        }
    }

    try test("detects a file change after inspection") {
        let fixture = MachOFixture.universalBinary(includePatterns: true)
        let hash = SHA256Digest.hex(of: fixture)
        let rules = CompatibilityRules(rules: [
            CompatibilityRule(
                id: "test-rule",
                version: try Version("4.1.7"),
                build: "34371",
                executableSHA256: [hash]
            ),
        ])
        let app = try makeFixtureApp(executable: fixture)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let report = try ApplicationInspector(compatibilityRules: rules).inspect(appURL: app)
        var changed = fixture
        changed[changed.count - 1] ^= 0x01

        try expectThrows(PatchPlanningError.executableChanged) {
            try PatchPlanner.prepareExecutable(changed, report: report)
        }
    }
}

private func makeFixtureApp(executable: Data) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeChatGuardPlannerTests-\(UUID().uuidString)", isDirectory: true)
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
    let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try plistData.write(to: contents.appendingPathComponent("Info.plist"))
    try executable.write(to: macOS.appendingPathComponent("WeChat"))
    return app
}
