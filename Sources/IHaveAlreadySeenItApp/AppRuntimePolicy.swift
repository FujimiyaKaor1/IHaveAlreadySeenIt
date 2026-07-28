import Foundation
import IHaveAlreadySeenItCore

enum AppRuntimeCapabilities {
    static var localDevelopmentEnabled: Bool {
#if IHAVEALREADYSEENIT_LOCAL_DEVELOPMENT
        true
#else
        false
#endif
    }

    static func mutationBackend(
        in bundle: Bundle = .main,
        verifier: any CodeSignatureVerifying = SystemCodeSignatureVerifier()
    ) -> AppMutationBackend {
        AppMutationBackend.resolve(
            localDevelopmentEnabled: localDevelopmentEnabled,
            signedHelperAvailable: hasSignedPrivilegedHelper(in: bundle, verifier: verifier)
        )
    }

    static func hasSignedPrivilegedHelper(
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
