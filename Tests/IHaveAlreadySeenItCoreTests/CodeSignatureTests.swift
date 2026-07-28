import IHaveAlreadySeenItCore
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
}
