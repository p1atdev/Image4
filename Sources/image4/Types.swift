import Foundation
import SwiftASN1

public enum Image4Error: Error {
    case invalidData
    case unexpectedTag(ASN1Identifier)
    case missingProperty(String)
    case compressionError
    case decryptionError
}

public enum Compression: Int {
    case none = 0
    case lzss = 1
    case lzfse = 2
    case lzfseEncrypted = 3
}

extension Data {
    public func reversedData() -> Data {
        Data(Array(self.reversed()))
    }

    public func contains(_ other: Data) -> Bool {
        return self.range(of: other) != nil
    }

    public init(hexString: String) throws {
        var data = Data()
        var hex = hexString
        if hex.count % 2 != 0 {
            hex = "0" + hex
        }

        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        self = data
    }
}
