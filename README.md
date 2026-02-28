# Image4 (Swift)

A Swift library and CLI tool for parsing and creating Apple's [Image4 format](https://www.theiphonewiki.com/wiki/IMG4_File_Format).

This project is a Swift reimplementation of [PyIMG4](https://github.com/m1stadev/PyIMG4).

## Features

- **Parse & Create**: Supports IMG4 containers, IM4P payloads, IM4M manifests, and IM4R restore info.
- **Compression**: Native support for **LZSS** and **LZFSE** (using Apple's `Compression` framework).
- **Security**: Handles encrypted payloads and keybag parsing.
- **CLI**: A powerful command-line interface for managing Image4 files.
- **Modern Swift**: Built with Swift 6.2 and `Apple/Swift-ASN1`.

## Requirements

- Swift 6.2 or later
- macOS (requires native `Compression` and `CommonCrypto` frameworks)

## Installation

### Swift Package Manager

Add the following to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/p1atdev/Image4.git", from: "1.0.0"),
```

### CLI Tool

```bash
git clone https://github.com/p1atdev/Image4.git
cd Image4
swift build -c release
cp .build/release/image4 /usr/local/bin/
```

## Usage

### Command Line Interface

```bash
USAGE: image4 <subcommand>

OPTIONS:
  -h, --help      Show help information.

SUBCOMMANDS:
  im4m            Image4 manifest commands.
  im4p            Image4 payload commands.
  im4r            Image4 restore info commands.
  img4            Image4 commands.
```

#### Example: Inspect an Image4 file
```bash
image4 img4 info -i kernelcache.release.iphone10b
```

### Library API

#### Parsing an IM4P Payload
```swift
import Image4
import Foundation

let data = try Data(contentsOf: URL(fileURLWithPath: "kernelcache.im4p"))
let im4p = try IM4P(data: data)

print("FourCC: \(im4p.fourcc ?? "unknown")")

if let payload = im4p.payload {
    if payload.compression == .lzfse {
        try payload.decompress()
    }
    print("Decoded payload size: \(payload.data.count) bytes")
}
```

#### Creating an Image4 Container
```swift
import Image4

let im4p = IM4P()
im4p.fourcc = "krnl"
im4p.payload = IM4PData(data: rawData)
try im4p.payload?.compress(to: .lzfse)

let im4m = try IM4M(data: shshData)

let img4 = IMG4()
img4.im4p = im4p
img4.im4m = im4m

let finalData = try img4.output()
```

## Credits

- [PyIMG4](https://github.com/m1stadev/PyIMG4) by [@m1stadev](https://github.com/m1stadev) for the original implementation and reference.
- [LZSS](https://github.com/p1atdev/LZSS) for the Swift LZSS support.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
