// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JSON2Proto",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.38.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", from: "5.0.2")
    ],
    targets: [
        .executableTarget(
            name: "JSON2Proto",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "SwiftyJSON"
            ],
            path: ".",
            exclude: ["JSON2Proto.xcodeproj", "Tests", "README.md", "Scripts"],
            sources: ["JSON2Proto", "SekaiProtoDef"],
            plugins: [.plugin(name: "SwiftProtobufPlugin", package: "swift-protobuf")]
        ),
        .testTarget(name: "JSON2ProtoTests", dependencies: ["JSON2Proto"])
    ],
    swiftLanguageModes: [.v5]
)
