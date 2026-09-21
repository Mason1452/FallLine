#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
board_edge_coreml_spike.py
==========================

候选 F 骨架脚本（spec §12.14，Design only）：为 CoreML 板边分割 spike 预留
「模型加载 → 逐帧推理 → 与现有 fallback 对比」的可行性验证入口。

**本文件当前仅为占位骨架**——不加载真实模型、不引入任何 CoreML 二进制、
不改动生产代码；用于承接 §12.14 的决策标准落地时的第一版 spike 入口。
真正启动 spike 前需先完成 §12.14 决策标准 + ADR-003（在 spec 尾追加）。

结构：
  * `discover_clips()`      — 复用 gate_g1_probe.CLIPS，与其他 §12 脚本口径一致
  * `SegmentationBackend`   — 抽象接口，`CoreMLBackend` / `NoopBackend` 两种实现
  * `evaluate_segmentation` — 对齐 §12.11 GT 小闸门指标（角度中位、准入 ≤12°）
  * `compare_against_fallback` — 与 outputs/board_edge_p2/fallback_gt_cache.json 逐帧对齐
  * `main`                  — 命令行入口，未启动 spike 时打印占位与 TODO

用法（占位阶段）：
  python3 scripts/board_edge_coreml_spike.py                 # 打印占位与 TODO
  python3 scripts/board_edge_coreml_spike.py --list-clips    # 列出 44 片 clip 名
  python3 scripts/board_edge_coreml_spike.py --check-plan    # 打印 §12.14 决策标准

启动 spike 后（待 ADR-003 生效）：
  python3 scripts/board_edge_coreml_spike.py --model yolov8seg_nano.mlmodel \\
      --gt outputs/board_edge_p2/coreml_gt/masks.json \\
      --report outputs/board_edge_p2/coreml_spike/report.json
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))

# 复用 §12 脚本已固化的 44 片 CLIPS 列表 + v3 常量，保证与 v3 探针同口径。
try:
    from board_edge_gate_g1_probe import CLIPS  # noqa: E402
except ImportError as exc:  # pragma: no cover
    print(f"[WARN] 无法导入 board_edge_gate_g1_probe.CLIPS：{exc}")
    CLIPS = []


# ---------------------------------------------------------------------------
# §12.14 决策标准。2026-09-21（Gate-G2 NO-GO 激活候选 F）用户锁定三条硬门槛：
# IoU≥0.65 / 推理≤20ms / farShot 恢复率≥50%，须同时满足，不再放宽。
# ---------------------------------------------------------------------------

LOCKED_NOTE = (
    "已锁定（2026-09-21）：精度/推理/farShot 三条硬门槛须同时满足，任一 FAIL 即候选 F 失败。"
)

DECISION_CRITERIA = [
    ("精度",     "分割 IoU ≥ 0.65（板身像素级 GT）【已锁定】"),
    ("推理开销", "CoreML M1 Pro 单帧 ≤ 20ms（对齐 Gate-G1 性能 ≤+30%）【已锁定】"),
    ("准入精度", "转出板轴后 §12.11 同口径 GT 准入 ≥ 90%"),
    ("覆盖率",   "远景 / farShot 桶恢复率 ≥ 50%（否则不比 fallback 强）【已锁定】"),
    ("确定性",   "模型推理 bit-identical（float 容差 <1e-4）"),
    ("迁移成本", "训练 + 微调 + CoreML export + 集成总人力 ≤ 20 人时"),
]

# 决策路径（详见 spec §12.14）
DECISION_PATHS = [
    "若 §12.13 v3 通过后 Gate-G2 顺利过 → 候选 F 降级为 Phase 3+ 增强，不启动 spike。",
    "若 v3 通过但 Gate-G2 因 fallback 精度不足失败 → 候选 F 升到 P0，本脚本正式启用。",
    "任何后续启动前，需要在 spec §12.14 追加实测数据 + ADR-003。",
]


# ---------------------------------------------------------------------------
# 后端抽象：占位阶段仅提供 NoopBackend；正式 spike 时另实现 CoreMLBackend。
# ---------------------------------------------------------------------------

@dataclass
class SegmentationSample:
    """单帧的分割 → 板轴产物（占位；正式 spike 时补齐）。"""
    clip: str
    frame_index: int
    board_iou: Optional[float] = None
    axis_angle_deg: Optional[float] = None
    axis_confidence: Optional[float] = None
    inference_ms: Optional[float] = None
    is_bit_identical: Optional[bool] = None


class SegmentationBackend:
    """所有分割后端需实现的最小接口。"""

    name: str = "abstract"

    def predict(self, clip: str, frame_index: int) -> SegmentationSample:
        raise NotImplementedError


class NoopBackend(SegmentationBackend):
    """占位阶段默认后端：不做任何真实推理，仅返回 None 供上层跳过。"""

    name = "noop"

    def predict(self, clip: str, frame_index: int) -> SegmentationSample:
        return SegmentationSample(clip=clip, frame_index=frame_index)


# TODO(ADR-003)：正式 spike 时新增 CoreMLBackend
# class CoreMLBackend(SegmentationBackend):
#     name = "coreml"
#     def __init__(self, model_path: Path): ...
#     def predict(self, clip: str, frame_index: int) -> SegmentationSample: ...
#     - 需集成：VNCoreMLRequest / MLModel 推理、板身 mask → PCA 主轴、
#       计时（不含 IO）、bit-identical 校验（同帧两次推理容差 <1e-4）。


# ---------------------------------------------------------------------------
# 评估：与 §12.11 GT 小闸门指标同口径（等待正式 spike 补齐真实实现）
# ---------------------------------------------------------------------------

@dataclass
class SegmentationReport:
    backend: str
    total_samples: int = 0
    valid_axis_samples: int = 0
    median_iou: Optional[float] = None
    median_angle_error_deg: Optional[float] = None
    admission_rate_at_12deg: Optional[float] = None
    median_inference_ms: Optional[float] = None
    bit_identical_ratio: Optional[float] = None
    notes: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {
            "backend": self.backend,
            "totalSamples": self.total_samples,
            "validAxisSamples": self.valid_axis_samples,
            "medianIoU": self.median_iou,
            "medianAngleErrorDeg": self.median_angle_error_deg,
            "admissionRateAt12Deg": self.admission_rate_at_12deg,
            "medianInferenceMs": self.median_inference_ms,
            "bitIdenticalRatio": self.bit_identical_ratio,
            "notes": self.notes,
        }


def evaluate_segmentation(
    backend: SegmentationBackend,
    clip_iter: Callable[[], list[tuple[str, list[int]]]],
    gt_lookup: Optional[Callable[[str, int], Optional[float]]] = None,
) -> SegmentationReport:
    """占位实现：遍历 clip，聚合样本，暂不做真实统计。

    正式 spike 时补齐：
      - median_iou = statistics.median(sample.board_iou for sample in valid)
      - median_angle_error_deg = statistics.median(|sample.axis_angle_deg - gt|)
      - admission_rate_at_12deg = |err ≤ 12°| / valid_axis_samples
      - median_inference_ms、bit_identical_ratio 同理
    """
    report = SegmentationReport(backend=backend.name)
    for clip, frames in clip_iter():
        for frame_index in frames:
            sample = backend.predict(clip, frame_index)
            report.total_samples += 1
            if sample.axis_angle_deg is not None:
                report.valid_axis_samples += 1
    if backend.name == "noop":
        report.notes.append(
            "占位阶段：NoopBackend 未产出任何真实推理结果；"
            "启动正式 spike 前请实现 CoreMLBackend 并接入 GT。"
        )
    return report


def compare_against_fallback(
    report: SegmentationReport,
    fallback_cache_path: Path,
) -> list[str]:
    """占位：正式 spike 后需与 fallback_gt_cache.json 逐帧对齐 (angle_err, coverage)。"""
    notes: list[str] = []
    if not fallback_cache_path.exists():
        notes.append(f"未找到 fallback 缓存 {fallback_cache_path}，跳过对比。")
        return notes
    notes.append(
        f"TODO(ADR-003)：逐帧对齐 {fallback_cache_path.name} 中的 fallback pick 与 "
        f"{report.backend} 分割转出的板轴，比较 (angle_err, effCov, farShot 恢复率)。"
    )
    return notes


# ---------------------------------------------------------------------------
# CLI 入口
# ---------------------------------------------------------------------------

def discover_clips() -> list[str]:
    return [clip[0] for clip in CLIPS] if CLIPS else []


def print_plan() -> None:
    print("=" * 72)
    print("候选 F CoreML 板边分割 spike — 决策标准（spec §12.14）")
    print("=" * 72)
    print(f"  {LOCKED_NOTE}")
    print()
    for key, desc in DECISION_CRITERIA:
        print(f"  • [{key}] {desc}")
    print()
    print("决策路径：")
    for path in DECISION_PATHS:
        print(f"  - {path}")
    print()
    print("当前状态：已激活（Gate-G2 NO-GO，§12.15.3）。待拍板模型选型 + 像素级 GT 标注预算后启动 spike。")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[3])
    parser.add_argument("--list-clips", action="store_true",
                        help="列出 §4.4 44 片 clip 别名（与 v3 探针同口径）")
    parser.add_argument("--check-plan", action="store_true",
                        help="打印 §12.14 决策标准与决策路径")
    parser.add_argument("--model", type=Path, default=None,
                        help="[TODO] 正式 spike 时的 CoreML 模型路径")
    parser.add_argument("--gt", type=Path, default=None,
                        help="[TODO] 正式 spike 时的板身像素 GT 标注 JSON 路径")
    parser.add_argument("--report", type=Path, default=None,
                        help="[TODO] 结果 JSON 输出路径 "
                             "(outputs/board_edge_p2/coreml_spike/report.json)")
    args = parser.parse_args()

    if args.list_clips:
        clips = discover_clips()
        print(f"共 {len(clips)} 片：")
        for name in clips:
            print(f"  - {name}")
        return 0

    if args.check_plan:
        print_plan()
        return 0

    if args.model is not None:
        print("[SKIP] 已识别 --model 参数，但 CoreMLBackend 尚未实现；"
              "参见 spec §12.14 决策路径与 ADR-003（未撰写）。")
        return 2

    # 默认路径：打印占位说明。
    print("board_edge_coreml_spike.py — 占位骨架（Design only）")
    print("-" * 72)
    print("当前脚本不加载任何模型、不做真实推理，仅承接 spec §12.14 决策入口。")
    print("如需查看决策标准：python3 scripts/board_edge_coreml_spike.py --check-plan")
    print("如需列 clip 集合：  python3 scripts/board_edge_coreml_spike.py --list-clips")
    print()
    report = evaluate_segmentation(
        NoopBackend(),
        clip_iter=lambda: [(name, []) for name in discover_clips()],
    )
    fallback_cache = Path("outputs/board_edge_p2/fallback_gt_cache.json")
    report.notes.extend(compare_against_fallback(report, fallback_cache))
    print(json.dumps(report.as_dict(), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
