import Foundation

public enum CompatibilityDiagnostic: Codable, Equatable, Sendable {
    case supported(ruleID: String)
    case unknownHash(ruleID: String)
    case unsupportedVersion
}

public enum InstallationDiagnostic: Codable, Equatable, Sendable {
    case notInstalled
    case installed(architectures: [String])
    case partiallyInstalled(architectures: [String])
}

public enum BackupDiagnostic: String, Codable, Equatable, Sendable {
    case missing
    case present
    case invalid
}

public struct InstallationStateMetadata: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let appPath: String
    public let originalSHA256: String
    public let installedAt: Date
    public let toolVersion: String

    public init(
        schemaVersion: Int,
        appPath: String,
        originalSHA256: String,
        installedAt: Date,
        toolVersion: String
    ) {
        self.schemaVersion = schemaVersion
        self.appPath = appPath
        self.originalSHA256 = originalSHA256
        self.installedAt = installedAt
        self.toolVersion = toolVersion
    }
}

public struct DiagnosticReport: Codable, Equatable, Sendable {
    public let applicationPath: String
    public let version: String
    public let build: String
    public let executableSHA256: String
    public let architectures: [String]
    public let signatureMatches: [String: Int]
    public let codeSignature: CodeSignatureStatus
    public let compatibility: CompatibilityDiagnostic
    public let installation: InstallationDiagnostic
    public let backup: BackupDiagnostic

    public init(
        applicationPath: String,
        version: String,
        build: String,
        executableSHA256: String,
        architectures: [String],
        signatureMatches: [String: Int],
        codeSignature: CodeSignatureStatus,
        compatibility: CompatibilityDiagnostic,
        installation: InstallationDiagnostic,
        backup: BackupDiagnostic
    ) {
        self.applicationPath = applicationPath
        self.version = version
        self.build = build
        self.executableSHA256 = executableSHA256
        self.architectures = architectures
        self.signatureMatches = signatureMatches
        self.codeSignature = codeSignature
        self.compatibility = compatibility
        self.installation = installation
        self.backup = backup
    }

    public var isSafeToInstall: Bool {
        guard codeSignature == .official(teamIdentifier: DiagnosticService.expectedTeamIdentifier),
              case .supported = compatibility,
              installation == .notInstalled,
              backup == .missing else {
            return false
        }
        return Set(architectures) == Set(MachOArchitecture.allCases.map(\.rawValue))
            && MachOArchitecture.allCases.allSatisfy { signatureMatches[$0.rawValue] == 1 }
    }
}

public enum DiagnosticReportEncoder {
    public static func jsonData(_ report: DiagnosticReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    public static func jsonString(_ report: DiagnosticReport) throws -> String {
        String(decoding: try jsonData(report), as: UTF8.self)
    }
}

public struct DiagnosticService: @unchecked Sendable {
    public static let expectedTeamIdentifier = "5A4RE8SF68"

    private let inspector: ApplicationInspector
    private let signatureVerifier: any CodeSignatureVerifying
    private let fileManager: FileManager

    public init(
        inspector: ApplicationInspector = ApplicationInspector(),
        signatureVerifier: any CodeSignatureVerifying = SystemCodeSignatureVerifier(),
        fileManager: FileManager = .default
    ) {
        self.inspector = inspector
        self.signatureVerifier = signatureVerifier
        self.fileManager = fileManager
    }

    public func report(appURL: URL) throws -> DiagnosticReport {
        let inspected = try inspector.inspect(appURL: appURL)
        let architectures = inspected.injection.architectures.map(\.rawValue).sorted()
        let injected = inspected.injection.slicesContainingDylib.map(\.rawValue).sorted()
        let installation: InstallationDiagnostic
        if injected.isEmpty {
            installation = .notInstalled
        } else if injected == architectures {
            installation = .installed(architectures: injected)
        } else {
            installation = .partiallyInstalled(architectures: injected)
        }
        let backup = backupStatus(appURL: inspected.appURL)
        return DiagnosticReport(
            applicationPath: inspected.appURL.path,
            version: inspected.version.description,
            build: inspected.build,
            executableSHA256: inspected.executableSHA256,
            architectures: architectures,
            signatureMatches: Dictionary(uniqueKeysWithValues: MachOArchitecture.allCases.map {
                ($0.rawValue, inspected.signatureScan[$0] ?? 0)
            }),
            codeSignature: try signatureVerifier.status(of: inspected.appURL),
            compatibility: compatibilityDiagnostic(inspected.compatibility),
            installation: installation,
            backup: backup
        )
    }

    public func backupStatus(appURL: URL) -> BackupDiagnostic {
        let standardizedApp = appURL.standardizedFileURL
        let paths = InstallationPaths(appURL: standardizedApp)
        let backupURL = paths.backupApp
        if !fileManager.fileExists(atPath: backupURL.path) {
            return .missing
        }
        guard (try? signatureVerifier.status(of: backupURL))
                == .official(teamIdentifier: Self.expectedTeamIdentifier),
              let stateData = try? Data(contentsOf: paths.state) else {
            return .invalid
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(InstallationStateMetadata.self, from: stateData),
              state.schemaVersion == 2,
              URL(fileURLWithPath: state.appPath).standardizedFileURL.path == standardizedApp.path,
              let backupReport = try? inspector.inspect(appURL: backupURL),
              backupReport.executableSHA256 == state.originalSHA256 else {
            return .invalid
        }
        return .present
    }

    private func compatibilityDiagnostic(_ result: CompatibilityResult) -> CompatibilityDiagnostic {
        switch result {
        case .supported(let ruleID): return .supported(ruleID: ruleID)
        case .unknownHash(let ruleID): return .unknownHash(ruleID: ruleID)
        case .unsupportedVersion: return .unsupportedVersion
        }
    }
}

public struct InstallationPaths: Sendable {
    public let root: URL
    public let backupApp: URL
    public let state: URL

    public init(appURL: URL) {
        root = appURL.deletingLastPathComponent()
            .appendingPathComponent(".IHaveAlreadySeenItBackup", isDirectory: true)
        backupApp = root.appendingPathComponent("Original-WeChat.bundle", isDirectory: true)
        state = root.appendingPathComponent("state.json")
    }
}

public struct UserActionPolicy: Equatable, Sendable {
    public let canInspect: Bool
    public let canPlan: Bool
    public let canInstall: Bool
    public let canRestore: Bool

    public init(
        report: DiagnosticReport?,
        isBusy: Bool,
        hasRecoverableBackupWithoutApplication: Bool = false,
        allowsMutatingOperations: Bool = true
    ) {
        canInspect = !isBusy
        canPlan = report != nil && !isBusy
        canInstall = allowsMutatingOperations && report?.isSafeToInstall == true && !isBusy
        if allowsMutatingOperations, let report, report.backup == .present, !isBusy {
            switch report.installation {
            case .installed, .partiallyInstalled:
                canRestore = true
            case .notInstalled:
                canRestore = false
            }
        } else {
            canRestore = allowsMutatingOperations
                && hasRecoverableBackupWithoutApplication
                && !isBusy
        }
    }
}
