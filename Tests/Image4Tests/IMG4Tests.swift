import Foundation
import Testing
@testable import Image4

struct IMG4Tests {
    @Test func testIMG4() async throws {
        let data = try loadResource(name: "IMG4")
        let img4 = try IMG4(data: data)
        #expect(img4.im4m != nil)
        #expect(img4.im4p != nil)

        let outputData = try img4.output()
        let img4Re = try IMG4(data: outputData)
        #expect(img4Re.im4m?.chip_id == img4.im4m?.chip_id)
        #expect(img4Re.im4p?.fourcc == img4.im4p?.fourcc)
    }
}
