// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clippy",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Clippy", targets: ["Clippy"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.16.0")
    ],
    targets: [
        .executableTarget(
            name: "Clippy",
            dependencies: ["KeyboardShortcuts"],
            path: "Sources"
        )
    ]
)
