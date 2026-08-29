#!/bin/bash
# FallLine iOS App SPM 化脚本
#
# 作用：删除 SkiAnaylze/SkiAnaylze/Sources/ 下与 FallLineCore 重复的 8 个源文件，
#      让 iOS App 通过 SwiftPM 依赖核心库，消除代码重复。
#
# 用法：
#   ./scripts/setup_ios_deps.sh          # 交互式（默认，会二次确认）
#   ./scripts/setup_ios_deps.sh --dry    # 只打印将要执行的操作，不改动磁盘
#   ./scripts/setup_ios_deps.sh --yes    # 跳过确认，直接执行
#   ./scripts/setup_ios_deps.sh --rollback  # 从 .ios_migration_backup/ 恢复
#
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SKI_SOURCES="SkiAnaylze/SkiAnaylze/Sources"
BACKUP_DIR=".ios_migration_backup"

# 与 FallLineCore 一一对应的 8 个复制文件（DemoData.swift 是 iOS-only，保留！）
DUPLICATE_FILES=(
    "Models.swift"
    "VideoAnalyzer.swift"
    "VisionFrameAnalyzer.swift"
    "PoseMetrics.swift"
    "PoseScorer.swift"
    "SkiMetricsCalculator.swift"
    "KeyMomentDetector.swift"
    "ReportGenerator.swift"
)

MODE="interactive"
case "${1:-}" in
    --dry|--dry-run) MODE="dry" ;;
    --yes|-y) MODE="yes" ;;
    --rollback)
        if [ ! -d "$BACKUP_DIR" ]; then
            echo "❌ 未找到备份目录 $BACKUP_DIR，无法回滚"
            exit 1
        fi
        echo "== 从 $BACKUP_DIR 恢复到 $SKI_SOURCES/ =="
        for file in "${DUPLICATE_FILES[@]}"; do
            if [ -f "$BACKUP_DIR/$file" ]; then
                cp "$BACKUP_DIR/$file" "$SKI_SOURCES/$file"
                echo "  ↩️  恢复 $file"
            fi
        done
        echo "✅ 回滚完成"
        exit 0
        ;;
    "") MODE="interactive" ;;
    *) echo "未知参数: $1"; exit 1 ;;
esac

echo "============================================"
echo "  FallLine iOS App SPM 化脚本"
echo "============================================"
echo "仓库根目录: $REPO_ROOT"
echo "模式: $MODE"
echo ""
echo "将要处理的 8 个重复文件（DemoData.swift 保留）："
for file in "${DUPLICATE_FILES[@]}"; do
    if [ -f "$SKI_SOURCES/$file" ]; then
        echo "  [存在] $SKI_SOURCES/$file"
    else
        echo "  [已删] $SKI_SOURCES/$file"
    fi
done
echo ""

if [ "$MODE" == "dry" ]; then
    echo "(dry-run 结束，不改动磁盘)"
    exit 0
fi

if [ "$MODE" == "interactive" ]; then
    read -p "确认执行？会先备份到 $BACKUP_DIR/ 再删除。 [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消"
        exit 0
    fi
fi

# 备份
mkdir -p "$BACKUP_DIR"
echo ""
echo "== 备份到 $BACKUP_DIR/ =="
for file in "${DUPLICATE_FILES[@]}"; do
    if [ -f "$SKI_SOURCES/$file" ]; then
        cp "$SKI_SOURCES/$file" "$BACKUP_DIR/$file"
        echo "  📦 $file"
    fi
done

# 删除
echo ""
echo "== 删除 $SKI_SOURCES/ 下的 8 个重复文件 =="
for file in "${DUPLICATE_FILES[@]}"; do
    if [ -f "$SKI_SOURCES/$file" ]; then
        rm "$SKI_SOURCES/$file"
        echo "  🗑  $file"
    fi
done

echo ""
echo "============================================"
echo "  ✅ 磁盘清理完成"
echo "============================================"
echo ""
echo "剩余 iOS-only 文件（保留）："
ls -1 "$SKI_SOURCES/" 2>/dev/null | sed 's/^/  /'
echo ""
echo "============================================"
echo "  下一步：Xcode 手动操作（约 1 分钟）"
echo "============================================"
cat <<'EOF'

1. 打开 SkiAnaylze/SkiAnaylze.xcodeproj

2. Xcode 顶部菜单：File → Add Package Dependencies...
   在弹窗左下角点击 "Add Local..."
   在 Finder 里选择 FallLine 仓库根目录（包含 Package.swift 的那一层）
   确认 Add Package

3. 在 Project Navigator 里选中 SkiAnaylze 顶层 → 中间面板 target 选中 SkiAnaylze
   → General → Frameworks, Libraries, and Embedded Content
   → + → 选择 FallLineCore → Add

4. Project Navigator 里删掉红色（丢失引用）的 8 个文件条目：
   Models.swift / VideoAnalyzer.swift / VisionFrameAnalyzer.swift /
   PoseMetrics.swift / PoseScorer.swift / SkiMetricsCalculator.swift /
   KeyMomentDetector.swift / ReportGenerator.swift
   删除时选择 "Remove Reference"（不勾选 Move to Trash）

5. 在以下 iOS UI 文件顶部加一行 `import FallLineCore`：
   - SkiAnaylze/SkiAnaylze/VideoAnalysisManager.swift
   - SkiAnaylze/SkiAnaylze/Views/HistoryView.swift
   - SkiAnaylze/SkiAnaylze/Views/HomeView.swift
   - SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift
   - SkiAnaylze/SkiAnaylze/DemoData.swift  （若引用 Core 类型）
   （提示：Cmd+B 编译时报 "Cannot find type X in scope" 就补 import）

6. Cmd+B 编译；若有报错常见问题：
   - "Cannot find AnalysisError"       → import FallLineCore
   - "Duplicate symbol Models"         → 说明步骤 4 有文件没删干净
   - "Missing package product"         → 重新执行步骤 2/3

7. 编译通过后跑一次模拟器烟测，把之前跑通的 demo 视频过一遍。

如果任何步骤搞坏了，运行：
  ./scripts/setup_ios_deps.sh --rollback
可以从 .ios_migration_backup/ 恢复所有已删文件。

EOF
