// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TinyRazer",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "TinyRazer", targets: ["TinyRazer"]),
        .library(name: "RazerKit", targets: ["RazerKit"]),
    ],
    targets: [
        .target(
            name: "RazerKit",
            path: "Sources/RazerKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "TinyRazer",
            dependencies: ["RazerKit"],
            path: "Sources/TinyRazer",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "RazerKitTests",
            dependencies: ["RazerKit"],
            path: "Tests/RazerKitTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
