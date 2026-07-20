// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LillistSearchIntelligence",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(name: "LillistSearchIntelligence", targets: ["LillistSearchIntelligence"])
    ],
    dependencies: [
        .package(path: "../LillistCore")
    ],
    targets: [
        .target(
            name: "LillistSearchIntelligence",
            dependencies: [
                .product(name: "LillistCore", package: "LillistCore")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .treatAllWarnings(as: .error)
            ]
        ),
        .testTarget(
            name: "LillistSearchIntelligenceTests",
            dependencies: ["LillistSearchIntelligence"],
            swiftSettings: [
                .treatAllWarnings(as: .error)
            ]
        )
    ]
)
