// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "announce-helper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "announce-helper",
            targets: ["announce-helper"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "announce-helper",
            dependencies: []
        )
    ]
)

