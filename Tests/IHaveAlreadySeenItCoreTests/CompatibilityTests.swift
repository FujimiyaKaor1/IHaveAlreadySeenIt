import IHaveAlreadySeenItCore
import Testing

@Suite struct CompatibilityTests {
    let rules = CompatibilityRules.builtIn

    @Test
    func testAcceptsKnownLocalWeChatBuild() throws {
        let result = rules.evaluate(
            version: try Version("4.1.7"),
            build: "34371",
            executableSHA256: "764966cdaaf945bc8b23968bb7b3dca3cdc4067e2891a38e28c7556788e0682c",
            architectureSHA256: [
                .arm64: "f7f9b8044c911e674d5a7c8b377f410a2784c07d67d80b5bce188ed221b199be",
                .x86_64: "a76693656f01bb7fd012844a9887fcb3897136f6ab18ede37473ac02f7d92060",
            ]
        )
        #expect(result == .supported(ruleID: "wechat-macos-4.1.7-34371"))
    }

    @Test
    func testRejectsMissingArchitectureHashesForAProfileThatRequiresThem() throws {
        let result = rules.evaluate(
            version: try Version("4.1.7"),
            build: "34371",
            executableSHA256: "764966cdaaf945bc8b23968bb7b3dca3cdc4067e2891a38e28c7556788e0682c"
        )

        #expect(result == .architectureHashMismatch(
            ruleID: "wechat-macos-4.1.7-34371"
        ))
    }

    @Test
    func testRejectsUnknownExecutableHash() throws {
        let result = rules.evaluate(
            version: try Version("4.1.7"),
            build: "34371",
            executableSHA256: String(repeating: "0", count: 64)
        )
        #expect(result == .unknownHash(ruleID: "wechat-macos-4.1.7-34371"))
    }

    @Test
    func testRejectsUnsupportedVersion() throws {
        let result = rules.evaluate(
            version: try Version("4.2.0"),
            build: "1",
            executableSHA256: String(repeating: "0", count: 64)
        )
        #expect(result == .unsupportedVersion)
    }

    @Test
    func testRejectsUnknownBuildOfAKnownVersion() throws {
        let result = rules.evaluate(
            version: try Version("4.1.7"),
            build: "34372",
            executableSHA256: "764966cdaaf945bc8b23968bb7b3dca3cdc4067e2891a38e28c7556788e0682c"
        )
        #expect(result == .unsupportedVersion)
    }

    @Test
    func oneProfileCanOwnMultipleSeparatelyVerifiedWholeHashes() throws {
        let first = String(repeating: "a", count: 64)
        let second = String(repeating: "b", count: 64)
        let rules = CompatibilityRules(rules: [
            CompatibilityRule(
                id: "multi-hash",
                version: try Version("4.2.0"),
                build: "40000",
                executableSHA256: [first, second]
            ),
        ])

        #expect(rules.evaluate(
            version: try Version("4.2.0"), build: "40000", executableSHA256: first
        ) == .supported(ruleID: "multi-hash"))
        #expect(rules.evaluate(
            version: try Version("4.2.0"), build: "40000", executableSHA256: second
        ) == .supported(ruleID: "multi-hash"))
    }
}
