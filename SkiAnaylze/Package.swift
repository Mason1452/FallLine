// swift-tools-version: 5.9
import PackageDescription

/// SkiAnaylze iOS/macOS App
///
/// 构建方式：
///   1. Xcode: 在项目设置中添加本地 Swift Package 依赖（路径: ../），
///      然后删除 SkiAnaylze/Sources/ 下与 VideoVisionCore 重复的 8 个文件
///   2. 命令行: 执行 scripts/setup_ios.sh 自动完成上述步骤
///
/// 注意: 此 Package.swift 仅用于声明依赖关系。
/// 当前 App 的 Xcode 项目需要手动添加本地 Package 引用。
let package = Package(
    name: "SkiAnaylze",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../")
    ],
    targets: [
        .target(
            name: "SkiAnaylze",
            dependencies: [
                .product(name: "VideoVisionCore", package: "VideoVision")
            ],
            path: "SkiAnaylze",
            exclude: ["Sources"]
        )
    ]
)
