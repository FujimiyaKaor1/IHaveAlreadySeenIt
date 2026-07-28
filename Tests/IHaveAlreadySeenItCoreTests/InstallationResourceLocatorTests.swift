import Foundation
import IHaveAlreadySeenItCore
import Testing

@Suite struct InstallationResourceLocatorTests {
    @Test
    func resolvesACompleteStandardResourceBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHaveAlreadySeenIt-Resources-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent(
            InstallationResourceLocator.bundleName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("hook".utf8).write(to: bundle.appendingPathComponent("AntiRevokeHook.c"))
        try Data("entitlements".utf8).write(
            to: bundle.appendingPathComponent("IHaveAlreadySeenIt.entitlements")
        )

        let resources = try InstallationResourceLocator().resolve(searchRoots: [root])

        #expect(resources.hookSourceURL.lastPathComponent == "AntiRevokeHook.c")
        #expect(resources.entitlementsURL.lastPathComponent == "IHaveAlreadySeenIt.entitlements")
    }

    @Test
    func rejectsMissingOrPartialResourceBundles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHaveAlreadySeenIt-Partial-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent(
            InstallationResourceLocator.bundleName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("hook".utf8).write(to: bundle.appendingPathComponent("AntiRevokeHook.c"))

        #expect(throws: InstallationServiceError.resourceMissing(bundle.path)) {
            try InstallationResourceLocator().resolve(searchRoots: [root])
        }
    }
}
