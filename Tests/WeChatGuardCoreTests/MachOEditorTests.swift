import Foundation
import WeChatGuardCore

func runMachOEditorTests() throws {
    let dylibPath = "@executable_path/../Resources/WeChatGuardHook.dylib"

    try test("injects a load command into every universal slice") {
        let fixture = MachOFixture.universalBinary()
        let patched = try MachOEditor.injectLoadDylib(path: dylibPath, into: fixture)
        let inspection = try MachOEditor.inspect(patched, dylibPath: dylibPath)
        try expect(inspection.architectures == Set([.arm64, .x86_64]))
        try expect(inspection.slicesContainingDylib == Set([.arm64, .x86_64]))
    }

    try test("keeps injection idempotent") {
        let fixture = MachOFixture.universalBinary()
        let first = try MachOEditor.injectLoadDylib(path: dylibPath, into: fixture)
        let second = try MachOEditor.injectLoadDylib(path: dylibPath, into: first)
        try expect(first == second)
    }

    try test("rejects a Mach-O header without enough slack") {
        let fixture = MachOFixture.universalBinary(headerSlack: 0)
        try expectThrows(MachOError.insufficientHeaderSpace(.x86_64)) {
            try MachOEditor.injectLoadDylib(path: dylibPath, into: fixture)
        }
    }

    try test("requires one signature match per architecture") {
        let fixture = MachOFixture.universalBinary(includePatterns: true)
        let report = try SignatureScanner.scan(fixture, signatures: .antiRevoke)
        try expect(report[.arm64] == 1)
        try expect(report[.x86_64] == 1)
        try expect(report.isSafeToPatch)
    }

    try test("rejects duplicate signature matches") {
        let fixture = MachOFixture.universalBinary(includePatterns: true, duplicateArmPattern: true)
        let report = try SignatureScanner.scan(fixture, signatures: .antiRevoke)
        try expect(report[.arm64] == 2)
        try expect(!report.isSafeToPatch)
    }
}

enum MachOFixture {
    static func universalBinary(
        headerSlack: Int = 512,
        includePatterns: Bool = false,
        duplicateArmPattern: Bool = false
    ) -> Data {
        let x86 = thinBinary(
            cpuType: 0x0100_0007,
            pattern: includePatterns ? AntiRevokeSignatures.x86_64 : nil,
            duplicatePattern: false,
            headerSlack: headerSlack
        )
        let arm = thinBinary(
            cpuType: 0x0100_000C,
            pattern: includePatterns ? AntiRevokeSignatures.arm64 : nil,
            duplicatePattern: duplicateArmPattern,
            headerSlack: max(headerSlack, 512)
        )
        let firstOffset = 0x4000
        let secondOffset = firstOffset + 0x4000
        var result = Data(repeating: 0, count: secondOffset + arm.count)

        result.writeUInt32BE(0xCAFE_BABE, at: 0)
        result.writeUInt32BE(2, at: 4)
        writeFatArch(into: &result, at: 8, cpuType: 0x0100_0007, offset: firstOffset, size: x86.count)
        writeFatArch(into: &result, at: 28, cpuType: 0x0100_000C, offset: secondOffset, size: arm.count)
        result.replaceSubrange(firstOffset..<(firstOffset + x86.count), with: x86)
        result.replaceSubrange(secondOffset..<(secondOffset + arm.count), with: arm)
        return result
    }

    private static func writeFatArch(
        into data: inout Data,
        at offset: Int,
        cpuType: UInt32,
        offset sliceOffset: Int,
        size: Int
    ) {
        data.writeUInt32BE(cpuType, at: offset)
        data.writeUInt32BE(0, at: offset + 4)
        data.writeUInt32BE(UInt32(sliceOffset), at: offset + 8)
        data.writeUInt32BE(UInt32(size), at: offset + 12)
        data.writeUInt32BE(14, at: offset + 16)
    }

    private static func thinBinary(
        cpuType: UInt32,
        pattern: Data?,
        duplicatePattern: Bool,
        headerSlack: Int
    ) -> Data {
        let segmentSize = 72 + 80
        let sectionOffset = 32 + segmentSize + headerSlack
        var data = Data(repeating: 0, count: max(0x2000, sectionOffset + 1024))

        data.writeUInt32LE(0xFEED_FACF, at: 0)
        data.writeUInt32LE(cpuType, at: 4)
        data.writeUInt32LE(0, at: 8)
        data.writeUInt32LE(2, at: 12)
        data.writeUInt32LE(1, at: 16)
        data.writeUInt32LE(UInt32(segmentSize), at: 20)
        data.writeUInt32LE(0, at: 24)
        data.writeUInt32LE(0, at: 28)

        data.writeUInt32LE(0x19, at: 32)
        data.writeUInt32LE(UInt32(segmentSize), at: 36)
        data.writeASCII("__TEXT", at: 40, fieldLength: 16)
        data.writeUInt64LE(0x1_0000_0000, at: 56)
        data.writeUInt64LE(UInt64(data.count), at: 64)
        data.writeUInt64LE(0, at: 72)
        data.writeUInt64LE(UInt64(data.count), at: 80)
        data.writeUInt32LE(5, at: 88)
        data.writeUInt32LE(5, at: 92)
        data.writeUInt32LE(1, at: 96)
        data.writeUInt32LE(0, at: 100)

        data.writeASCII("__text", at: 104, fieldLength: 16)
        data.writeASCII("__TEXT", at: 120, fieldLength: 16)
        data.writeUInt64LE(0x1_0000_0000 + UInt64(sectionOffset), at: 136)
        data.writeUInt64LE(512, at: 144)
        data.writeUInt32LE(UInt32(sectionOffset), at: 152)

        if let pattern {
            data.replaceSubrange(sectionOffset..<(sectionOffset + pattern.count), with: pattern)
            if duplicatePattern {
                let second = sectionOffset + pattern.count + 16
                data.replaceSubrange(second..<(second + pattern.count), with: pattern)
            }
        }
        return data
    }
}

private extension Data {
    mutating func writeUInt32LE(_ value: UInt32, at offset: Int) {
        replaceSubrange(offset..<(offset + 4), with: Swift.withUnsafeBytes(of: value.littleEndian, Array.init))
    }

    mutating func writeUInt64LE(_ value: UInt64, at offset: Int) {
        replaceSubrange(offset..<(offset + 8), with: Swift.withUnsafeBytes(of: value.littleEndian, Array.init))
    }

    mutating func writeUInt32BE(_ value: UInt32, at offset: Int) {
        replaceSubrange(offset..<(offset + 4), with: Swift.withUnsafeBytes(of: value.bigEndian, Array.init))
    }

    mutating func writeASCII(_ value: String, at offset: Int, fieldLength: Int) {
        let bytes = Array(value.utf8.prefix(fieldLength))
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }
}
