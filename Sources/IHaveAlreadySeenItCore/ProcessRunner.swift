import Foundation

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
}

public enum CommandExecutionError: Error, Equatable, Sendable {
    case launchFailed(String)
    case unexpectedExit(executable: String, code: Int32, output: String)
}

public protocol ProcessRunning: Sendable {
    func run(
        _ executable: String,
        _ arguments: [String],
        allowedExitCodes: Set<Int32>
    ) throws -> CommandResult
}

public extension ProcessRunning {
    @discardableResult
    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        try run(executable, arguments, allowedExitCodes: [0])
    }
}

public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    @discardableResult
    public func run(
        _ executable: String,
        _ arguments: [String],
        allowedExitCodes: Set<Int32> = [0]
    ) throws -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw CommandExecutionError.launchFailed("\(executable): \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard allowedExitCodes.contains(process.terminationStatus) else {
            throw CommandExecutionError.unexpectedExit(
                executable: executable,
                code: process.terminationStatus,
                output: output
            )
        }
        return CommandResult(exitCode: process.terminationStatus, output: output)
    }
}
