import IHaveAlreadySeenItCore
import Foundation
import Testing

@Suite struct CodeSignatureTests {
    @Test
    func parsesTheVerifiedOfficialTeamIdentifier() {
        let output = """
        Identifier=com.tencent.xinWeChat
        Authority=Apple Mac OS Application Signing
        Authority=Apple Root CA
        TeamIdentifier=5A4RE8SF68
        """

        #expect(CodeSignatureParser.parse(description: output, verificationSucceeded: true)
            == .official(teamIdentifier: "5A4RE8SF68"))
    }

    @Test
    func distinguishesAnAdHocPatchedApplication() {
        let output = """
        Identifier=com.tencent.xinWeChat
        Signature=adhoc
        TeamIdentifier=not set
        """

        #expect(CodeSignatureParser.parse(description: output, verificationSucceeded: true) == .adHoc)
    }

    @Test
    func rejectsAnInvalidSignatureEvenWhenMetadataLooksOfficial() {
        let output = "TeamIdentifier=5A4RE8SF68"

        #expect(CodeSignatureParser.parse(description: output, verificationSucceeded: false)
            == .invalid(reason: "code signature verification failed"))
    }

    @Test
    func acceptsOfficialSignatureWhenStrictFailureIsOnlyFinderMetadata() throws {
        let runner = ScriptedSignatureRunner(results: [
            CommandResult(
                exitCode: 1,
                output: "WeChat.app: resource fork, Finder information, or similar detritus not allowed"
            ),
            CommandResult(exitCode: 0, output: String(repeating: "00", count: 32)),
            CommandResult(exitCode: 0, output: "WeChat.app: valid on disk"),
            CommandResult(
                exitCode: 0,
                output: """
                Identifier=com.tencent.xinWeChat
                TeamIdentifier=5A4RE8SF68
                """
            ),
        ])

        let status = try SystemCodeSignatureVerifier(runner: runner).status(
            of: URL(fileURLWithPath: "/Applications/WeChat.app")
        )

        #expect(status == .official(teamIdentifier: "5A4RE8SF68"))
        #expect(runner.arguments == [
            ["--verify", "--deep", "--strict", "/Applications/WeChat.app"],
            ["-px", "com.apple.FinderInfo", "/Applications/WeChat.app"],
            ["--verify", "--deep", "/Applications/WeChat.app"],
            ["-dv", "--verbose=4", "/Applications/WeChat.app"],
        ])
        #expect(runner.executables == [
            "/usr/bin/codesign",
            "/usr/bin/xattr",
            "/usr/bin/codesign",
            "/usr/bin/codesign",
        ])
    }

    @Test
    func doesNotRelaxVerificationWhenFinderMetadataIsNotTheOnlyFailure() throws {
        let runner = ScriptedSignatureRunner(results: [
            CommandResult(
                exitCode: 1,
                output: """
                WeChat.app: resource fork, Finder information, or similar detritus not allowed
                file with invalid attached data: Disallowed xattr com.apple.FinderInfo found on WeChat.app
                WeChat.app: a sealed resource is missing or invalid
                """
            ),
            CommandResult(exitCode: 0, output: "TeamIdentifier=5A4RE8SF68"),
        ])

        let status = try SystemCodeSignatureVerifier(runner: runner).status(
            of: URL(fileURLWithPath: "/Applications/WeChat.app")
        )

        #expect(status == .invalid(reason: "code signature verification failed"))
        #expect(runner.arguments == [
            ["--verify", "--deep", "--strict", "/Applications/WeChat.app"],
            ["-dv", "--verbose=4", "/Applications/WeChat.app"],
        ])
    }

    @Test
    func doesNotRelaxVerificationForUnexpectedFinderInfoSize() throws {
        let runner = ScriptedSignatureRunner(results: [
            CommandResult(
                exitCode: 1,
                output: "WeChat.app: resource fork, Finder information, or similar detritus not allowed"
            ),
            CommandResult(exitCode: 0, output: String(repeating: "00", count: 31)),
            CommandResult(exitCode: 0, output: "TeamIdentifier=5A4RE8SF68"),
        ])

        let status = try SystemCodeSignatureVerifier(runner: runner).status(
            of: URL(fileURLWithPath: "/Applications/WeChat.app")
        )

        #expect(status == .invalid(reason: "code signature verification failed"))
        #expect(runner.executables == [
            "/usr/bin/codesign",
            "/usr/bin/xattr",
            "/usr/bin/codesign",
        ])
    }
}

private final class ScriptedSignatureRunner: @unchecked Sendable, ProcessRunning {
    private var results: [CommandResult]
    private(set) var executables: [String] = []
    private(set) var arguments: [[String]] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(
        _ executable: String,
        _ arguments: [String],
        allowedExitCodes: Set<Int32>
    ) throws -> CommandResult {
        executables.append(executable)
        self.arguments.append(arguments)
        return results.removeFirst()
    }
}
