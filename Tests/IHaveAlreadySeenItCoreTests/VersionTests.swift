import IHaveAlreadySeenItCore
import Testing

@Suite struct VersionTests {
    @Test
    func testParsesAndComparesNumericVersions() throws {
        let older = try Version("4.1.7")
        let newer = try Version("4.1.10")

        #expect(older < newer)
        #expect(try Version("4.1.7.0") == older)
        #expect(newer.description == "4.1.10")
    }

    @Test
    func testRejectsMalformedVersions() {
        #expect(throws: VersionError.self) { try Version("4.1.beta") }
        #expect(throws: VersionError.self) { try Version("") }
    }

    @Test
    func testComparesVersionsWithDifferentComponentCounts() throws {
        #expect(try Version("4.2") > Version("4.1.99"))
        #expect(try !(Version("4.1.7") < Version("4.1.7.0")))
    }
}
