// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TinyToriiSupport",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "TinyToriiSupport", targets: ["TinyToriiSupport"]),
        .executable(name: "torii-cli", targets: ["torii-cli"]),
    ],
    dependencies: [
        .package(path: "../../../../MetalSprockets/SceneSprockets"),
        .package(url: "https://github.com/schwa/GeometryLite3D", .upToNextMinor(from: "0.2.7")),
        .package(url: "https://github.com/schwa/MetalSprockets", .upToNextMinor(from: "0.2.9")),
        .package(url: "https://github.com/schwa/SwiftMesh", .upToNextMinor(from: "0.0.11")),
        .package(url: "https://github.com/schwa/MetalSprocketsParticles", .upToNextMinor(from: "0.0.2")),
    ],
    targets: [
        .target(
            name: "TinyToriiSupport",
            dependencies: [
                .product(name: "SceneSprockets", package: "SceneSprockets"),
                .product(name: "SceneSprocketsBlinnPhong", package: "SceneSprockets"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "MetalSprocketsSupport", package: "MetalSprockets"),
                .product(name: "MetalSprocketsParticles", package: "MetalSprocketsParticles"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ],
            // Palette pictures, made with `torii-cli thumbnails`.
            resources: [.copy("Thumbnails")]
        ),
        .executableTarget(
            name: "torii-cli",
            dependencies: ["TinyToriiSupport"]
        ),
        .testTarget(
            name: "TinyToriiSupportTests",
            dependencies: ["TinyToriiSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
