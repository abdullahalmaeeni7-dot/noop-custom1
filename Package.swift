// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WHOOPCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "WHOOPCore", targets: ["WHOOPCore"])],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .target(name: "WHOOPCore", dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")], path: "Core", resources: [.process("Resources")]),
        .testTarget(name: "WHOOPCoreTests", dependencies: ["WHOOPCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")], path: "Tests/WHOOPCoreTests", resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
