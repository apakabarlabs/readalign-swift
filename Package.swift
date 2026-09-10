// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadAlign",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "ReadAlign",
            targets: ["ReadAlign"]),
    ],
    dependencies: [
        .package(url: "https://github.com/botforge-pro/swift-embed", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "ReadAlign",
            dependencies: [.product(name: "SwiftEmbed", package: "swift-embed")],
            resources: [.process("Resources")]),
        .testTarget(
            name: "ReadAlignTests",
            dependencies: [
                "ReadAlign",
                .product(name: "SwiftEmbed", package: "swift-embed")
            ],
            resources: [.process("Resources")]),
    ]
)
