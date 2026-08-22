// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "mizu-extract",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "mizu-extract", targets: ["MizuExtract"])
    ],
    targets: [
        .executableTarget(name: "MizuExtract"),
        .testTarget(name: "MizuExtractTests", dependencies: ["MizuExtract"]),
    ]
)
