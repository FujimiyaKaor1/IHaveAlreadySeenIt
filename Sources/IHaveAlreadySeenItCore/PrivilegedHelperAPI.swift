import Foundation

public enum PrivilegedOperation: String, Codable, Sendable {
    case install
    case restore
}

public struct PrivilegedOperationResponse: Codable, Equatable, Sendable {
    public let succeeded: Bool
    public let message: String

    public init(succeeded: Bool, message: String) {
        self.succeeded = succeeded
        self.message = message
    }
}

@objc public protocol PrivilegedHelperProtocol {
    func ping(reply: @escaping (String) -> Void)
    func perform(operation: String, appPath: String, reply: @escaping (Data) -> Void)
}

public enum PrivilegedHelperConstants {
    public static let machServiceName = "io.github.fujimiyakaor1.IHaveAlreadySeenIt.PrivilegedHelper"
    public static let launchDaemonPlist = "io.github.fujimiyakaor1.IHaveAlreadySeenIt.PrivilegedHelper.plist"
}
