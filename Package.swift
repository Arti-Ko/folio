// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Folio",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "FolioApp", targets: ["FolioApp"]),
        .executable(name: "folio", targets: ["FolioCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "FolioCore",
            dependencies: ["Yams"]
        ),
        .executableTarget(
            name: "FolioCLI",
            dependencies: [
                "FolioCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "FolioApp",
            dependencies: ["FolioCore"]
        ),
        .testTarget(
            name: "FolioCoreTests",
            dependencies: ["FolioCore"]
        ),
    ]
)
