import Foundation
import IHaveAlreadySeenItCore
import Security

private final class PrivilegedHelperService: NSObject, PrivilegedHelperProtocol {
    func ping(reply: @escaping (String) -> Void) {
        reply(InstallationService.toolVersion)
    }

    func perform(operation: String, appPath: String, reply: @escaping (Data) -> Void) {
        let response: PrivilegedOperationResponse
        do {
            guard geteuid() == 0 else {
                throw InstallationServiceError.needsPrivileges
            }
            guard let operation = PrivilegedOperation(rawValue: operation) else {
                throw HelperError.invalidOperation
            }
            let appURL = URL(fileURLWithPath: appPath, isDirectory: true)
            let service = try makeInstallationService()
            switch operation {
            case .install:
                let report = try ApplicationInspector().inspect(appURL: appURL)
                try service.install(appURL: appURL, report: report)
            case .restore:
                try service.restore(appURL: appURL)
            }
            response = PrivilegedOperationResponse(succeeded: true, message: "completed")
        } catch {
            response = PrivilegedOperationResponse(
                succeeded: false,
                message: String(describing: error)
            )
        }
        let encoder = JSONEncoder()
        reply((try? encoder.encode(response)) ?? Data())
    }

    private func makeInstallationService() throws -> InstallationService {
        var appRoot = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        for _ in 0..<4 {
            appRoot.deleteLastPathComponent()
        }
        let resources = appRoot.appendingPathComponent(
            "IHaveAlreadySeenIt_IHaveAlreadySeenItCore.bundle",
            isDirectory: true
        )
        let hook = resources.appendingPathComponent("AntiRevokeHook.c")
        let entitlements = resources.appendingPathComponent("IHaveAlreadySeenIt.entitlements")
        guard FileManager.default.fileExists(atPath: hook.path),
              FileManager.default.fileExists(atPath: entitlements.path) else {
            throw InstallationServiceError.resourceMissing(resources.path)
        }
        return InstallationService(hookSourceURL: hook, entitlementsURL: entitlements)
    }
}

private enum HelperError: Error {
    case invalidOperation
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = PrivilegedHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard isAuthorized(connection) else { return false }
        connection.exportedInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }

    private func isAuthorized(_ connection: NSXPCConnection) -> Bool {
        guard let requirementText = ProcessInfo.processInfo.environment["AUTHORIZED_CLIENT_REQUIREMENT"],
              !requirementText.isEmpty else {
            return false
        }
        var guestCode: SecCode?
        let attributes = [kSecGuestAttributePid: connection.processIdentifier] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guestCode) == errSecSuccess,
              let guestCode else {
            return false
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            return false
        }
        return SecCodeCheckValidity(guestCode, [], requirement) == errSecSuccess
    }
}

private let delegate = ListenerDelegate()
private let listener = NSXPCListener(machServiceName: PrivilegedHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
