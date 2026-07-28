import Foundation
import IHaveAlreadySeenItCore
import Testing

@Suite struct PathSecurityTests {
    @Test
    func acceptsARealAppDirectoryOwnedByTheCurrentUser() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("WeChat.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        let result = try ApplicationPathValidator().validate(appURL: app, requireWritableParent: true)

        #expect(result == app.standardizedFileURL)
    }

    @Test
    func rejectsANonAppDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: ApplicationPathValidationError.notAppBundle) {
            try ApplicationPathValidator().validate(appURL: root, requireWritableParent: false)
        }
    }

    @Test
    func rejectsASymbolicLinkApp() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("Real.app", isDirectory: true)
        let link = root.appendingPathComponent("WeChat.app", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(throws: ApplicationPathValidationError.symbolicLink) {
            try ApplicationPathValidator().validate(appURL: link, requireWritableParent: false)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IHaveAlreadySeenIt-PathTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
