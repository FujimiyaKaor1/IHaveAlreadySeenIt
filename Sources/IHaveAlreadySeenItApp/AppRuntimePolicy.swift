import Foundation
import IHaveAlreadySeenItCore

enum AppRuntimeCapabilities {
    static func allowsPrivilegedOperations(
        in bundle: Bundle = .main,
        verifier: any CodeSignatureVerifying = SystemCodeSignatureVerifier()
    ) -> Bool {
        let appURL = bundle.bundleURL.standardizedFileURL
        guard appURL.pathExtension.lowercased() == "app" else { return false }

        let helperURL = appURL.appendingPathComponent(
            "Contents/Library/LaunchServices/IHaveAlreadySeenItPrivilegedHelper"
        )
        let daemonURL = appURL.appendingPathComponent(
            "Contents/Library/LaunchDaemons/\(PrivilegedHelperConstants.launchDaemonPlist)"
        )
        guard FileManager.default.isExecutableFile(atPath: helperURL.path),
              FileManager.default.fileExists(atPath: daemonURL.path) else {
            return false
        }

        guard case .official(let appTeam) = try? verifier.status(of: appURL),
              case .official(let helperTeam) = try? verifier.status(of: helperURL) else {
            return false
        }
        return !appTeam.isEmpty && appTeam == helperTeam
    }
}
