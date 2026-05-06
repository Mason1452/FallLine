// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoVision",
    platforms: [
        .macOS(.v14)
        // macOS 14 (Sonoma) 是必须的，因为：
        // - VNDetectHumanBodyPoseRequest 在 macOS 14 才稳定支持
        // - async/await AVAsset.load() 需要 macOS 10.15+，但完整支持在 macOS 14
        // - Xcode 16 + macOS 15 SDK 可向前编译出 macOS 14 target
    ],
    dependencies: [],
    targets: [
        // MARK: - 核心库（同时供给 CLI 和 iOS App 使用）
        .target(
            name: "VideoVisionCore",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreImage"),
            ]
        ),

        // MARK: - CLI 可执行文件（macOS）
        .executableTarget(
            name: "VideoVisionCLI",
            dependencies: ["VideoVisionCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreImage"),
            ]
        ),

        // MARK: - 测试
        .testTarget(
            name: "VideoVisionCoreTests",
            dependencies: ["VideoVisionCore"]
        ),
    ]
)
