// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveDesktop",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LiveDesktop", targets: ["LiveDesktop"])
    ],
    targets: [
        .executableTarget(
            name: "LiveDesktop",
            path: "Sources"
        )
    ]
)
