import Foundation
import IHaveAlreadySeenItCore
import Testing

@Suite struct PatchPlannerTests {
    @Test
    func testPreparesInjectableExecutableAfterEverySafetyGatePasses() throws {
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
        #expect(inspection.slicesContainingDylib == Set([.arm64, .x86_64]))
    }

    @Test
    func testRefusesUnknownExecutableHash() throws {
        let fixture = MachOFixture.universalBinary(includePatterns: true)
        let app = try makeFixtureApp(executable: fixture)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let report = try ApplicationInspector().inspect(appURL: app)

        do {
            _ = try PatchPlanner.prepareExecutable(fixture, report: report)
            Issue.record("expected an unknown hash error")
        } catch {
            #expect(error as? PatchPlanningError == .unknownExecutableHash)
        }
    }

    @Test
    func testRefusesWhenSignaturesAreMissing() throws {
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

        do {
            _ = try PatchPlanner.prepareExecutable(fixture, report: report)
            Issue.record("expected an unsafe signature error")
        } catch {
            #expect(error as? PatchPlanningError == .unsafeSignatureMatches)
        }
    }

    @Test
    func testDetectsFileChangeAfterInspection() throws {
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

        do {
            _ = try PatchPlanner.prepareExecutable(changed, report: report)
            Issue.record("expected an executable-changed error")
        } catch {
            #expect(error as? PatchPlanningError == .executableChanged)
        }
    }
}

private func makeFixtureApp(executable: Data) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("IHaveAlreadySeenItPlannerTests-\(UUID().uuidString)", isDirectory: true)
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
