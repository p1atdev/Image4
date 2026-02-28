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
    func reversedData() -> Data {
        Data(Array(self.reversed()))
    }
    
    func contains(_ other: Data) -> Bool {
        return self.range(of: other) != nil
    }
}
