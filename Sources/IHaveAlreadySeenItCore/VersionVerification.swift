import Foundation

public struct ProfileVerificationCheck: Codable, Equatable, Sendable {
    public let ruleID: String
    public let validationStatus: CompatibilityValidationStatus
    public let versionBuildMatches: Bool
    public let executableHashMatches: Bool
    public let architectureHashMatches: [String: Bool]
    public let signatureMatches: [String: Int]
    public let signaturesAreUnique: Bool
    public let headerSlackPasses: Bool
}

public struct VersionVerificationReport: Codable, Equatable, Sendable {
    public let applicationPath: String
    public let version: String
    public let build: String
    public let executableSHA256: String
    public let architectureSHA256: [String: String]
    public let architectures: [String]
    public let codeSignature: CodeSignatureStatus
    public let headerSlack: [String: Int]
    public let profileChecks: [ProfileVerificationCheck]
    public let isCandidateReadyForManualReview: Bool
    public let passesInstallAllowlist: Bool
}

public struct VersionVerificationService: @unchecked Sendable {
    private let rules: CompatibilityRules
    private let signatureVerifier: any CodeSignatureVerifying
    private let fileManager: FileManager

    public init(
        rules: CompatibilityRules = .builtIn,
        signatureVerifier: any CodeSignatureVerifying = SystemCodeSignatureVerifier(),
        fileManager: FileManager = .default
    ) {
        self.rules = rules
        self.signatureVerifier = signatureVerifier
        self.fileManager = fileManager
    }

    public func report(appURL: URL) throws -> VersionVerificationReport {
        let validated = try ApplicationPathValidator(fileManager: fileManager).validate(
            appURL: appURL,
            requireWritableParent: false
        )
        let inspected = try ApplicationInspector(compatibilityRules: rules).inspect(appURL: validated)
        let executable = try Data(contentsOf: inspected.executableURL, options: .mappedIfSafe)
        let signature = try signatureVerifier.status(of: inspected.appURL)
        let architectures = inspected.injection.architectures.map(\.rawValue).sorted()
        let architectureHashes = Dictionary(uniqueKeysWithValues: inspected.architectureSHA256.map {
            ($0.key.rawValue, $0.value)
        })
        let slack = Dictionary(uniqueKeysWithValues: inspected.injection.headerSlack.map {
            ($0.key.rawValue, $0.value)
        })

        let checks = try rules.rules.map { rule in
            let scan = try SignatureScanner.scan(executable, signatures: rule.signatures)
            let matches = Dictionary(uniqueKeysWithValues: rule.supportedArchitectures.map {
                ($0.rawValue, scan[$0] ?? 0)
            })
            let architectureMatches = Dictionary(uniqueKeysWithValues: rule.supportedArchitectures.map {
                architecture in
                let actual = inspected.architectureSHA256[architecture]
                let expected = rule.architectureSHA256[architecture] ?? []
                return (architecture.rawValue, actual.map(expected.contains) ?? false)
            })
            return ProfileVerificationCheck(
                ruleID: rule.id,
                validationStatus: rule.validationStatus,
                versionBuildMatches: rule.version == inspected.version && rule.build == inspected.build,
                executableHashMatches: rule.executableSHA256.contains(
                    inspected.executableSHA256.lowercased()
                ),
                architectureHashMatches: architectureMatches,
                signatureMatches: matches,
                signaturesAreUnique: rule.supportedArchitectures.allSatisfy { scan[$0] == 1 },
                headerSlackPasses: rule.supportedArchitectures.allSatisfy {
                    (inspected.injection.headerSlack[$0] ?? -1) >= rule.minimumHeaderSlack
                }
            )
        }

        let official = signature == .official(
            teamIdentifier: DiagnosticService.expectedTeamIdentifier
        )
        let matchesVerifiedProfile: Bool
        if case .supported = inspected.compatibility {
            matchesVerifiedProfile = true
        } else {
            matchesVerifiedProfile = false
        }
        let candidateReady = official
            && !matchesVerifiedProfile
            && inspected.injection.architectures == Set(MachOArchitecture.allCases)
            && checks.contains { $0.signaturesAreUnique && $0.headerSlackPasses }
        let passesInstallAllowlist = official && inspected.isProfileSafeToPatch

        return VersionVerificationReport(
            applicationPath: Self.privacySafePath(inspected.appURL),
            version: inspected.version.description,
            build: inspected.build,
            executableSHA256: inspected.executableSHA256,
            architectureSHA256: architectureHashes,
            architectures: architectures,
            codeSignature: signature,
            headerSlack: slack,
            profileChecks: checks,
            isCandidateReadyForManualReview: candidateReady,
            passesInstallAllowlist: passesInstallAllowlist
        )
    }

    private static func privacySafePath(_ appURL: URL) -> String {
        let path = appURL.standardizedFileURL.path
        if path == "/Applications" || path.hasPrefix("/Applications/") {
            return path
        }
        return "<selected-app>/\(appURL.lastPathComponent)"
    }
}
