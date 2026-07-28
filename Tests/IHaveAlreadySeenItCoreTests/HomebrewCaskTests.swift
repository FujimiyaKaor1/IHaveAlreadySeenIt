import Foundation
import Testing

@Suite struct HomebrewCaskTests {
    @Test
    func shippedCaskPinsThePublishedReleaseWithoutBypassingGatekeeper() throws {
        let cask = try reviewedCask()
        let metadata = try caskMetadata(from: cask)

        #expect(cask.contains("version \"\(metadata.version)\""))
        #expect(cask.contains("sha256 \"\(metadata.sha256)\""))
        #expect(cask.contains(
            "releases/download/v#{version}/IHaveAlreadySeenIt-#{version}-Community.dmg"
        ))
        #expect(cask.contains("depends_on macos: :sonoma"))
        #expect(cask.contains("app \"IHaveAlreadySeenIt.app\""))
        #expect(cask.contains("右键"))
        #expect(cask.contains("恢复原版微信"))
        #expect(cask.contains("brew uninstall --cask ihavealreadyseenit"))
        #expect(!cask.contains("no_quarantine"))
        #expect(!cask.contains("system "))
        #expect(!cask.contains("uninstall_preflight"))
    }

    @Test
    func rendererProducesTheReviewedCaskFromVersionAndDigest() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHaveAlreadySeenIt-CaskTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = temporary.appendingPathComponent("ihavealreadyseenit.rb")
        let metadata = try caskMetadata(from: reviewedCask())

        let result = try runRenderer(
            version: metadata.version,
            sha256: metadata.sha256,
            output: output
        )

        #expect(result.status == 0)
        let rendered = try Data(contentsOf: output)
        let reviewed = try Data(contentsOf: repositoryRoot.appendingPathComponent("Casks/ihavealreadyseenit.rb"))
        #expect(rendered == reviewed)
    }

    @Test(arguments: [
        ("v1.0.0", String(repeating: "a", count: 64)),
        ("1.0", String(repeating: "a", count: 64)),
        ("1.0.0", "not-a-sha256"),
        ("1.0.0; touch /tmp/unsafe", String(repeating: "a", count: 64)),
    ])
    func rendererRejectsInvalidOrInjectableInputs(version: String, sha256: String) throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHaveAlreadySeenIt-invalid-\(UUID().uuidString).rb")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runRenderer(version: version, sha256: sha256, output: output)

        #expect(result.status != 0)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test
    func readmeOffersHomebrewAndManualInstallWithSafeUninstallGuidance() throws {
        let readme = try String(
            contentsOf: repositoryRoot.appendingPathComponent("README.md"),
            encoding: .utf8
        )

        #expect(readme.contains(
            "brew tap FujimiyaKaor1/ihavealreadyseenit https://github.com/FujimiyaKaor1/IHaveAlreadySeenIt.git"
        ))
        #expect(readme.contains(
            "brew install --cask FujimiyaKaor1/ihavealreadyseenit/ihavealreadyseenit"
        ))
        #expect(readme.contains("brew upgrade --cask ihavealreadyseenit"))
        #expect(readme.contains("brew uninstall --cask ihavealreadyseenit"))
        #expect(readme.contains("先恢复原版微信"))
        #expect(readme.contains("Community.dmg"))
        #expect(readme.contains("右键"))
    }

    @Test
    func releaseAndCIWorkflowsGenerateAndAuditTheCask() throws {
        let releaseScript = try contents("scripts/release.sh")
        let releaseWorkflow = try contents(".github/workflows/release.yml")
        let ciWorkflow = try contents(".github/workflows/ci.yml")
        let updateWorkflow = try contents(".github/workflows/update-homebrew-cask.yml")

        #expect(releaseScript.contains("render-homebrew-cask.sh"))
        #expect(releaseScript.contains("Community.dmg.sha256"))
        #expect(releaseWorkflow.contains("dist/Casks/ihavealreadyseenit.rb"))
        #expect(ciWorkflow.contains("verify-homebrew-cask.sh"))
        #expect(updateWorkflow.contains("workflow_dispatch:"))
        #expect(updateWorkflow.contains("permissions:"))
        #expect(updateWorkflow.contains("contents: write"))
        #expect(updateWorkflow.contains("render-homebrew-cask.sh"))
        #expect(updateWorkflow.contains("status --porcelain -- Casks/ihavealreadyseenit.rb"))
        #expect(updateWorkflow.contains("push origin HEAD:main"))
        #expect(!updateWorkflow.contains("HOMEBREW_TAP_TOKEN"))
        #expect(!updateWorkflow.contains("FujimiyaKaor1/homebrew-tap"))
        #expect(!updateWorkflow.contains("no_quarantine"))
    }

    @Test
    func tapReadmeDocumentsInstallUpgradeAndSafeUninstall() throws {
        let tapReadme = try contents("Packaging/Homebrew/README.md")

        #expect(tapReadme.contains(
            "brew tap FujimiyaKaor1/ihavealreadyseenit https://github.com/FujimiyaKaor1/IHaveAlreadySeenIt.git"
        ))
        #expect(tapReadme.contains(
            "brew install --cask FujimiyaKaor1/ihavealreadyseenit/ihavealreadyseenit"
        ))
        #expect(tapReadme.contains("brew upgrade --cask ihavealreadyseenit"))
        #expect(tapReadme.contains("恢复原版微信"))
        #expect(tapReadme.contains("right-click"))
        #expect(tapReadme.contains("GitHub Release"))
    }

    @Test
    func caskLivesAtTapRootAndNeedsNoNestedTapRepository() throws {
        let fileManager = FileManager.default

        #expect(fileManager.fileExists(atPath: repositoryRoot
            .appendingPathComponent("Casks/ihavealreadyseenit.rb").path))
        #expect(!fileManager.fileExists(atPath: repositoryRoot
            .appendingPathComponent("Packaging/Homebrew/Casks/ihavealreadyseenit.rb").path))
        #expect(!fileManager.fileExists(atPath: repositoryRoot
            .appendingPathComponent(".github/workflows/sync-homebrew-tap.yml").path))
        #expect(!fileManager.fileExists(atPath: repositoryRoot
            .appendingPathComponent("Packaging/Homebrew/.github/workflows/audit.yml").path))
    }

    @Test
    func homebrewSmokeTestUsesAnIsolatedAppDirectoryAndPreservesTheWeChatBackup() throws {
        let smokeTest = try contents("scripts/test-homebrew-cask.sh")

        #expect(smokeTest.contains("--appdir="))
        #expect(smokeTest.contains("brew tap \"$TAP\" \"file://$TAP_SOURCE\""))
        #expect(smokeTest.contains("Casks/ihavealreadyseenit.rb"))
        #expect(smokeTest.contains("brew install --cask"))
        #expect(smokeTest.contains("brew reinstall --cask"))
        #expect(smokeTest.contains("brew uninstall --cask"))
        #expect(smokeTest.contains("brew untrust --cask"))
        #expect(smokeTest.contains("xattr -p com.apple.quarantine"))
        #expect(smokeTest.contains("spctl --assess --type execute"))
        #expect(smokeTest.contains(".IHaveAlreadySeenItBackup/Original-WeChat.bundle"))
        #expect(smokeTest.contains("shasum -a 256"))
        #expect(!smokeTest.contains("/Applications/WeChat.app"))
        #expect(!smokeTest.contains("killall"))
        #expect(!smokeTest.contains("no-quarantine"))
        #expect(!smokeTest.contains("brew tap-new"))
    }

    @Test
    func packageAndReleaseWorkflowsExerciseThePackagedGUIResources() throws {
        let packageScript = try contents("scripts/package-app.sh")
        let releaseWorkflow = try contents(".github/workflows/release.yml")

        #expect(packageScript.contains("APP_BUNDLE=\"$APP_RESOURCES/IHaveAlreadySeenIt_IHaveAlreadySeenItApp.bundle\""))
        #expect(packageScript.contains("Contents/Resources/AppIcon.icns"))
        #expect(releaseWorkflow.contains("test -d \"$MOUNT/IHaveAlreadySeenIt.app/Contents/Resources"))
        #expect(releaseWorkflow.contains("scripts/test-app-launch.sh"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func reviewedCask() throws -> String {
        try contents("Casks/ihavealreadyseenit.rb")
    }

    private func caskMetadata(from cask: String) throws -> (version: String, sha256: String) {
        let lines = cask.split(whereSeparator: \.isNewline).map(String.init)
        guard let versionLine = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("version ") }),
              let shaLine = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("sha256 ") }),
              let version = versionLine.split(separator: "\"").dropFirst().first,
              let sha256 = shaLine.split(separator: "\"").dropFirst().first else {
            throw NSError(domain: "HomebrewCaskTests", code: 1)
        }
        return (String(version), String(sha256))
    }

    private func runRenderer(
        version: String,
        sha256: String,
        output: URL
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            repositoryRoot.appendingPathComponent("scripts/render-homebrew-cask.sh").path,
            version,
            sha256,
            output.path,
        ]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
