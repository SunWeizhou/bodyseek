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
            url: "https://github.com/StanfordSpezi/SpeziLLM.git",
            from: "0.9.0"
        ),
        .package(
            url: "https://github.com/apple/swift-openapi-generator.git",
            "1.8.0"..<"1.13.0"
        ),
        .package(
            url: "https://github.com/apple/swift-openapi-runtime.git",
            from: "1.8.0"
        ),
        .package(
            url: "https://github.com/apple/swift-http-types.git",
            from: "1.8.0"
        ),
        .package(
            url: "https://github.com/melihcolpan/MuscleMap.git",
            from: "1.9.0"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            from: "7.0.0"
        ),
    ],
    targets: [
        .target(
            name: "BodySeekCore",
            dependencies: []
        ),
        .target(
            name: "BodySeekDesign",
            dependencies: [
                "BodySeekCore",
            ]
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
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "SpeziFoundation", package: "SpeziFoundation"),
                .product(name: "SpeziHealthKit", package: "SpeziHealthKit"),
                .product(name: "SpeziLLM", package: "SpeziLLM"),
                .product(name: "SpeziLLMOpenAI", package: "SpeziLLM"),
            ]
        ),
        .target(
            name: "BodySeekFeatures",
            dependencies: [
                "BodySeekCore",
                "BodySeekDesign",
                "BodySeekStore",
                "BodySeekHealth",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "MuscleMap", package: "MuscleMap"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "SpeziHealthKit", package: "SpeziHealthKit"),
                .product(name: "SpeziLLM", package: "SpeziLLM"),
                .product(name: "SpeziLLMOpenAI", package: "SpeziLLM"),
            ]
        ),
        .testTarget(
            name: "BodySeekKitTests",
            dependencies: [
                "BodySeekCore",
                "BodySeekDesign",
                "BodySeekStore",
                "BodySeekHealth",
                "BodySeekFeatures",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
    ]
)
