// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShrimpInstaller",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ShrimpInstaller", path: "Sources/ShrimpInstaller")
    ]
)
