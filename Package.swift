// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MenuTimer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MenuTimer", path: "Sources/MenuTimer")
    ]
)
