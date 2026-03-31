// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CedarSpecSwift",
    products: [
        .library(name: "CedarSpecSwift", targets: ["CedarSpecSwift"]),
        .executable(name: "cedar", targets: ["cedar"]),
        .executable(name: "Benchmarks", targets: ["Benchmarks"]),
    ],
    targets: [
        .target(name: "CedarSpecSwift"),
        .testTarget(name: "CedarSpecSwiftTests", dependencies: ["CedarSpecSwift"]),
        .executableTarget(name: "Example", dependencies: ["CedarSpecSwift"], path: "Examples"),
        .executableTarget(name: "cedar", dependencies: ["CedarSpecSwift"], path: "Sources/CedarCLI"),
        .executableTarget(name: "Benchmarks", dependencies: ["CedarSpecSwift"]),
    ]
)
