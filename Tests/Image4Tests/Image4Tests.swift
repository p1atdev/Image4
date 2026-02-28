import Foundation
import Testing

@testable import Image4

struct Image4Tests {
    func loadResource(name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "bin") else {
            fatalError("Resource \(name) not found")
        }
        return try Data(contentsOf: url)
    }

    @Test func testIM4M() async throws {
        let data = try loadResource(name: "IM4M")
        let im4m = try IM4M(data: data)

        #expect(im4m.apnonce?.map { String(format: "%02x", $0) }.joined() == "0123456789012345678901234567890123456789012345678901234567890123")
        #expect(im4m.chip_id == 0x8015)
        #expect(im4m.ecid == 0x0123456789012)
        #expect(im4m.sepnonce?.map { String(format: "%02x", $0) }.joined() == "0123456789012345678901234567890123456789")
        #expect(im4m.properties.count == 11)
        #expect(im4m.images.count == 35)

        let outputData = try im4m.output()
        let im4mRe = try IM4M(data: outputData)
        #expect(im4mRe.chip_id == im4m.chip_id)
        #expect(im4mRe.ecid == im4m.ecid)
    }

    @Test func testIM4P() async throws {
        let data = try loadResource(name: "IM4P")
        let im4p = try IM4P(data: data)
        #expect(im4p.fourcc == "test")

        let outputData = try im4p.output()
        let im4pRe = try IM4P(data: outputData)
        #expect(im4pRe.fourcc == im4p.fourcc)
    }

    @Test func testIM4R() async throws {
        let data = try loadResource(name: "IM4R")
        let im4r = try IM4R(data: data)
        #expect(im4r.boot_nonce?.map { String(format: "%02x", $0) }.joined() == "5f56bbaee8c2d27c")

        let outputData = try im4r.output()
        let im4rRe = try IM4R(data: outputData)
        #expect(im4rRe.boot_nonce == im4r.boot_nonce)
    }

    @Test func testIMG4() async throws {
        let data = try loadResource(name: "IMG4")
        let img4 = try IMG4(data: data)
        #expect(img4.im4m != nil)
        #expect(img4.im4p != nil)

        let outputData = try img4.output()
        let img4Re = try IMG4(data: outputData)
        #expect(img4Re.im4m?.chip_id == img4.im4m?.chip_id)
    }
}
