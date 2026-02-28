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
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-asn1.git", .upToNextMajor(from: "1.0.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Image4",
            dependencies: [
                .product(name: "SwiftASN1", package: "swift-asn1")
            ]
        ),
        .testTarget(
            name: "Image4Tests",
            dependencies: ["Image4"],
            resources: [
                .copy("Resources/bin")
            ]
        ),
    ],

)
