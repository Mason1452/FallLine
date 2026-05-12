#!/bin/bash
# iOS App 依赖设置脚本
# 删除与 FallLineCore 重复的源文件，让 App 通过 SwiftPM 依赖核心库
set -e

SKI_SOURCES="SkiAnaylze/SkiAnaylze/Sources"
FILES=(
    "Models.swift"
    "VideoAnalyzer.swift"
    "VisionFrameAnalyzer.swift"
    "PoseMetrics.swift"
    "PoseScorer.swift"
    "SkiMetricsCalculator.swift"
    "KeyMomentDetector.swift"
    "ReportGenerator.swift"
)

echo "=== FallLine iOS App 依赖设置 ==="
echo ""

for file in "${FILES[@]}"; do
    if [ -f "$SKI_SOURCES/$file" ]; then
        echo "删除重复文件: $SKI_SOURCES/$file"
        rm "$SKI_SOURCES/$file"
    else
        echo "已删除或不存在: $SKI_SOURCES/$file"
    fi
done

echo ""
echo "✅ 重复文件清理完成"
echo ""
echo "后续步骤（在 Xcode 中操作）："
echo "1. 打开 SkiAnaylze/SkiAnaylze.xcodeproj"
echo "2. File → Add Package Dependencies → Add Local..."
echo "3. 选择 FallLine 仓库根目录（包含 Package.swift）"
echo "4. 将 FallLineCore 添加到 App target"
echo ""
echo "或者使用 SwiftPM 命令行构建："
echo "  cd SkiAnaylze && swift build"
