import Foundation
import Testing

@testable import Image4

@Suite("Remote Resource Tests")
struct RemoteResourceTests {

    @Test("Fetch Decrypted LZSS IM4P")
    func testFetchDecLZSS() async throws {
        let data = try await TestResource.decLZSSIM4P
        #expect(!data.isEmpty)
    }

    @Test("Fetch Encrypted LZSS IM4P")
    func testFetchEncLZSS() async throws {
        let data = try await TestResource.encLZSSIM4P
        #expect(!data.isEmpty)
    }

    @Test("Fetch Decrypted LZFSE IM4P")
    func testFetchDecLZFSE() async throws {
        let data = try await TestResource.decLZFSEIM4P
        #expect(!data.isEmpty)
    }

    @Test("Fetch Encrypted LZFSE IM4P")
    func testFetchEncLZFSE() async throws {
        let data = try await TestResource.encLZFSEIM4P
        #expect(!data.isEmpty)
    }

    @Test("Fetch PAYP IM4P")
    func testFetchPayp() async throws {
        let data = try await TestResource.paypIM4P
        #expect(!data.isEmpty)
    }
}
