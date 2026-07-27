import WeChatGuardCore

func runCompatibilityTests() throws {
    let rules = CompatibilityRules.builtIn

    try test("accepts the known local WeChat build") {
        let result = rules.evaluate(
            version: try Version("4.1.7"),
            build: "34371",
            executableSHA256: "764966cdaaf945bc8b23968bb7b3dca3cdc4067e2891a38e28c7556788e0682c"
        )
        try expect(result == .supported(ruleID: "wechat-macos-4.1.7-34371"))
    }

    try test("rejects an unknown executable hash") {
        let result = rules.evaluate(
            version: try Version("4.1.7"),
            build: "34371",
            executableSHA256: String(repeating: "0", count: 64)
        )
        try expect(result == .unknownHash(ruleID: "wechat-macos-4.1.7-34371"))
    }

    try test("rejects an unsupported version") {
        let result = rules.evaluate(
            version: try Version("4.2.0"),
            build: "1",
            executableSHA256: String(repeating: "0", count: 64)
        )
        try expect(result == .unsupportedVersion)
    }
}
