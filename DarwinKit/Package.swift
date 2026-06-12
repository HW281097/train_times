// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DarwinKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DarwinKit", targets: ["DarwinKit"])
    ],
    targets: [
        .target(name: "DarwinKit"),
        .testTarget(
            name: "DarwinKitTests",
            dependencies: ["DarwinKit"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
