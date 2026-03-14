// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuniControle",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MuniControleCore", targets: ["MuniControleCore"]),
        .executable(name: "muni-controle-cli", targets: ["MuniControleCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.7.0")
    ],
    targets: [
        .target(name: "MuniControleCore"),
        .executableTarget(name: "MuniControleCLI", dependencies: ["MuniControleCore"]),
        .testTarget(
            name: "MuniControleTests",
            dependencies: [
                "MuniControleCore",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
