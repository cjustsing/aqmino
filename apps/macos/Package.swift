// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AqminoMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Aqmino", targets: ["Aqmino"])],
    dependencies: [.package(path: "../../packages/AqminoCore")],
    targets: [
        .executableTarget(name: "Aqmino", dependencies: ["AqminoCore"], path: "Sources"),
        .testTarget(name: "AqminoMacTests", dependencies: ["Aqmino", "AqminoCore"], path: "Tests/Unit")
    ]
)
