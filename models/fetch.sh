#!/usr/bin/env bash
# models/fetch.sh
# ================
# 一键补齐候选 F CoreML 板边分割 spike 所需的开源骨架权重。
# 只拉 .pt（PyTorch）；.mlpackage（CoreML）由用户在本机通过 `yolo export` 生成，
# 见 models/README.md。
#
# 用法：
#   bash models/fetch.sh                # 默认拉 yolov8n-seg.pt
#   bash models/fetch.sh --verify       # 只校验现有权重的 SHA256（不重新下载）
#   bash models/fetch.sh --model yolov8n-seg
#
# 退出码：
#   0 成功；1 网络失败；2 SHA256 mismatch；3 参数错误。

set -euo pipefail

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && /bin/pwd)"

# ---- 骨架清单（新增骨架时改这里）----
# key=<name>  value="<url>|<expected_sha256>"
declare -A MODELS
MODELS[yolov8n-seg]="https://github.com/ultralytics/assets/releases/download/v8.2.0/yolov8n-seg.pt|"
# 第二个字段为空 = 首次 fetch 后需在 README 与此处回填官方 SHA256。

# ---- 参数解析 ----
MODEL="yolov8n-seg"
VERIFY_ONLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)  MODEL="$2"; shift 2 ;;
        --verify) VERIFY_ONLY=1; shift ;;
        -h|--help)
            /usr/bin/sed -n '2,15p' "$0"; exit 0 ;;
        *)
            /bin/echo "[ERROR] 未知参数: $1" >&2; exit 3 ;;
    esac
done

if [[ -z "${MODELS[$MODEL]+_}" ]]; then
    /bin/echo "[ERROR] 未知骨架名: $MODEL"
    /bin/echo "       已注册: ${!MODELS[*]}"
    exit 3
fi

URL="${MODELS[$MODEL]%|*}"
EXPECTED_SHA="${MODELS[$MODEL]#*|}"
FILENAME="$(/usr/bin/basename "$URL")"
OUT_DIR="${SCRIPT_DIR}/${MODEL}"
OUT_FILE="${OUT_DIR}/${FILENAME}"

/bin/mkdir -p "$OUT_DIR"

sha256_of() {
    /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

verify_or_fail() {
    local file="$1"
    local expected="$2"
    if [[ ! -f "$file" ]]; then
        /bin/echo "[MISS] $file 不存在，无法校验"
        return 1
    fi
    local actual
    actual="$(sha256_of "$file")"
    /bin/echo "SHA256=$actual"
    if [[ -z "$expected" ]]; then
        /bin/echo "[NOTE] models/README.md 中该骨架未固化 SHA256。"
        /bin/echo "       把上面这行 SHA256 值贴进 README 的哈希表，然后同步到 fetch.sh 的 MODELS 数组末段（\"...v8.2.0/yolov8n-seg.pt|$actual\"）。"
        return 0
    fi
    if [[ "$actual" != "$expected" ]]; then
        /bin/echo "[FAIL] SHA256 mismatch"
        /bin/echo "       expected: $expected"
        /bin/echo "       actual:   $actual"
        /bin/rm -f "$file"
        return 2
    fi
    /bin/echo "[OK] SHA256 一致"
    return 0
}

if [[ "$VERIFY_ONLY" -eq 1 ]]; then
    /bin/echo "=== [$MODEL] 校验现有权重 ==="
    verify_or_fail "$OUT_FILE" "$EXPECTED_SHA"
    exit $?
fi

if [[ -f "$OUT_FILE" ]]; then
    /bin/echo "=== [$MODEL] 已存在，改为只校验 SHA256（重下请先删 $OUT_FILE）==="
    verify_or_fail "$OUT_FILE" "$EXPECTED_SHA"
    exit $?
fi

/bin/echo "=== [$MODEL] 从 Ultralytics 下载 $FILENAME ==="
/bin/echo "URL: $URL"
if ! /usr/bin/curl -L --fail --show-error --output "$OUT_FILE" "$URL"; then
    /bin/echo "[ERROR] 下载失败，请检查网络或代理" >&2
    /bin/rm -f "$OUT_FILE"
    exit 1
fi

/bin/echo "=== [$MODEL] SHA256 校验 ==="
verify_or_fail "$OUT_FILE" "$EXPECTED_SHA"
STATUS=$?
if [[ $STATUS -eq 2 ]]; then
    exit 2
fi

/bin/echo
/bin/echo "完成。下一步："
/bin/echo "  1) 若首次 fetch，将上面的 SHA256 回填到 models/README.md 与本脚本 MODELS 数组。"
/bin/echo "  2) 本机 export CoreML（见 models/README.md）："
/bin/echo "     cd models/${MODEL} && yolo export model=${FILENAME} format=coreml half=True nms=True imgsz=640"
/bin/echo "  3) Zero-shot 验证："
/bin/echo "     python3 scripts/board_edge_coreml_spike.py --model models/${MODEL}/${MODEL}.mlpackage --dry-run"
