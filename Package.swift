// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XiaoLeiWallpaper",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "XiaoLeiWallpaper", targets: ["XiaoLeiWallpaper"])
    ],
    targets: [
        .executableTarget(
            name: "XiaoLeiWallpaper",
            path: "Sources"
        )
    ]
)
