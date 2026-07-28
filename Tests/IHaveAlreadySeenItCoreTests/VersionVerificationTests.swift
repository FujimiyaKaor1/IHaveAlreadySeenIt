import Foundation
import IHaveAlreadySeenItCore
import Testing

@Suite struct VersionVerificationTests {
    @Test
    func unknownVersionProducesReadOnlyCandidateEvidenceForEveryProfile() throws {
        let executable = MachOFixture.universalBinary(includePatterns: true)
        let app = try makeVerificationFixtureApp(executable: executable)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let service = VersionVerificationService(
            rules: .builtIn,
            signatureVerifier: VerificationSignatureVerifier(
                status: .official(teamIdentifier: DiagnosticService.expectedTeamIdentifier)
            )
        )

        let report = try service.report(appURL: app)

        #expect(report.version == "9.9.9")
        #expect(report.build == "99999")
        #expect(report.codeSignature == .official(
            teamIdentifier: DiagnosticService.expectedTeamIdentifier
        ))
        #expect(report.architectureSHA256.keys.sorted() == ["arm64", "x86_64"])
        #expect(report.headerSlack.values.allSatisfy { $0 >= 512 })
        let check = try #require(report.profileChecks.first)
        #expect(check.ruleID == "wechat-macos-4.1.7-34371")
        #expect(!check.versionBuildMatches)
        #expect(check.signatureMatches == ["arm64": 1, "x86_64": 1])
        #expect(check.signaturesAreUnique)
        #expect(check.headerSlackPasses)
        #expect(report.isCandidateReadyForManualReview)
        #expect(!report.passesInstallAllowlist)
    }

    @Test
    func verifiedOfficialProfilePassesAllowlistWithoutBecomingACandidate() throws {
        let executable = MachOFixture.universalBinary(includePatterns: true)
        let hashes = try MachOAnalyzer.architectureSHA256(in: executable)
        let rule = CompatibilityRule(
            id: "verified-profile",
            version: try Version("4.2.0"),
            build: "42000",
            executableSHA256: [SHA256Digest.hex(of: executable)],
            architectureSHA256: hashes.mapValues { [$0] },
            signatures: .antiRevoke,
            supportedArchitectures: Set(MachOArchitecture.allCases),
            minimumHeaderSlack: 128,
            validationStatus: .verified
        )
        let app = try makeVerificationFixtureApp(
            executable: executable,
            version: "4.2.0",
            build: "42000"
        )
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let service = VersionVerificationService(
            rules: CompatibilityRules(rules: [rule]),
            signatureVerifier: VerificationSignatureVerifier(
                status: .official(teamIdentifier: DiagnosticService.expectedTeamIdentifier)
            )
        )

        let report = try service.report(appURL: app)

        #expect(report.passesInstallAllowlist)
        #expect(!report.isCandidateReadyForManualReview)
    }

    @Test
    func verificationJSONContainsNoExecutableBytesOrAccountData() throws {
        let executable = MachOFixture.universalBinary(includePatterns: true)
        let app = try makeVerificationFixtureApp(executable: executable)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let report = try VersionVerificationService(
            rules: .builtIn,
            signatureVerifier: VerificationSignatureVerifier(status: .adHoc)
        ).report(appURL: app)

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(VersionVerificationReport.self, from: data)
        let text = String(decoding: data, as: UTF8.self)

        #expect(decoded == report)
        #expect(!text.contains("message"))
        #expect(!text.contains("account"))
        #expect(!text.contains(executable.base64EncodedString()))
        #expect(!report.isCandidateReadyForManualReview)
    }
}

private struct VerificationSignatureVerifier: CodeSignatureVerifying {
    let status: CodeSignatureStatus
    func status(of appURL: URL) throws -> CodeSignatureStatus { status }
}

private func makeVerificationFixtureApp(
    executable: Data,
    version: String = "9.9.9",
    build: String = "99999"
) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("IHaveAlreadySeenIt-VerificationTests-\(UUID().uuidString)")
    let app = root.appendingPathComponent("WeChat.app", isDirectory: true)
    let contents = app.appendingPathComponent("Contents", isDirectory: true)
    let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleExecutable": "WeChat",
        "CFBundleIdentifier": ApplicationInspector.expectedBundleIdentifier,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
    try executable.write(to: macOS.appendingPathComponent("WeChat"))
    return app
}
