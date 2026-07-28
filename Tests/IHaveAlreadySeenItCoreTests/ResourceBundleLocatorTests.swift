import Foundation
import IHaveAlreadySeenItCore
import Testing

@Suite struct ResourceBundleLocatorTests {
    private let bundleName = "IHaveAlreadySeenIt_IHaveAlreadySeenItApp.bundle"

    @Test
    func prefersTheStandardAppResourcesDirectory() {
        let appResources = URL(fileURLWithPath: "/Applications/IHaveAlreadySeenIt.app/Contents/Resources")
        let appBundle = URL(fileURLWithPath: "/Applications/IHaveAlreadySeenIt.app")
        let executable = URL(fileURLWithPath: "/Applications/IHaveAlreadySeenIt.app/Contents/MacOS/IHaveAlreadySeenItApp")

        let candidates = ResourceBundleLocator.candidateURLs(
            bundleName: bundleName,
            mainResourceURL: appResources,
            bundleURL: appBundle,
            executableURL: executable
        )

        #expect(candidates.first?.standardizedFileURL.path == appResources.appendingPathComponent(bundleName).standardizedFileURL.path)
        #expect(candidates.contains { $0.standardizedFileURL.path == appBundle.appendingPathComponent(bundleName).standardizedFileURL.path })
        #expect(candidates.contains { $0.standardizedFileURL.path == executable.deletingLastPathComponent().appendingPathComponent(bundleName).standardizedFileURL.path })
        #expect(candidates.count == Set(candidates).count)
    }

    @Test
    func includesSwiftPMExecutableAdjacentResourceFallback() {
        let executable = URL(fileURLWithPath: "/tmp/.build/arm64-apple-macosx/debug/IHaveAlreadySeenItApp")
        let adjacent = executable.deletingLastPathComponent()
            .appendingPathComponent(bundleName)

        let candidates = ResourceBundleLocator.candidateURLs(
            bundleName: bundleName,
            mainResourceURL: nil,
            bundleURL: nil,
            executableURL: executable
        )

        #expect(candidates.map { $0.standardizedFileURL.path } == [adjacent.standardizedFileURL.path])
    }

    @Test
    func missingResourceFallsBackToMainBundleWithoutFatalError() {
        let fallback = Bundle.main
        let resolved = ResourceBundleLocator.locate(
            bundleName: "Missing-(UUID().uuidString).bundle",
            mainBundle: fallback,
            executableURL: URL(fileURLWithPath: "/tmp/missing/IHaveAlreadySeenItApp")
        )

        #expect(resolved.bundleURL == fallback.bundleURL)
    }
}
