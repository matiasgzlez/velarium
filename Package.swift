// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Velarium",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Velarium",
            resources: [.copy("Web")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
