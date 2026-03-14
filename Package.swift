// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeMosaic",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeMosaic",
            path: "Sources/ClaudeMosaic"
        )
    ]
)
