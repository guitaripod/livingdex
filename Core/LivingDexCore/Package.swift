// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LivingDexCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LivingDexCore", targets: ["LivingDexCore"]),
    ],
    targets: [
        .target(
            name: "LivingDexCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "LivingDexCoreTests",
            dependencies: ["LivingDexCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
    ]
)
