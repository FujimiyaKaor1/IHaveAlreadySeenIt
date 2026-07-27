import Foundation

public struct Version: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init(_ rawValue: String) throws {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else {
            throw VersionError.invalid(rawValue)
        }

        let parsed = try parts.map { part -> Int in
            guard !part.isEmpty, let value = Int(part), value >= 0 else {
                throw VersionError.invalid(rawValue)
            }
            return value
        }
        var normalized = parsed
        while normalized.count > 1, normalized.last == 0 {
            normalized.removeLast()
        }
        components = normalized
    }

    init(components: [Int]) {
        self.components = components
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }
}

public enum VersionError: Error, Equatable, Sendable {
    case invalid(String)
}
