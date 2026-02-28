import Foundation
import Testing
@testable import Image4

@Suite("IM4M Tests")
struct IM4MTests {
    @Test("Read IM4M")
    func testRead() async throws {
        let data = try TestResource.im4m
        let im4m = try IM4M(data: data)

        #expect(im4m.apnonce?.map { String(format: "%02x", $0) }.joined() == "0123456789012345678901234567890123456789012345678901234567890123")
        #expect(im4m.chip_id == 0x8015)
        #expect(im4m.ecid == 0x0123456789012)
        #expect(im4m.sepnonce?.map { String(format: "%02x", $0) }.joined() == "0123456789012345678901234567890123456789")

        #expect(im4m.properties.count == 11)
        #expect(im4m.images.count == 35)
        
        _ = try im4m.output()
    }
}
