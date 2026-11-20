// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BodySeekKit",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "BodySeekCore", targets: ["BodySeekCore"]),
        .library(name: "BodySeekDesign", targets: ["BodySeekDesign"]),
        .library(name: "BodySeekStore", targets: ["BodySeekStore"]),
        .library(name: "BodySeekHealth", targets: ["BodySeekHealth"]),
        .library(name: "BodySeekAgent", targets: ["BodySeekAgent"]),
        .library(name: "BodySeekFeatures", targets: ["BodySeekFeatures"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "1.17.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies",
            from: "1.17.0"
        ),
        .package(
            url: "https://github.com/StanfordSpezi/SpeziHealthKit",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/StanfordSpezi/Spezi",
            from: "1.8.0"
        ),
        .package(
            url: "https://github.com/StanfordSpezi/SpeziFoundation.git",
            from: "2.7.0"
        ),
        .package(
            url: "https://github.com/melihcolpan/MuscleMap.git",
            from: "1.9.0"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            from: "7.0.0"
        ),
        .package(
            url: "https://github.com/gonzalezreal/textual.git",
            exact: "0.5.0"
        ),
        .package(
            url: "https://github.com/DanielJamesTronca/SleepChartKit.git",
            exact: "1.2.0"
        ),
    ],
    targets: [
        .target(
            name: "BodySeekCore",
            dependencies: [],
            resources: [
                .copy("Resources/personal_forecaster_v1_spec.json"),
                .copy("Resources/BodySeekPersonalForecasterV1.mlpackage"),
            ]
        ),
        .target(
            name: "BodySeekDesign",
            dependencies: [
                "BodySeekCore",
                .product(name: "SleepChartKit", package: "SleepChartKit"),
            ],
            resources: [.copy("Resources/SleepChartKit-LICENSE.txt")]
        ),
        .target(
            name: "BodySeekStore",
            dependencies: [
                "BodySeekCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "BodySeekHealth",
            dependencies: [
                "BodySeekCore",
                "BodySeekStore",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "SpeziFoundation", package: "SpeziFoundation"),
                .product(name: "SpeziHealthKit", package: "SpeziHealthKit"),
            ]
        ),
        .target(
            name: "BodySeekAgent",
            dependencies: [
                "BodySeekCore",
                "BodySeekStore",
                "BodySeekHealth",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "BodySeekFeatures",
            dependencies: [
                "BodySeekCore",
                "BodySeekDesign",
                "BodySeekStore",
                "BodySeekHealth",
                "BodySeekAgent",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "MuscleMap", package: "MuscleMap"),
                .product(name: "Textual", package: "textual"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "SpeziHealthKit", package: "SpeziHealthKit"),
            ]
        ),
        .testTarget(
            name: "BodySeekKitTests",
            dependencies: [
                "BodySeekCore",
                "BodySeekDesign",
                "BodySeekStore",
                "BodySeekHealth",
                "BodySeekAgent",
                "BodySeekFeatures",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "BodySeekAgentEvals",
            dependencies: [
                "BodySeekCore",
                "BodySeekStore",
                "BodySeekHealth",
                "BodySeekAgent",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
    ]
)
