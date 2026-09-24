# FallLine Models

候选 F（CoreML 板边分割 spike，spec §12.14 / ADR-003）的模型工作目录。

**目录用途**：存放 spike 阶段的开源分割骨架权重、以及本机 export 出的 CoreML `.mlpackage`。**二进制不入库**（走 fetch 脚本一键补齐 + SHA256 校验），Git 里只留 README + fetch 脚本 + .gitkeep。

## 现有清单

| 目录 | 骨架 | 用途 | 许可 | 大小（fp32 .pt） |
|---|---|---|---|---|
| [yolov8n-seg/](file:///Users/mingsen/Project/FallLine/models/yolov8n-seg/) | Ultralytics YOLOv8-seg nano | zero-shot 板身像素分割 → PCA 主轴 | **AGPL-3.0** | ~7 MB |

## 许可与项目定位

- **SkiAnaylze 项目定位（2026-09-22 拍板）**：开源；因此可长期依赖 AGPL-3.0 骨架（YOLOv8）。
- 如未来切换到闭源商用，须换成 **YOLO-NAS-seg（Apache-2.0）** 或 **DeepLabV3+ MobileNetV2（MIT，Apple Sample）**。切换点在 [board_edge_coreml_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_coreml_spike.py) 的 `CoreMLBackend` 类；模型目录并列新增即可。

## 一键补齐（`bash models/fetch.sh`）

```bash
cd /Users/mingsen/Project/FallLine
bash models/fetch.sh                    # 默认拉 yolov8n-seg.pt
bash models/fetch.sh --verify           # 只校验现有权重的 SHA256
bash models/fetch.sh --model yolov8n-seg  # 指定骨架
```

脚本行为：
1. `curl -L` 从 Ultralytics 官方 GitHub Release 拉取 `yolov8n-seg.pt`（v8.2.0 tag，稳定版）。
2. `shasum -a 256` 校验，与本 README 记录的哈希对齐；不一致直接删档，避免中毒。
3. **不做 CoreML export**——export 涉及 `pip install ultralytics coremltools`，交由用户按需在本机跑（spike 脚本会自动检测 `.mlpackage` 是否存在，缺失时提示 export 命令）。

## SHA256 哈希清单

以下哈希为 Ultralytics v8.2.0 官方 Release 提供的 PyTorch 权重。首次 fetch 后请把实测值补进本表：

| 文件 | 官方 SHA256 | 本地实测 | 拉取源 |
|---|---|---|---|
| `yolov8n-seg/yolov8n-seg.pt` | *(首次 fetch 后回填)* | *(首次 fetch 后回填)* | https://github.com/ultralytics/assets/releases/download/v8.2.0/yolov8n-seg.pt |

> **回填规则**：`bash models/fetch.sh` 会打印 `SHA256=xxxx…`，把值贴进"官方 SHA256"列，`--verify` 分支后续会读该列做完整性校验。

## 本机 export CoreML（zero-shot 验证前必跑）

Ultralytics 官方支持一条命令导出：

```bash
# 建议单独的 venv，避免污染系统 Python
python3 -m venv .venv-coreml
source .venv-coreml/bin/activate
pip install --upgrade pip
pip install "ultralytics>=8.2,<8.3" "coremltools>=7.1"

# 从 pt 生成 mlpackage（NMS 内嵌 + fp16 权重，M1 ANE 友好）
cd models/yolov8n-seg
yolo export model=yolov8n-seg.pt format=coreml half=True nms=True imgsz=640

# 产出：yolov8n-seg.mlpackage/（目录 bundle，~7 MB）
ls yolov8n-seg.mlpackage
```

## Zero-shot 验证入口

```bash
# 骨架脚本骨架级"仅 --check-plan"仍可用；实现 CoreMLBackend 后：
python3 scripts/board_edge_coreml_spike.py --check-plan
python3 scripts/board_edge_coreml_spike.py \
    --model models/yolov8n-seg/yolov8n-seg.mlpackage \
    --frames 100 \
    --dry-run   # 不写报告，先看 IoU 分布与推理耗时
```

Zero-shot 判据（[spec §12.14](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L774)）：
- IoU ≥ 0.55 → 有希望，投入 100 帧 GT 微调冲 0.65 门槛。
- IoU < 0.30 → COCO 场景不迁移，换骨架（YOLO-NAS-seg / DeepLabV3+）。
- 30–55 → 视用户预算决定是否微调。

## 版本 pin

- **ultralytics**：v8.2.x（v8.3 起 API 有变，先 pin 到 8.2 稳定版）。
- **coremltools**：≥7.1（<8 避开尚未验证的路径）。
- **PyTorch**：随 Ultralytics 自动装（≥2.0）。

## 相关引用

- 决策历史：[spec §12.14](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L774)（骨架 / 决策标准 / 成本预算）
- ADR：[ADR-003](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md)（正式启动 spike 时撰写）
- 前置结论：[Gate-G2 NO-GO §12.15.3](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L907)
- 进度记录：[WORK_LOG.md](file:///Users/mingsen/Project/FallLine/WORK_LOG.md) / [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md)
