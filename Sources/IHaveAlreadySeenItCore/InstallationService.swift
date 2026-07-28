import Darwin
import Foundation

public enum InstallationStage: String, Codable, CaseIterable, Sendable {
    case validating
    case backingUp
    case staging
    case injecting
    case signing
    case verifying
    case replacing
    case writingState
    case completed
    case rollingBack
}

public enum InstallationServiceError: Error, Equatable, Sendable {
    case weChatIsRunning
    case needsPrivileges
    case backupAlreadyExists(String)
    case backupMissing(String)
    case invalidBackupSignature
    case invalidInstallState
    case invalidOriginalSignature(CodeSignatureStatus)
    case resourceMissing(String)
    case postInstallVerificationFailed
    case restoredHashMismatch
    case rollbackFailed(original: String, rollback: String)
}

public typealias InstallerError = InstallationServiceError

public struct InstallationService: @unchecked Sendable {
    public static let toolVersion = "0.2.0"

    private let runner: any ProcessRunning
    private let signatureVerifier: any CodeSignatureVerifying
    private let fileManager: FileManager
    private let hookSourceURL: URL
    private let entitlementsURL: URL

    public init(
        hookSourceURL: URL,
        entitlementsURL: URL,
        runner: any ProcessRunning = SystemProcessRunner(),
        signatureVerifier: (any CodeSignatureVerifying)? = nil,
        fileManager: FileManager = .default
    ) {
        self.hookSourceURL = hookSourceURL
        self.entitlementsURL = entitlementsURL
        self.runner = runner
        self.signatureVerifier = signatureVerifier ?? SystemCodeSignatureVerifier(runner: runner)
        self.fileManager = fileManager
    }

    public static func bundled(
        runner: any ProcessRunning = SystemProcessRunner(),
        signatureVerifier: (any CodeSignatureVerifying)? = nil
    ) throws -> InstallationService {
        guard let hookSource = Bundle.module.url(forResource: "AntiRevokeHook", withExtension: "c"),
              let entitlements = Bundle.module.url(
                  forResource: "IHaveAlreadySeenIt",
                  withExtension: "entitlements"
              ) else {
            throw InstallationServiceError.resourceMissing(
                "AntiRevokeHook.c or IHaveAlreadySeenIt.entitlements"
            )
        }
        return InstallationService(
            hookSourceURL: hookSource,
            entitlementsURL: entitlements,
            runner: runner,
            signatureVerifier: signatureVerifier
        )
    }

    public func install(
        appURL: URL,
        report: ApplicationReport,
        progress: (InstallationStage) -> Void = { _ in }
    ) throws {
        progress(.validating)
        let validatedApp = try validateOriginalApplication(appURL)
        guard validatedApp == report.appURL.standardizedFileURL else {
            throw ApplicationPathValidationError.notAppBundle
        }
        try ensureStopped(appURL: validatedApp)
        try ensureWritable(validatedApp)
        try DiskCapacityChecker(fileManager: fileManager).ensureCapacity(
            for: validatedApp,
            at: validatedApp.deletingLastPathComponent()
        )

        let paths = InstallationPaths(appURL: validatedApp)
        guard !fileManager.fileExists(atPath: paths.backupApp.path) else {
            throw InstallationServiceError.backupAlreadyExists(paths.backupApp.path)
        }

        let executable = try Data(contentsOf: report.executableURL, options: .mappedIfSafe)
        let patchedExecutable = try PatchPlanner.prepareExecutable(executable, report: report)
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("IHaveAlreadySeenIt-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }
        let compiledHook = temporaryDirectory.appendingPathComponent("IHaveAlreadySeenItHook.dylib")
        try compileHook(outputURL: compiledHook)

        let stageApp = paths.root.appendingPathComponent("Stage-WeChat.bundle", isDirectory: true)
        let protectedOriginal = paths.root.appendingPathComponent(
            "Protected-Original.bundle",
            isDirectory: true
        )
        var originalWasMoved = false
        var backupRootWasCreated = false

        do {
            progress(.backingUp)
            try fileManager.createDirectory(at: paths.root, withIntermediateDirectories: true)
            backupRootWasCreated = true
            try runner.run("/usr/bin/ditto", [
                "--rsrc", "--extattr", "--acl", validatedApp.path, paths.backupApp.path,
            ])
            guard try signatureVerifier.status(of: paths.backupApp)
                    == .official(teamIdentifier: DiagnosticService.expectedTeamIdentifier) else {
                throw InstallationServiceError.invalidBackupSignature
            }
            let backupReport = try ApplicationInspector().inspect(appURL: paths.backupApp)
            guard backupReport.executableSHA256 == report.executableSHA256 else {
                throw InstallationServiceError.restoredHashMismatch
            }

            progress(.staging)
            try runner.run("/usr/bin/ditto", [
                "--rsrc", "--extattr", "--acl", paths.backupApp.path, stageApp.path,
            ])
            try runner.run("/usr/bin/xattr", ["-cr", stageApp.path])

            progress(.injecting)
            let stageExecutable = stageApp.appendingPathComponent(
                "Contents/MacOS/\(report.executableURL.lastPathComponent)"
            )
            let attributes = try fileManager.attributesOfItem(atPath: stageExecutable.path)
            try patchedExecutable.write(to: stageExecutable, options: .atomic)
            if let permissions = attributes[.posixPermissions] {
                try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: stageExecutable.path)
            }

            let hookDestination = stageApp.appendingPathComponent(
                "Contents/Resources/IHaveAlreadySeenItHook.dylib"
            )
            if fileManager.fileExists(atPath: hookDestination.path) {
                try fileManager.removeItem(at: hookDestination)
            }
            try fileManager.copyItem(at: compiledHook, to: hookDestination)

            progress(.signing)
            try sign(appURL: stageApp, executableURL: stageExecutable, hookURL: hookDestination)

            progress(.verifying)
            try verifyInstalled(appURL: stageApp)

            progress(.replacing)
            try fileManager.moveItem(at: validatedApp, to: protectedOriginal)
            originalWasMoved = true
            try fileManager.moveItem(at: stageApp, to: validatedApp)
            try verifyInstalled(appURL: validatedApp)

            progress(.writingState)
            try writeState(
                InstallationStateMetadata(
                    schemaVersion: 2,
                    appPath: validatedApp.path,
                    originalSHA256: report.executableSHA256,
                    installedAt: Date(),
                    toolVersion: Self.toolVersion
                ),
                to: paths.state
            )
            try fileManager.removeItem(at: protectedOriginal)
            progress(.completed)
        } catch {
            progress(.rollingBack)
            if originalWasMoved {
                do {
                    if fileManager.fileExists(atPath: validatedApp.path) {
                        try fileManager.removeItem(at: validatedApp)
                    }
                    try fileManager.moveItem(at: protectedOriginal, to: validatedApp)
                    let restored = try ApplicationInspector().inspect(appURL: validatedApp)
                    guard restored.executableSHA256 == report.executableSHA256 else {
                        throw InstallationServiceError.restoredHashMismatch
                    }
                    if fileManager.fileExists(atPath: paths.state.path) {
                        try fileManager.removeItem(at: paths.state)
                    }
                } catch let rollbackError {
                    throw InstallationServiceError.rollbackFailed(
                        original: String(describing: error),
                        rollback: String(describing: rollbackError)
                    )
                }
            }
            if backupRootWasCreated, !originalWasMoved,
               fileManager.fileExists(atPath: paths.root.path) {
                try? fileManager.removeItem(at: paths.root)
            }
            throw error
        }
    }

    public func restore(
        appURL: URL,
        progress: (InstallationStage) -> Void = { _ in }
    ) throws {
        progress(.validating)
        let validatedApp = try ApplicationPathValidator(fileManager: fileManager)
            .validate(appURL: appURL, requireWritableParent: true, allowMissing: true)
        try ensureStopped(appURL: validatedApp)
        try ensureWritable(validatedApp)
        let paths = InstallationPaths(appURL: validatedApp)
        guard fileManager.fileExists(atPath: paths.backupApp.path) else {
            throw InstallationServiceError.backupMissing(paths.backupApp.path)
        }
        guard try signatureVerifier.status(of: paths.backupApp)
                == .official(teamIdentifier: DiagnosticService.expectedTeamIdentifier) else {
            throw InstallationServiceError.invalidBackupSignature
        }
        let state = try readState(from: paths.state)
        guard URL(fileURLWithPath: state.appPath).standardizedFileURL.path == validatedApp.path,
              state.schemaVersion == 2 else {
            throw InstallationServiceError.invalidInstallState
        }
        let backupReport = try ApplicationInspector().inspect(appURL: paths.backupApp)
        guard backupReport.executableSHA256 == state.originalSHA256 else {
            throw InstallationServiceError.restoredHashMismatch
        }

        progress(.staging)
        let stage = validatedApp.deletingLastPathComponent()
            .appendingPathComponent(".IHaveAlreadySeenItRestore-\(UUID().uuidString).app")
        let patchedHold = paths.root.appendingPathComponent("Patched-WeChat.bundle")
        defer {
            if fileManager.fileExists(atPath: stage.path) {
                try? fileManager.removeItem(at: stage)
            }
        }
        try runner.run("/usr/bin/ditto", [
            "--rsrc", "--extattr", "--acl", paths.backupApp.path, stage.path,
        ])
        try runner.run("/usr/bin/xattr", ["-cr", stage.path])
        guard try signatureVerifier.status(of: stage)
                == .official(teamIdentifier: DiagnosticService.expectedTeamIdentifier) else {
            try? fileManager.removeItem(at: stage)
            throw InstallationServiceError.invalidBackupSignature
        }

        let hadCurrentApp = fileManager.fileExists(atPath: validatedApp.path)
        do {
            progress(.replacing)
            if fileManager.fileExists(atPath: patchedHold.path) {
                try fileManager.removeItem(at: patchedHold)
            }
            if hadCurrentApp {
                try fileManager.moveItem(at: validatedApp, to: patchedHold)
            }
            try fileManager.moveItem(at: stage, to: validatedApp)
            guard try signatureVerifier.status(of: validatedApp)
                    == .official(teamIdentifier: DiagnosticService.expectedTeamIdentifier) else {
                throw InstallationServiceError.invalidBackupSignature
            }
            try fileManager.removeItem(at: paths.root)
            progress(.completed)
        } catch {
            progress(.rollingBack)
            do {
                if fileManager.fileExists(atPath: validatedApp.path) {
                    try fileManager.removeItem(at: validatedApp)
                }
                if hadCurrentApp {
                    guard fileManager.fileExists(atPath: patchedHold.path) else {
                        throw InstallationServiceError.backupMissing(patchedHold.path)
                    }
                    try fileManager.moveItem(at: patchedHold, to: validatedApp)
                }
            } catch let rollbackError {
                throw InstallationServiceError.rollbackFailed(
                    original: String(describing: error),
                    rollback: String(describing: rollbackError)
                )
            }
            if fileManager.fileExists(atPath: stage.path) {
                try? fileManager.removeItem(at: stage)
            }
            throw error
        }
    }

    public func uninstall(appURL: URL) throws {
        try restore(appURL: appURL)
    }

    private func validateOriginalApplication(_ appURL: URL) throws -> URL {
        let validated = try ApplicationPathValidator(fileManager: fileManager)
            .validate(appURL: appURL, requireWritableParent: true)
        let signature = try signatureVerifier.status(of: validated)
        guard signature == .official(teamIdentifier: DiagnosticService.expectedTeamIdentifier) else {
            throw InstallationServiceError.invalidOriginalSignature(signature)
        }
        return validated
    }

    private func compileHook(outputURL: URL) throws {
        guard fileManager.fileExists(atPath: hookSourceURL.path) else {
            throw InstallationServiceError.resourceMissing(hookSourceURL.path)
        }
        try runner.run("/usr/bin/clang", [
            "-arch", "arm64",
            "-arch", "x86_64",
            "-dynamiclib",
            "-O2",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-install_name", ApplicationInspector.defaultDylibPath,
            hookSourceURL.path,
            "-o", outputURL.path,
        ])
    }

    private func sign(appURL: URL, executableURL: URL, hookURL: URL) throws {
        guard fileManager.fileExists(atPath: entitlementsURL.path) else {
            throw InstallationServiceError.resourceMissing(entitlementsURL.path)
        }
        try runner.run("/usr/bin/codesign", ["--force", "--sign", "-", hookURL.path])
        try runner.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", appURL.path])
        try runner.run("/usr/bin/codesign", [
            "--force", "--sign", "-",
            "--entitlements", entitlementsURL.path,
            executableURL.path,
        ])
        try runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
    }

    private func verifyInstalled(appURL: URL) throws {
        let report = try ApplicationInspector().inspect(appURL: appURL)
        guard report.injection.slicesContainingDylib == Set(MachOArchitecture.allCases),
              try signatureVerifier.status(of: appURL) == .adHoc else {
            throw InstallationServiceError.postInstallVerificationFailed
        }
    }

    private func ensureStopped(appURL: URL) throws {
        let result = try runner.run("/usr/bin/pgrep", ["-x", "WeChat"], allowedExitCodes: [0, 1])
        guard result.exitCode == 0 else { return }

        let targetPrefix = appURL.standardizedFileURL.path + "/"
        for line in result.output.split(whereSeparator: \.isNewline) {
            guard let pid = Int32(line.trimmingCharacters(in: .whitespaces)) else {
                throw InstallationServiceError.weChatIsRunning
            }
            var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { throw InstallationServiceError.weChatIsRunning }
            let terminator = buffer.firstIndex(of: 0) ?? buffer.endIndex
            let processPath = String(
                decoding: buffer[..<terminator].map(UInt8.init(bitPattern:)),
                as: UTF8.self
            )
            if processPath == appURL.path || processPath.hasPrefix(targetPrefix) {
                throw InstallationServiceError.weChatIsRunning
            }
        }
    }

    private func ensureWritable(_ appURL: URL) throws {
        let parent = appURL.deletingLastPathComponent()
        let appIsWritable = !fileManager.fileExists(atPath: appURL.path)
            || fileManager.isWritableFile(atPath: appURL.path)
        guard appIsWritable,
              fileManager.isWritableFile(atPath: parent.path) else {
            throw InstallationServiceError.needsPrivileges
        }
    }

    private func writeState(_ state: InstallationStateMetadata, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    private func readState(from url: URL) throws -> InstallationStateMetadata {
        guard let data = try? Data(contentsOf: url) else {
            throw InstallationServiceError.invalidInstallState
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(InstallationStateMetadata.self, from: data) else {
            throw InstallationServiceError.invalidInstallState
        }
        return state
    }
}

public typealias Installer = InstallationService
