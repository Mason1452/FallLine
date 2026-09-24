#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
board_edge_coreml_spike.py
==========================

候选 F CoreML 板边分割 spike 入口（spec §12.14 / ADR-003 撰写中）。

**当前状态（2026-09-22）**：
  - 用户拍板：`yolov8n-seg` (nano) + `.pt` + `fetch.sh` + 项目开源（AGPL-3.0 兼容）。
  - `CoreMLBackend` 从占位骨架升级为真实实现：读取本机 export 出的
    `.mlpackage`，跑 zero-shot 单帧 predict，计算板身 mask IoU（若给 GT），
    并测量单帧推理耗时（对齐 §12.14 的 ≤20ms 硬门槛）。
  - **模型二进制不入库**（`.gitignore` 里 `models/**/*.pt`、`models/**/*.mlpackage/`），
    由 `models/fetch.sh` 拉 `.pt` + 本机 `yolo export` 生成 `.mlpackage`。
  - 主要用法：先跑 `--check-plan` / `--list-clips` 看骨架就绪；补齐模型后跑
    `--model <path>` 做 zero-shot 抽帧验证；100 帧 GT 就位后跑 `--gt <path>` 出 IoU 报告。

结构：
  * `discover_clips()`      — 复用 gate_g1_probe.CLIPS，与其他 §12 脚本口径一致
  * `SegmentationBackend`   — 抽象接口
  * `NoopBackend`           — 占位后端（--check-plan / --list-clips 时用）
  * `CoreMLBackend`         — 真实后端：coremltools 加载 mlpackage 单帧 predict
  * `evaluate_segmentation` — 遍历样本产出 SegmentationReport
  * `compare_against_fallback` — 与 outputs/board_edge_p2/fallback_gt_cache.json 逐帧对齐
  * `main`                  — 命令行入口

用法（骨架阶段，不需要模型）：
  python3 scripts/board_edge_coreml_spike.py                 # 打印占位与 TODO
  python3 scripts/board_edge_coreml_spike.py --list-clips    # 列出 44 片 clip 名
  python3 scripts/board_edge_coreml_spike.py --check-plan    # 打印 §12.14 决策标准

用法（zero-shot 阶段，需要 models/yolov8n-seg/yolov8n-seg.mlpackage）：
  bash models/fetch.sh                                       # 拉 .pt
  cd models/yolov8n-seg && yolo export model=yolov8n-seg.pt \\
      format=coreml half=True nms=True imgsz=640            # 生成 .mlpackage
  python3 scripts/board_edge_coreml_spike.py \\
      --model models/yolov8n-seg/yolov8n-seg.mlpackage \\
      --frames 20 --dry-run                                  # 跑 20 帧 zero-shot
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))

# 复用 §12 脚本已固化的 44 片 CLIPS 列表 + v3 常量，保证与 v3 探针同口径。
try:
    from board_edge_gate_g1_probe import CLIPS  # noqa: E402
except ImportError as exc:  # pragma: no cover
    print(f"[WARN] 无法导入 board_edge_gate_g1_probe.CLIPS：{exc}")
    CLIPS = []


ROOT = Path(__file__).resolve().parent.parent

# COCO class id for snowboard（YOLOv8-seg pretrain on COCO 80 类）。
# skis=30, snowboard=31。zero-shot 抽这两类的 mask 做联合。
COCO_SNOWBOARD_CLASS_IDS = {30, 31}


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

# 用户 2026-09-22 拍板的骨架/许可/目录配置
LOCKED_CONFIG = {
    "backbone": "yolov8n-seg",
    "format": ".pt (fetch) + .mlpackage (local export)",
    "license": "AGPL-3.0（项目开源，合规）",
    "storage": "models/yolov8n-seg/ 目录，二进制不入库（fetch.sh + shasum）",
    "default_model_path": "models/yolov8n-seg/yolov8n-seg.mlpackage",
}


# ---------------------------------------------------------------------------
# 后端抽象
# ---------------------------------------------------------------------------

@dataclass
class SegmentationSample:
    """单帧的分割 → 板轴产物。"""
    clip: str
    frame_index: int
    board_iou: Optional[float] = None
    axis_angle_deg: Optional[float] = None
    axis_confidence: Optional[float] = None
    inference_ms: Optional[float] = None
    is_bit_identical: Optional[bool] = None
    mask_pixel_count: Optional[int] = None
    class_ids: Optional[list[int]] = None


class SegmentationBackend:
    """所有分割后端需实现的最小接口。"""

    name: str = "abstract"

    def predict(self, clip: str, frame_index: int) -> SegmentationSample:
        raise NotImplementedError

    def close(self) -> None:  # 可选：释放资源
        pass


class NoopBackend(SegmentationBackend):
    """占位后端：不做任何真实推理，仅返回 None 供上层跳过（用于 --check-plan 等只读命令）。"""

    name = "noop"

    def predict(self, clip: str, frame_index: int) -> SegmentationSample:
        return SegmentationSample(clip=clip, frame_index=frame_index)


class CoreMLBackend(SegmentationBackend):
    """
    读取本机 export 的 YOLOv8-seg CoreML `.mlpackage`，单帧跑 zero-shot 分割。

    - 输入：`.mlpackage` 目录（`yolo export model=yolov8n-seg.pt format=coreml`）+ clip 路径
    - 输出：SegmentationSample：class_ids / mask_pixel_count / inference_ms / board_iou（如提供 GT）
    - PCA 主轴（axis_angle_deg / axis_confidence）：本 spike 版**未**从 mask 反推，
      先跑 zero-shot 精度评估，判定过 §12.14 IoU≥0.65 门槛后再补 PCA 逻辑。

    依赖（首次使用请按 `models/README.md` 建 `.venv-coreml` 并 pip install）：
      - coremltools >= 7.1
      - Pillow >= 10.0
      - numpy
      - opencv-python 或 av（用于抽帧；这里默认走 ffmpeg 命令行或 PIL 单帧 fallback）

    本类采用 lazy import，只有真正调用 predict 时才 import coremltools/PIL/numpy，
    保证 `--check-plan` 等只读命令在无 venv 环境下也能运行。
    """

    name = "coreml"

    def __init__(self, model_path: Path, image_size: int = 640):
        self.model_path = Path(model_path)
        if not self.model_path.exists():
            raise FileNotFoundError(
                f"CoreML 模型不存在：{self.model_path}\n"
                f"请先运行：\n"
                f"  bash models/fetch.sh\n"
                f"  cd models/yolov8n-seg && yolo export model=yolov8n-seg.pt "
                f"format=coreml half=True nms=True imgsz={image_size}"
            )
        self.image_size = image_size
        self._model = None  # lazy
        self._np = None
        self._Image = None

    def _lazy_import(self):
        if self._model is not None:
            return
        try:
            import coremltools as ct  # noqa: F401
            import numpy as np
            from PIL import Image
        except ImportError as exc:
            raise ImportError(
                "缺少 coremltools/numpy/Pillow。请按 models/README.md 安装：\n"
                "  python3 -m venv .venv-coreml && source .venv-coreml/bin/activate\n"
                "  pip install 'ultralytics>=8.2,<8.3' 'coremltools>=7.1' Pillow numpy\n"
                f"原始错误：{exc}"
            ) from exc

        self._np = np
        self._Image = Image
        print(f"[CoreMLBackend] 加载模型：{self.model_path}")
        t0 = time.perf_counter()
        self._model = ct.models.MLModel(str(self.model_path))
        dt = (time.perf_counter() - t0) * 1000
        print(f"[CoreMLBackend] 加载耗时 {dt:.1f}ms")

    def _extract_frame(self, clip_relpath: str, frame_index: int):
        """从视频中抽单帧。走 ffmpeg 命令行（macOS 通常带）；失败则报错。"""
        import subprocess
        import io
        clip_path = ROOT / clip_relpath
        if not clip_path.exists():
            raise FileNotFoundError(f"视频不存在：{clip_path}")
        # 以 5fps 视为主流程口径；这里用 frame_index 直接抽 -vf select 索引。
        # 为简化 spike，我们直接按秒定位（frame_index 视为 5fps 序号）。
        seconds = frame_index / 5.0
        cmd = [
            "/opt/homebrew/bin/ffmpeg",
            "-loglevel", "error",
            "-ss", f"{seconds:.3f}",
            "-i", str(clip_path),
            "-frames:v", "1",
            "-f", "image2pipe",
            "-vcodec", "png",
            "pipe:1",
        ]
        try:
            proc = subprocess.run(cmd, capture_output=True, check=True)
        except FileNotFoundError:
            # 回退 /usr/local/bin/ffmpeg 或提示
            cmd[0] = "/usr/local/bin/ffmpeg"
            try:
                proc = subprocess.run(cmd, capture_output=True, check=True)
            except FileNotFoundError as exc:
                raise FileNotFoundError(
                    "未找到 ffmpeg（尝试了 /opt/homebrew/bin 和 /usr/local/bin）。\n"
                    "请安装：brew install ffmpeg"
                ) from exc
        img = self._Image.open(io.BytesIO(proc.stdout)).convert("RGB")
        return img

    def _preprocess(self, img):
        """resize 到 image_size，保持 letterbox（YOLOv8 官方 export 一般已内嵌 preprocess）。"""
        img_resized = img.resize((self.image_size, self.image_size), self._Image.BILINEAR)
        return img_resized

    def _iou(self, pred_mask, gt_mask) -> float:
        """两个 bool 二值 mask 的 IoU。"""
        inter = (pred_mask & gt_mask).sum()
        union = (pred_mask | gt_mask).sum()
        if union == 0:
            return 0.0
        return float(inter) / float(union)

    def predict(
        self,
        clip: str,
        frame_index: int,
        gt_mask=None,
    ) -> SegmentationSample:
        self._lazy_import()

        # 从 CLIPS 别名找 relpath
        clip_relpath = None
        for alias, _grp, relpath in CLIPS:
            if alias == clip:
                clip_relpath = relpath
                break
        if clip_relpath is None:
            raise KeyError(f"未在 CLIPS 中找到别名：{clip}")

        img = self._extract_frame(clip_relpath, frame_index)
        img_pre = self._preprocess(img)

        # 推理计时（不含 IO 与 preprocess）
        t0 = time.perf_counter()
        out = self._model.predict({"image": img_pre})
        inference_ms = (time.perf_counter() - t0) * 1000

        # Ultralytics coreml export 一般输出两支：
        #   - "confidence" / "coordinates" (detection heads)
        #   - "masks" 或 "proto" + "masks"（分割 head）
        # 具体键名依 Ultralytics 版本而定；这里做健壮扫描：
        mask_arr = None
        class_ids: list[int] = []
        for key, val in out.items():
            low = key.lower()
            if "mask" in low and hasattr(val, "shape"):
                mask_arr = val
            if "class" in low and hasattr(val, "shape"):
                # 常见 shape (N, 1) 或 (N,)
                try:
                    for cid in self._np.asarray(val).flatten().astype(int).tolist():
                        class_ids.append(cid)
                except Exception:
                    pass

        pixel_count: Optional[int] = None
        board_iou: Optional[float] = None
        if mask_arr is not None:
            arr = self._np.asarray(mask_arr)
            # 常见形状：(N_instances, H, W) 或 (H, W)
            # zero-shot 阶段筛 snowboard/skis（COCO 30/31）
            if class_ids:
                keep_idx = [
                    i for i, cid in enumerate(class_ids)
                    if cid in COCO_SNOWBOARD_CLASS_IDS
                ]
                if keep_idx and arr.ndim == 3:
                    board_masks = arr[keep_idx]
                    board_mask = (board_masks > 0.5).any(axis=0)
                else:
                    board_mask = None
            else:
                # 无类别信息 → 所有 mask 联合，仅供 sanity check
                if arr.ndim == 3:
                    board_mask = (arr > 0.5).any(axis=0)
                elif arr.ndim == 2:
                    board_mask = arr > 0.5
                else:
                    board_mask = None
            if board_mask is not None:
                pixel_count = int(board_mask.sum())
                if gt_mask is not None:
                    board_iou = self._iou(board_mask, gt_mask.astype(bool))

        return SegmentationSample(
            clip=clip,
            frame_index=frame_index,
            board_iou=board_iou,
            axis_angle_deg=None,  # TODO：过 IoU 门槛后补 PCA 主轴
            axis_confidence=None,
            inference_ms=inference_ms,
            is_bit_identical=None,  # 双跑对比在 evaluate 层做
            mask_pixel_count=pixel_count,
            class_ids=class_ids or None,
        )


# ---------------------------------------------------------------------------
# 评估
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
    p95_inference_ms: Optional[float] = None
    max_inference_ms: Optional[float] = None
    bit_identical_ratio: Optional[float] = None
    inference_le_20ms_ratio: Optional[float] = None
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
            "p95InferenceMs": self.p95_inference_ms,
            "maxInferenceMs": self.max_inference_ms,
            "bitIdenticalRatio": self.bit_identical_ratio,
            "inferenceLE20msRatio": self.inference_le_20ms_ratio,
            "notes": self.notes,
        }


def _percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    vs = sorted(values)
    k = (len(vs) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(vs) - 1)
    return vs[lo] + (vs[hi] - vs[lo]) * (k - lo)


def evaluate_segmentation(
    backend: SegmentationBackend,
    clip_iter: Callable[[], Iterable[tuple[str, list[int]]]],
    gt_lookup: Optional[Callable[[str, int], Optional[object]]] = None,
) -> SegmentationReport:
    """遍历 clip / frame，聚合样本，输出报告。

    - `clip_iter()` 返回 [(clip_alias, [frame_index, ...])]
    - `gt_lookup(clip, frame_index)` 返回 gt_mask（bool ndarray）或 None
    """
    report = SegmentationReport(backend=backend.name)
    ious: list[float] = []
    lat: list[float] = []
    for clip, frames in clip_iter():
        for frame_index in frames:
            gt = gt_lookup(clip, frame_index) if gt_lookup else None
            try:
                sample = backend.predict(clip, frame_index) if gt is None else backend.predict(clip, frame_index, gt_mask=gt)  # type: ignore[call-arg]
            except TypeError:
                sample = backend.predict(clip, frame_index)
            report.total_samples += 1
            if sample.axis_angle_deg is not None:
                report.valid_axis_samples += 1
            if sample.board_iou is not None:
                ious.append(sample.board_iou)
            if sample.inference_ms is not None:
                lat.append(sample.inference_ms)

    if ious:
        report.median_iou = statistics.median(ious)
    if lat:
        report.median_inference_ms = statistics.median(lat)
        report.p95_inference_ms = _percentile(lat, 0.95)
        report.max_inference_ms = max(lat)
        le20 = sum(1 for v in lat if v <= 20.0)
        report.inference_le_20ms_ratio = le20 / len(lat)

    if backend.name == "noop":
        report.notes.append(
            "占位阶段：NoopBackend 未产出任何真实推理结果；"
            "启动正式 spike 前请实现 CoreMLBackend 并接入 GT。"
        )
    else:
        # 快速自检门槛
        if report.median_iou is not None:
            if report.median_iou >= 0.65:
                report.notes.append(f"[PASS] medianIoU={report.median_iou:.3f} ≥ 0.65")
            else:
                report.notes.append(
                    f"[FAIL/待微调] medianIoU={report.median_iou:.3f} < 0.65（zero-shot 未达门槛，"
                    f"若 ≥0.55 有希望，投 100 帧 GT 微调；<0.30 建议换骨架）"
                )
        if report.median_inference_ms is not None:
            if report.median_inference_ms <= 20.0:
                report.notes.append(
                    f"[PASS] medianInferenceMs={report.median_inference_ms:.1f}ms ≤ 20ms"
                )
            else:
                report.notes.append(
                    f"[FAIL] medianInferenceMs={report.median_inference_ms:.1f}ms > 20ms（M1 Pro 硬门槛）"
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
    print("2026-09-22 拍板配置：")
    for k, v in LOCKED_CONFIG.items():
        print(f"  • {k}: {v}")
    print()
    print("当前状态：已激活（Gate-G2 NO-GO，§12.15.3）+ models/ 目录就绪 + CoreMLBackend 实现。")
    print("下一步：`bash models/fetch.sh` → 本机 `yolo export` → 本脚本 `--model <path> --dry-run`。")


def default_frames_for_dryrun(clips: list[str], per_clip: int = 5) -> list[tuple[str, list[int]]]:
    """--dry-run 模式：每片抽 per_clip 帧（0.5s / 1.5s / 2.5s / 3.5s / 4.5s，对应 5fps 索引）。"""
    frames = [int(0.5 * 5 + i * 5) for i in range(per_clip)]  # 3, 8, 13, 18, 23
    return [(name, frames) for name in clips]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[3])
    parser.add_argument("--list-clips", action="store_true",
                        help="列出 §4.4 44 片 clip 别名（与 v3 探针同口径）")
    parser.add_argument("--check-plan", action="store_true",
                        help="打印 §12.14 决策标准与决策路径")
    parser.add_argument("--model", type=Path, default=None,
                        help="CoreML 模型路径（.mlpackage）；缺省时回退 NoopBackend")
    parser.add_argument("--gt", type=Path, default=None,
                        help="[TODO] 板身像素 GT 标注 JSON 路径（含 mask 二进制或路径引用）")
    parser.add_argument("--report", type=Path, default=None,
                        help="结果 JSON 输出路径 (默认 outputs/board_edge_p2/coreml_spike/report.json)")
    parser.add_argument("--dry-run", action="store_true",
                        help="每片抽 5 帧的 zero-shot 快检（不需要 GT，只看 IoU=None + 推理耗时）")
    parser.add_argument("--frames", type=int, default=5,
                        help="每片抽帧数（默认 5，仅在 --dry-run 时生效）")
    parser.add_argument("--only", type=str, default=None,
                        help="只跑一个 clip 别名（用于调试）")
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

    # 选后端
    if args.model is None:
        print("board_edge_coreml_spike.py — 未指定 --model，回退 NoopBackend（Design only）")
        print("-" * 72)
        print("如需查看决策标准：python3 scripts/board_edge_coreml_spike.py --check-plan")
        print("如需实测 zero-shot：先运行 `bash models/fetch.sh` 拉 .pt，然后本机 `yolo export`")
        print("                    再传 --model models/yolov8n-seg/yolov8n-seg.mlpackage --dry-run")
        print()
        backend: SegmentationBackend = NoopBackend()
    else:
        try:
            backend = CoreMLBackend(args.model)
        except FileNotFoundError as exc:
            print(f"[ERROR] {exc}", file=sys.stderr)
            return 2

    # 挑帧
    clip_names = discover_clips()
    if args.only:
        if args.only not in clip_names:
            print(f"[ERROR] --only 别名不存在：{args.only}", file=sys.stderr)
            return 3
        clip_names = [args.only]

    if args.dry_run or backend.name == "noop":
        clip_frames = default_frames_for_dryrun(clip_names, per_clip=args.frames)
    else:
        # 非 dry-run 且未提供 GT 时，也跑 5 帧仅评推理耗时
        clip_frames = default_frames_for_dryrun(clip_names, per_clip=args.frames)

    report = evaluate_segmentation(
        backend,
        clip_iter=lambda: clip_frames,
        gt_lookup=None,  # GT 走 --gt 时接线
    )
    fallback_cache = ROOT / "outputs" / "board_edge_p2" / "fallback_gt_cache.json"
    report.notes.extend(compare_against_fallback(report, fallback_cache))

    out_path = args.report or (ROOT / "outputs" / "board_edge_p2" / "coreml_spike" / "report.json")
    if not args.dry_run:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(report.as_dict(), ensure_ascii=False, indent=2))
        print(f"报告写入：{out_path}")

    print(json.dumps(report.as_dict(), ensure_ascii=False, indent=2))
    backend.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
