import WeChatGuardCore

func runVersionTests() throws {
    try test("parses and compares numeric versions") {
        let older = try Version("4.1.7")
        let newer = try Version("4.1.10")

        try expect(older < newer)
        try expect(try Version("4.1.7.0") == older)
        try expect(newer.description == "4.1.10")
    }

    try test("rejects malformed versions") {
        try expectThrows(VersionError.self) { try Version("4.1.beta") }
        try expectThrows(VersionError.self) { try Version("") }
    }

    try test("compares versions with different component counts") {
        try expect(try Version("4.2") > Version("4.1.99"))
        try expect(!(try Version("4.1.7") < Version("4.1.7.0")))
    }
}
