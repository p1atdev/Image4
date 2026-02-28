import Foundation
import Testing
@testable import Image4

@Suite("IM4R Tests")
struct IM4RTests {
    @Test("Create IM4R")
    func testCreate() async throws {
        let im4r = IM4R()
        im4r.boot_nonce = Data(hex: "1234567890123456")
        
        _ = try im4r.output()
    }

    @Test("Read IM4R")
    func testRead() async throws {
        let data = try TestResource.im4r
        let im4r = try IM4R(data: data)
        #expect(im4r.boot_nonce?.map { String(format: "%02x", $0) }.joined() == "5f56bbaee8c2d27c")

        _ = try im4r.output()
    }
}
