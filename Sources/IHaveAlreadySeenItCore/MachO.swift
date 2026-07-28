import Darwin
import Foundation

public enum MachOArchitecture: String, CaseIterable, Hashable, Sendable {
    case arm64
    case x86_64

    fileprivate init?(cpuType: UInt32) {
        switch cpuType {
        case 0x0100_000C: self = .arm64
        case 0x0100_0007: self = .x86_64
        default: return nil
        }
    }
}

public enum MachOError: Error, Equatable, Sendable {
    case malformedBinary
    case unsupportedArchitecture(UInt32)
    case insufficientHeaderSpace(MachOArchitecture)
    case occupiedHeaderSpace(MachOArchitecture)
    case invalidDylibPath
}

public struct MachOInspection: Equatable, Sendable {
    public let architectures: Set<MachOArchitecture>
    public let slicesContainingDylib: Set<MachOArchitecture>
}

public enum MachOEditor {
    private static let loadDylib: UInt32 = 0x0C

    public static func inspect(_ data: Data, dylibPath: String) throws -> MachOInspection {
        let slices = try MachOParser.slices(in: data)
        var containing = Set<MachOArchitecture>()
        for slice in slices where try containsDylib(path: dylibPath, in: data, slice: slice) {
            containing.insert(slice.architecture)
        }
        return MachOInspection(
            architectures: Set(slices.map(\.architecture)),
            slicesContainingDylib: containing
        )
    }

    public static func injectLoadDylib(path: String, into source: Data) throws -> Data {
        guard path.utf8.count > 0, !path.utf8.contains(0) else {
            throw MachOError.invalidDylibPath
        }
        let command = makeDylibCommand(path: path)
        let slices = try MachOParser.slices(in: source)
        var result = source

        for slice in slices {
            if try containsDylib(path: path, in: result, slice: slice) {
                continue
            }
            let header = try MachOParser.header(in: result, slice: slice)
            let insertionOffset = slice.offset + 32 + Int(header.sizeOfCommands)
            let firstSectionOffset = try MachOParser.firstSectionOffset(in: result, slice: slice)
            let insertionEnd = insertionOffset + command.count

            guard insertionEnd <= slice.offset + firstSectionOffset else {
                throw MachOError.insufficientHeaderSpace(slice.architecture)
            }
            guard result[insertionOffset..<insertionEnd].allSatisfy({ $0 == 0 }) else {
                throw MachOError.occupiedHeaderSpace(slice.architecture)
            }

            result.replaceSubrange(insertionOffset..<insertionEnd, with: command)
            try result.writeUInt32LE(header.numberOfCommands + 1, at: slice.offset + 16)
            try result.writeUInt32LE(header.sizeOfCommands + UInt32(command.count), at: slice.offset + 20)
        }
        return result
    }

    private static func containsDylib(path: String, in data: Data, slice: MachOSlice) throws -> Bool {
        let header = try MachOParser.header(in: data, slice: slice)
        var commandOffset = slice.offset + 32
        for _ in 0..<header.numberOfCommands {
            let command = try data.readUInt32LE(at: commandOffset)
            let commandSize = try data.readUInt32LE(at: commandOffset + 4)
            guard commandSize >= 8, commandOffset + Int(commandSize) <= slice.end else {
                throw MachOError.malformedBinary
            }
            if command == loadDylib {
                let nameOffset = try data.readUInt32LE(at: commandOffset + 8)
                guard nameOffset < commandSize else {
                    throw MachOError.malformedBinary
                }
                let name = try data.readCString(
                    at: commandOffset + Int(nameOffset),
                    limit: commandOffset + Int(commandSize)
                )
                if name == path {
                    return true
                }
            }
            commandOffset += Int(commandSize)
        }
        return false
    }

    private static func makeDylibCommand(path: String) -> Data {
        let fixedSize = 24
        let unalignedSize = fixedSize + path.utf8.count + 1
        let commandSize = (unalignedSize + 7) & ~7
        var data = Data(repeating: 0, count: commandSize)
        data.writeUInt32LEUnchecked(loadDylib, at: 0)
        data.writeUInt32LEUnchecked(UInt32(commandSize), at: 4)
        data.writeUInt32LEUnchecked(UInt32(fixedSize), at: 8)
        data.writeUInt32LEUnchecked(2, at: 12)
        data.writeUInt32LEUnchecked(0x1_0000, at: 16)
        data.writeUInt32LEUnchecked(0x1_0000, at: 20)
        data.replaceSubrange(fixedSize..<(fixedSize + path.utf8.count), with: path.utf8)
        return data
    }
}

public enum AntiRevokeSignatures {
    public static let arm64 = Data([
        0x08, 0x0C, 0x40, 0xB9,
        0x49, 0xE2, 0x84, 0x52,
        0x1F, 0x01, 0x09, 0x6B,
        0xE0, 0x17, 0x9F, 0x1A,
        0xC0, 0x03, 0x5F, 0xD6,
    ])
    public static let x86_64 = Data([
        0x55, 0x48, 0x89, 0xE5,
        0x81, 0x7F, 0x0C, 0x12, 0x27, 0x00, 0x00,
        0x0F, 0x94, 0xC0,
        0x5D, 0xC3,
    ])
}

public struct SignatureSet: Sendable {
    public let arm64: Data
    public let x86_64: Data

    public static let antiRevoke = SignatureSet(
        arm64: AntiRevokeSignatures.arm64,
        x86_64: AntiRevokeSignatures.x86_64
    )
}

public struct SignatureScanReport: Equatable, Sendable {
    private let matches: [MachOArchitecture: Int]

    fileprivate init(matches: [MachOArchitecture: Int]) {
        self.matches = matches
    }

    public subscript(architecture: MachOArchitecture) -> Int? {
        matches[architecture]
    }

    public var isSafeToPatch: Bool {
        Set(matches.keys) == Set(MachOArchitecture.allCases) && matches.values.allSatisfy { $0 == 1 }
    }
}

public enum SignatureScanner {
    public static func scan(_ data: Data, signatures: SignatureSet) throws -> SignatureScanReport {
        let slices = try MachOParser.slices(in: data)
        var matches: [MachOArchitecture: Int] = [:]
        for slice in slices {
            let pattern = slice.architecture == .arm64 ? signatures.arm64 : signatures.x86_64
            matches[slice.architecture] = data.countOccurrences(of: pattern, in: slice.offset..<slice.end)
        }
        return SignatureScanReport(matches: matches)
    }
}

private struct MachOSlice {
    let architecture: MachOArchitecture
    let offset: Int
    let size: Int
    var end: Int { offset + size }
}

private struct MachOHeader {
    let numberOfCommands: UInt32
    let sizeOfCommands: UInt32
}

private enum MachOParser {
    static func slices(in data: Data) throws -> [MachOSlice] {
        guard data.count >= 4 else { throw MachOError.malformedBinary }
        let bigEndianMagic = try data.readUInt32BE(at: 0)
        if bigEndianMagic == 0xCAFE_BABE {
            let count = Int(try data.readUInt32BE(at: 4))
            guard count > 0, data.count >= 8 + count * 20 else {
                throw MachOError.malformedBinary
            }
            return try (0..<count).map { index in
                let entryOffset = 8 + index * 20
                let cpuType = try data.readUInt32BE(at: entryOffset)
                guard let architecture = MachOArchitecture(cpuType: cpuType) else {
                    throw MachOError.unsupportedArchitecture(cpuType)
                }
                let offset = Int(try data.readUInt32BE(at: entryOffset + 8))
                let size = Int(try data.readUInt32BE(at: entryOffset + 12))
                guard offset >= 0, size >= 32, offset + size <= data.count else {
                    throw MachOError.malformedBinary
                }
                return MachOSlice(architecture: architecture, offset: offset, size: size)
            }
        }

        let littleEndianMagic = try data.readUInt32LE(at: 0)
        guard littleEndianMagic == 0xFEED_FACF, data.count >= 32 else {
            throw MachOError.malformedBinary
        }
        let cpuType = try data.readUInt32LE(at: 4)
        guard let architecture = MachOArchitecture(cpuType: cpuType) else {
            throw MachOError.unsupportedArchitecture(cpuType)
        }
        return [MachOSlice(architecture: architecture, offset: 0, size: data.count)]
    }

    static func header(in data: Data, slice: MachOSlice) throws -> MachOHeader {
        guard try data.readUInt32LE(at: slice.offset) == 0xFEED_FACF else {
            throw MachOError.malformedBinary
        }
        let numberOfCommands = try data.readUInt32LE(at: slice.offset + 16)
        let sizeOfCommands = try data.readUInt32LE(at: slice.offset + 20)
        guard slice.offset + 32 + Int(sizeOfCommands) <= slice.end else {
            throw MachOError.malformedBinary
        }
        return MachOHeader(numberOfCommands: numberOfCommands, sizeOfCommands: sizeOfCommands)
    }

    static func firstSectionOffset(in data: Data, slice: MachOSlice) throws -> Int {
        let header = try header(in: data, slice: slice)
        var commandOffset = slice.offset + 32
        var minimum = slice.size
        for _ in 0..<header.numberOfCommands {
            let command = try data.readUInt32LE(at: commandOffset)
            let commandSize = Int(try data.readUInt32LE(at: commandOffset + 4))
            guard commandSize >= 8, commandOffset + commandSize <= slice.end else {
                throw MachOError.malformedBinary
            }
            if command == 0x19 {
                let sectionCount = Int(try data.readUInt32LE(at: commandOffset + 64))
                guard commandSize >= 72 + sectionCount * 80 else {
                    throw MachOError.malformedBinary
                }
                for sectionIndex in 0..<sectionCount {
                    let sectionOffset = Int(try data.readUInt32LE(
                        at: commandOffset + 72 + sectionIndex * 80 + 48
                    ))
                    if sectionOffset > 0 {
                        minimum = min(minimum, sectionOffset)
                    }
                }
            }
            commandOffset += commandSize
        }
        return minimum
    }
}

private extension Data {
    func readUInt32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw MachOError.malformedBinary }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }

    func readUInt32BE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw MachOError.malformedBinary }
        return UInt32(self[offset]) << 24
            | UInt32(self[offset + 1]) << 16
            | UInt32(self[offset + 2]) << 8
            | UInt32(self[offset + 3])
    }

    mutating func writeUInt32LE(_ value: UInt32, at offset: Int) throws {
        guard offset >= 0, offset + 4 <= count else { throw MachOError.malformedBinary }
        self[offset] = UInt8(truncatingIfNeeded: value)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        self[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        self[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    mutating func writeUInt32LEUnchecked(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(truncatingIfNeeded: value)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        self[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        self[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    func readCString(at offset: Int, limit: Int) throws -> String {
        guard offset >= 0, offset < limit, limit <= count else { throw MachOError.malformedBinary }
        var end = offset
        while end < limit, self[end] != 0 {
            end += 1
        }
        guard end < limit, let value = String(data: self[offset..<end], encoding: .utf8) else {
            throw MachOError.malformedBinary
        }
        return value
    }

    func countOccurrences(of pattern: Data, in range: Range<Int>) -> Int {
        guard !pattern.isEmpty, range.lowerBound >= 0, range.upperBound <= count,
              pattern.count <= range.count else { return 0 }

        return withUnsafeBytes { sourceBuffer in
            pattern.withUnsafeBytes { patternBuffer in
                guard let source = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let needle = patternBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                var matches = 0
                var index = range.lowerBound
                let lastStart = range.upperBound - pattern.count
                while index <= lastStart {
                    if source[index] == needle[0],
                       memcmp(source + index, needle, pattern.count) == 0 {
                        matches += 1
                        index += pattern.count
                    } else {
                        index += 1
                    }
                }
                return matches
            }
        }
    }
}
