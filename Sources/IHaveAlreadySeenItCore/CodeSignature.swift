import Foundation

public enum CodeSignatureStatus: Codable, Equatable, Sendable {
    case official(teamIdentifier: String)
    case adHoc
    case invalid(reason: String)

    public var displayName: String {
        switch self {
        case .official(let teamIdentifier): return "Official (\(teamIdentifier))"
        case .adHoc: return "Ad-hoc"
        case .invalid(let reason): return "Invalid (\(reason))"
        }
    }
}

public enum CodeSignatureParser {
    public static func parse(description: String, verificationSucceeded: Bool) -> CodeSignatureStatus {
        guard verificationSucceeded else {
            return .invalid(reason: "code signature verification failed")
        }
        var values: [String: String] = [:]
        for line in description.split(whereSeparator: \.isNewline) {
            let pieces = line.split(separator: "=", maxSplits: 1).map(String.init)
            if pieces.count == 2 {
                values[pieces[0]] = pieces[1]
            }
        }
        if values["Signature"] == "adhoc" || values["TeamIdentifier"] == "not set" {
            return .adHoc
        }
        guard let teamIdentifier = values["TeamIdentifier"], !teamIdentifier.isEmpty else {
            return .invalid(reason: "missing team identifier")
        }
        return .official(teamIdentifier: teamIdentifier)
    }
}

public protocol CodeSignatureVerifying: Sendable {
    func status(of appURL: URL) throws -> CodeSignatureStatus
}

public struct SystemCodeSignatureVerifier: CodeSignatureVerifying {
    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    public func status(of appURL: URL) throws -> CodeSignatureStatus {
        let strictVerification = try runner.run(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", appURL.path],
            allowedExitCodes: [0, 1]
        )
        var verificationSucceeded = strictVerification.exitCode == 0
        if !verificationSucceeded, Self.isFinderMetadataCandidate(strictVerification.output) {
            let finderInfo = try runner.run(
                "/usr/bin/xattr",
                ["-px", "com.apple.FinderInfo", appURL.path],
                allowedExitCodes: [0, 1]
            )
            if finderInfo.exitCode == 0, Self.isFinderInfoPayload(finderInfo.output) {
                let relaxedVerification = try runner.run(
                    "/usr/bin/codesign",
                    ["--verify", "--deep", appURL.path],
                    allowedExitCodes: [0, 1]
                )
                verificationSucceeded = relaxedVerification.exitCode == 0
            }
        }
        let description = try runner.run(
            "/usr/bin/codesign",
            ["-dv", "--verbose=4", appURL.path],
            allowedExitCodes: [0, 1]
        )
        return CodeSignatureParser.parse(
            description: description.output,
            verificationSucceeded: verificationSucceeded && description.exitCode == 0
        )
    }

    private static func isFinderMetadataCandidate(_ output: String) -> Bool {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count == 1 || lines.count == 2,
              lines[0].hasSuffix(
            ": resource fork, Finder information, or similar detritus not allowed"
        ) else {
            return false
        }
        return lines.count == 1 || lines[1].hasPrefix(
            "file with invalid attached data: Disallowed xattr com.apple.FinderInfo found on "
        )
    }

    private static func isFinderInfoPayload(_ output: String) -> Bool {
        let hex = output.filter(\.isHexDigit)
        return hex.count == 64
    }
}
