import Foundation
import SwiftASN1

public class IM4M: DERSerializable {
    public private(set) var apnonce: Data?
    public private(set) var chip_id: UInt64?
    public private(set) var ecid: UInt64?
    public private(set) var sepnonce: Data?
    public private(set) var properties: [ManifestProperty] = []
    public private(set) var images: [ManifestImageProperties] = []
    public private(set) var board_id: UInt64?
    public private(set) var signature: Data?
    public private(set) var certificates: Data?

    public convenience init(data: Data) throws {
        let rootNode = try DER.parse(Array(data))
        try self.init(node: rootNode)
    }

    internal init(node: ASN1Node) throws {
        try DER.sequence(node, identifier: .sequence) {
            (scanner: inout ASN1NodeCollection.Iterator) in
            guard let first = scanner.next(),
                let identifier = try? String(ASN1IA5String(derEncoded: first)),
                identifier == "IM4M"
            else {
                throw Image4Error.invalidData
            }

            _ = scanner.next()

            guard let setNode = scanner.next(), setNode.identifier == .set else {
                throw Image4Error.invalidData
            }

            try parseSet(setNode)

            if let sigNode = scanner.next() {
                if sigNode.identifier == .octetString {
                    self.signature = Data(try ASN1OctetString(derEncoded: sigNode).bytes)
                }
            }

            if let certNode = scanner.next() {
                if certNode.identifier == .sequence {
                    self.certificates = Data(certNode.encodedBytes)
                }
            }
        }
    }

    private func parseSet(_ node: ASN1Node) throws {
        guard case .constructed(let nodes) = node.content else { return }
        var scanner = nodes.makeIterator()
        guard let privateNode = scanner.next() else { return }

        let manbTag = ASN1Identifier(tagWithNumber: 0x4D41_4E42, tagClass: .private)
        guard privateNode.identifier.tagNumber == manbTag.tagNumber,
            privateNode.identifier.tagClass == manbTag.tagClass
        else {
            return
        }

        guard case .constructed(let innerNodes) = privateNode.content else { return }
        var innerScanner = innerNodes.makeIterator()
        guard let manbSeqNode = innerScanner.next(), manbSeqNode.identifier == .sequence else {
            return
        }

        try DER.sequence(manbSeqNode, identifier: .sequence) {
            (manbScanner: inout ASN1NodeCollection.Iterator) in
            _ = manbScanner.next()
            guard let setNode = manbScanner.next(), setNode.identifier == .set else {
                throw Image4Error.invalidData
            }
            guard case .constructed(let groupNodes) = setNode.content else { return }
            for groupNode in groupNodes {
                try parsePropertyGroup(groupNode)
            }
        }
    }

    private func parsePropertyGroup(_ node: ASN1Node) throws {
        guard case .constructed(let nodes) = node.content else { return }
        var scanner = nodes.makeIterator()
        guard let seqNode = scanner.next(), seqNode.identifier == .sequence else { return }

        try DER.sequence(seqNode, identifier: .sequence) {
            (scanner: inout ASN1NodeCollection.Iterator) in
            guard let fourccNode = scanner.next(),
                let fourcc = try? String(ASN1IA5String(derEncoded: fourccNode))
            else {
                throw Image4Error.invalidData
            }

            if fourcc == "MANP" {
                guard let setNode = scanner.next(), setNode.identifier == .set else {
                    throw Image4Error.invalidData
                }
                guard case .constructed(let propNodes) = setNode.content else { return }
                for propNode in propNodes {
                    if let prop = try? parseProperty(propNode) {
                        self.properties.append(prop)
                        assignWellKnownProperty(prop)
                    }
                }
            } else {
                guard let setNode = scanner.next(), setNode.identifier == .set else {
                    throw Image4Error.invalidData
                }
                guard case .constructed(let propNodes) = setNode.content else { return }
                var imgProps = ManifestImageProperties(fourcc: fourcc)
                for propNode in propNodes {
                    if let prop = try? parseProperty(propNode) {
                        imgProps.properties.append(prop)
                    }
                }
                self.images.append(imgProps)
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

    private func assignWellKnownProperty(_ prop: ManifestProperty) {
        switch prop.fourcc {
        case "BNCH": self.apnonce = prop.value as? Data
        case "CHIP": self.chip_id = prop.value as? UInt64
        case "ECID": self.ecid = prop.value as? UInt64
        case "snon": self.sepnonce = prop.value as? Data
        case "BORD": self.board_id = prop.value as? UInt64
        default: break
        }
    }

    public func serialize(into coder: inout DER.Serializer) throws {
        try coder.appendConstructedNode(identifier: .sequence) { coder in
            try ASN1IA5String("IM4M").serialize(into: &coder)
            try Int(0).serialize(into: &coder)

            try coder.appendConstructedNode(identifier: .set) { coder in
                let manbTag = ASN1Identifier(tagWithNumber: 0x4D41_4E42, tagClass: .private)
                try coder.appendConstructedNode(identifier: manbTag) { coder in
                    try coder.appendConstructedNode(identifier: .sequence) { coder in
                        try ASN1IA5String("MANB").serialize(into: &coder)
                        try coder.appendConstructedNode(identifier: .set) { coder in
                            // MANP
                            let manpTag = ASN1Identifier(
                                tagWithNumber: 0x4D41_4E50, tagClass: .private)
                            try coder.appendConstructedNode(identifier: manpTag) { coder in
                                try coder.appendConstructedNode(identifier: .sequence) { coder in
                                    try ASN1IA5String("MANP").serialize(into: &coder)
                                    try coder.appendConstructedNode(identifier: .set) { coder in
                                        for prop in self.properties {
                                            try prop.serialize(into: &coder)
                                        }
                                    }
                                }
                            }

                            // Images
                            for img in self.images {
                                try img.serialize(into: &coder)
                            }
                        }
                    }
                }
            }

            if let sig = self.signature {
                try ASN1OctetString(contentBytes: ArraySlice(sig)).serialize(into: &coder)
            }

            if let certs = self.certificates {
                let certNode = try DER.parse(Array(certs))
                coder.serialize(certNode)
            }
        }
    }

    public func output() throws -> Data {
        var serializer = DER.Serializer()
        try self.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }
}

public struct ManifestProperty: DERSerializable {
    public let fourcc: String
    public let value: Any

    public init(fourcc: String, value: Any) {
        self.fourcc = fourcc
        self.value = value
    }

    public func serialize(into coder: inout DER.Serializer) throws {
        let tagNumber = UInt(Data(fourcc.utf8).reduce(0) { ($0 << 8) | UInt($1) })
        let identifier = ASN1Identifier(tagWithNumber: tagNumber, tagClass: .private)

        try coder.appendConstructedNode(identifier: identifier) { coder in
            try coder.appendConstructedNode(identifier: .sequence) { coder in
                try ASN1IA5String(fourcc).serialize(into: &coder)
                if let intVal = value as? UInt64 {
                    try intVal.serialize(into: &coder)
                } else if let intVal = value as? Int {
                    try intVal.serialize(into: &coder)
                } else if let dataVal = value as? Data {
                    try ASN1OctetString(contentBytes: ArraySlice(dataVal)).serialize(into: &coder)
                } else if let bytesVal = value as? ArraySlice<UInt8> {
                    try ASN1OctetString(contentBytes: bytesVal).serialize(into: &coder)
                }
            }
        }
    }
}

public struct ManifestImageProperties: DERSerializable {
    public let fourcc: String
    public var properties: [ManifestProperty] = []

    public init(fourcc: String) {
        self.fourcc = fourcc
    }

    public var digest: Data? {
        properties.first { $0.fourcc == "DGST" }?.value as? Data
    }

    public func serialize(into coder: inout DER.Serializer) throws {
        let tagNumber = UInt(Data(fourcc.utf8).reduce(0) { ($0 << 8) | UInt($1) })
        let identifier = ASN1Identifier(tagWithNumber: tagNumber, tagClass: .private)

        try coder.appendConstructedNode(identifier: identifier) { coder in
            try coder.appendConstructedNode(identifier: .sequence) { coder in
                try ASN1IA5String(fourcc).serialize(into: &coder)
                try coder.appendConstructedNode(identifier: .set) { coder in
                    for prop in properties {
                        try prop.serialize(into: &coder)
                    }
                }
            }
        }
    }
}
