// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyAsset",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MyAsset",
            path: "Sources/MyAsset",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/Logos")
            ]
        )
    ]
)
