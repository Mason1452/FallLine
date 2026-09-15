#!/usr/bin/env bash
# ============================================================================
# alpha_ab_run.sh
# 方案 α confidence-aware smoothing A/B 主 corpus 对照跑数脚本
# ----------------------------------------------------------------------------
# 用法:
#     bash scripts/alpha_ab_run.sh
#
# 输出:
#     testvideo/baseline_alpha_off/{1,2,3,4,5,6}.json     (env 未设 → 旧行为)
#     testvideo/baseline_alpha_on/{1,2,3,4,5,6}.json      (FALLLINE_CONFIDENCE_AWARE=1)
#
# 副作用:
#     每次会覆盖 testvideo/N.json / .md（CLI 默认写路径）；跑完后已复制到快照目录。
#     若你有别的 JSON 想保留，请先自行备份。
# ============================================================================

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

TESTDIR="$REPO/testvideo"
OFF_DIR="$TESTDIR/baseline_alpha_off"
ON_DIR="$TESTDIR/baseline_alpha_on"

mkdir -p "$OFF_DIR" "$ON_DIR"

# 主 corpus 视频列表（1..6，视频 5 为小写扩展名）
declare -a VIDEOS=("1.MP4" "2.MP4" "3.MP4" "4.MP4" "5.mp4" "6.MP4")

echo "==== 方案 α A/B 对照：先跑 OFF（baseline）===="
unset FALLLINE_CONFIDENCE_AWARE
for v in "${VIDEOS[@]}"; do
    stem="${v%.*}"
    echo ""
    echo ">>> [OFF] $v"
    swift run -c release FallLineCLI "$TESTDIR/$v" > /dev/null
    cp "$TESTDIR/$stem.json" "$OFF_DIR/$stem.json"
    cp "$TESTDIR/$stem.md"   "$OFF_DIR/$stem.md"
    echo "    → $OFF_DIR/$stem.json"
done

echo ""
echo "==== 方案 α A/B 对照：再跑 ON (FALLLINE_CONFIDENCE_AWARE=1) ===="
export FALLLINE_CONFIDENCE_AWARE=1
for v in "${VIDEOS[@]}"; do
    stem="${v%.*}"
    echo ""
    echo ">>> [ON]  $v"
    swift run -c release FallLineCLI "$TESTDIR/$v" > /dev/null
    cp "$TESTDIR/$stem.json" "$ON_DIR/$stem.json"
    cp "$TESTDIR/$stem.md"   "$ON_DIR/$stem.md"
    echo "    → $ON_DIR/$stem.json"
done

echo ""
echo "==== A/B 完成 ===="
echo "OFF: $OFF_DIR"
echo "ON:  $ON_DIR"
