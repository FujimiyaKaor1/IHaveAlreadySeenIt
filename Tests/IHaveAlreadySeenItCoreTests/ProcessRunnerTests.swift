import IHaveAlreadySeenItCore
import Testing

@Suite struct ProcessRunnerTests {
    @Test
    func capturesSuccessfulCommandOutput() throws {
        let result = try SystemProcessRunner().run("/usr/bin/printf", ["hello"])

        #expect(result == CommandResult(exitCode: 0, output: "hello"))
    }

    @Test
    func reportsARejectedExitCode() {
        #expect(throws: CommandExecutionError.self) {
            try SystemProcessRunner().run("/usr/bin/false", [])
        }
    }

    @Test
    func reportsAnExecutableThatCannotBeLaunched() {
        #expect(throws: CommandExecutionError.self) {
            try SystemProcessRunner().run("/definitely/missing/IHaveAlreadySeenIt", [])
        }
    }
}
