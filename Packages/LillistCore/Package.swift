// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LillistCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(name: "LillistCore", targets: ["LillistCore"]),
        .executable(name: "lillist", targets: ["lillist-cli"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.0")
    ],
    targets: [
        .plugin(
            name: "CompileCoreDataModel",
            capability: .buildTool()
        ),
        .target(
            name: "LillistCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            resources: [
                .process("Model/LillistModel.xcdatamodeld")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .treatAllWarnings(as: .error)
            ],
            plugins: ["CompileCoreDataModel"]
        ),
        .testTarget(
            name: "LillistCoreTests",
            dependencies: ["LillistCore"],
            resources: [
                .copy("CrashReporting/Fixtures"),
                .copy("LinkPreview/HTMLFixtures")
            ],
            swiftSettings: [
                .treatAllWarnings(as: .error)
            ]
        ),
        .executableTarget(
            name: "lillist-cli",
            dependencies: [
                "LillistCore",
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
                "LillistCore",
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
