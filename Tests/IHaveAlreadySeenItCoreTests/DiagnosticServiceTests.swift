import Foundation
import IHaveAlreadySeenItCore
import Testing

@Suite struct DiagnosticServiceTests {
    @Test
    func reportsASupportedOfficialApplication() throws {
        let fixture = try makeDiagnosticFixture(injected: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = DiagnosticService(
            inspector: ApplicationInspector(compatibilityRules: fixture.rules),
            signatureVerifier: FixedDiagnosticSignatureVerifier(status: .official(teamIdentifier: "5A4RE8SF68"))
        )

        let report = try service.report(appURL: fixture.app)

        #expect(report.compatibility == .supported(ruleID: "diagnostic-fixture"))
        #expect(report.installation == .notInstalled)
        #expect(report.backup == .missing)
        #expect(report.isSafeToInstall)
    }

    @Test
    func reportsAnInstalledAdHocApplicationAndValidBackup() throws {
        let fixture = try makeDiagnosticFixture(injected: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let paths = InstallationPaths(appURL: fixture.app)
        let backup = paths.backupApp
        let backupContents = backup.appendingPathComponent("Contents", isDirectory: true)
        let backupMacOS = backupContents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: backupMacOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: fixture.app.appendingPathComponent("Contents/Info.plist"),
            to: backupContents.appendingPathComponent("Info.plist")
        )
        let originalExecutable = MachOFixture.universalBinary(includePatterns: true)
        try originalExecutable.write(to: backupMacOS.appendingPathComponent("WeChat"))
        let state = InstallationStateMetadata(
            schemaVersion: 2,
            appPath: fixture.app.path,
            originalSHA256: SHA256Digest.hex(of: originalExecutable),
            installedAt: Date(timeIntervalSince1970: 0),
            toolVersion: "fixture"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: paths.state)
        let service = DiagnosticService(
            inspector: ApplicationInspector(compatibilityRules: fixture.rules),
            signatureVerifier: PathAwareDiagnosticSignatureVerifier(backupURL: backup)
        )

        let report = try service.report(appURL: fixture.app)

        #expect(report.codeSignature == .adHoc)
        #expect(report.installation == .installed(architectures: ["arm64", "x86_64"]))
        #expect(report.backup == .present)
        #expect(!report.isSafeToInstall)
    }

    private func makeDiagnosticFixture(
        injected: Bool
    ) throws -> (root: URL, app: URL, rules: CompatibilityRules) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHaveAlreadySeenIt-DiagnosticTests-\(UUID().uuidString)", isDirectory: true)
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
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        var executable = MachOFixture.universalBinary(includePatterns: true)
        if injected {
            executable = try MachOEditor.injectLoadDylib(
                path: ApplicationInspector.defaultDylibPath,
                into: executable
            )
        }
        try executable.write(to: macOS.appendingPathComponent("WeChat"))
        let rules = CompatibilityRules(rules: [
            CompatibilityRule(
                id: "diagnostic-fixture",
                version: try Version("4.1.7"),
                build: "34371",
                executableSHA256: [SHA256Digest.hex(of: executable)]
            ),
        ])
        return (root, app, rules)
    }
}

private struct FixedDiagnosticSignatureVerifier: CodeSignatureVerifying {
    let status: CodeSignatureStatus
    func status(of appURL: URL) throws -> CodeSignatureStatus { status }
}

private struct PathAwareDiagnosticSignatureVerifier: CodeSignatureVerifying {
    let backupURL: URL

    func status(of appURL: URL) throws -> CodeSignatureStatus {
        appURL.standardizedFileURL == backupURL.standardizedFileURL
            ? .official(teamIdentifier: DiagnosticService.expectedTeamIdentifier)
            : .adHoc
    }
}
