import Foundation
import Testing
import LZSS
@testable import Image4

@Suite("IM4P Tests")
struct IM4PTests {
    @Test("Create IM4P")
    func testCreate() async throws {
        let payloadData = try TestResource.testPayload
        let im4p = IM4P()
        im4p.fourcc = "test"
        im4p.description = "Test Image4 payload."
        im4p.payload = IM4PData(data: payloadData)

        let expectedData = try TestResource.im4p
        let outputData = try im4p.output()
        
        #expect(outputData == expectedData)
    }

    @Test("Read Decrypted LZSS IM4P")
    func testReadLZSSDec() async throws {
        let data = try await TestResource.decLZSSIM4P
        let im4p = try IM4P(data: data)

        #expect(im4p.fourcc == "krnl")
        #expect(im4p.description == "KernelCacheBuilder_release-2238.10.3")

        guard let payload = im4p.payload else {
            Issue.record("Payload missing")
            return
        }

        #expect(payload.encrypted == false)
        #expect(payload.compression == .lzss)

        try payload.decompress()

        #expect(payload.compression == .none)
        #expect(payload.extra?.count == 0xC000)

        _ = try im4p.output()
    }

    @Test("Read Encrypted LZSS IM4P")
    func testReadLZSSEnc() async throws {
        let data = try await TestResource.encLZSSIM4P
        let im4p = try IM4P(data: data)

        #expect(im4p.fourcc == "krnl")
        #expect(im4p.description == "KernelCacheBuilder-960.40.11")

        guard let payload = im4p.payload else {
            Issue.record("Payload missing")
            return
        }

        #expect(payload.encrypted == true)
        #expect(payload.keybags.count == 2)
        #expect(payload.compression == .none)

        let decKbag = Keybag(
            iv: Data(hex: "6a6a294d029536665fc51b7bd493e2df")!,
            key: Data(hex: "ba2bdd5485677d9b40465dd0e332b419f759cffcd57be73468afc61050d42091")!
        )

        try payload.decrypt(with: decKbag)

        #expect(payload.compression == .lzss)

        try payload.decompress()

        #expect(payload.compression == .none)
        #expect(payload.extra?.count == 0xC008)

        _ = try im4p.output()
    }

    @Test("Read Decrypted LZFSE IM4P")
    func testReadLZFSEDec() async throws {
        let data = try await TestResource.decLZFSEIM4P
        let im4p = try IM4P(data: data)

        #expect(im4p.fourcc == "krnl")
        #expect(im4p.description == "KernelCacheBuilder_release-2238.10.3")

        guard let payload = im4p.payload else {
            Issue.record("Payload missing")
            return
        }

        #expect(payload.compression == .lzfse)

        try payload.decompress()

        #expect(payload.compression == .none)

        _ = try im4p.output()
    }

    @Test("Read Encrypted LZFSE IM4P")
    func testReadLZFSEEnc() async throws {
        let data = try await TestResource.encLZFSEIM4P
        let im4p = try IM4P(data: data)

        #expect(im4p.fourcc == "ibss")
        #expect(im4p.description == "iBoot-7429.12.15")

        guard let payload = im4p.payload else {
            Issue.record("Payload missing")
            return
        }

        #expect(payload.encrypted == true)
        #expect(payload.keybags.count == 2)
        #expect(payload.compression == .lzfseEncrypted)

        let decKbag = Keybag(
            iv: Data(hex: "0d0a39d2e3ea94f70076192e7d225e9e")!,
            key: Data(hex: "4567c8444b839a08b4a7c408531efb54ae69f1dcc24557ad0e21768b472f95cd")!
        )

        try payload.decrypt(with: decKbag)

        #expect(payload.compression == .lzfse)

        try payload.decompress()

        #expect(payload.compression == .none)

        _ = try im4p.output()
    }

    @Test("Read PAYP IM4P")
    func testReadPayp() async throws {
        let data = try await TestResource.paypIM4P
        let im4p = try IM4P(data: data)

        #expect(im4p.fourcc == "ibss")
        #expect(im4p.description == "iBoot-8419.40.112")

        guard let payload = im4p.payload else {
            Issue.record("Payload missing")
            return
        }

        #expect(payload.encrypted == true)
        #expect(payload.keybags.count == 2)
        #expect(payload.compression == .lzfseEncrypted)

        #expect(im4p.properties.count == 2)
        #expect(im4p.properties.allSatisfy { ["mmap", "rddg"].contains($0.fourcc) })

        _ = try im4p.output()
    }
}

extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        for i in 0..<len {
            let j = hex.index(hex.startIndex, offsetBy: i * 2)
            let k = hex.index(j, offsetBy: 2)
            let bytes = hex[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }
}
