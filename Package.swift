// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Barabri",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "BarabriCore", targets: ["BarabriCore"]),
        .executable(name: "BarabriApp", targets: ["BarabriApp"])
    ],
    targets: [
        .target(name: "BarabriCore"),
        .executableTarget(name: "BarabriApp", dependencies: ["BarabriCore"]),
        .testTarget(name: "BarabriCoreTests", dependencies: ["BarabriCore"])
    ]
)
