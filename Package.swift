// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuniControle",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MuniControleCore", targets: ["MuniControleCore"]),
        .library(name: "MuniControleInterop", targets: ["MuniControleInterop"]),
        .executable(name: "muni-controle-cli", targets: ["MuniControleCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.7.0"),
        .package(url: "https://github.com/Macthieu/OrchivisteKit.git", exact: "0.2.0")
    ],
    targets: [
        .target(name: "MuniControleCore"),
        .target(
            name: "MuniControleInterop",
            dependencies: [
                "MuniControleCore",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit")
            ]
        ),
        .executableTarget(
            name: "MuniControleCLI",
            dependencies: [
                "MuniControleInterop",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit"),
                .product(name: "OrchivisteKitInterop", package: "OrchivisteKit")
            ]
        ),
        .testTarget(
            name: "MuniControleTests",
            dependencies: [
                "MuniControleCore",
                "MuniControleInterop",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit"),
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
