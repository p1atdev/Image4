import Foundation
import SwiftASN1
import Compression
import CommonCrypto
import LZSS

public class IM4P: DERSerializable {
    public var fourcc: String?
    public var description: String?
    public var payload: IM4PData?
    public var properties: [ManifestProperty] = []

    public convenience init(data: Data) throws {
        let rootNode = try DER.parse(Array(data))
        try self.init(node: rootNode)
    }

    internal init(node: ASN1Node) throws {
        try DER.sequence(node, identifier: .sequence) {
            (scanner: inout ASN1NodeCollection.Iterator) in
            guard let head = scanner.next(),
                (try? String(ASN1IA5String(derEncoded: head))) == "IM4P"
            else {
                throw Image4Error.invalidData
            }

            if let fNode = scanner.next() {
                self.fourcc = try? String(ASN1IA5String(derEncoded: fNode))
            }
            if let dNode = scanner.next() {
                self.description = try? String(ASN1IA5String(derEncoded: dNode))
            }

            guard let pNode = scanner.next() else { throw Image4Error.invalidData }
            let payloadData = Data(try ASN1OctetString(derEncoded: pNode).bytes)
            self.payload = IM4PData(data: payloadData)

            while let nextNode = scanner.next() {
                if nextNode.identifier == .octetString {
                    // Keybags
                    let kbagData = try ASN1OctetString(derEncoded: nextNode).bytes
                    try parseKeybags(Data(kbagData))
                } else if nextNode.identifier == .sequence {
                    // Size sequence
                    try parseSize(nextNode)
                } else if nextNode.identifier.tagClass == .contextSpecific && nextNode.identifier.tagNumber == 0 {
                    // PAYP properties
                    try parsePayp(nextNode)
                }
            }
        }
    }

    public init() {}

    private func parseKeybags(_ data: Data) throws {
        let node = try DER.parse(Array(data))
        guard node.identifier == .sequence, case .constructed(let nodes) = node.content else {
            return
        }
        for kNode in nodes {
            if let kbag = try? Keybag(node: kNode) {
                self.payload?.keybags.append(kbag)
            }
        }
    }

    private func parseSize(_ node: ASN1Node) throws {
        try DER.sequence(node, identifier: .sequence) { scanner in
            guard let first = scanner.next(), (try? UInt64(derEncoded: first)) == 1,
                let sizeNode = scanner.next(), let size = try? UInt64(derEncoded: sizeNode)
            else {
                return
            }
            self.payload?.size = size
        }
    }
    
    private func parsePayp(_ node: ASN1Node) throws {
        guard case .constructed(let nodes) = node.content else { return }
        var nodesScanner = nodes.makeIterator()
        guard let innerSeq = nodesScanner.next() else { return }
        
        try DER.sequence(innerSeq, identifier: .sequence) { scanner in
            guard let head = scanner.next(), (try? String(ASN1IA5String(derEncoded: head))) == "PAYP" else { return }
            guard let setNode = scanner.next(), setNode.identifier == .set else { return }
            guard case .constructed(let propNodes) = setNode.content else { return }
            
            for pNode in propNodes {
                if let prop = try? parseProperty(pNode) {
                    self.properties.append(prop)
                }
            }
        }
    }
    
    private func parseProperty(_ node: ASN1Node) throws -> ManifestProperty {
        guard case .constructed(let nodes) = node.content else { throw Image4Error.invalidData }
        var scanner = nodes.makeIterator()
        guard let seqNode = scanner.next(), seqNode.identifier == .sequence else {
            throw Image4Error.invalidData
        }

        return try DER.sequence(seqNode, identifier: .sequence) {
            (scanner: inout ASN1NodeCollection.Iterator) in
            guard let fourccNode = scanner.next(),
                let fourcc = try? String(ASN1IA5String(derEncoded: fourccNode)),
                let valueNode = scanner.next()
            else {
                throw Image4Error.invalidData
            }

            let value: Any
            if valueNode.identifier == .integer {
                value = try UInt64(derEncoded: valueNode)
            } else if valueNode.identifier == .octetString {
                value = Data(try ASN1OctetString(derEncoded: valueNode).bytes)
            } else {
                if case .primitive(let bytes) = valueNode.content {
                    value = Data(bytes)
                } else {
                    value = Data(valueNode.encodedBytes)
                }
            }

            return ManifestProperty(fourcc: fourcc, value: value)
        }
    }

    public func serialize(into coder: inout DER.Serializer) throws {
        try coder.appendConstructedNode(identifier: .sequence) { coder in
            try ASN1IA5String("IM4P").serialize(into: &coder)
            try ASN1IA5String(self.fourcc ?? "").serialize(into: &coder)
            try ASN1IA5String(self.description ?? "").serialize(into: &coder)

            if let payload = self.payload {
                try ASN1OctetString(contentBytes: ArraySlice(payload.data)).serialize(into: &coder)

                if !payload.keybags.isEmpty {
                    var kbagSerializer = DER.Serializer()
                    try kbagSerializer.appendConstructedNode(identifier: .sequence) { coder in
                        for kbag in payload.keybags {
                            try kbag.serialize(into: &coder)
                        }
                    }
                    try ASN1OctetString(contentBytes: ArraySlice(kbagSerializer.serializedBytes))
                        .serialize(into: &coder)
                }

                if payload.compression == .lzfse || payload.compression == .lzfseEncrypted {
                    try coder.appendConstructedNode(identifier: .sequence) { coder in
                        try Int(1).serialize(into: &coder)
                        try Int(payload.size).serialize(into: &coder)
                    }
                }
                
                if !self.properties.isEmpty {
                    let tag = ASN1Identifier(tagWithNumber: 0, tagClass: .contextSpecific)
                    try coder.appendConstructedNode(identifier: tag) { coder in
                        try coder.appendConstructedNode(identifier: .sequence) { coder in
                            try ASN1IA5String("PAYP").serialize(into: &coder)
                            try coder.appendConstructedNode(identifier: .set) { coder in
                                for prop in self.properties {
                                    try prop.serialize(into: &coder)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    public func output() throws -> Data {
        var serializer = DER.Serializer()
        try self.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }
}

public class IM4PData {
    public var extra: Data?
    public var keybags: [Keybag] = []
    public private(set) var data: Data
    public var compression: Compression = .none
    public var size: UInt64 = 0 {
        didSet {
            detectCompression()
        }
    }

    public var encrypted: Bool {
        !keybags.isEmpty
    }

    public init(data: Data) {
        self.data = data
        detectCompression()
        
        // Handle complzss header if present
        if compression == .lzss {
            parseComplzssHeader()
        }
    }

    private func detectCompression() {
        if encrypted && size > 0 {
            self.compression = .lzfseEncrypted
        } else if data.prefix(8) == Data("complzss".utf8) {
            self.compression = .lzss
        } else if data.prefix(3) == Data("bvx".utf8) && data.contains(Data("bvx$".utf8)) {
            self.compression = .lzfse
        } else {
            self.compression = .none
        }
    }
    
    private func parseComplzssHeader() {
        // complzss header is 0x180 bytes
        // 0x8: adler32 (4 bytes)
        // 0xC: uncompressed size (4 bytes, big endian)
        // 0x10: compressed size (4 bytes, big endian)
        guard data.count >= 0x180 else { return }
        
        let uncompSize = data.subdata(in: 0xC..<0x10).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let compSize = data.subdata(in: 0x10..<0x14).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        self.size = UInt64(uncompSize)
        
        // If there's data after (0x180 + compSize), it's extra data (like KPP)
        let totalLzssSize = 0x180 + Int(compSize)
        if data.count > totalLzssSize {
            self.extra = data.subdata(in: totalLzssSize..<data.count)
            self.data = data.subdata(in: 0..<totalLzssSize)
        }
    }

    private func createComplzssHeader(compSize: UInt32) -> Data {
        var header = Data("complzss".utf8)
        
        // adler32
        var adler: UInt32 = 1
        var s1: UInt32 = 1
        var s2: UInt32 = 0
        for byte in data {
            s1 = (s1 + UInt32(byte)) % 65521
            s2 = (s2 + s1) % 65521
        }
        adler = (s2 << 16) | s1
        
        var adlerBE = adler.bigEndian
        header.append(Data(bytes: &adlerBE, count: 4))
        
        var uncompSizeBE = UInt32(size).bigEndian
        header.append(Data(bytes: &uncompSizeBE, count: 4))
        
        var compSizeBE = compSize.bigEndian
        header.append(Data(bytes: &compSizeBE, count: 4))
        
        var unknown = UInt32(1).bigEndian
        header.append(Data(bytes: &unknown, count: 4))
        
        // Padding to 0x180
        header.append(Data(repeating: 0, count: 0x180 - header.count))
        
        return header
    }

    public func compress(to compression: Compression) throws {
        switch compression {
        case .lzfse:
            let bufferSize = data.count + 128 // Some extra space
            var destinationBuffer = [UInt8](repeating: 0, count: bufferSize)
            let result = data.withUnsafeBytes { sourceBuffer in
                compression_encode_buffer(
                    &destinationBuffer, bufferSize,
                    sourceBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), data.count, nil,
                    COMPRESSION_LZFSE)
            }
            guard result > 0 else { throw Image4Error.compressionError }
            self.size = UInt64(data.count)
            self.data = Data(destinationBuffer.prefix(result))
            self.compression = .lzfse
        case .lzss:
            let compressed = LZSS.encode(data)
            self.size = UInt64(data.count)
            self.data = createComplzssHeader(compSize: UInt32(compressed.data.count)) + compressed.data
            self.compression = .lzss
        default:
            return
        }
    }

    public func decompress() throws {
        switch compression {
        case .lzfse, .lzfseEncrypted:
            guard size > 0 else { throw Image4Error.compressionError }
            var destinationBuffer = [UInt8](repeating: 0, count: Int(size))
            let result = data.withUnsafeBytes { sourceBuffer in
                compression_decode_buffer(
                    &destinationBuffer, Int(size),
                    sourceBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), data.count, nil,
                    COMPRESSION_LZFSE)
            }
            guard result == Int(size) else { throw Image4Error.compressionError }
            self.data = Data(destinationBuffer)
            self.compression = .none
        case .lzss:
            guard size > 0 else { throw Image4Error.compressionError }
            // Skip the 0x180 complzss header
            let compressedData = data.subdata(in: 0x180..<data.count)
            let decompressed = LZSS.decode(compressedData)
            self.data = decompressed
            self.compression = .none
        default:
            return
        }
    }

    public func decrypt(with keybag: Keybag) throws {
        let key = keybag.key
        let iv = keybag.iv

        var decryptedData = Data(count: data.count)
        var numBytesDecrypted: Int = 0
        let decryptedDataCount = decryptedData.count

        var status = decryptedData.withUnsafeMutableBytes { decryptedBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            decryptedBytes.baseAddress, decryptedDataCount,
                            &numBytesDecrypted)
                    }
                }
            }
        }

        if status != kCCSuccess {
            status = decryptedData.withUnsafeMutableBytes { decryptedBytes in
                data.withUnsafeBytes { dataBytes in
                    key.withUnsafeBytes { keyBytes in
                        iv.withUnsafeBytes { ivBytes in
                            CCCrypt(
                                CCOperation(kCCDecrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                0,
                                keyBytes.baseAddress, key.count,
                                ivBytes.baseAddress,
                                dataBytes.baseAddress, data.count,
                                decryptedBytes.baseAddress, decryptedDataCount,
                                &numBytesDecrypted)
                        }
                    }
                }
            }
        }

        guard status == kCCSuccess else { throw Image4Error.decryptionError }

        self.data = decryptedData.prefix(numBytesDecrypted)
        self.keybags = []
        detectCompression()
        
        if compression == .lzss {
            parseComplzssHeader()
        }
    }
}

public class Keybag: DERSerializable {
    public var iv: Data
    public var key: Data
    public var type: UInt64

    public init(iv: Data, key: Data, type: UInt64 = 1) {
        self.iv = iv
        self.key = key
        self.type = type
    }

    internal init(node: ASN1Node) throws {
        var iv: Data?
        var key: Data?
        var type: UInt64 = 1

        try DER.sequence(node, identifier: .sequence) { scanner in
            if let tNode = scanner.next() { type = (try? UInt64(derEncoded: tNode)) ?? 1 }
            if let iNode = scanner.next() {
                iv = Data(try ASN1OctetString(derEncoded: iNode).bytes)
            }
            if let kNode = scanner.next() {
                key = Data(try ASN1OctetString(derEncoded: kNode).bytes)
            }
        }

        guard let iv = iv, let key = key else { throw Image4Error.invalidData }
        self.iv = iv
        self.key = key
        self.type = type
    }

    public func serialize(into coder: inout DER.Serializer) throws {
        try coder.appendConstructedNode(identifier: .sequence) { coder in
            try self.type.serialize(into: &coder)
            try ASN1OctetString(contentBytes: ArraySlice(self.iv)).serialize(into: &coder)
            try ASN1OctetString(contentBytes: ArraySlice(self.key)).serialize(into: &coder)
        }
    }
}
