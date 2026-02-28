import Foundation
import ArgumentParser
import Image4

@main
struct Image4CLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "image4",
        abstract: "A Swift CLI tool for parsing Apple's Image4 format.",
        subcommands: [IM4MCommand.self, IM4PCommand.self, IM4RCommand.self, IMG4Command.self]
    )
}

struct IM4MCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "im4m",
        abstract: "Image4 manifest commands.",
        subcommands: [Info.self, Verify.self, Extract.self]
    )

    struct Info: ParsableCommand {
        @Option(name: .shortAndLong, help: "Input Image4 manifest file.")
        var input: String

        @Flag(name: .shortAndLong, help: "Increase verbosity.")
        var verbose: Bool = false

        func run() throws {
            let data = try Data(contentsOf: URL(fileURLWithPath: input))
            let im4m = try IM4M(data: data)

            print("Reading \(input)...")
            print("Image4 manifest info:")

            let soc: String
            if let chipId = im4m.chip_id {
                if 0x8720 <= chipId && chipId <= 0x8960 {
                    soc = String(format: "S5L%02x", chipId)
                } else if 0x7002...0x8003 ~= chipId {
                    soc = String(format: "S%02x", chipId)
                } else {
                    soc = String(format: "T%02x", chipId)
                }

                if verbose {
                    print("  Device Processor: \(soc) (0x\(String(chipId, radix: 16)))")
                } else {
                    print("  Device Processor: \(soc)")
                }
            }

            if let ecid = im4m.ecid {
                print("  ECID (hex): 0x\(String(ecid, radix: 16))")
            }

            if let apnonce = im4m.apnonce {
                print("  ApNonce (hex): \(apnonce.map { String(format: "%02x", $0) }.joined())")
            }

            if let sepnonce = im4m.sepnonce {
                print("  SepNonce (hex): \(sepnonce.map { String(format: "%02x", $0) }.joined())")
            }

            if verbose {
                for (index, prop) in im4m.properties.enumerated() {
                    if ["BNCH", "CHIP", "ECID", "snon"].contains(prop.fourcc) {
                        continue
                    }

                    if let dataVal = prop.value as? Data {
                        print("  \(prop.fourcc) (hex): \(dataVal.map { String(format: "%02x", $0) }.joined())")
                    } else {
                        print("  \(prop.fourcc): \(prop.value)")
                    }

                    if index == im4m.properties.count - 1 {
                        print()
                    }
                }

                print("  Manifest images (\(im4m.images.count)):")
                for (index, image) in im4m.images.enumerated() {
                    print("    \(image.fourcc):")
                    for prop in image.properties {
                        let valueStr: String
                        if let dataVal = prop.value as? Data {
                            valueStr = dataVal.map { String(format: "%02x", $0) }.joined()
                        } else {
                            valueStr = "\(prop.value)"
                        }
                        print("      \(prop.fourcc): \(valueStr)")
                    }

                    if index != im4m.images.count - 1 {
                        print()
                    }
                }
            } else {
                let imagesStr = im4m.images.map { $0.fourcc }.joined(separator: ", ")
                print("  Manifest images (\(im4m.images.count)): \(imagesStr)")
            }
        }
    }

    struct Verify: ParsableCommand {
        @Option(name: .shortAndLong, help: "Input Image4 manifest file.")
        var input: String

        @Option(name: .shortAndLong, help: "Input build manifest file.")
        var buildManifest: String

        @Flag(name: .shortAndLong, help: "Increase verbosity.")
        var verbose: Bool = false

        func run() throws {
            let im4mData = try Data(contentsOf: URL(fileURLWithPath: input))
            let im4m = try IM4M(data: im4mData)

            let manifestData = try Data(contentsOf: URL(fileURLWithPath: buildManifest))
            guard let manifest = try PropertyListSerialization.propertyList(from: manifestData, options: [], format: nil) as? [String: Any],
                  let buildIdentities = manifest["BuildIdentities"] as? [[String: Any]] else {
                print("Failed to parse build manifest file: \(buildManifest)")
                return
            }

            print("Reading \(input)...")
            print("Reading \(buildManifest)...")

            for (index, identity) in buildIdentities.enumerated() {
                guard let apBoardIDStr = identity["ApBoardID"] as? String,
                      let apBoardID = UInt64(apBoardIDStr.dropFirst(2), radix: 16),
                      let apChipIDStr = identity["ApChipID"] as? String,
                      let apChipID = UInt64(apChipIDStr.dropFirst(2), radix: 16) else {
                    continue
                }

                if apBoardID != im4m.board_id || apChipID != im4m.chip_id {
                    if verbose {
                        print("Skipping build identity \(index + 1)...")
                    }
                    continue
                }

                print("Selected build identity: \(index + 1)")
                guard let componentManifest = identity["Manifest"] as? [String: [String: Any]] else {
                    continue
                }

                var allMatch = true
                for (name, imageInfo) in componentManifest {
                    guard let digest = imageInfo["Digest"] as? Data else {
                        if verbose {
                            print("Component: \(name) has no hash, skipping...")
                        }
                        continue
                    }

                    if verbose {
                        print("Verifying hash of component: \(name)...")
                    }

                    if !im4m.images.contains(where: { $0.digest == digest }) {
                        if verbose {
                            print("No hash found for component: \(name) in Image4 manifest!")
                        }
                        allMatch = false
                        break
                    }
                }

                if allMatch {
                    print("\nImage4 manifest was successfully validated with the build manifest for the following restore:")
                    if let info = identity["Info"] as? [String: Any] {
                        print("Board config: \(info["DeviceClass"] ?? "")")
                        print("Build ID: \(info["BuildNumber"] ?? "")")
                        print("Restore type: \(info["RestoreBehavior"] ?? "")")
                    }
                    return
                }
            }

            print("Image4 manifest is not valid for the provided build manifest!")
        }
    }

    struct Extract: ParsableCommand {
        @Option(name: .shortAndLong, help: "Input SHSH blob file.")
        var input: String

        @Option(name: .shortAndLong, help: "Output file.")
        var output: String

        @Flag(help: "Extract update Image4 manifest (if available).")
        var update: Bool = false

        @Flag(help: "Extract no-nonce Image4 manifest (if available).")
        var noNonce: Bool = false

        func run() throws {
            let data = try Data(contentsOf: URL(fileURLWithPath: input))
            guard var plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                print("Failed to read SHSH blob: \(input)")
                return
            }

            if update {
                guard let updateInstall = plist["updateInstall"] as? [String: Any] else {
                    print("SHSH blob does not contain an update Image4 manifest: \(input)")
                    return
                }
                plist = updateInstall
            } else if noNonce {
                guard let noNonceDict = plist["noNonce"] as? [String: Any] else {
                    print("SHSH blob does not contain a no-nonce Image4 manifest: \(input)")
                    return
                }
                plist = noNonceDict
            }

            guard let ticket = plist["ApImg4Ticket"] as? Data else {
                print("SHSH blob does not contain an Image4 manifest: \(input)")
                return
            }

            let im4m = try IM4M(data: ticket)
            try im4m.output().write(to: URL(fileURLWithPath: output))
            print("Image4 manifest outputted to: \(output)")
        }
    }
}

struct IM4PCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "im4p",
        abstract: "Image4 payload commands.",
        subcommands: [Create.self, Extract.self, Info.self]
    )

    struct Create: ParsableCommand {
        @Option(name: .shortAndLong, help: "Input file.")
        var input: String
        @Option(name: .shortAndLong, help: "Output file.")
        var output: String
        @Option(name: .shortAndLong, help: "FourCC to set.")
        var fourcc: String
        @Option(name: .shortAndLong, help: "Description to set.")
        var description: String?

        @Flag(help: "LZSS compress the data.")
        var lzss: Bool = false
        @Flag(help: "LZFSE compress the data.")
        var lzfse: Bool = false

        @Option(name: .long, help: "Extra IM4P payload data to set (requires --lzss).")
        var extra: String?

        func run() throws {
            guard fourcc.count == 4 else {
                print("FourCC must be 4 characters long")
                return
            }

            let inputData = try Data(contentsOf: URL(fileURLWithPath: input))
            let im4p = IM4P()
            im4p.fourcc = fourcc
            im4p.description = description
            
            let payload = IM4PData(data: inputData)
            im4p.payload = payload

            if let extraPath = extra {
                guard lzss else {
                    print("--extra requires --lzss flag to be set")
                    return
                }
                payload.extra = try Data(contentsOf: URL(fileURLWithPath: extraPath))
            }

            if lzss {
                try payload.compress(to: .lzss)
            } else if lzfse {
                try payload.compress(to: .lzfse)
            }

            try im4p.output().write(to: URL(fileURLWithPath: output))
            print("Image4 payload outputted to: \(output)")
        }
    }

    struct Extract: ParsableCommand {
        @Option(name: .shortAndLong, help: "Input Image4 payload file.")
        var input: String
        @Option(name: .shortAndLong, help: "File to output Image4 payload data to.")
        var output: String
        @Option(name: .long, help: "File to output extra Image4 payload data to.")
        var extra: String?

        @Flag(name: .customLong("no-decompress"), help: "Don't decompress the Image4 payload data.")
        var noDecompress: Bool = false

        @Option(help: "The IV used to encrypt the Image4 payload data.")
        var iv: String?
        @Option(help: "The key used to encrypt the Image4 payload data.")
        var key: String?

        func run() throws {
            let data = try Data(contentsOf: URL(fileURLWithPath: input))
            let im4p = try IM4P(data: data)

            guard let payload = im4p.payload else { return }

            if let ivStr = iv, let keyStr = key {
                print("[NOTE] Image4 payload data is encrypted, decrypting...")
                let ivData = try Data(hexString: ivStr.hasPrefix("0x") ? String(ivStr.dropFirst(2)) : ivStr)
                let keyData = try Data(hexString: keyStr.hasPrefix("0x") ? String(keyStr.dropFirst(2)) : keyStr)
                
                let kbag = Keybag(iv: ivData, key: keyData)
                try payload.decrypt(with: kbag)
            } else if payload.encrypted {
                print("[NOTE] Image4 payload data is encrypted")
            }

            if payload.compression != .none {
                if !noDecompress {
                    print("[NOTE] Image4 payload data is \(payload.compression) compressed, decompressing...")
                    try payload.decompress()
                } else {
                    print("[NOTE] Image4 payload data is \(payload.compression) compressed, skipping decompression")
                }
            }

            if let extraPath = extra {
                if let extraData = payload.extra {
                    try extraData.write(to: URL(fileURLWithPath: extraPath))
                    print("Extracted extra Image4 payload data to: \(extraPath)")
                } else {
                    print("[WARN] No extra Image4 payload data found")
                }
            }

            try payload.data.write(to: URL(fileURLWithPath: output))
            print("Extracted Image4 payload data to: \(output)")
        }
    }

    struct Info: ParsableCommand {
        @Option(name: .shortAndLong, help: "Input Image4 payload file.")
        var input: String
        @Flag(name: .shortAndLong, help: "Increase verbosity.")
        var verbose: Bool = false

        func run() throws {
            let data = try Data(contentsOf: URL(fileURLWithPath: input))
            let im4p = try IM4P(data: data)

            print("Reading \(input)...")
            print("Image4 payload info:")
            print("  FourCC: \(im4p.fourcc ?? "")")
            print("  Description: \(im4p.description ?? "")")

            guard let payload = im4p.payload else { return }
            let sizeStr = verbose ? "\(payload.data.count)" : String(format: "%.2fKB", Double(payload.data.count) / 1000.0)
            print("  Data size: \(sizeStr)")

            if payload.compression != .none {
                print("  Data compression type: \(payload.compression)")
                let uncompSizeStr = verbose ? "\(payload.size)" : String(format: "%.2fKB", Double(payload.size) / 1000.0)
                print("  Data size (uncompressed): \(uncompSizeStr)")
            }

            if let extra = payload.extra {
                let extraSizeStr = verbose ? "\(extra.count)" : String(format: "%.2fKB", Double(extra.count) / 1000.0)
                print("  Extra data size: \(extraSizeStr)")
            }

            print("  Encrypted: \(payload.encrypted)")
            if payload.encrypted {
                print("  Keybags (\(payload.keybags.count)):")
                for (index, kbag) in payload.keybags.enumerated() {
                    print("    Type: \(kbag.type)")
                    print("    IV: \(kbag.iv.map { String(format: "%02x", $0) }.joined())")
                    print("    Key: \(kbag.key.map { String(format: "%02x", $0) }.joined())")
                    if index != payload.keybags.count - 1 {
                        print()
                    }
                }
            }

            if !im4p.properties.isEmpty {
                if verbose {
                    print("\n  Properties:")
                    for (index, prop) in im4p.properties.enumerated() {
                        let valueStr: String
                        if let dataVal = prop.value as? Data {
                            valueStr = dataVal.map { String(format: "%02x", $0) }.joined()
                        } else {
                            valueStr = "\(prop.value)"
                        }
                        print("    \(prop.fourcc): \(valueStr)")
                        if index != im4p.properties.count - 1 {
                            print()
                        }
                    }
                } else {
                    let propsStr = im4p.properties.map { $0.fourcc }.joined(separator: ", ")
                    print("\n  Properties (\(im4p.properties.count)): \(propsStr)")
                }
            }
        }
    }
}

struct IM4RCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "im4r",
        abstract: "Image4 restore info commands.",
        subcommands: [Create.self, Info.self]
    )

    struct Create: ParsableCommand {
        @Option(name: .shortAndLong, help: "The boot nonce used to encrypt the Image4 restore info.")
        var bootNonce: String
        @Option(name: .shortAndLong, help: "File to output Image4 restore info to.")
        var output: String

        func run() throws {
            let nonceStr = bootNonce.hasPrefix("0x") ? String(bootNonce.dropFirst(2)) : bootNonce
            let nonceData = try Data(hexString: nonceStr)
            guard nonceData.count == 8 else {
                print("Boot nonce must be 8 bytes long")
                return
            }

            let im4r = IM4R()
            im4r.boot_nonce = nonceData
            im4r.properties.append(ManifestProperty(fourcc: "BNCN", value: nonceData.reversedData()))

            try im4r.output().write(to: URL(fileURLWithPath: output))
            print("Image4 restore info outputted to: \(output)")
        }
    }

    struct Info: ParsableCommand {
        @Option(name: .shortAndLong, help: "Input Image4 restore info file.")
        var input: String
        @Flag(name: .shortAndLong, help: "Increase verbosity.")
        var verbose: Bool = false

        func run() throws {
            let data = try Data(contentsOf: URL(fileURLWithPath: input))
            let im4r = try IM4R(data: data)

            print("Reading \(input)...")
            print("Image4 restore info:")
            if let nonce = im4r.boot_nonce {
                print("  Boot nonce (hex): 0x\(nonce.map { String(format: "%02x", $0) }.joined())")
            }

            let extraProps = im4r.properties.filter { $0.fourcc != "BNCN" }
            if !extraProps.isEmpty {
                if verbose {
                    print("  Properties (\(extraProps.count)):")
                    for (index, prop) in extraProps.enumerated() {
                        let valueStr: String
                        if let dataVal = prop.value as? Data {
                            valueStr = dataVal.map { String(format: "%02x", $0) }.joined()
                        } else {
                            valueStr = "\(prop.value)"
                        }
                        print("    \(prop.fourcc): \(valueStr)")
                        if index != extraProps.count - 1 {
                            print()
                        }
                    }
                } else {
                    let propsStr = extraProps.map { $0.fourcc }.joined(separator: ", ")
                    print("  Properties (\(extraProps.count)): \(propsStr)")
                }
            }
        }
    }
}

struct IMG4Command: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "img4",
        abstract: "Image4 commands.",
        subcommands: [Create.self, Extract.self, Info.self]
    )

    struct Create: ParsableCommand {
        @Option(name: .shortAndLong, help: "Input file.")
        var input: String?
        @Option(name: .shortAndLong, help: "FourCC to set.")
        var fourcc: String?
        @Option(name: .shortAndLong, help: "Description to set.")
        var description: String?

        @Flag(help: "LZSS compress the data.")
        var lzss: Bool = false
        @Flag(help: "LZFSE compress the data.")
        var lzfse: Bool = false
        @Option(help: "Extra IM4P payload data to set (requires --lzss).")
        var extra: String?

        @Option(name: .customShort("p"), help: "Input Image4 payload file.")
        var im4p: String?
        @Option(name: .customShort("m"), help: "Input Image4 manifest file.")
        var im4m: String
        @Option(name: .customShort("r"), help: "Input Image4 restore info file.")
        var im4r: String?
        @Option(name: .customShort("g"), help: "Boot nonce to set in Image4 restore info.")
        var bootNonce: String?

        @Option(name: .shortAndLong, help: "Output file.")
        var output: String

        func run() throws {
            let img4 = IMG4()

            if let im4pPath = im4p {
                let data = try Data(contentsOf: URL(fileURLWithPath: im4pPath))
                img4.im4p = try IM4P(data: data)
            } else if let inputPath = input {
                guard let fcc = fourcc else {
                    print("No FourCC specified")
                    return
                }
                let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
                let payloadObj = IM4P()
                payloadObj.fourcc = fcc
                payloadObj.description = description
                let payloadDataObj = IM4PData(data: data)
                payloadObj.payload = payloadDataObj

                if let extraPath = extra {
                    payloadDataObj.extra = try Data(contentsOf: URL(fileURLWithPath: extraPath))
                }
                
                if lzss {
                    try payloadDataObj.compress(to: .lzss)
                } else if lzfse {
                    try payloadDataObj.compress(to: .lzfse)
                }

                img4.im4p = payloadObj
            }

            let im4mData = try Data(contentsOf: URL(fileURLWithPath: im4m))
            img4.im4m = try IM4M(data: im4mData)

            if let im4rPath = im4r {
                let data = try Data(contentsOf: URL(fileURLWithPath: im4rPath))
                img4.im4r = try IM4R(data: data)
            } else if let nonceStr = bootNonce {
                let nonce = try Data(hexString: nonceStr.hasPrefix("0x") ? String(nonceStr.dropFirst(2)) : nonceStr)
                let im4rObj = IM4R()
                im4rObj.boot_nonce = nonce
                im4rObj.properties.append(ManifestProperty(fourcc: "BNCN", value: nonce.reversedData()))
                img4.im4r = im4rObj
            }

            try img4.output().write(to: URL(fileURLWithPath: output))
            print("Image4 file outputted to: \(output)")
        }
    }

    struct Extract: ParsableCommand {
        @Option(name: .shortAndLong, help: "Input Image4 file.")
        var input: String
        @Option(help: "File to output Image4 payload data to.")
        var raw: String?
        @Option(help: "File to output extra Image4 payload data to.")
        var extra: String?
        @Option(help: "File to output Image4 payload to.")
        var im4p: String?
        @Option(help: "File to output Image4 manifest to.")
        var im4m: String?
        @Option(help: "File to output Image4 restore info to.")
        var im4r: String?

        func run() throws {
            let data = try Data(contentsOf: URL(fileURLWithPath: input))
            let img4 = try IMG4(data: data)

            if let rawPath = raw {
                if let payload = img4.im4p?.payload {
                    try payload.data.write(to: URL(fileURLWithPath: rawPath))
                    print("Extracted Image4 payload data to: \(rawPath)")
                }
            }

            if let extraPath = extra {
                if let extraData = img4.im4p?.payload?.extra {
                    try extraData.write(to: URL(fileURLWithPath: extraPath))
                    print("Extracted extra Image4 payload data to: \(extraPath)")
                } else {
                    print("No extra Image4 payload data found")
                }
            }

            if let im4pPath = im4p {
                if let im4pObj = img4.im4p {
                    try im4pObj.output().write(to: URL(fileURLWithPath: im4pPath))
                    print("Extracted Image4 payload to: \(im4pPath)")
                }
            }

            if let im4mPath = im4m {
                if let im4mObj = img4.im4m {
                    try im4mObj.output().write(to: URL(fileURLWithPath: im4mPath))
                    print("Extracted Image4 manifest to: \(im4mPath)")
                }
            }

            if let im4rPath = im4r {
                if let im4rObj = img4.im4r {
                    try im4rObj.output().write(to: URL(fileURLWithPath: im4rPath))
                    print("Extracted Image4 restore info to: \(im4rPath)")
                }
            }
        }
    }

    struct Info: ParsableCommand {
        @Option(name: .shortAndLong, help: "Input Image4 file.")
        var input: String
        @Flag(name: .shortAndLong, help: "Increase verbosity.")
        var verbose: Bool = false

        func run() throws {
            let data = try Data(contentsOf: URL(fileURLWithPath: input))
            let img4 = try IMG4(data: data)

            print("Reading \(input)...")
            print("Image4 info:")

            if let im4p = img4.im4p {
                print("  Image4 payload info:")
                print("    FourCC: \(im4p.fourcc ?? "")")
                print("    Description: \(im4p.description ?? "")")
                if let payload = im4p.payload {
                    let sizeStr = String(format: "%.2fKB", Double(payload.data.count) / 1000.0)
                    print("    Data size: \(sizeStr)")

                    if payload.compression != .none {
                        print("    Data compression type: \(payload.compression)")
                        try? payload.decompress()
                        let uncompSizeStr = String(format: "%.2fKB", Double(payload.data.count) / 1000.0)
                        print("    Data size (uncompressed): \(uncompSizeStr)")
                    }

                    if let extra = payload.extra {
                        let extraSizeStr = String(format: "%.2fKB", Double(extra.count) / 1000.0)
                        print("    Extra data size: \(extraSizeStr)")
                    }

                    print("    Encrypted: \(payload.encrypted)")
                    if payload.encrypted {
                        print("    Keybags (\(payload.keybags.count)):")
                        for (index, kbag) in payload.keybags.enumerated() {
                            print("      Type: \(kbag.type)")
                            print("      IV: \(kbag.iv.map { String(format: "%02x", $0) }.joined())")
                            print("      Key: \(kbag.key.map { String(format: "%02x", $0) }.joined())")
                            if index != payload.keybags.count - 1 {
                                print()
                            }
                        }
                    }
                }
            }

            if let im4m = img4.im4m {
                print("\n  Image4 manifest info:")
                let soc: String
                if let chipId = im4m.chip_id {
                    if 0x8720 <= chipId && chipId <= 0x8960 {
                        soc = String(format: "S5L%02x", chipId)
                    } else if 0x7002...0x8003 ~= chipId {
                        soc = String(format: "S%02x", chipId)
                    } else {
                        soc = String(format: "T%02x", chipId)
                    }

                    if verbose {
                        print("    Device Processor: \(soc) (0x\(String(chipId, radix: 16)))")
                    } else {
                        print("    Device Processor: \(soc)")
                    }
                }

                if let ecid = im4m.ecid {
                    print("    ECID (hex): 0x\(String(ecid, radix: 16))")
                }

                if let apnonce = im4m.apnonce {
                    print("    ApNonce (hex): \(apnonce.map { String(format: "%02x", $0) }.joined())")
                }

                if let sepnonce = im4m.sepnonce {
                    print("    SepNonce (hex): \(sepnonce.map { String(format: "%02x", $0) }.joined())")
                }

                if verbose {
                    for (index, prop) in im4m.properties.enumerated() {
                        if ["BNCH", "CHIP", "ECID", "snon"].contains(prop.fourcc) {
                            continue
                        }

                        if let dataVal = prop.value as? Data {
                            print("    \(prop.fourcc) (hex): \(dataVal.map { String(format: "%02x", $0) }.joined())")
                        } else {
                            print("    \(prop.fourcc): \(prop.value)")
                        }

                        if index == im4m.properties.count - 1 {
                            print()
                        }
                    }

                    print("    Manifest images (\(im4m.images.count)):")
                    for (index, image) in im4m.images.enumerated() {
                        print("      \(image.fourcc):")
                        for prop in image.properties {
                            let valueStr: String
                            if let dataVal = prop.value as? Data {
                                valueStr = dataVal.map { String(format: "%02x", $0) }.joined()
                            } else {
                                valueStr = "\(prop.value)"
                            }
                            print("        \(prop.fourcc): \(valueStr)")
                        }

                        if index != im4m.images.count - 1 {
                            print()
                        }
                    }
                } else {
                    let imagesStr = im4m.images.map { $0.fourcc }.joined(separator: ", ")
                    print("    Manifest images (\(im4m.images.count)): \(imagesStr)")
                }
            }

            if let im4r = img4.im4r {
                print("\n  Image4 restore info:")
                if let nonce = im4r.boot_nonce {
                    print("    Boot nonce (hex): 0x\(nonce.map { String(format: "%02x", $0) }.joined())")
                }

                let extraProps = im4r.properties.filter { $0.fourcc != "BNCN" }
                if !extraProps.isEmpty {
                    if verbose {
                        print("    Properties (\(extraProps.count)):")
                        for (index, prop) in extraProps.enumerated() {
                            let valueStr: String
                            if let dataVal = prop.value as? Data {
                                valueStr = dataVal.map { String(format: "%02x", $0) }.joined()
                            } else {
                                valueStr = "\(prop.value)"
                            }
                            print("      \(prop.fourcc): \(valueStr)")
                            if index != extraProps.count - 1 {
                                print()
                            }
                        }
                    } else {
                        let propsStr = extraProps.map { $0.fourcc }.joined(separator: ", ")
                        print("    Properties (\(extraProps.count)): \(propsStr)")
                    }
                }
            }
        }
    }
}
