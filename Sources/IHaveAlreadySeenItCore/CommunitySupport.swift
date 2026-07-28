import Foundation

public enum AdministratorOperation: Equatable, Sendable {
    case install
    case restore
}

public enum AdministratorCommandError: Error, Equatable, Sendable {
    case invalidToolBundle
    case invalidApplication
    case unsafePath
}

public struct AdministratorCommandBuilder: Sendable {
    private let toolBundleURL: URL

    public init(toolBundleURL: URL) {
        self.toolBundleURL = toolBundleURL.standardizedFileURL
    }

    public func command(for operation: AdministratorOperation, appURL: URL) throws -> String {
        guard toolBundleURL.pathExtension.lowercased() == "app" else {
            throw AdministratorCommandError.invalidToolBundle
        }
        let application = appURL.standardizedFileURL
        guard application.pathExtension.lowercased() == "app" else {
            throw AdministratorCommandError.invalidApplication
        }
        let cli = toolBundleURL.appendingPathComponent("Contents/Helpers/ihavealreadyseenit")
        guard Self.isSafePath(cli.path), Self.isSafePath(application.path) else {
            throw AdministratorCommandError.unsafePath
        }

        let action: String
        let confirmation: String
        switch operation {
        case .install:
            action = "install"
            confirmation = " --confirm-i-understand"
        case .restore:
            action = "uninstall"
            confirmation = ""
        }
        return "/usr/bin/sudo -- \(Self.shellQuote(cli.path)) \(action)\(confirmation) --app \(Self.shellQuote(application.path))"
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func isSafePath(_ path: String) -> Bool {
        !path.isEmpty && !path.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }
}

public enum CommunityHomeStatus: Equatable, Sendable {
    case readyToInstall
    case installed
    case needsAttention
    case working
}

public enum CommunityPrimaryAction: Equatable, Sendable {
    case install
    case restore
    case recheck
}

public struct CommunityHomePresentation: Equatable, Sendable {
    public let status: CommunityHomeStatus
    public let primaryAction: CommunityPrimaryAction
    public let isPrimaryEnabled: Bool

    public init(
        report: DiagnosticReport?,
        isBusy: Bool,
        backend: AppMutationBackend,
        hasRecoverableBackupWithoutApplication: Bool = false
    ) {
        if isBusy {
            status = .working
            primaryAction = .recheck
            isPrimaryEnabled = false
            return
        }
        guard let report else {
            status = hasRecoverableBackupWithoutApplication ? .installed : .needsAttention
            primaryAction = hasRecoverableBackupWithoutApplication ? .restore : .recheck
            isPrimaryEnabled = hasRecoverableBackupWithoutApplication
                ? backend.allowsMutatingOperations
                : true
            return
        }
        switch report.installation {
        case .installed where report.backup == .present,
             .partiallyInstalled where report.backup == .present:
            status = .installed
            primaryAction = .restore
            isPrimaryEnabled = backend.allowsMutatingOperations
        default:
            if report.isSafeToInstall {
                status = .readyToInstall
                primaryAction = .install
                isPrimaryEnabled = backend.allowsMutatingOperations
            } else {
                status = .needsAttention
                primaryAction = .recheck
                isPrimaryEnabled = true
            }
        }
    }
}
