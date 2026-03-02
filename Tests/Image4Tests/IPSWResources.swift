import Foundation

#if canImport(Compression)
    import Compression
#endif

enum IPSWResource {
    static let LZSS_DEC_IPSW =
        "https://updates.cdn-apple.com/2021FallFCS/fullrestores/002-03194/8EC63AF9-19BE-4829-B389-27AECB41DD6A/iPhone_5.5_15.0_19A346_Restore.ipsw"
    static let LZSS_ENC_IPSW =
        "http://appldnld.apple.com/iOS9.3.5/031-73130-20160825-6A2C2FD4-6711-11E6-B3F4-173834D2D062/iPhone8,2_9.3.5_13G36_Restore.ipsw"
    static let LZFSE_IPSW =
        "https://updates.cdn-apple.com/2021FallFCS/fullrestores/002-02910/AF984499-D03A-43E7-9472-6D16BA756E5E/iPhone10,3,iPhone10,6_15.0_19A346_Restore.ipsw"
    static let PAYP_IPSW =
        "https://updates.cdn-apple.com/2022FallFCS/fullrestores/032-11449/3995EAD9-8F0E-491E-BEC8-C97B6B1845C7/iPhone15,3_16.1.2_20B110_Restore.ipsw"

    static func getIPSWFile(url: String, filename: String) async throws -> Data {
        let cacheDir = URL(fileURLWithPath: ".build/test-cache")
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            try? FileManager.default.createDirectory(
                at: cacheDir, withIntermediateDirectories: true)
        }

        // Create a stable cache filename
        let safeUrl = url.replacingOccurrences(
            of: "[:/\\.]", with: "_", options: .regularExpression)
        let cacheFile = cacheDir.appendingPathComponent(
            "\(safeUrl)_\(filename.replacingOccurrences(of: "/", with: "_"))")

        if FileManager.default.fileExists(atPath: cacheFile.path) {
            return try Data(contentsOf: cacheFile)
        }

        let remoteZip = try await RemoteZip(url: url)
        let data = try await remoteZip.read(filename: filename)

        try? data.write(to: cacheFile)
        return data
    }

    static var decLZSSIM4P: Data {
        get async throws {
            try await getIPSWFile(url: LZSS_DEC_IPSW, filename: "kernelcache.release.n66")
        }
    }

    static var encLZSSIM4P: Data {
        get async throws {
            try await getIPSWFile(url: LZSS_ENC_IPSW, filename: "kernelcache.release.n66")
        }
    }

    static var decLZFSEIM4P: Data {
        get async throws {
            try await getIPSWFile(url: LZFSE_IPSW, filename: "kernelcache.release.iphone10b")
        }
    }

    static var encLZFSEIM4P: Data {
        get async throws {
            try await getIPSWFile(url: LZFSE_IPSW, filename: "Firmware/dfu/iBSS.d22.RELEASE.im4p")
        }
    }

    static var paypIM4P: Data {
        get async throws {
            try await getIPSWFile(url: PAYP_IPSW, filename: "Firmware/dfu/iBSS.d74.RELEASE.im4p")
        }
    }
}

struct RemoteZip {
    let url: String
    let fileSize: Int64

    struct CentralDirectoryEntry {
        let fileName: String
        let relativeOffset: Int64
        let compressedSize: Int64
        let uncompressedSize: Int64
        let compressionMethod: UInt16
    }

    private var entries: [String: CentralDirectoryEntry] = [:]

    init(url: String) async throws {
        self.url = url

        // 1. Get file size
        var headRequest = URLRequest(url: URL(string: url)!)
        headRequest.httpMethod = "HEAD"
        let (_, headResponse) = try await URLSession.shared.data(for: headRequest)
        guard let httpHeadResponse = headResponse as? HTTPURLResponse,
            let lengthStr = httpHeadResponse.value(forHTTPHeaderField: "Content-Length"),
            let length = Int64(lengthStr)
        else {
            throw RemoteZipError.missingContentLength
        }
        self.fileSize = length

        // 2. Find EOCD
        let endSize = min(fileSize, 65536 + 22)
        let endData = try await fetchRange(start: fileSize - endSize, end: fileSize - 1)

        guard let eocdOffset = findEOCD(in: endData) else {
            throw RemoteZipError.eocdNotFound
        }

        var cdSize = Int64(endData.readUInt32(at: eocdOffset + 12))
        var cdOffset = Int64(endData.readUInt32(at: eocdOffset + 16))

        // 2.5 Handle ZIP64
        if cdOffset == 0xFFFF_FFFF || cdSize == 0xFFFF_FFFF {
            let locatorOffset = eocdOffset - 20
            if locatorOffset >= 0 && endData[locatorOffset] == 0x50
                && endData[locatorOffset + 1] == 0x4b && endData[locatorOffset + 2] == 0x06
                && endData[locatorOffset + 3] == 0x07
            {

                let zip64EOCDOffset = Int64(endData.readUInt64(at: locatorOffset + 8))

                let zip64EOCDData = try await fetchRange(
                    start: zip64EOCDOffset, end: zip64EOCDOffset + 56 - 1)
                if zip64EOCDData[0] == 0x50 && zip64EOCDData[1] == 0x4b && zip64EOCDData[2] == 0x06
                    && zip64EOCDData[3] == 0x06
                {
                    cdSize = Int64(zip64EOCDData.readUInt64(at: 40))
                    cdOffset = Int64(zip64EOCDData.readUInt64(at: 48))
                }
            }
        }

        // 3. Read Central Directory
        let cdData = try await fetchRange(start: cdOffset, end: cdOffset + cdSize - 1)
        self.entries = try parseCentralDirectory(data: cdData)
    }

    func read(filename: String) async throws -> Data {
        guard let entry = entries[filename] else {
            throw RemoteZipError.fileNotFound(filename)
        }

        let fetchStart = entry.relativeOffset
        let fetchEnd = fetchStart + 30 + entry.compressedSize + 1024

        let dataWithHeader = try await fetchRange(
            start: fetchStart, end: min(fetchEnd, fileSize - 1))

        let fileNameLength = Int(dataWithHeader.readUInt16(at: 26))
        let extraFieldLength = Int(dataWithHeader.readUInt16(at: 28))
        let dataOffset = 30 + fileNameLength + extraFieldLength

        let compressedData = dataWithHeader.subdata(
            in: dataOffset..<(dataOffset + Int(entry.compressedSize)))

        if entry.compressionMethod == 0 {
            return compressedData
        } else if entry.compressionMethod == 8 {
            return try decompressDeflate(
                compressedData, uncompressedSize: Int(entry.uncompressedSize))
        } else {
            throw RemoteZipError.unsupportedCompression(entry.compressionMethod)
        }
    }

    private func fetchRange(start: Int64, end: Int64) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 206 || httpResponse.statusCode == 200
        else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw RemoteZipError.httpError(UInt(code))
        }
        return data
    }

    private func findEOCD(in data: Data) -> Int? {
        if data.count < 22 { return nil }
        for i in (0...data.count - 22).reversed() {
            if data[i] == 0x50 && data[i + 1] == 0x4b && data[i + 2] == 0x05 && data[i + 3] == 0x06
            {
                return i
            }
        }
        return nil
    }

    private func parseCentralDirectory(data: Data) throws -> [String: CentralDirectoryEntry] {
        var entries: [String: CentralDirectoryEntry] = [:]
        var offset = 0
        while offset < data.count {
            guard offset + 46 <= data.count else { break }
            guard
                data[offset] == 0x50 && data[offset + 1] == 0x4b && data[offset + 2] == 0x01
                    && data[offset + 3] == 0x02
            else {
                break
            }

            let compressionMethod = data.readUInt16(at: offset + 10)
            var compressedSize = Int64(data.readUInt32(at: offset + 20))
            var uncompressedSize = Int64(data.readUInt32(at: offset + 24))
            let fileNameLength = Int(data.readUInt16(at: offset + 28))
            let extraFieldLength = Int(data.readUInt16(at: offset + 30))
            let fileCommentLength = Int(data.readUInt16(at: offset + 32))
            var relativeOffset = Int64(data.readUInt32(at: offset + 42))

            guard offset + 46 + fileNameLength <= data.count else { break }
            let fileNameData = data.subdata(in: (offset + 46)..<(offset + 46 + fileNameLength))
            let fileName = String(data: fileNameData, encoding: .utf8) ?? ""

            // Handle ZIP64 extra field
            if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF
                || relativeOffset == 0xFFFF_FFFF
            {
                var extraOffset = offset + 46 + fileNameLength
                let extraEnd = extraOffset + extraFieldLength
                while extraOffset + 4 <= extraEnd {
                    let headerId = data.readUInt16(at: extraOffset)
                    let dataSize = Int(data.readUInt16(at: extraOffset + 2))
                    if headerId == 0x0001 {  // ZIP64 extra field
                        var innerOffset = extraOffset + 4
                        if uncompressedSize == 0xFFFF_FFFF && innerOffset + 8 <= extraEnd {
                            uncompressedSize = Int64(data.readUInt64(at: innerOffset))
                            innerOffset += 8
                        }
                        if compressedSize == 0xFFFF_FFFF && innerOffset + 8 <= extraEnd {
                            compressedSize = Int64(data.readUInt64(at: innerOffset))
                            innerOffset += 8
                        }
                        if relativeOffset == 0xFFFF_FFFF && innerOffset + 8 <= extraEnd {
                            relativeOffset = Int64(data.readUInt64(at: innerOffset))
                            innerOffset += 8
                        }
                        break
                    }
                    extraOffset += 4 + dataSize
                }
            }

            entries[fileName] = CentralDirectoryEntry(
                fileName: fileName,
                relativeOffset: relativeOffset,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                compressionMethod: compressionMethod
            )

            offset += 46 + fileNameLength + extraFieldLength + fileCommentLength
        }
        return entries
    }

    private func decompressDeflate(_ data: Data, uncompressedSize: Int) throws -> Data {
        #if canImport(Compression)
            let sourceBuffer = Array(data)
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
            defer { destinationBuffer.deallocate() }

            let decompressedSize = sourceBuffer.withUnsafeBufferPointer { sourcePtr in
                compression_decode_buffer(
                    destinationBuffer, uncompressedSize,
                    sourcePtr.baseAddress!, data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }

            if decompressedSize == 0 {
                throw RemoteZipError.decompressionFailed
            }

            return Data(bytes: destinationBuffer, count: decompressedSize)
        #else
            throw RemoteZipError.decompressionUnsupported
        #endif
    }
}

enum RemoteZipError: Error {
    case missingContentLength
    case eocdNotFound
    case fileNotFound(String)
    case httpError(UInt)
    case unsupportedCompression(UInt16)
    case decompressionFailed
    case decompressionUnsupported
}

extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        return UInt32(self[offset]) | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16) | (UInt32(self[offset + 3]) << 24)
    }

    func readUInt64(at offset: Int) -> UInt64 {
        return UInt64(readUInt32(at: offset)) | (UInt64(readUInt32(at: offset + 4)) << 32)
    }
}
