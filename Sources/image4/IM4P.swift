import Foundation
import SwiftASN1
import Compression
import CommonCrypto

public class IM4P: DERSerializable {
    public var fourcc: String?
    public var description: String?
    public var payload: IM4PData?

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
                    let kbagData = try ASN1OctetString(derEncoded: nextNode).bytes
                    try parseKeybags(Data(kbagData))
                } else {
                    try parseSize(nextNode)
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
        guard node.identifier == .sequence else { return }
        try DER.sequence(node, identifier: .sequence) { scanner in
            guard let first = scanner.next(), (try? UInt64(derEncoded: first)) == 1,
                let sizeNode = scanner.next(), let size = try? UInt64(derEncoded: sizeNode)
            else {
                return
            }
            self.payload?.size = size
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
            throw Image4Error.compressionError
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
