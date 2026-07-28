import Foundation

public enum PatchPlanningError: Error, Equatable, Sendable {
    case unsupportedVersion
    case unknownExecutableHash
    case architectureHashMismatch
    case candidateVersion
    case unsafeSignatureMatches
    case unsupportedArchitectures
    case insufficientHeaderSpace
    case alreadyInstalled
    case executableChanged
    case injectionVerificationFailed
}

public enum PatchPlanner {
    public static func prepareExecutable(_ executable: Data, report: ApplicationReport) throws -> Data {
        switch report.compatibility {
        case .supported:
            break
        case .unknownHash:
            throw PatchPlanningError.unknownExecutableHash
        case .architectureHashMismatch:
            throw PatchPlanningError.architectureHashMismatch
        case .candidate:
            throw PatchPlanningError.candidateVersion
        case .unsupportedVersion:
            throw PatchPlanningError.unsupportedVersion
        }
        guard SHA256Digest.hex(of: executable) == report.executableSHA256 else {
            throw PatchPlanningError.executableChanged
        }
        guard report.signatureScan.isSafeToPatch else {
            throw PatchPlanningError.unsafeSignatureMatches
        }
        let requiredArchitectures = report.compatibilityProfile?.supportedArchitectures
            ?? Set(MachOArchitecture.allCases)
        guard report.injection.architectures == requiredArchitectures else {
            throw PatchPlanningError.unsupportedArchitectures
        }
        if let profile = report.compatibilityProfile,
           !requiredArchitectures.allSatisfy({ architecture in
               (report.injection.headerSlack[architecture] ?? -1) >= profile.minimumHeaderSlack
           }) {
            throw PatchPlanningError.insufficientHeaderSpace
        }
        guard report.injection.slicesContainingDylib.isEmpty else {
            throw PatchPlanningError.alreadyInstalled
        }

        let patched = try MachOEditor.injectLoadDylib(
            path: ApplicationInspector.defaultDylibPath,
            into: executable
        )
        let inspection = try MachOEditor.inspect(
            patched,
            dylibPath: ApplicationInspector.defaultDylibPath
        )
        guard inspection.slicesContainingDylib == requiredArchitectures else {
            throw PatchPlanningError.injectionVerificationFailed
        }
        return patched
    }
}
