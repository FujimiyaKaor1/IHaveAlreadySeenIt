import IHaveAlreadySeenItCore
import Testing

@Suite struct UserActionPolicyTests {
    @Test
    func enablesInstallOnlyForASafeIdleReport() {
        let policy = UserActionPolicy(report: makeReport(), isBusy: false)

        #expect(policy.canInspect)
        #expect(policy.canPlan)
        #expect(policy.canInstall)
        #expect(!policy.canRestore)
    }

    @Test
    func blocksAllMutatingActionsWhileBusy() {
        let policy = UserActionPolicy(report: makeReport(), isBusy: true)

        #expect(!policy.canInspect)
        #expect(!policy.canPlan)
        #expect(!policy.canInstall)
        #expect(!policy.canRestore)
    }

    @Test
    func readOnlyDistributionKeepsPlanningButBlocksMutations() {
        let policy = UserActionPolicy(
            report: makeReport(),
            isBusy: false,
            allowsMutatingOperations: false
        )

        #expect(policy.canInspect)
        #expect(policy.canPlan)
        #expect(!policy.canInstall)
        #expect(!policy.canRestore)
    }

    @Test
    func enablesRestoreOnlyForAnInstalledAppWithAValidBackup() {
        let report = makeReport(
            signature: .adHoc,
            compatibility: .unknownHash(ruleID: "fixture"),
            installation: .installed(architectures: ["arm64", "x86_64"]),
            backup: .present
        )
        let policy = UserActionPolicy(report: report, isBusy: false)

        #expect(!policy.canInstall)
        #expect(policy.canRestore)
    }

    @Test
    func enablesRestoreForAMissingApplicationWithAValidBackup() {
        let policy = UserActionPolicy(
            report: nil,
            isBusy: false,
            hasRecoverableBackupWithoutApplication: true
        )

        #expect(policy.canRestore)
        #expect(!policy.canInstall)
    }

    private func makeReport(
        signature: CodeSignatureStatus = .official(teamIdentifier: "5A4RE8SF68"),
        compatibility: CompatibilityDiagnostic = .supported(ruleID: "fixture"),
        installation: InstallationDiagnostic = .notInstalled,
        backup: BackupDiagnostic = .missing
    ) -> DiagnosticReport {
        DiagnosticReport(
            applicationPath: "/Applications/WeChat.app",
            version: "4.1.7",
            build: "34371",
            executableSHA256: String(repeating: "a", count: 64),
            architectures: ["arm64", "x86_64"],
            signatureMatches: ["arm64": 1, "x86_64": 1],
            codeSignature: signature,
            compatibility: compatibility,
            installation: installation,
            backup: backup
        )
    }
}
