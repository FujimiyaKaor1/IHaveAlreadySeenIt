import Foundation

public enum CompatibilityValidationStatus: String, Codable, Equatable, Sendable {
    case verified
    case candidate
}

public struct CompatibilityRule: Equatable, Sendable {
    public let id: String
    public let version: Version
    public let build: String
    public let executableSHA256: Set<String>
    public let architectureSHA256: [MachOArchitecture: Set<String>]
    public let signatures: SignatureSet
    public let supportedArchitectures: Set<MachOArchitecture>
    public let minimumHeaderSlack: Int
    public let validationStatus: CompatibilityValidationStatus

    public init(
        id: String,
        version: Version,
        build: String,
        executableSHA256: Set<String>,
        architectureSHA256: [MachOArchitecture: Set<String>] = [:],
        signatures: SignatureSet = .antiRevoke,
        supportedArchitectures: Set<MachOArchitecture> = Set(MachOArchitecture.allCases),
        minimumHeaderSlack: Int = 0,
        validationStatus: CompatibilityValidationStatus = .verified
    ) {
        self.id = id
        self.version = version
        self.build = build
        self.executableSHA256 = Set(executableSHA256.map { $0.lowercased() })
        self.architectureSHA256 = architectureSHA256.mapValues { hashes in
            Set(hashes.map { $0.lowercased() })
        }
        self.signatures = signatures
        self.supportedArchitectures = supportedArchitectures
        self.minimumHeaderSlack = minimumHeaderSlack
        self.validationStatus = validationStatus
    }
}

public enum CompatibilityResult: Equatable, Sendable {
    case supported(ruleID: String)
    case candidate(ruleID: String)
    case unknownHash(ruleID: String)
    case architectureHashMismatch(ruleID: String)
    case unsupportedVersion
}

public enum CompatibilityRulesValidationError: Error, Equatable, Sendable {
    case duplicateRuleID(String)
    case duplicateVersionBuild(String)
    case duplicateExecutableHash(String)
    case invalidHash(ruleID: String)
    case incompleteArchitectures(ruleID: String)
    case emptySignature(ruleID: String)
    case unsupportedVerifiedArchitectures(ruleID: String)
    case invalidHeaderSlack(ruleID: String)
    case tooManyVerifiedProfiles(Int)
}

public struct SupportedVersionDescriptor: Codable, Equatable, Sendable {
    public let ruleID: String
    public let version: String
    public let build: String
    public let architectures: [String]
    public let status: CompatibilityValidationStatus
}

public struct CompatibilityRules: Sendable {
    public let rules: [CompatibilityRule]

    /// Retained for source compatibility with tests and callers that construct
    /// ephemeral rules. Shipped rule catalogs use the validating initializer.
    public init(rules: [CompatibilityRule]) {
        self.rules = rules
    }

    public init(validating rules: [CompatibilityRule]) throws {
        let requiredSlack = try MachOEditor.requiredLoadCommandSpace(
            path: ApplicationInspector.defaultDylibPath
        )
        let verifiedCount = rules.count { $0.validationStatus == .verified }
        guard verifiedCount <= 2 else {
            throw CompatibilityRulesValidationError.tooManyVerifiedProfiles(verifiedCount)
        }
        var identifiers = Set<String>()
        var versions = Set<String>()
        var hashes = Set<String>()
        for rule in rules {
            guard identifiers.insert(rule.id).inserted else {
                throw CompatibilityRulesValidationError.duplicateRuleID(rule.id)
            }
            let versionBuild = "\(rule.version.description)-\(rule.build)"
            guard versions.insert(versionBuild).inserted else {
                throw CompatibilityRulesValidationError.duplicateVersionBuild(versionBuild)
            }
            guard !rule.executableSHA256.isEmpty,
                  rule.executableSHA256.allSatisfy(Self.isSHA256),
                  rule.architectureSHA256.values.allSatisfy({
                      !$0.isEmpty && $0.allSatisfy(Self.isSHA256)
                  }) else {
                throw CompatibilityRulesValidationError.invalidHash(ruleID: rule.id)
            }
            for hash in rule.executableSHA256 {
                guard hashes.insert(hash).inserted else {
                    throw CompatibilityRulesValidationError.duplicateExecutableHash(hash)
                }
            }
        }
        for rule in rules {
            guard !rule.executableSHA256.isEmpty,
                  rule.executableSHA256.allSatisfy(Self.isSHA256),
                  rule.architectureSHA256.values.flatMap(Array.init).allSatisfy(Self.isSHA256) else {
                throw CompatibilityRulesValidationError.invalidHash(ruleID: rule.id)
            }
            guard !rule.supportedArchitectures.isEmpty,
                  Set(rule.architectureSHA256.keys) == rule.supportedArchitectures else {
                throw CompatibilityRulesValidationError.incompleteArchitectures(ruleID: rule.id)
            }
            guard rule.signatures.arm64.count >= 8, rule.signatures.x86_64.count >= 8 else {
                throw CompatibilityRulesValidationError.emptySignature(ruleID: rule.id)
            }
            if rule.validationStatus == .verified,
               rule.supportedArchitectures != Set(MachOArchitecture.allCases) {
                throw CompatibilityRulesValidationError.unsupportedVerifiedArchitectures(
                    ruleID: rule.id
                )
            }
            guard rule.minimumHeaderSlack >= 0,
                  rule.validationStatus != .verified || rule.minimumHeaderSlack >= requiredSlack else {
                throw CompatibilityRulesValidationError.invalidHeaderSlack(ruleID: rule.id)
            }
        }
        self.rules = rules
    }

    public func rule(version: Version, build: String) -> CompatibilityRule? {
        rules.first { $0.version == version && $0.build == build }
    }

    public var supportMatrix: [SupportedVersionDescriptor] {
        rules.map { rule in
            SupportedVersionDescriptor(
                ruleID: rule.id,
                version: rule.version.description,
                build: rule.build,
                architectures: rule.supportedArchitectures.map(\.rawValue).sorted(),
                status: rule.validationStatus
            )
        }
    }

    public var verifiedSupportSummary: String {
        supportMatrix
            .filter { $0.status == .verified }
            .map { "\($0.version) (\($0.build))" }
            .joined(separator: ", ")
    }

    public func evaluate(
        version: Version,
        build: String,
        executableSHA256: String,
        architectureSHA256: [MachOArchitecture: String] = [:]
    ) -> CompatibilityResult {
        guard let rule = rule(version: version, build: build) else {
            return .unsupportedVersion
        }
        guard rule.executableSHA256.contains(executableSHA256.lowercased()) else {
            return .unknownHash(ruleID: rule.id)
        }
        if !rule.architectureSHA256.isEmpty {
            guard rule.supportedArchitectures.allSatisfy({ architecture in
                guard let actual = architectureSHA256[architecture]?.lowercased(),
                      let expected = rule.architectureSHA256[architecture] else {
                    return false
                }
                return expected.contains(actual)
            }) else {
                return .architectureHashMismatch(ruleID: rule.id)
            }
        }
        return rule.validationStatus == .verified
            ? .supported(ruleID: rule.id)
            : .candidate(ruleID: rule.id)
    }

    public static let builtIn: CompatibilityRules = {
        let requiredSlack = (try? MachOEditor.requiredLoadCommandSpace(
            path: ApplicationInspector.defaultDylibPath
        )) ?? .max
        let rule = CompatibilityRule(
            id: "wechat-macos-4.1.7-34371",
            version: Version(components: [4, 1, 7]),
            build: "34371",
            executableSHA256: [
                "764966cdaaf945bc8b23968bb7b3dca3cdc4067e2891a38e28c7556788e0682c",
            ],
            architectureSHA256: [
                .arm64: ["f7f9b8044c911e674d5a7c8b377f410a2784c07d67d80b5bce188ed221b199be"],
                .x86_64: ["a76693656f01bb7fd012844a9887fcb3897136f6ab18ede37473ac02f7d92060"],
            ],
            signatures: .antiRevoke,
            supportedArchitectures: Set(MachOArchitecture.allCases),
            minimumHeaderSlack: requiredSlack,
            validationStatus: .verified
        )
        return (try? CompatibilityRules(validating: [rule])) ?? CompatibilityRules(rules: [])
    }()

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }
}
