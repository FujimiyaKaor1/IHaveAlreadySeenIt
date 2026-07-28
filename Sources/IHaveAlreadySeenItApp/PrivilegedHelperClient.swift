import Foundation
import IHaveAlreadySeenItCore
import ServiceManagement

enum PrivilegedHelperClientError: LocalizedError {
    case readOnlyPreview
    case registrationRequired
    case unavailable(String)
    case invalidResponse
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .readOnlyPreview:
            return "当前是未签名只读预览版，未包含可注册的权限组件。"
        case .registrationRequired:
            return "请先在系统设置中批准 IHaveAlreadySeenIt 权限组件。"
        case .unavailable(let message):
            return "权限组件不可用：\(message)"
        case .invalidResponse:
            return "权限组件返回了无法识别的结果。"
        case .operationFailed(let message):
            return "操作失败：\(message)"
        }
    }
}

struct PrivilegedHelperClient {
    private var service: SMAppService {
        SMAppService.daemon(plistName: PrivilegedHelperConstants.launchDaemonPlist)
    }

    func ensureRegistered() throws {
        switch service.status {
        case .enabled:
            return
        case .requiresApproval:
            throw PrivilegedHelperClientError.registrationRequired
        case .notRegistered, .notFound:
            try service.register()
            guard service.status == .enabled else {
                throw PrivilegedHelperClientError.registrationRequired
            }
        @unknown default:
            throw PrivilegedHelperClientError.unavailable("unknown registration state")
        }
    }

    func perform(_ operation: PrivilegedOperation, appURL: URL) async throws {
        guard AppRuntimeCapabilities.hasSignedPrivilegedHelper() else {
            throw PrivilegedHelperClientError.readOnlyPreview
        }
        try ensureRegistered()
        let connection = NSXPCConnection(
            machServiceName: PrivilegedHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        let data = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data, Error>) in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: PrivilegedHelperClientError.unavailable(error.localizedDescription))
            }) as? PrivilegedHelperProtocol else {
                continuation.resume(throwing: PrivilegedHelperClientError.invalidResponse)
                return
            }
            proxy.perform(operation: operation.rawValue, appPath: appURL.path) { data in
                continuation.resume(returning: data)
            }
        }
        let response = try JSONDecoder().decode(PrivilegedOperationResponse.self, from: data)
        guard response.succeeded else {
            throw PrivilegedHelperClientError.operationFailed(response.message)
        }
    }
}
