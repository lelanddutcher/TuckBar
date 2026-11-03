// swift-tools-version: 6.0
// Experiments for issue #1 (windows in the tucked strip), run on GitHub-hosted macOS runners.
// Not part of the app. Swift 5 language mode: this is throwaway probe code.
import PackageDescription

let package = Package(
    name: "Lab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Lab", path: "Sources/Lab")
    ],
    swiftLanguageModes: [.v5]
)
