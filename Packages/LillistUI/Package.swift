// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LillistUI",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(name: "LillistUI", targets: ["LillistUI"])
    ],
    dependencies: [
        .package(path: "../LillistCore"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "LillistUI",
            dependencies: [
                .product(name: "LillistCore", package: "LillistCore")
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "LillistUITests",
            dependencies: [
                "LillistUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ]
        )
    ]
)
