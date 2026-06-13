// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TfLKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TfLKit", targets: ["TfLKit"])
    ],
    targets: [
        .target(name: "TfLKit"),
        .testTarget(
            name: "TfLKitTests",
            dependencies: ["TfLKit"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
