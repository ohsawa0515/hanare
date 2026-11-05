// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hanare",
    defaultLocalization: "en",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Hanare", targets: ["Hanare"]),
    ],
    targets: [
        .target(name: "HanareCore"),
        .executableTarget(
            name: "Hanare",
            dependencies: ["HanareCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "HanareCoreTests", dependencies: ["HanareCore"]),
    ]
)
