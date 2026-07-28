import Foundation
import IHaveAlreadySeenItCore
import Testing

@Suite struct CommunitySupportTests {
    @Test
    func buildsAFixedAdministratorInstallCommand() throws {
        let builder = AdministratorCommandBuilder(
            toolBundleURL: URL(fileURLWithPath: "/Applications/IHaveAlreadySeenIt.app")
        )

        let command = try builder.command(
            for: .install,
            appURL: URL(fileURLWithPath: "/Applications/WeChat.app")
        )

        #expect(command == """
        /usr/bin/sudo -- '/Applications/IHaveAlreadySeenIt.app/Contents/Helpers/ihavealreadyseenit' install --confirm-i-understand --app '/Applications/WeChat.app'
        """)
    }

    @Test
    func shellQuotesSpacesUnicodeAndSingleQuotes() throws {
        let builder = AdministratorCommandBuilder(
            toolBundleURL: URL(fileURLWithPath: "/Applications/I Have 已读.app")
        )

        let command = try builder.command(
            for: .restore,
            appURL: URL(fileURLWithPath: "/Applications/We'Chat 微信.app")
        )

        #expect(command == """
        /usr/bin/sudo -- '/Applications/I Have 已读.app/Contents/Helpers/ihavealreadyseenit' uninstall --app '/Applications/We'\\''Chat 微信.app'
        """)
    }

    @Test
    func rejectsControlCharactersAndNonAppToolBundles() {
        let validBuilder = AdministratorCommandBuilder(
            toolBundleURL: URL(fileURLWithPath: "/Applications/IHaveAlreadySeenIt.app")
        )
        #expect(throws: AdministratorCommandError.unsafePath) {
            try validBuilder.command(
                for: .install,
                appURL: URL(fileURLWithPath: "/Applications/WeChat\n.app")
            )
        }

        let invalidBuilder = AdministratorCommandBuilder(
            toolBundleURL: URL(fileURLWithPath: "/tmp/IHaveAlreadySeenIt")
        )
        #expect(throws: AdministratorCommandError.invalidToolBundle) {
            try invalidBuilder.command(
                for: .restore,
                appURL: URL(fileURLWithPath: "/Applications/WeChat.app")
            )
        }
    }

    @Test
    func commandInjectionCharactersRemainInsideOneQuotedArgument() throws {
        let builder = AdministratorCommandBuilder(
            toolBundleURL: URL(fileURLWithPath: "/Applications/IHaveAlreadySeenIt.app")
        )
        let command = try builder.command(
            for: .install,
            appURL: URL(fileURLWithPath: "/Applications/$(touch PWNED); 微信.app")
        )

        #expect(command.hasSuffix("--app '/Applications/$(touch PWNED); 微信.app'"))
        #expect(!command.contains("; /"))
    }

    @Test
    func mapsReportsToOneClearPrimaryAction() {
        let ready = CommunityHomePresentation(
            report: report(),
            isBusy: false,
            backend: .localDevelopment
        )
        #expect(ready.status == .readyToInstall)
        #expect(ready.primaryAction == .install)
        #expect(ready.isPrimaryEnabled)

        let installed = CommunityHomePresentation(
            report: report(
                signature: .adHoc,
                compatibility: .unknownHash(ruleID: "fixture"),
                installation: .installed(architectures: ["arm64", "x86_64"]),
                backup: .present
            ),
            isBusy: false,
            backend: .localDevelopment
        )
        #expect(installed.status == .installed)
        #expect(installed.primaryAction == .restore)

        let blocked = CommunityHomePresentation(
            report: report(compatibility: .unsupportedVersion),
            isBusy: false,
            backend: .localDevelopment
        )
        #expect(blocked.status == .needsAttention)
        #expect(blocked.primaryAction == .recheck)

        let busy = CommunityHomePresentation(
            report: report(),
            isBusy: true,
            backend: .localDevelopment
        )
        #expect(busy.status == .working)
        #expect(!busy.isPrimaryEnabled)
    }

    @Test
    func localizedStringCatalogsHaveIdenticalKeys() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resources = repository.appendingPathComponent("Sources/IHaveAlreadySeenItApp/Resources")
        let chinese = try #require(NSDictionary(
            contentsOf: resources.appendingPathComponent("zh-Hans.lproj/Localizable.strings")
        ) as? [String: String])
        let english = try #require(NSDictionary(
            contentsOf: resources.appendingPathComponent("en.lproj/Localizable.strings")
        ) as? [String: String])

        #expect(Set(chinese.keys) == Set(english.keys))
        let chineseHasEmptyValue = chinese.values.contains { $0.isEmpty }
        let englishHasEmptyValue = english.values.contains { $0.isEmpty }
        #expect(!chineseHasEmptyValue)
        #expect(!englishHasEmptyValue)
    }

    @Test
    func readmeSupportMatrixExactlyMatchesVerifiedProfiles() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let readme = try String(
            contentsOf: repository.appendingPathComponent("README.md"),
            encoding: .utf8
        )
        let actualRows = readme.split(separator: "\n").map(String.init).filter {
            $0.hasPrefix("| ") && !$0.contains("微信版本") && !$0.contains("---")
        }
        let expectedRows = CompatibilityRules.builtIn.rules
            .filter { $0.validationStatus == .verified }
            .map { rule in
                let architectures = rule.supportedArchitectures.map(\.rawValue).sorted()
                    .joined(separator: " + ")
                let hashes = rule.executableSHA256.sorted().map { "`\($0)`" }
                    .joined(separator: "<br>")
                return "| \(rule.version.description) | \(rule.build) | \(architectures) | \(hashes) | 已验证 |"
            }

        #expect(actualRows == expectedRows)
    }

    private func report(
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
