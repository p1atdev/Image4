import Foundation
import SwiftASN1

public class IMG4: DERSerializable {
    public var im4m: IM4M?
    public var im4p: IM4P?
    public var im4r: IM4R?

    public convenience init(data: Data) throws {
        let rootNode = try DER.parse(Array(data))
        try self.init(node: rootNode)
    }

    internal init(node: ASN1Node) throws {
        try DER.sequence(node, identifier: .sequence) {
            (scanner: inout ASN1NodeCollection.Iterator) in
            guard let head = scanner.next(),
                (try? String(ASN1IA5String(derEncoded: head))) == "IMG4"
            else {
                throw Image4Error.invalidData
            }

            if let pNode = scanner.next() {
                self.im4p = try IM4P(node: pNode)
            }

            while let nextNode = scanner.next() {
                if nextNode.identifier.tagClass == .contextSpecific {
                    guard case .constructed(let innerNodes) = nextNode.content else {
                        continue
                    }
                    var innerScanner = innerNodes.makeIterator()
                    guard let innerSeq = innerScanner.next() else {
                        continue
                    }

                    if nextNode.identifier.tagNumber == 0 {
                        self.im4m = try IM4M(node: innerSeq)
                    } else if nextNode.identifier.tagNumber == 1 {
                        self.im4r = try IM4R(node: innerSeq)
                    }
                }
            }
        }
    }

    public init(im4m: IM4M? = nil, im4p: IM4P? = nil, im4r: IM4R? = nil) {
        self.im4m = im4m
        self.im4p = im4p
        self.im4r = im4r
    }

    public func serialize(into coder: inout DER.Serializer) throws {
        try coder.appendConstructedNode(identifier: .sequence) { coder in
            try ASN1IA5String("IMG4").serialize(into: &coder)

            if let im4p = self.im4p {
                try im4p.serialize(into: &coder)
            }

            if let im4m = self.im4m {
                let tag = ASN1Identifier(tagWithNumber: 0, tagClass: .contextSpecific)
                try coder.appendConstructedNode(identifier: tag) { coder in
                    try im4m.serialize(into: &coder)
                }
            }

            if let im4r = self.im4r {
                let tag = ASN1Identifier(tagWithNumber: 1, tagClass: .contextSpecific)
                try coder.appendConstructedNode(identifier: tag) { coder in
                    try im4r.serialize(into: &coder)
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
