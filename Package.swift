// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Image4",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Image4",
            targets: ["Image4"]
        ),
        .executable(
            name: "image4",
            targets: ["image4cli"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-asn1.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/p1atdev/LZSS.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Image4",
            dependencies: [
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "LZSS", package: "LZSS"),
            ]
        ),
        .executableTarget(
            name: "image4cli",
            dependencies: [
                "Image4",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "Image4Tests",
            dependencies: [
                "Image4",
                .product(name: "AsyncHTTPClient", package: "async-http-client")
            ],
            resources: [
                .copy("Resources/bin")
            ]
        ),
    ],

)
