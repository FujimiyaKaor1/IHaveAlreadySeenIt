import Foundation

public struct InstallationResources: Equatable, Sendable {
    public let hookSourceURL: URL
    public let entitlementsURL: URL

    public init(hookSourceURL: URL, entitlementsURL: URL) {
        self.hookSourceURL = hookSourceURL
        self.entitlementsURL = entitlementsURL
    }
}

public struct InstallationResourceLocator: @unchecked Sendable {
    public static let bundleName = "IHaveAlreadySeenIt_IHaveAlreadySeenItCore.bundle"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func resolve(searchRoots: [URL]) throws -> InstallationResources {
        for root in searchRoots {
            let bundle = root.appendingPathComponent(Self.bundleName, isDirectory: true)
            let hook = bundle.appendingPathComponent("AntiRevokeHook.c")
            let entitlements = bundle.appendingPathComponent("IHaveAlreadySeenIt.entitlements")
            if fileManager.fileExists(atPath: hook.path),
               fileManager.fileExists(atPath: entitlements.path) {
                return InstallationResources(
                    hookSourceURL: hook.standardizedFileURL,
                    entitlementsURL: entitlements.standardizedFileURL
                )
            }
        }
        let missing = (searchRoots.first ?? fileManager.temporaryDirectory)
            .appendingPathComponent(Self.bundleName, isDirectory: true)
        throw InstallationServiceError.resourceMissing(missing.path)
    }

    public static func standardSearchRoots(
        mainBundle: Bundle = .main,
        executablePath: String? = CommandLine.arguments.first
    ) -> [URL] {
        var roots: [URL] = []
        if let resources = mainBundle.resourceURL {
            roots.append(resources)
        }
        if let executablePath {
            var cursor = URL(fileURLWithPath: executablePath).standardizedFileURL
            while cursor.path != "/" {
                if cursor.pathExtension.lowercased() == "app" {
                    roots.append(cursor.appendingPathComponent("Contents/Resources", isDirectory: true))
                    break
                }
                cursor.deleteLastPathComponent()
            }
        }
        return Array(NSOrderedSet(array: roots.map(\.path)))
            .compactMap { $0 as? String }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}
