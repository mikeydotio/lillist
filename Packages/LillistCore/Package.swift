// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LillistCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(name: "LillistCore", targets: ["LillistCore"])
    ],
    targets: [
        .target(
            name: "LillistCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "LillistCoreTests",
            dependencies: ["LillistCore"]
        )
    ]
)
