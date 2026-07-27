import Darwin
import Foundation
import WeChatGuardCore

struct CommandResult {
    let exitCode: Int32
    let output: String
}

enum CommandExecutionError: Error {
    case launchFailed(String)
    case unexpectedExit(executable: String, code: Int32, output: String)
}

struct ProcessRunner {
    @discardableResult
    func run(
        _ executable: String,
        _ arguments: [String],
        allowedExitCodes: Set<Int32> = [0]
    ) throws -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw CommandExecutionError.launchFailed("\(executable): \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard allowedExitCodes.contains(process.terminationStatus) else {
            throw CommandExecutionError.unexpectedExit(
                executable: executable,
                code: process.terminationStatus,
                output: output
            )
        }
        return CommandResult(exitCode: process.terminationStatus, output: output)
    }
}

enum InstallerError: Error {
    case weChatIsRunning
    case needsPrivileges
    case backupAlreadyExists(String)
    case backupMissing(String)
    case resourceMissing(String)
    case postInstallVerificationFailed
    case restoredHashMismatch
    case rollbackFailed(original: String, rollback: String)
}

private struct InstallState: Codable {
    let appPath: String
    let originalSHA256: String
    let installedAt: Date
    let toolVersion: String
}

struct Installer {
    static let toolVersion = "0.1.0"

    private let runner = ProcessRunner()
    private let fileManager = FileManager.default
    private let hookSourceURL: URL
    private let entitlementsURL: URL

    init(hookSourceURL: URL, entitlementsURL: URL) {
        self.hookSourceURL = hookSourceURL
        self.entitlementsURL = entitlementsURL
    }

    func install(appURL: URL, report: ApplicationReport) throws {
        try ensureStopped(appURL: appURL)
        try ensureWritable(appURL)

        let backup = backupLocations(for: appURL)
        guard !fileManager.fileExists(atPath: backup.app.path) else {
            throw InstallerError.backupAlreadyExists(backup.app.path)
        }

        let executable = try Data(contentsOf: report.executableURL, options: .mappedIfSafe)
        let patchedExecutable = try PatchPlanner.prepareExecutable(executable, report: report)
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("WeChatGuard-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }
        let compiledHook = temporaryDirectory.appendingPathComponent("WeChatGuardHook.dylib")
        try compileHook(outputURL: compiledHook)

        let stageApp = backup.root.appendingPathComponent("Stage-WeChat.bundle", isDirectory: true)
        let protectedOriginal = backup.root.appendingPathComponent("Protected-Original.bundle", isDirectory: true)
        var originalWasMoved = false
        defer {
            if fileManager.fileExists(atPath: stageApp.path) {
                try? fileManager.removeItem(at: stageApp)
            }
        }

        do {
            try fileManager.createDirectory(at: backup.root, withIntermediateDirectories: true)
            try runner.run("/usr/bin/ditto", ["--rsrc", "--extattr", "--acl", appURL.path, backup.app.path])
            try runner.run("/usr/bin/ditto", ["--rsrc", "--extattr", "--acl", backup.app.path, stageApp.path])
            try runner.run("/usr/bin/xattr", ["-cr", stageApp.path])

            let stageExecutable = stageApp.appendingPathComponent(
                "Contents/MacOS/\(report.executableURL.lastPathComponent)"
            )
            let attributes = try fileManager.attributesOfItem(atPath: stageExecutable.path)
            try patchedExecutable.write(to: stageExecutable, options: .atomic)
            if let permissions = attributes[.posixPermissions] {
                try fileManager.setAttributes(
                    [.posixPermissions: permissions],
                    ofItemAtPath: stageExecutable.path
                )
            }

            let hookDestination = stageApp.appendingPathComponent("Contents/Resources/WeChatGuardHook.dylib")
            if fileManager.fileExists(atPath: hookDestination.path) {
                try fileManager.removeItem(at: hookDestination)
            }
            try fileManager.copyItem(at: compiledHook, to: hookDestination)

            try sign(appURL: stageApp, executableURL: stageExecutable, hookURL: hookDestination)
            try verifyInstalled(appURL: stageApp)

            try fileManager.moveItem(at: appURL, to: protectedOriginal)
            originalWasMoved = true
            try fileManager.moveItem(at: stageApp, to: appURL)
            try verifyInstalled(appURL: appURL)
            try writeState(
                InstallState(
                    appPath: appURL.path,
                    originalSHA256: report.executableSHA256,
                    installedAt: Date(),
                    toolVersion: Self.toolVersion
                ),
                to: backup.state
            )
            try fileManager.removeItem(at: protectedOriginal)
        } catch {
            guard originalWasMoved else { throw error }
            do {
                if fileManager.fileExists(atPath: appURL.path) {
                    try fileManager.removeItem(at: appURL)
                }
                try fileManager.moveItem(at: protectedOriginal, to: appURL)
                let restored = try ApplicationInspector().inspect(appURL: appURL)
                guard restored.executableSHA256 == report.executableSHA256 else {
                    throw InstallerError.restoredHashMismatch
                }
            } catch let rollbackError {
                throw InstallerError.rollbackFailed(
                    original: String(describing: error),
                    rollback: String(describing: rollbackError)
                )
            }
            throw error
        }
    }

    func uninstall(appURL: URL) throws {
        try ensureStopped(appURL: appURL)
        try ensureWritable(appURL)
        let backup = backupLocations(for: appURL)
        guard fileManager.fileExists(atPath: backup.app.path) else {
            throw InstallerError.backupMissing(backup.app.path)
        }

        let stage = appURL.deletingLastPathComponent()
            .appendingPathComponent(".WeChatGuardRestore-\(UUID().uuidString).app")
        let patchedHold = backup.root.appendingPathComponent("Patched-WeChat.bundle")
        try runner.run("/usr/bin/ditto", ["--rsrc", "--extattr", "--acl", backup.app.path, stage.path])
        try runner.run("/usr/bin/xattr", ["-cr", stage.path])
        try runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", stage.path])

        let hadCurrentApp = fileManager.fileExists(atPath: appURL.path)
        do {
            if fileManager.fileExists(atPath: patchedHold.path) {
                try fileManager.removeItem(at: patchedHold)
            }
            if hadCurrentApp {
                try fileManager.moveItem(at: appURL, to: patchedHold)
            }
            try fileManager.moveItem(at: stage, to: appURL)
            try runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
            try fileManager.removeItem(at: backup.root)
        } catch {
            if !fileManager.fileExists(atPath: appURL.path),
               fileManager.fileExists(atPath: patchedHold.path) {
                try? fileManager.moveItem(at: patchedHold, to: appURL)
            }
            if fileManager.fileExists(atPath: stage.path) {
                try? fileManager.removeItem(at: stage)
            }
            throw error
        }
    }

    private func compileHook(outputURL: URL) throws {
        guard fileManager.fileExists(atPath: hookSourceURL.path) else {
            throw InstallerError.resourceMissing(hookSourceURL.path)
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
            throw InstallerError.resourceMissing(entitlementsURL.path)
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
        guard report.injection.slicesContainingDylib == Set(MachOArchitecture.allCases) else {
            throw InstallerError.postInstallVerificationFailed
        }
    }

    private func ensureStopped(appURL: URL) throws {
        let result = try runner.run("/usr/bin/pgrep", ["-x", "WeChat"], allowedExitCodes: [0, 1])
        guard result.exitCode == 0 else { return }

        let targetPrefix = appURL.standardizedFileURL.path + "/"
        for line in result.output.split(whereSeparator: \.isNewline) {
            guard let pid = Int32(line.trimmingCharacters(in: .whitespaces)) else {
                throw InstallerError.weChatIsRunning
            }
            var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else {
                throw InstallerError.weChatIsRunning
            }
            let terminator = buffer.firstIndex(of: 0) ?? buffer.endIndex
            let processPath = String(decoding: buffer[..<terminator].map(UInt8.init(bitPattern:)), as: UTF8.self)
            if processPath == appURL.standardizedFileURL.path || processPath.hasPrefix(targetPrefix) {
                throw InstallerError.weChatIsRunning
            }
        }
    }

    private func ensureWritable(_ appURL: URL) throws {
        let parent = appURL.deletingLastPathComponent()
        let appIsWritable = !fileManager.fileExists(atPath: appURL.path)
            || fileManager.isWritableFile(atPath: appURL.path)
        guard appIsWritable, fileManager.isWritableFile(atPath: parent.path) else {
            throw InstallerError.needsPrivileges
        }
    }

    private func backupLocations(for appURL: URL) -> (root: URL, app: URL, state: URL) {
        let root = appURL.deletingLastPathComponent()
            .appendingPathComponent(".WeChatGuardBackup", isDirectory: true)
        return (
            root,
            root.appendingPathComponent("Original-WeChat.bundle", isDirectory: true),
            root.appendingPathComponent("state.json")
        )
    }

    private func writeState(_ state: InstallState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
