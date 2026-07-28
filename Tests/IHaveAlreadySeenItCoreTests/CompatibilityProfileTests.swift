import Foundation
import IHaveAlreadySeenItCore
import Testing

@Suite struct CompatibilityProfileTests {
    private let customSignatures = SignatureSet(
        arm64: Data([0x10, 0x20, 0x30, 0x40, 0x50]),
        x86_64: Data([0x60, 0x70, 0x80, 0x90, 0xA0])
    )

    @Test
    func inspectorUsesTheMatchedProfilesArchitectureSignatures() throws {
        let executable = MachOFixture.universalBinary(
            includePatterns: true,
            signatures: customSignatures
        )
        let hashes = try MachOAnalyzer.architectureSHA256(in: executable)
        let rule = CompatibilityRule(
            id: "custom-profile",
            version: try Version("4.2.0"),
            build: "40000",
            executableSHA256: [SHA256Digest.hex(of: executable)],
            architectureSHA256: hashes.mapValues { [$0] },
            signatures: customSignatures,
            supportedArchitectures: Set(MachOArchitecture.allCases),
            minimumHeaderSlack: 128,
            validationStatus: .verified
        )
        let app = try makeProfileFixtureApp(
            executable: executable,
            version: "4.2.0",
            build: "40000"
        )
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let report = try ApplicationInspector(
            compatibilityRules: CompatibilityRules(rules: [rule])
        ).inspect(appURL: app)

        #expect(report.compatibility == .supported(ruleID: "custom-profile"))
        #expect(report.signatureScan[.arm64] == 1)
        #expect(report.signatureScan[.x86_64] == 1)
        #expect(report.compatibilityProfile?.id == "custom-profile")
    }

    @Test
    func candidateProfilesRemainDiagnosticOnly() throws {
        let executable = MachOFixture.universalBinary(includePatterns: true)
        let rule = CompatibilityRule(
            id: "candidate-profile",
            version: try Version("4.2.1"),
            build: "40100",
            executableSHA256: [SHA256Digest.hex(of: executable)],
            signatures: .antiRevoke,
            validationStatus: .candidate
        )
        let app = try makeProfileFixtureApp(
            executable: executable,
            version: "4.2.1",
            build: "40100"
        )
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let report = try ApplicationInspector(
            compatibilityRules: CompatibilityRules(rules: [rule])
        ).inspect(appURL: app)

        #expect(report.compatibility == .candidate(ruleID: "candidate-profile"))
        #expect(throws: PatchPlanningError.candidateVersion) {
            try PatchPlanner.prepareExecutable(executable, report: report)
        }
    }

    @Test
    func verifiedProfileRejectsAnUnexpectedArchitectureDigest() throws {
        let executable = MachOFixture.universalBinary(includePatterns: true)
        let rule = CompatibilityRule(
            id: "digest-profile",
            version: try Version("4.2.2"),
            build: "40200",
            executableSHA256: [SHA256Digest.hex(of: executable)],
            architectureSHA256: [
                .arm64: [String(repeating: "a", count: 64)],
                .x86_64: [String(repeating: "b", count: 64)],
            ],
            signatures: .antiRevoke,
            validationStatus: .verified
        )
        let app = try makeProfileFixtureApp(
            executable: executable,
            version: "4.2.2",
            build: "40200"
        )
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let report = try ApplicationInspector(
            compatibilityRules: CompatibilityRules(rules: [rule])
        ).inspect(appURL: app)

        #expect(report.compatibility == .architectureHashMismatch(ruleID: "digest-profile"))
        #expect(!report.isProfileSafeToPatch)
    }

    @Test
    func profileHeaderSlackRequirementBlocksPlanning() throws {
        let executable = MachOFixture.universalBinary(
            headerSlack: 128,
            includePatterns: true
        )
        let hashes = try MachOAnalyzer.architectureSHA256(in: executable)
        let rule = CompatibilityRule(
            id: "slack-profile",
            version: try Version("4.2.3"),
            build: "40300",
            executableSHA256: [SHA256Digest.hex(of: executable)],
            architectureSHA256: hashes.mapValues { [$0] },
            signatures: .antiRevoke,
            minimumHeaderSlack: 256,
            validationStatus: .verified
        )
        let app = try makeProfileFixtureApp(
            executable: executable,
            version: "4.2.3",
            build: "40300"
        )
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let report = try ApplicationInspector(
            compatibilityRules: CompatibilityRules(rules: [rule])
        ).inspect(appURL: app)

        #expect(report.compatibility == .supported(ruleID: "slack-profile"))
        #expect(!report.isProfileSafeToPatch)
        #expect(throws: PatchPlanningError.insufficientHeaderSpace) {
            try PatchPlanner.prepareExecutable(executable, report: report)
        }
    }

    @Test
    func validatedRulesRejectDuplicateIdentifiersAndHashOwnership() throws {
        let hash = String(repeating: "c", count: 64)
        let first = CompatibilityRule(
            id: "duplicate",
            version: try Version("4.2.0"),
            build: "1",
            executableSHA256: [hash]
        )
        let secondID = CompatibilityRule(
            id: "duplicate",
            version: try Version("4.2.1"),
            build: "2",
            executableSHA256: [String(repeating: "d", count: 64)]
        )
        #expect(throws: CompatibilityRulesValidationError.duplicateRuleID("duplicate")) {
            try CompatibilityRules(validating: [first, secondID])
        }

        let secondHash = CompatibilityRule(
            id: "other",
            version: try Version("4.2.1"),
            build: "2",
            executableSHA256: [hash]
        )
        #expect(throws: CompatibilityRulesValidationError.duplicateExecutableHash(hash)) {
            try CompatibilityRules(validating: [first, secondHash])
        }

        let duplicateBuild = CompatibilityRule(
            id: "same-version-build",
            version: try Version("4.2.0"),
            build: "1",
            executableSHA256: [String(repeating: "e", count: 64)]
        )
        #expect(throws: CompatibilityRulesValidationError.duplicateVersionBuild("4.2-1")) {
            try CompatibilityRules(validating: [first, duplicateBuild])
        }
    }

    @Test
    func shippedCatalogCapsVerifiedProfilesAtTwo() throws {
        let rules = try (0..<3).map { index in
            CompatibilityRule(
                id: "verified-\(index)",
                version: try Version("4.\(index).0"),
                build: "\(index)",
                executableSHA256: [String(repeating: ["a", "d", "0"][index], count: 64)],
                architectureSHA256: [
                    .arm64: [String(repeating: ["b", "e", "1"][index], count: 64)],
                    .x86_64: [String(repeating: ["c", "f", "2"][index], count: 64)],
                ],
                validationStatus: .verified
            )
        }

        #expect(throws: CompatibilityRulesValidationError.tooManyVerifiedProfiles(3)) {
            try CompatibilityRules(validating: rules)
        }
    }

    @Test
    func armOnlyProfilesCannotBecomeVerifiedInTheUniversalPhase() throws {
        let rule = CompatibilityRule(
            id: "arm-only",
            version: try Version("5.0.0"),
            build: "50000",
            executableSHA256: [String(repeating: "a", count: 64)],
            architectureSHA256: [
                .arm64: [String(repeating: "b", count: 64)],
            ],
            signatures: .antiRevoke,
            supportedArchitectures: [.arm64],
            minimumHeaderSlack: try MachOEditor.requiredLoadCommandSpace(
                path: ApplicationInspector.defaultDylibPath
            ),
            validationStatus: .verified
        )

        #expect(throws: CompatibilityRulesValidationError.unsupportedVerifiedArchitectures(
            ruleID: "arm-only"
        )) {
            try CompatibilityRules(validating: [rule])
        }
    }

    @Test
    func validatedRulesRejectIncompleteHashesShortSignaturesAndUnsafeSlack() throws {
        let wholeHash = String(repeating: "a", count: 64)
        let architectureHashes: [MachOArchitecture: Set<String>] = [
            .arm64: [String(repeating: "b", count: 64)],
            .x86_64: [String(repeating: "c", count: 64)],
        ]

        let incomplete = CompatibilityRule(
            id: "incomplete",
            version: try Version("5.0.0"),
            build: "50000",
            executableSHA256: [wholeHash],
            architectureSHA256: [.arm64: architectureHashes[.arm64] ?? []],
            validationStatus: .candidate
        )
        #expect(throws: CompatibilityRulesValidationError.incompleteArchitectures(
            ruleID: "incomplete"
        )) {
            try CompatibilityRules(validating: [incomplete])
        }

        let shortSignature = CompatibilityRule(
            id: "short-signature",
            version: try Version("5.0.1"),
            build: "50001",
            executableSHA256: [wholeHash],
            architectureSHA256: architectureHashes,
            signatures: SignatureSet(arm64: Data([0x01]), x86_64: Data([0x02])),
            validationStatus: .candidate
        )
        #expect(throws: CompatibilityRulesValidationError.emptySignature(
            ruleID: "short-signature"
        )) {
            try CompatibilityRules(validating: [shortSignature])
        }

        let unsafeSlack = CompatibilityRule(
            id: "unsafe-slack",
            version: try Version("5.0.2"),
            build: "50002",
            executableSHA256: [wholeHash],
            architectureSHA256: architectureHashes,
            minimumHeaderSlack: 0,
            validationStatus: .verified
        )
        #expect(throws: CompatibilityRulesValidationError.invalidHeaderSlack(
            ruleID: "unsafe-slack"
        )) {
            try CompatibilityRules(validating: [unsafeSlack])
        }

        let invalidHash = CompatibilityRule(
            id: "invalid-hash",
            version: try Version("5.0.3"),
            build: "50003",
            executableSHA256: ["not-a-sha256"],
            architectureSHA256: architectureHashes,
            validationStatus: .candidate
        )
        #expect(throws: CompatibilityRulesValidationError.invalidHash(
            ruleID: "invalid-hash"
        )) {
            try CompatibilityRules(validating: [invalidHash])
        }
    }
}

private func makeProfileFixtureApp(
    executable: Data,
    version: String,
    build: String
) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("IHaveAlreadySeenIt-ProfileTests-\(UUID().uuidString)", isDirectory: true)
    let app = root.appendingPathComponent("WeChat.app", isDirectory: true)
    let contents = app.appendingPathComponent("Contents", isDirectory: true)
    let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleExecutable": "WeChat",
        "CFBundleIdentifier": "com.tencent.xinWeChat",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
    try executable.write(to: macOS.appendingPathComponent("WeChat"))
    return app
}
