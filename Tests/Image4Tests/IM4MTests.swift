import Foundation
import Testing
@testable import Image4

struct IM4MTests {
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
        #expect(im4mRe.apnonce == im4m.apnonce)
        #expect(im4mRe.sepnonce == im4m.sepnonce)
    }
}
