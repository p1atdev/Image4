import Foundation
import SwiftASN1

public class IM4R: DERSerializable {
    public var boot_nonce: Data?
    public var properties: [ManifestProperty] = []

    public convenience init(data: Data) throws {
        let rootNode = try DER.parse(Array(data))
        try self.init(node: rootNode)
    }

    internal init(node: ASN1Node) throws {
        try DER.sequence(node, identifier: .sequence) {
            (scanner: inout ASN1NodeCollection.Iterator) in
            guard let head = scanner.next(),
                (try? String(ASN1IA5String(derEncoded: head))) == "IM4R"
            else {
                throw Image4Error.invalidData
            }

            guard let setNode = scanner.next(), setNode.identifier == .set else {
                throw Image4Error.invalidData
            }
            guard case .constructed(let propNodes) = setNode.content else { return }
            for propNode in propNodes {
                if let prop = try? parseProperty(propNode) {
                    self.properties.append(prop)
                    if prop.fourcc == "BNCN" {
                        self.boot_nonce = (prop.value as? Data)?.reversedData()
                    }
                }
            }
        }
    }

    public init() {}

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
            try ASN1IA5String("IM4R").serialize(into: &coder)
            try coder.appendConstructedNode(identifier: .set) { coder in
                for prop in properties {
                    try prop.serialize(into: &coder)
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
