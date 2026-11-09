// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Haftnotiz",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Haftnotiz", path: "Sources/Haftnotiz"),
        .testTarget(name: "HaftnotizTests", dependencies: ["Haftnotiz"], path: "Tests/HaftnotizTests"),
    ]
)
