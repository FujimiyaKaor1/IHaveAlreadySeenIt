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
        let verification = try runner.run(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", appURL.path],
            allowedExitCodes: [0, 1]
        )
        let description = try runner.run(
            "/usr/bin/codesign",
            ["-dv", "--verbose=4", appURL.path],
            allowedExitCodes: [0, 1]
        )
        return CodeSignatureParser.parse(
            description: description.output,
            verificationSucceeded: verification.exitCode == 0 && description.exitCode == 0
        )
    }
}
