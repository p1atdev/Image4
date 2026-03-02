import Compression
import Foundation
import Testing

@testable import Image4

@Suite("IM4P Edge Case Tests")
struct IM4PEdgeCaseTests {

    // MARK: - 1. Compress → Decompress Roundtrip

    @Test("LZFSE roundtrip: compress then decompress")
    func testLZFSERoundtrip() throws {
        let original =
            Data(repeating: 0xAB, count: 4096)
            + Data("Hello, Image4 LZFSE roundtrip test!".utf8)
            + Data(repeating: 0x00, count: 2048)

        let payload = IM4PData(data: original)
        #expect(payload.compression == .none)

        try payload.compress(to: .lzfse)
        #expect(payload.compression == .lzfse)
        #expect(payload.size == UInt64(original.count))
        #expect(payload.data != original)

        try payload.decompress()
        #expect(payload.compression == .none)
        #expect(payload.data == original)
    }

    @Test("LZSS roundtrip: compress then decompress")
    func testLZSSRoundtrip() throws {
        let original =
            Data(repeating: 0xCD, count: 4096)
            + Data("Hello, Image4 LZSS roundtrip test!".utf8)
            + Data(repeating: 0x00, count: 2048)

        let payload = IM4PData(data: original)
        #expect(payload.compression == .none)

        try payload.compress(to: .lzss)
        #expect(payload.compression == .lzss)
        #expect(payload.size == UInt64(original.count))

        try payload.decompress()
        #expect(payload.compression == .none)
        #expect(payload.data == original)
    }

    // MARK: - 2. Incompressible (Random) Data

    @Test("LZFSE compress with incompressible random data")
    func testLZFSEIncompressibleData() throws {
        // Random-like data that is hard to compress; output may exceed input size
        var rng = RandomDataGenerator(seed: 42)
        let original = rng.generate(count: 8192)

        let payload = IM4PData(data: original)
        try payload.compress(to: .lzfse)
        #expect(payload.compression == .lzfse)
        #expect(payload.size == UInt64(original.count))

        try payload.decompress()
        #expect(payload.compression == .none)
        #expect(payload.data == original)
    }

    // MARK: - 3. Small Payloads

    @Test("LZFSE roundtrip with 1-byte payload")
    func testLZFSE1Byte() throws {
        let original = Data([0xFF])
        let payload = IM4PData(data: original)

        try payload.compress(to: .lzfse)
        #expect(payload.compression == .lzfse)

        try payload.decompress()
        #expect(payload.data == original)
    }

    @Test("LZFSE roundtrip with small payload")
    func testLZFSESmall() throws {
        let original = Data("tiny".utf8)
        let payload = IM4PData(data: original)

        try payload.compress(to: .lzfse)
        try payload.decompress()
        #expect(payload.data == original)
    }

    @Test("LZSS roundtrip with small payload")
    func testLZSSSmall() throws {
        let original = Data(repeating: 0x41, count: 32)
        let payload = IM4PData(data: original)

        try payload.compress(to: .lzss)
        #expect(payload.compression == .lzss)

        try payload.decompress()
        #expect(payload.data == original)
    }

    // MARK: - 4. Invalid Operations

    @Test("Decompress on uncompressed data is no-op")
    func testDecompressNone() throws {
        let original = Data("not compressed".utf8)
        let payload = IM4PData(data: original)
        #expect(payload.compression == .none)

        // decompress with .none hits the default branch and returns without error
        try payload.decompress()
        #expect(payload.data == original)
        #expect(payload.compression == .none)
    }

    @Test("Compress to .none is no-op")
    func testCompressToNone() throws {
        let original = Data("test data".utf8)
        let payload = IM4PData(data: original)

        try payload.compress(to: .none)
        #expect(payload.data == original)
        #expect(payload.compression == .none)
    }

    @Test("Double LZFSE compress produces valid data")
    func testDoubleCompress() throws {
        let original = Data(repeating: 0xAA, count: 1024)
        let payload = IM4PData(data: original)

        try payload.compress(to: .lzfse)
        let firstCompressed = payload.data
        #expect(payload.compression == .lzfse)

        // Compressing again should just re-compress the already-compressed bytes
        try payload.compress(to: .lzfse)
        #expect(payload.compression == .lzfse)

        // Decompress twice to recover original
        try payload.decompress()
        #expect(payload.data == firstCompressed)

        // Reset compression state for second decompress
        payload.size = UInt64(original.count)
        try payload.decompress()
        #expect(payload.data == original)
    }

    // MARK: - 5. detectCompression Boundary Cases

    @Test("Data starting with 'bvx' but without 'bvx$' is not LZFSE")
    func testBvxWithoutTerminator() {
        let data = Data("bvx-no-terminator-here".utf8)
        let payload = IM4PData(data: data)
        #expect(payload.compression == .none)
    }

    @Test("Data starting with 'bvx2' and containing 'bvx$' is LZFSE")
    func testBvxWithTerminator() {
        var data = Data("bvx2".utf8)
        data.append(Data(repeating: 0x00, count: 100))
        data.append(Data("bvx$".utf8))
        let payload = IM4PData(data: data)
        #expect(payload.compression == .lzfse)
    }

    @Test("Short 'complzss' header (< 0x180 bytes) is detected but header not fully parsed")
    func testShortComplzssHeader() {
        // "complzss" prefix but too short for full header
        var data = Data("complzss".utf8)
        data.append(Data(repeating: 0x00, count: 32))
        let payload = IM4PData(data: data)
        // Should still be detected as LZSS based on prefix
        #expect(payload.compression == .lzss)
        // But size should remain 0 because parseComplzssHeader guards on count >= 0x180
        #expect(payload.size == 0)
    }

    @Test("Encrypted payload with size > 0 detects as lzfseEncrypted")
    func testEncryptedWithSize() {
        let data = Data(repeating: 0x00, count: 256)
        let payload = IM4PData(data: data)
        // Add a keybag to make it "encrypted"
        payload.keybags.append(
            Keybag(iv: Data(repeating: 0, count: 16), key: Data(repeating: 0, count: 32)))
        // Setting size triggers detectCompression
        payload.size = 512
        #expect(payload.compression == .lzfseEncrypted)
    }

    @Test("Encrypted payload with size == 0 does not detect as lzfseEncrypted")
    func testEncryptedWithZeroSize() {
        let data = Data(repeating: 0x00, count: 256)
        let payload = IM4PData(data: data)
        payload.keybags.append(
            Keybag(iv: Data(repeating: 0, count: 16), key: Data(repeating: 0, count: 32)))
        // size remains 0 → should not be lzfseEncrypted
        #expect(payload.compression == .none)
    }

    // MARK: - 6. Full IM4P Serialize → Deserialize Roundtrip with Compression

    @Test("IM4P LZFSE serialize roundtrip")
    func testIM4PLZFSESerializeRoundtrip() throws {
        let original =
            Data(repeating: 0xBE, count: 2048)
            + Data("IM4P roundtrip payload".utf8)

        let im4p = IM4P()
        im4p.fourcc = "test"
        im4p.description = "Edge case roundtrip"
        im4p.payload = IM4PData(data: original)

        try im4p.payload!.compress(to: .lzfse)
        #expect(im4p.payload!.compression == .lzfse)

        let serialized = try im4p.output()

        // Re-parse from serialized bytes
        let restored = try IM4P(data: serialized)
        #expect(restored.fourcc == "test")
        #expect(restored.description == "Edge case roundtrip")

        guard let restoredPayload = restored.payload else {
            Issue.record("Restored payload missing")
            return
        }

        #expect(restoredPayload.compression == .lzfse)

        try restoredPayload.decompress()
        #expect(restoredPayload.compression == .none)
        #expect(restoredPayload.data == original)
    }

    @Test("IM4P LZSS serialize roundtrip")
    func testIM4PLZSSSerializeRoundtrip() throws {
        let original =
            Data(repeating: 0xEF, count: 2048)
            + Data("IM4P LZSS roundtrip".utf8)

        let im4p = IM4P()
        im4p.fourcc = "krnl"
        im4p.description = "LZSS roundtrip test"
        im4p.payload = IM4PData(data: original)

        try im4p.payload!.compress(to: .lzss)
        #expect(im4p.payload!.compression == .lzss)

        let serialized = try im4p.output()

        let restored = try IM4P(data: serialized)
        #expect(restored.fourcc == "krnl")

        guard let restoredPayload = restored.payload else {
            Issue.record("Restored payload missing")
            return
        }

        #expect(restoredPayload.compression == .lzss)

        try restoredPayload.decompress()
        #expect(restoredPayload.data == original)
    }

    @Test("IM4P with nil payload serializes without error")
    func testIM4PNilPayload() throws {
        let im4p = IM4P()
        im4p.fourcc = "test"
        im4p.description = "no payload"
        // payload is nil

        let data = try im4p.output()
        #expect(!data.isEmpty)
    }
}

// MARK: - Helpers

/// Simple deterministic pseudo-random data generator for reproducible tests.
private struct RandomDataGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func generate(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            // xorshift64
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            bytes[i] = UInt8(state & 0xFF)
        }
        return Data(bytes)
    }
}
