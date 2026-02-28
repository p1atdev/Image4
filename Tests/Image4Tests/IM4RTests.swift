import Foundation
import Testing
@testable import Image4

struct IM4RTests {
    @Test func testIM4R() async throws {
        let data = try loadResource(name: "IM4R")
        let im4r = try IM4R(data: data)
        #expect(im4r.boot_nonce?.map { String(format: "%02x", $0) }.joined() == "5f56bbaee8c2d27c")

        let outputData = try im4r.output()
        let im4rRe = try IM4R(data: outputData)
        #expect(im4rRe.boot_nonce == im4r.boot_nonce)
        #expect(im4rRe.properties.count == im4r.properties.count)
    }
}
