// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LillistCLI",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .executable(name: "lillist", targets: ["lillist-cli"])
    ],
    dependencies: [
        .package(path: "../LillistCore"),
        .package(path: "../LillistSearchIntelligence"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "lillist-cli",
            dependencies: [
                .product(name: "LillistCore", package: "LillistCore"),
                .product(name: "LillistSearchIntelligence", package: "LillistSearchIntelligence"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .treatAllWarnings(as: .error)
            ]
        ),
        .testTarget(
            name: "lillistCLITests",
            dependencies: [
                "lillist-cli",
                .product(name: "LillistCore", package: "LillistCore"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            resources: [
                .copy("Fixtures/snapshots")
            ],
            swiftSettings: [
                .treatAllWarnings(as: .error)
            ]
        )
    ]
)
