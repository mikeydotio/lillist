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
        .plugin(
            name: "CompileCoreDataModel",
            capability: .buildTool()
        ),
        .target(
            name: "LillistCore",
            resources: [
                .process("Model/LillistModel.xcdatamodeld")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ],
            plugins: ["CompileCoreDataModel"]
        ),
        .testTarget(
            name: "LillistCoreTests",
            dependencies: ["LillistCore"]
        )
    ]
)
