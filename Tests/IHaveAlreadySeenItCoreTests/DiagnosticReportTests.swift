import Foundation
import IHaveAlreadySeenItCore
import Testing

@Suite struct DiagnosticReportTests {
    @Test
    func JSONReportContainsOnlyPortableDiagnosticFields() throws {
        let report = DiagnosticReport(
            applicationPath: "/Applications/WeChat.app",
            version: "4.1.7",
            build: "34371",
            executableSHA256: String(repeating: "a", count: 64),
            architectures: ["arm64", "x86_64"],
            signatureMatches: ["arm64": 1, "x86_64": 1],
            codeSignature: .official(teamIdentifier: "5A4RE8SF68"),
            compatibility: .supported(ruleID: "rule"),
            installation: .notInstalled,
            backup: .missing
        )

        let data = try DiagnosticReportEncoder.jsonData(report)
        let decoded = try JSONDecoder().decode(DiagnosticReport.self, from: data)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(decoded == report)
        #expect(!text.contains(NSHomeDirectory()))
        #expect(!text.contains("account"))
    }

    @Test
    func supportedOfficialUnmodifiedApplicationIsSafeToInstall() {
        let report = DiagnosticReport(
            applicationPath: "/Applications/WeChat.app",
            version: "4.1.7",
            build: "34371",
            executableSHA256: String(repeating: "a", count: 64),
            architectures: ["arm64", "x86_64"],
            signatureMatches: ["arm64": 1, "x86_64": 1],
            codeSignature: .official(teamIdentifier: "5A4RE8SF68"),
            compatibility: .supported(ruleID: "rule"),
            installation: .notInstalled,
            backup: .missing
        )

        #expect(report.isSafeToInstall)
    }
}
