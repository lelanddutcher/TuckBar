// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TuckBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TuckBar",
            path: "Sources/TuckBar"
        )
    ]
)
