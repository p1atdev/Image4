import Foundation
import Testing
import LZSS
import CommonCrypto
@testable import Image4

struct IM4PTests {
    @Test func testIM4PRead() async throws {
        let data = try loadResource(name: "IM4P")
        let im4p = try IM4P(data: data)
        #expect(im4p.fourcc == "test")
        #expect(im4p.description == "Test Image4 payload.")

        let outputData = try im4p.output()
        let im4pRe = try IM4P(data: outputData)
        #expect(im4pRe.fourcc == im4p.fourcc)
        #expect(im4pRe.description == im4p.description)
        #expect(im4pRe.payload?.data == im4p.payload?.data)
    }

    @Test func testIM4PCreate() async throws {
        let payloadData = try loadResource(name: "test_payload")
        let im4p = IM4P()
        im4p.fourcc = "test"
        im4p.description = "Test Image4 payload."
        im4p.payload = IM4PData(data: payloadData)

        let expectedData = try loadResource(name: "IM4P")
        let outputData = try im4p.output()
        
        // Compare with expected binary
        #expect(outputData == expectedData)
    }

    @Test func testLZSSDecompression() async throws {
        let rawString = "Hello LZSS!"
        let rawData = Data(rawString.utf8)
        let compressed = LZSS.encode(rawData)
        
        var mockData = Data("complzss".utf8)
        mockData.append(contentsOf: [0, 0, 0, 0]) // adler32
        
        let uncompSize = UInt32(rawData.count).bigEndian
        mockData.append(withUnsafeBytes(of: uncompSize) { Data($0) })
        
        let compSize = UInt32(compressed.data.count).bigEndian
        mockData.append(withUnsafeBytes(of: compSize) { Data($0) })
        
        mockData.append(Data(repeating: 0, count: 0x180 - mockData.count)) // padding
        mockData.append(compressed.data)
        
        let im4pData = IM4PData(data: mockData)
        #expect(im4pData.compression == .lzss)
        #expect(im4pData.size == UInt64(rawData.count))
        
        try im4pData.decompress()
        #expect(im4pData.compression == .none)
        #expect(String(data: im4pData.data, encoding: .utf8) == rawString)
    }
    
    @Test func testIM4PEncryption() async throws {
        let rawString = "Secret Message!"
        let rawData = Data(rawString.utf8)
        
        let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let iv = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let keybag = Keybag(iv: iv, key: key)
        
        var encryptedData = Data(count: rawData.count + 16)
        var numBytesEncrypted: Int = 0
        let encryptedDataCount = encryptedData.count
        
        let status = encryptedData.withUnsafeMutableBytes { encryptedBytes in
            rawData.withUnsafeBytes { rawBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            rawBytes.baseAddress, rawData.count,
                            encryptedBytes.baseAddress, encryptedDataCount,
                            &numBytesEncrypted)
                    }
                }
            }
        }
        
        #expect(status == kCCSuccess)
        let finalEncryptedData = encryptedData.prefix(numBytesEncrypted)
        
        let im4pData = IM4PData(data: finalEncryptedData)
        im4pData.keybags.append(keybag)
        
        #expect(im4pData.encrypted == true)
        
        try im4pData.decrypt(with: keybag)
        #expect(im4pData.encrypted == false)
        #expect(im4pData.data == rawData)
        #expect(String(data: im4pData.data, encoding: .utf8) == rawString)
    }
}
