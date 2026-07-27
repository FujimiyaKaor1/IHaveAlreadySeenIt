import Darwin
import Foundation
import WeChatGuardCore

enum CLICommand: String {
    case inspect
    case plan
    case install
    case uninstall
    case help
}

struct CLIOptions {
    let command: CLICommand
    let appURL: URL
    let acknowledgedRisk: Bool

    static func parse(_ arguments: [String]) throws -> CLIOptions {
        var command: CLICommand = .inspect
        var appURL = URL(fileURLWithPath: "/Applications/WeChat.app", isDirectory: true)
        var acknowledgedRisk = false
        var index = 0

        if let first = arguments.first, !first.hasPrefix("-") {
            guard let parsed = CLICommand(rawValue: first) else {
                throw CLIError.invalidCommand(first)
            }
            command = parsed
            index = 1
        }
        while index < arguments.count {
            switch arguments[index] {
            case "--app":
                guard index + 1 < arguments.count else { throw CLIError.missingValue("--app") }
                appURL = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                index += 2
            case "--confirm-i-understand":
                acknowledgedRisk = true
                index += 1
            case "--help", "-h":
                command = .help
                index += 1
            default:
                throw CLIError.unknownOption(arguments[index])
            }
        }
        return CLIOptions(command: command, appURL: appURL.standardizedFileURL, acknowledgedRisk: acknowledgedRisk)
    }
}

enum CLIError: Error {
    case invalidCommand(String)
    case missingValue(String)
    case unknownOption(String)
    case riskNotAcknowledged
}

func printHelp() {
    print("""
    WeChatGuard 0.1.0 - local, source-built macOS WeChat anti-revoke tool

    Usage:
      wechatguard inspect [--app PATH]
      wechatguard plan [--app PATH]
      sudo wechatguard install --confirm-i-understand [--app PATH]
      sudo wechatguard uninstall [--app PATH]

    Commands:
      inspect    Read-only compatibility and installation status
      plan       Read-only list of checks and changes an install would make
      install    Back up, build the hook from source, inject, and re-sign
      uninstall  Restore the complete original app backup

    No network access, background service, debugger attachment, or message-content collection.
    """)
}

func printReport(_ report: ApplicationReport) {
    print("Application: \(report.appURL.path)")
    print("Version:     \(report.version) (\(report.build))")
    print("SHA-256:     \(report.executableSHA256)")
    print("Architectures: \(report.injection.architectures.map(\.rawValue).sorted().joined(separator: ", "))")
    print("Signatures:  arm64=\(report.signatureScan[.arm64] ?? 0), x86_64=\(report.signatureScan[.x86_64] ?? 0)")
    switch report.compatibility {
    case .supported(let ruleID):
        print("Compatibility: supported (\(ruleID))")
    case .unknownHash(let ruleID):
        print("Compatibility: BLOCKED - executable hash is not known for \(ruleID)")
    case .unsupportedVersion:
        print("Compatibility: BLOCKED - version/build has no local rule")
    }
    if report.injection.slicesContainingDylib.isEmpty {
        print("Status:      not installed")
    } else {
        let slices = report.injection.slicesContainingDylib.map(\.rawValue).sorted().joined(separator: ", ")
        print("Status:      injected in \(slices)")
    }
    print("Signature gate: \(report.signatureScan.isSafeToPatch ? "pass" : "BLOCKED")")
}

func printPlan(_ report: ApplicationReport) {
    printReport(report)
    print("""

    Install actions:
      1. Refuse to continue unless WeChat is closed and all gates above pass.
      2. Compile a universal hook dylib from the bundled C source.
      3. Copy the complete original app to /Applications/.WeChatGuardBackup.
      4. Add one LC_LOAD_DYLIB command to both executable slices.
      5. Ad-hoc sign the hook and app with two required entitlements.
      6. Verify the signature and injected load commands; restore backup on failure.

    The install does not launch WeChat automatically.
    """)
}

func describe(_ error: Error) -> String {
    switch error {
    case CLIError.invalidCommand(let value): return "unknown command: \(value)"
    case CLIError.missingValue(let option): return "missing value for \(option)"
    case CLIError.unknownOption(let option): return "unknown option: \(option)"
    case CLIError.riskNotAcknowledged:
        return "install requires --confirm-i-understand after reviewing `wechatguard plan`"
    case InstallerError.weChatIsRunning: return "WeChat is running; quit it before install or uninstall"
    case InstallerError.needsPrivileges: return "the app is not writable; rerun the same command with sudo"
    case InstallerError.backupAlreadyExists(let path): return "backup already exists at \(path); inspect or uninstall first"
    case InstallerError.backupMissing(let path): return "original backup is missing at \(path)"
    case InstallerError.resourceMissing(let path): return "bundled build resource is missing: \(path)"
    case InstallerError.postInstallVerificationFailed: return "post-install load-command verification failed"
    case InstallerError.restoredHashMismatch: return "restored executable hash does not match the original"
    case InstallerError.rollbackFailed(let original, let rollback):
        return "install failed (\(original)) and automatic rollback also failed (\(rollback)); preserve the .WeChatGuardBackup folder beside the target app"
    case PatchPlanningError.unsupportedVersion: return "this WeChat version/build is not supported"
    case PatchPlanningError.unknownExecutableHash: return "this WeChat executable hash is not in the local allowlist"
    case PatchPlanningError.unsafeSignatureMatches: return "anti-revoke signatures are missing or ambiguous"
    case PatchPlanningError.unsupportedArchitectures: return "both arm64 and x86_64 slices are required"
    case PatchPlanningError.alreadyInstalled: return "WeChatGuard is already injected"
    case PatchPlanningError.executableChanged: return "the executable changed after inspection; no files were modified"
    case PatchPlanningError.injectionVerificationFailed: return "in-memory injection verification failed"
    case ApplicationInspectionError.appNotFound(let path): return "WeChat app not found: \(path)"
    case ApplicationInspectionError.malformedInfoPlist: return "WeChat Info.plist is missing or malformed"
    case ApplicationInspectionError.unexpectedBundleIdentifier(let identifier): return "unexpected bundle identifier: \(identifier)"
    case ApplicationInspectionError.invalidExecutableName: return "invalid CFBundleExecutable value"
    case ApplicationInspectionError.executableNotFound(let path): return "WeChat executable not found: \(path)"
    case CommandExecutionError.launchFailed(let message): return message
    case CommandExecutionError.unexpectedExit(let executable, let code, let output):
        return "\(executable) exited with \(code): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
    default: return String(describing: error)
    }
}

do {
    let options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
    if options.command == .help {
        printHelp()
        exit(0)
    }

    switch options.command {
    case .inspect:
        let report = try ApplicationInspector().inspect(appURL: options.appURL)
        printReport(report)
    case .plan:
        let report = try ApplicationInspector().inspect(appURL: options.appURL)
        let executable = try Data(contentsOf: report.executableURL, options: .mappedIfSafe)
        _ = try PatchPlanner.prepareExecutable(executable, report: report)
        printPlan(report)
        print("Dry-run injection: pass (no files changed)")
    case .install:
        guard options.acknowledgedRisk else { throw CLIError.riskNotAcknowledged }
        let report = try ApplicationInspector().inspect(appURL: options.appURL)
        guard let hookSource = Bundle.module.url(forResource: "AntiRevokeHook", withExtension: "c"),
              let entitlements = Bundle.module.url(forResource: "WeChatGuard", withExtension: "entitlements") else {
            throw InstallerError.resourceMissing("AntiRevokeHook.c or WeChatGuard.entitlements")
        }
        try Installer(hookSourceURL: hookSource, entitlementsURL: entitlements)
            .install(appURL: options.appURL, report: report)
        print("Installed successfully. Open WeChat manually and check /tmp/wechatguard-hook.log.")
    case .uninstall:
        guard let hookSource = Bundle.module.url(forResource: "AntiRevokeHook", withExtension: "c"),
              let entitlements = Bundle.module.url(forResource: "WeChatGuard", withExtension: "entitlements") else {
            throw InstallerError.resourceMissing("AntiRevokeHook.c or WeChatGuard.entitlements")
        }
        try Installer(hookSourceURL: hookSource, entitlementsURL: entitlements)
            .uninstall(appURL: options.appURL)
        print("Original WeChat.app restored and backup removed.")
    case .help:
        break
    }
} catch {
    let message = "Error: \(describe(error))\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
