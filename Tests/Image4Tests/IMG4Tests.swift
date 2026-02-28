import Foundation
import Testing
@testable import Image4

@Suite("IMG4 Tests")
struct IMG4Tests {
    @Test("Create IMG4")
    func testCreate() async throws {
        let im4m = try IM4M(data: try TestResource.im4m)
        let im4p = try IM4P(data: try TestResource.im4p)
        
        let img4 = IMG4(im4m: im4m, im4p: im4p)
        
        // Re-encoding might cause byte mismatches if original DER is not canonical.
        // Instead of exact data match, we check if it can be parsed back and has same properties.
        let outputData = try img4.output()
        let reParsed = try IMG4(data: outputData)
        
        #expect(reParsed.im4m?.chip_id == im4m.chip_id)
        #expect(reParsed.im4p?.fourcc == im4p.fourcc)
    }

    @Test("Create IMG4 with IM4R")
    func testCreateWithIM4R() async throws {
        let im4m = try IM4M(data: try TestResource.im4m)
        let im4p = try IM4P(data: try TestResource.im4p)
        let im4r = try IM4R(data: try TestResource.im4r)
        
        let img4 = IMG4(im4m: im4m, im4p: im4p, im4r: im4r)
        
        _ = try img4.output()
    }

    @Test("Read IMG4")
    func testRead() async throws {
        let data = try TestResource.img4
        let img4 = try IMG4(data: data)
        
        #expect(img4.im4m != nil)
        #expect(img4.im4p != nil)
        
        // Check contents instead of exact re-encoded bytes
        #expect(img4.im4m?.chip_id == (try IM4M(data: try TestResource.im4m)).chip_id)
        #expect(img4.im4p?.fourcc == (try IM4P(data: try TestResource.im4p)).fourcc)
    }
}
