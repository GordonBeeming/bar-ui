// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BarUI",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .target(
            name: "BarUICore",
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "BarUI",
            dependencies: ["BarUICore"]
        ),
        .executableTarget(
            name: "BarUIHelper",
            dependencies: ["BarUICore"]
        ),
        .testTarget(
            name: "BarUICoreTests",
            dependencies: ["BarUICore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
