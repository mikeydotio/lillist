// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LillistUI",
    defaultLocalization: "en",
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
                .enableExperimentalFeature("StrictConcurrency"),
                .treatAllWarnings(as: .error)
            ]
        ),
        .testTarget(
            name: "LillistUITests",
            dependencies: [
                "LillistUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            exclude: [
                "Recurrence/__Snapshots__",
                "DragReorder/__Snapshots__",
                "Tour/__Snapshots__",
                "Snapshots/__Snapshots__",
                "CrashReporting/__Snapshots__",
                "iOS/__Snapshots__"
            ],
            swiftSettings: [
                .treatAllWarnings(as: .error)
            ]
        )
    ]
)
