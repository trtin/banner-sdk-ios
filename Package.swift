// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BannerSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "BannerSDK", targets: ["BannerSDK"]),
        .executable(name: "BannerDemo", targets: ["BannerDemo"]),
    ],
    targets: [
        .target(name: "BannerSDK"),
        .executableTarget(name: "BannerDemo", dependencies: ["BannerSDK"]),
        .testTarget(name: "BannerSDKTests", dependencies: ["BannerSDK"]),
    ]
)
