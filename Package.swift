// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FallLine",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
        // macOS 14 (Sonoma) 是必须的，因为：
        // - VNDetectHumanBodyPoseRequest 在 macOS 14 才稳定支持
        // - async/await AVAsset.load() 需要 macOS 10.15+，但完整支持在 macOS 14
        // - Xcode 16 + macOS 15 SDK 可向前编译出 macOS 14 target
        //
        // iOS 17 是必须的，因为：
        // - VNDetectHumanBodyPose3DRequest 只在 iOS 17+ 提供
        // - FallLineCore 依赖 3D pose 融合作为默认路径（PoseMetrics3DAdapter）
        // - SkiAnaylze iOS App 走 SPM 依赖此库时，Xcode 会按此声明对齐 deployment target
    ],
    dependencies: [],
    targets: [
        // MARK: - 核心库（同时供给 CLI 和 iOS App 使用）
        .target(
            name: "FallLineCore",
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
            name: "FallLineCLI",
            dependencies: ["FallLineCore"],
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
            name: "FallLineCoreTests",
            dependencies: ["FallLineCore"]
        ),
    ]
)
