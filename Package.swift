// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhomemoD30",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [
        .library(name: "PhomemoD30", targets: ["PhomemoD30"]),
        .executable(name: "d30", targets: ["d30"]),
    ],
    targets: [
        .target(name: "PhomemoD30"),
        .executableTarget(name: "d30", dependencies: ["PhomemoD30"]),
        .testTarget(name: "PhomemoD30Tests", dependencies: ["PhomemoD30"]),
    ]
)
