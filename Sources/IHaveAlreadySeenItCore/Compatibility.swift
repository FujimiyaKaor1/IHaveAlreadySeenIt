import Foundation

public struct CompatibilityRule: Equatable, Sendable {
    public let id: String
    public let version: Version
    public let build: String
    public let executableSHA256: Set<String>

    public init(id: String, version: Version, build: String, executableSHA256: Set<String>) {
        self.id = id
        self.version = version
        self.build = build
        self.executableSHA256 = Set(executableSHA256.map { $0.lowercased() })
    }
}

public enum CompatibilityResult: Equatable, Sendable {
    case supported(ruleID: String)
    case unknownHash(ruleID: String)
    case unsupportedVersion
}

public struct CompatibilityRules: Sendable {
    public let rules: [CompatibilityRule]

    public init(rules: [CompatibilityRule]) {
        self.rules = rules
    }

    public func evaluate(
        version: Version,
        build: String,
        executableSHA256: String
    ) -> CompatibilityResult {
        guard let rule = rules.first(where: { $0.version == version && $0.build == build }) else {
            return .unsupportedVersion
        }
        guard rule.executableSHA256.contains(executableSHA256.lowercased()) else {
            return .unknownHash(ruleID: rule.id)
        }
        return .supported(ruleID: rule.id)
    }

    public static let builtIn = CompatibilityRules(rules: [
        CompatibilityRule(
            id: "wechat-macos-4.1.7-34371",
            version: Version(components: [4, 1, 7]),
            build: "34371",
            executableSHA256: [
                "764966cdaaf945bc8b23968bb7b3dca3cdc4067e2891a38e28c7556788e0682c",
            ]
        ),
    ])
}
