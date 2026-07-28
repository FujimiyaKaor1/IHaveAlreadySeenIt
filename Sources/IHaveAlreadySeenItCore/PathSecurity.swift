import Darwin
import Foundation

public enum ApplicationPathValidationError: Error, Equatable, Sendable {
    case notAppBundle
    case notDirectory
    case symbolicLink
    case unexpectedOwner
    case parentNotWritable
}

public struct ApplicationPathValidator: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func validate(
        appURL: URL,
        requireWritableParent: Bool,
        allowMissing: Bool = false
    ) throws -> URL {
        let standardized = appURL.standardizedFileURL
        guard standardized.pathExtension.lowercased() == "app" else {
            throw ApplicationPathValidationError.notAppBundle
        }
        if fileManager.fileExists(atPath: standardized.path) {
            let attributes = try fileManager.attributesOfItem(atPath: standardized.path)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw ApplicationPathValidationError.symbolicLink
            }
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw ApplicationPathValidationError.notDirectory
            }
            if let owner = attributes[.ownerAccountID] as? NSNumber {
                let ownerID = owner.uint32Value
                guard ownerID == 0 || ownerID == getuid() else {
                    throw ApplicationPathValidationError.unexpectedOwner
                }
            }
        } else if !allowMissing {
            throw ApplicationPathValidationError.notDirectory
        }
        if requireWritableParent {
            let parent = standardized.deletingLastPathComponent()
            guard fileManager.isWritableFile(atPath: parent.path) else {
                throw ApplicationPathValidationError.parentNotWritable
            }
        }
        return standardized
    }
}

public enum DiskCapacityError: Error, Equatable, Sendable {
    case unableToMeasure
    case insufficientSpace(required: Int64, available: Int64)
}

public struct DiskCapacityChecker: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func ensureCapacity(for appURL: URL, at destinationURL: URL) throws {
        let required = try allocatedSize(of: appURL) * 2 + 64 * 1_024 * 1_024
        let values = try destinationURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else {
            throw DiskCapacityError.unableToMeasure
        }
        guard available >= required else {
            throw DiskCapacityError.insufficientSpace(required: required, available: available)
        }
    }

    private func allocatedSize(of root: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            throw DiskCapacityError.unableToMeasure
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
