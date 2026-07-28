import CryptoKit
import Foundation

public enum SHA256Digest {
    public static func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum ApplicationInspectionError: Error, Equatable, Sendable {
    case appNotFound(String)
    case malformedInfoPlist
    case unexpectedBundleIdentifier(String)
    case invalidExecutableName
    case executableNotFound(String)
}

public struct ApplicationReport: Sendable {
    public let appURL: URL
    public let executableURL: URL
    public let bundleIdentifier: String
    public let version: Version
    public let build: String
    public let executableSHA256: String
    public let compatibility: CompatibilityResult
    public let signatureScan: SignatureScanReport
    public let injection: MachOInspection
}

public struct ApplicationInspector: Sendable {
    public static let expectedBundleIdentifier = "com.tencent.xinWeChat"
    public static let defaultDylibPath = "@executable_path/../Resources/IHaveAlreadySeenItHook.dylib"

    private let compatibilityRules: CompatibilityRules

    public init(compatibilityRules: CompatibilityRules = .builtIn) {
        self.compatibilityRules = compatibilityRules
    }

    public func inspect(appURL: URL) throws -> ApplicationReport {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: appURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ApplicationInspectionError.appNotFound(appURL.path)
        }

        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let infoData = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: infoData, options: [], format: nil),
              let info = plist as? [String: Any],
              let bundleIdentifier = info["CFBundleIdentifier"] as? String else {
            throw ApplicationInspectionError.malformedInfoPlist
        }
        guard bundleIdentifier == Self.expectedBundleIdentifier else {
            throw ApplicationInspectionError.unexpectedBundleIdentifier(bundleIdentifier)
        }
        guard let executableName = info["CFBundleExecutable"] as? String,
              !executableName.isEmpty,
              !executableName.contains("/"),
              executableName != ".",
              executableName != ".." else {
            throw ApplicationInspectionError.invalidExecutableName
        }
        guard let rawVersion = info["CFBundleShortVersionString"] as? String,
              let rawBuild = info["CFBundleVersion"] as? String else {
            throw ApplicationInspectionError.malformedInfoPlist
        }

        let executableURL = appURL.appendingPathComponent("Contents/MacOS/\(executableName)")
        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            throw ApplicationInspectionError.executableNotFound(executableURL.path)
        }

        let executableData = try Data(contentsOf: executableURL, options: .mappedIfSafe)
        let version = try Version(rawVersion)
        let digest = SHA256Digest.hex(of: executableData)
        return ApplicationReport(
            appURL: appURL,
            executableURL: executableURL,
            bundleIdentifier: bundleIdentifier,
            version: version,
            build: rawBuild,
            executableSHA256: digest,
            compatibility: compatibilityRules.evaluate(
                version: version,
                build: rawBuild,
                executableSHA256: digest
            ),
            signatureScan: try SignatureScanner.scan(executableData, signatures: .antiRevoke),
            injection: try MachOEditor.inspect(executableData, dylibPath: Self.defaultDylibPath)
        )
    }
}
