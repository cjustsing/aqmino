// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AqminoCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "AqminoCore", targets: ["AqminoCore"])],
    targets: [
        .target(name: "AqminoCore"),
        .testTarget(name: "AqminoCoreTests", dependencies: ["AqminoCore"])
    ]
)
