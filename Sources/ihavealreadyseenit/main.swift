import Darwin
import Foundation
import IHaveAlreadySeenItCore

enum CLICommand: String {
    case inspect
    case plan
    case install
    case uninstall
    case doctor
    case verifyVersion = "verify-version"
    case help
}

struct CLIOptions {
    let command: CLICommand
    let appURL: URL
    let acknowledgedRisk: Bool
    let jsonOutput: Bool

    static func parse(_ arguments: [String]) throws -> CLIOptions {
        var command: CLICommand = .inspect
        var appURL = URL(fileURLWithPath: "/Applications/WeChat.app", isDirectory: true)
        var acknowledgedRisk = false
        var jsonOutput = false
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
            case "--json":
                jsonOutput = true
                index += 1
            case "--help", "-h":
                command = .help
                index += 1
            default:
                throw CLIError.unknownOption(arguments[index])
            }
        }
        return CLIOptions(
            command: command,
            appURL: appURL.standardizedFileURL,
            acknowledgedRisk: acknowledgedRisk,
            jsonOutput: jsonOutput
        )
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
    IHaveAlreadySeenIt 1.0.0 Community - local macOS WeChat anti-revoke tool

    Usage:
      ihavealreadyseenit inspect [--app PATH]
      ihavealreadyseenit plan [--app PATH]
      ihavealreadyseenit doctor [--json] [--app PATH]
      ihavealreadyseenit verify-version [--json] [--app PATH]
      sudo ihavealreadyseenit install --confirm-i-understand [--app PATH]
      sudo ihavealreadyseenit uninstall [--app PATH]

    Commands:
      inspect    Read-only compatibility and installation status
      plan       Read-only list of checks and changes an install would make
      install    Back up, build the hook from source, inject, and re-sign
      uninstall  Restore the complete original app backup
      doctor     Produce a privacy-safe diagnostic report
      verify-version  Read-only maintainer evidence for a candidate WeChat build

    No network access, telemetry, debugger attachment, or message-content collection.
    """)
}

func printDiagnosticReport(_ report: DiagnosticReport) {
    print("Application:   \(report.applicationPath)")
    print("Version:       \(report.version) (\(report.build))")
    print("SHA-256:       \(report.executableSHA256)")
    for architecture in report.architectures {
        if let digest = report.architectureSHA256[architecture] {
            print("\(architecture) SHA-256: \(digest)")
        }
    }
    print("Architectures: \(report.architectures.joined(separator: ", "))")
    print("Code signature: \(report.codeSignature.displayName)")
    print("Compatibility: \(String(describing: report.compatibility))")
    print("Installation:  \(String(describing: report.installation))")
    print("Backup:        \(report.backup.rawValue)")
    print("Profile:       \(report.matchedProfileID ?? "none")")
    if !report.headerSlack.isEmpty {
        let slack = report.headerSlack.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        print("Header slack:  \(slack)")
    }
    print("Safe to install: \(report.isSafeToInstall ? "yes" : "no")")
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
    case .candidate(let ruleID):
        print("Compatibility: BLOCKED - candidate profile requires manual validation (\(ruleID))")
    case .unknownHash(let ruleID):
        print("Compatibility: BLOCKED - executable hash is not known for \(ruleID)")
    case .architectureHashMismatch(let ruleID):
        print("Compatibility: BLOCKED - architecture hash mismatch for \(ruleID)")
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
      3. Copy the complete original app to /Applications/.IHaveAlreadySeenItBackup.
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
        return "install requires --confirm-i-understand after reviewing `ihavealreadyseenit plan`"
    case InstallerError.weChatIsRunning: return "WeChat is running; quit it before install or uninstall"
    case InstallerError.needsPrivileges: return "the app is not writable; rerun the same command with sudo"
    case InstallerError.backupAlreadyExists(let path): return "backup already exists at \(path); inspect or uninstall first"
    case InstallerError.backupMissing(let path): return "original backup is missing at \(path)"
    case InstallerError.resourceMissing(let path): return "bundled build resource is missing: \(path)"
    case InstallerError.invalidBackupSignature: return "the original backup signature is invalid"
    case InstallerError.invalidInstallState: return "the backup state file is missing or invalid"
    case InstallerError.invalidOriginalSignature(let status):
        return "the selected app is not an untouched official WeChat build: \(status.displayName)"
    case InstallerError.postInstallVerificationFailed: return "post-install load-command verification failed"
    case InstallerError.restoredHashMismatch: return "restored executable hash does not match the original"
    case InstallerError.rollbackFailed(let original, let rollback):
        return "install failed (\(original)) and automatic rollback also failed (\(rollback)); preserve the .IHaveAlreadySeenItBackup folder beside the target app"
    case PatchPlanningError.unsupportedVersion: return "this WeChat version/build is not supported"
    case PatchPlanningError.unknownExecutableHash: return "this WeChat executable hash is not in the local allowlist"
    case PatchPlanningError.architectureHashMismatch:
        return "one or more architecture hashes do not match the selected profile"
    case PatchPlanningError.candidateVersion:
        return "this profile is a diagnostic candidate and cannot be installed"
    case PatchPlanningError.unsafeSignatureMatches: return "anti-revoke signatures are missing or ambiguous"
    case PatchPlanningError.unsupportedArchitectures: return "both arm64 and x86_64 slices are required"
    case PatchPlanningError.insufficientHeaderSpace:
        return "the executable does not have the profile's required Mach-O header space"
    case PatchPlanningError.alreadyInstalled: return "IHaveAlreadySeenIt is already injected"
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
    case ApplicationPathValidationError.notAppBundle: return "the selected path is not an .app bundle"
    case ApplicationPathValidationError.notDirectory: return "the selected app path is not a directory"
    case ApplicationPathValidationError.symbolicLink: return "symbolic-link app paths are not accepted"
    case ApplicationPathValidationError.unexpectedOwner: return "the app has an unexpected filesystem owner"
    case ApplicationPathValidationError.parentNotWritable: return "the app directory requires administrator privileges"
    case DiskCapacityError.unableToMeasure: return "available disk space could not be measured"
    case DiskCapacityError.insufficientSpace(let required, let available):
        return "insufficient disk space (required \(required) bytes, available \(available) bytes)"
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
        try InstallationService.bundled().install(appURL: options.appURL, report: report) { stage in
            print("[\(stage.rawValue)]")
        }
        print("Installed successfully. Open WeChat manually and check /tmp/ihavealreadyseenit-hook.log.")
    case .uninstall:
        try InstallationService.bundled().restore(appURL: options.appURL) { stage in
            print("[\(stage.rawValue)]")
        }
        print("Original WeChat.app restored and backup removed.")
    case .doctor:
        let report = try DiagnosticService().report(appURL: options.appURL)
        if options.jsonOutput {
            print(try DiagnosticReportEncoder.jsonString(report))
        } else {
            printDiagnosticReport(report)
        }
    case .verifyVersion:
        let report = try VersionVerificationService().report(appURL: options.appURL)
        if options.jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        } else {
            print("Application: \(report.applicationPath)")
            print("Version: \(report.version) (\(report.build))")
            print("SHA-256: \(report.executableSHA256)")
            print("Architectures: \(report.architectures.joined(separator: ", "))")
            print("Code signature: \(report.codeSignature.displayName)")
            for architecture in report.architectures {
                print("\(architecture) SHA-256: \(report.architectureSHA256[architecture] ?? "missing")")
                print("\(architecture) header slack: \(report.headerSlack[architecture] ?? -1) bytes")
            }
            for check in report.profileChecks {
                let matches = check.signatureMatches
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")
                print("Profile \(check.ruleID) [\(check.validationStatus.rawValue)]: \(matches)")
            }
            print("Candidate ready for manual review: \(report.isCandidateReadyForManualReview ? "yes" : "no")")
            print("Install allowlist gate: \(report.passesInstallAllowlist ? "pass" : "BLOCKED")")
        }
    case .help:
        break
    }
} catch {
    let message = "Error: \(describe(error))\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
