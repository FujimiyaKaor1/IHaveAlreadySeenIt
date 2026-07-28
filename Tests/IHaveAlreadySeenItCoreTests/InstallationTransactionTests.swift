import Foundation
import IHaveAlreadySeenItCore
import Testing

@Suite struct InstallationTransactionTests {
    @Test
    func rejectsANonOfficialOriginalBeforeCreatingABackup() throws {
        let fixture = try makeInstallFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = FixtureProcessRunner()
        let verifier = FixedSignatureVerifier(status: .official(teamIdentifier: "WRONGTEAM"))
        let service = try makeService(resourceRoot: fixture.root, runner: runner, verifier: verifier)

        #expect(throws: InstallationServiceError.invalidOriginalSignature(
            .official(teamIdentifier: "WRONGTEAM")
        )) {
            try service.install(appURL: fixture.app, report: fixture.report)
        }
        #expect(!FileManager.default.fileExists(atPath: InstallationPaths(appURL: fixture.app).root.path))
        #expect(runner.invocations.isEmpty)
    }

    @Test
    func removesAPartialBackupWhenStagingFailsBeforeReplacement() throws {
        let fixture = try makeInstallFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = FixtureProcessRunner(failingExecutable: "/usr/bin/xattr")
        let service = try makeService(
            resourceRoot: fixture.root,
            runner: runner,
            verifier: InspectingSignatureVerifier()
        )

        #expect(throws: CommandExecutionError.self) {
            try service.install(appURL: fixture.app, report: fixture.report)
        }

        #expect(FileManager.default.fileExists(atPath: fixture.app.path))
        #expect(!FileManager.default.fileExists(atPath: InstallationPaths(appURL: fixture.app).root.path))
    }

    @Test
    func rejectsAnOfficialBackupWhoseExecutableChangedAfterInspection() throws {
        let fixture = try makeInstallFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = FixtureProcessRunner(mutateBackupAfterCopy: true)
        let service = try makeService(
            resourceRoot: fixture.root,
            runner: runner,
            verifier: InspectingSignatureVerifier()
        )

        #expect(throws: InstallationServiceError.restoredHashMismatch) {
            try service.install(appURL: fixture.app, report: fixture.report)
        }

        #expect(FileManager.default.fileExists(atPath: fixture.app.path))
        #expect(!FileManager.default.fileExists(atPath: InstallationPaths(appURL: fixture.app).root.path))
    }

    @Test
    func restoresTheOriginalWhenWritingStateFailsAfterReplacement() throws {
        let fixture = try makeInstallFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let originalHash = fixture.report.executableSHA256
        let runner = FixtureProcessRunner(createInvalidStatePath: true)
        let service = try makeService(
            resourceRoot: fixture.root,
            runner: runner,
            verifier: InspectingSignatureVerifier()
        )

        #expect(throws: (any Error).self) {
            try service.install(appURL: fixture.app, report: fixture.report)
        }

        let restored = try ApplicationInspector().inspect(appURL: fixture.app)
        #expect(restored.executableSHA256 == originalHash)
        #expect(restored.injection.slicesContainingDylib.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: InstallationPaths(appURL: fixture.app).state.path))
    }

    @Test
    func installsAndRestoresThroughTheCompleteTransaction() throws {
        let fixture = try makeInstallFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = FixtureProcessRunner()
        let service = try makeService(
            resourceRoot: fixture.root,
            runner: runner,
            verifier: InspectingSignatureVerifier()
        )
        var installStages: [InstallationStage] = []

        try service.install(appURL: fixture.app, report: fixture.report) { stage in
            installStages.append(stage)
        }

        let installed = try ApplicationInspector().inspect(appURL: fixture.app)
        let paths = InstallationPaths(appURL: fixture.app)
        #expect(installed.injection.slicesContainingDylib == Set(MachOArchitecture.allCases))
        #expect(FileManager.default.fileExists(atPath: paths.backupApp.path))
        #expect(FileManager.default.fileExists(atPath: paths.state.path))
        #expect(installStages == InstallationStage.allCases.filter { $0 != .rollingBack })

        try service.restore(appURL: fixture.app)

        let restored = try ApplicationInspector().inspect(appURL: fixture.app)
        #expect(restored.executableSHA256 == fixture.report.executableSHA256)
        #expect(restored.injection.slicesContainingDylib.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: paths.root.path))
    }

    @Test
    func putsThePatchedApplicationBackWhenFinalRestoreVerificationFails() throws {
        let fixture = try makeInstallFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = FixtureProcessRunner()
        let installService = try makeService(
            resourceRoot: fixture.root,
            runner: runner,
            verifier: InspectingSignatureVerifier()
        )
        try installService.install(appURL: fixture.app, report: fixture.report)
        let restoreService = try makeService(
            resourceRoot: fixture.root,
            runner: runner,
            verifier: FailingFinalRestoreVerifier(finalAppURL: fixture.app)
        )

        #expect(throws: InstallationServiceError.invalidBackupSignature) {
            try restoreService.restore(appURL: fixture.app)
        }

        let current = try ApplicationInspector().inspect(appURL: fixture.app)
        #expect(current.injection.slicesContainingDylib == Set(MachOArchitecture.allCases))
        #expect(FileManager.default.fileExists(atPath: InstallationPaths(appURL: fixture.app).backupApp.path))
    }

    @Test
    func restoresTheOfficialBackupWhenTheCurrentApplicationIsMissing() throws {
        let fixture = try makeInstallFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = FixtureProcessRunner()
        let service = try makeService(
            resourceRoot: fixture.root,
            runner: runner,
            verifier: InspectingSignatureVerifier()
        )
        try service.install(appURL: fixture.app, report: fixture.report)
        try FileManager.default.removeItem(at: fixture.app)

        try service.restore(appURL: fixture.app)

        let restored = try ApplicationInspector().inspect(appURL: fixture.app)
        #expect(restored.executableSHA256 == fixture.report.executableSHA256)
        #expect(!FileManager.default.fileExists(atPath: InstallationPaths(appURL: fixture.app).root.path))
    }

    @Test
    func refusesToRestoreWhenTheStateFileWasTamperedWith() throws {
        let fixture = try makeInstallFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runner = FixtureProcessRunner()
        let service = try makeService(
            resourceRoot: fixture.root,
            runner: runner,
            verifier: InspectingSignatureVerifier()
        )
        try service.install(appURL: fixture.app, report: fixture.report)
        let paths = InstallationPaths(appURL: fixture.app)
        try Data("not-json".utf8).write(to: paths.state)

        #expect(throws: InstallationServiceError.invalidInstallState) {
            try service.restore(appURL: fixture.app)
        }

        let current = try ApplicationInspector().inspect(appURL: fixture.app)
        #expect(current.injection.slicesContainingDylib == Set(MachOArchitecture.allCases))
        #expect(FileManager.default.fileExists(atPath: paths.backupApp.path))
    }

    private func makeService(
        resourceRoot: URL,
        runner: FixtureProcessRunner,
        verifier: any CodeSignatureVerifying
    ) throws -> InstallationService {
        let resources = resourceRoot.appendingPathComponent("TestResources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let hook = resources.appendingPathComponent("AntiRevokeHook.c")
        let entitlements = resources.appendingPathComponent("IHaveAlreadySeenIt.entitlements")
        try Data("int main(void) { return 0; }".utf8).write(to: hook)
        try Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>".utf8)
            .write(to: entitlements)
        return InstallationService(
            hookSourceURL: hook,
            entitlementsURL: entitlements,
            runner: runner,
            signatureVerifier: verifier
        )
    }

    private func makeInstallFixture() throws -> (root: URL, app: URL, report: ApplicationReport) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHaveAlreadySeenIt-InstallTests-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent("WeChat.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let executable = MachOFixture.universalBinary(includePatterns: true)
        let hash = SHA256Digest.hex(of: executable)
        let plist: [String: Any] = [
            "CFBundleExecutable": "WeChat",
            "CFBundleIdentifier": "com.tencent.xinWeChat",
            "CFBundleShortVersionString": "4.1.7",
            "CFBundleVersion": "34371",
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        try executable.write(to: macOS.appendingPathComponent("WeChat"))
        let rules = CompatibilityRules(rules: [
            CompatibilityRule(
                id: "fixture",
                version: try Version("4.1.7"),
                build: "34371",
                executableSHA256: [hash]
            ),
        ])
        let report = try ApplicationInspector(compatibilityRules: rules).inspect(appURL: app)
        return (root, app, report)
    }
}

private final class FixtureProcessRunner: @unchecked Sendable, ProcessRunning {
    private let failingExecutable: String?
    private let createInvalidStatePath: Bool
    private let mutateBackupAfterCopy: Bool
    private(set) var invocations: [(String, [String])] = []

    init(
        failingExecutable: String? = nil,
        createInvalidStatePath: Bool = false,
        mutateBackupAfterCopy: Bool = false
    ) {
        self.failingExecutable = failingExecutable
        self.createInvalidStatePath = createInvalidStatePath
        self.mutateBackupAfterCopy = mutateBackupAfterCopy
    }

    func run(
        _ executable: String,
        _ arguments: [String],
        allowedExitCodes: Set<Int32>
    ) throws -> CommandResult {
        invocations.append((executable, arguments))
        if executable == failingExecutable {
            throw CommandExecutionError.unexpectedExit(executable: executable, code: 1, output: "fixture failure")
        }
        switch executable {
        case "/usr/bin/pgrep":
            return CommandResult(exitCode: 1, output: "")
        case "/usr/bin/clang":
            try Data("fixture hook".utf8).write(to: URL(fileURLWithPath: arguments.last!))
        case "/usr/bin/ditto":
            let source = URL(fileURLWithPath: arguments[arguments.count - 2], isDirectory: true)
            let destination = URL(fileURLWithPath: arguments[arguments.count - 1], isDirectory: true)
            try FileManager.default.copyItem(at: source, to: destination)
            if mutateBackupAfterCopy, destination.lastPathComponent == "Original-WeChat.bundle" {
                let executable = destination.appendingPathComponent("Contents/MacOS/WeChat")
                var data = try Data(contentsOf: executable)
                data[data.count - 1] ^= 0x01
                try data.write(to: executable)
            }
        case "/usr/bin/codesign":
            if createInvalidStatePath, arguments.contains("--verify"),
               let appPath = arguments.last, appPath.contains("Stage-WeChat.bundle") {
                let stage = URL(fileURLWithPath: appPath, isDirectory: true)
                let state = stage.deletingLastPathComponent().appendingPathComponent("state.json")
                try? FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
            }
        default:
            break
        }
        return CommandResult(exitCode: 0, output: "")
    }
}

private struct FixedSignatureVerifier: CodeSignatureVerifying {
    let status: CodeSignatureStatus

    func status(of appURL: URL) throws -> CodeSignatureStatus { status }
}

private struct InspectingSignatureVerifier: CodeSignatureVerifying {
    func status(of appURL: URL) throws -> CodeSignatureStatus {
        let report = try ApplicationInspector().inspect(appURL: appURL)
        return report.injection.slicesContainingDylib.isEmpty
            ? .official(teamIdentifier: DiagnosticService.expectedTeamIdentifier)
            : .adHoc
    }
}

private struct FailingFinalRestoreVerifier: CodeSignatureVerifying {
    let finalAppURL: URL

    func status(of appURL: URL) throws -> CodeSignatureStatus {
        if appURL.standardizedFileURL == finalAppURL.standardizedFileURL {
            return .invalid(reason: "fixture final verification failure")
        }
        return .official(teamIdentifier: DiagnosticService.expectedTeamIdentifier)
    }
}
