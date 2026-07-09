// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeRemote",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "ClaudeRemote",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/ClaudeRemote",
            exclude: ["Info.plist"]
            // ATS istisnası artık .app bundle'ın Contents/Info.plist'inden geliyor
            // (gömülü sectcreate plist çakışma yaratıyordu, kaldırıldı).
        )
    ]
)
