import IHaveAlreadySeenItCore
import Testing

@Suite struct CompatibilityTests {
    let rules = CompatibilityRules.builtIn

    @Test
    func testAcceptsKnownLocalWeChatBuild() throws {
        let result = rules.evaluate(
            version: try Version("4.1.7"),
            build: "34371",
            executableSHA256: "764966cdaaf945bc8b23968bb7b3dca3cdc4067e2891a38e28c7556788e0682c"
        )
        #expect(result == .supported(ruleID: "wechat-macos-4.1.7-34371"))
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
}
