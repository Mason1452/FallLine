#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
confidence_smoothing_audit.py
=============================

只读扫描主 corpus 内所有 AnalysisOutput JSON，量化 PoseSmoother 里 1€ Filter
输入信号的置信度分布，评估"把 confidence 传给滤波器"的潜在收益。

背景
----
PoseSmoother.filterMetric (Sources/FallLineCore/PoseSmoother.swift#L386-L396)
当前只把 `MetricWithConfidence.value` 传给 OneEuroFilter，`confidence` 完全被
忽略。而下游聚合层（PoseScorer bilateral 权重 / stability 权重）已经用
`AnalysisReliability.smoothConfidenceWeight` 做了二次曲线降权：

    conf ≤ 0.15  →  权重 0
    conf in (0.15, 0.75) → 权重 = ((conf-0.15)/0.60)²
    conf ≥ 0.75  →  权重 1

深度研究（2026-06-05 报告）建议参考 Anipose Viterbi / SmoothNet / Sports2D 的
confidence-aware smoothing：让滤波器在低置信度帧减少对状态的更新。

本脚本采集
----------
对每份 testvideo/{1..6}.json：

1. **置信度分布**：knee / calf / lean / cog 五组信号，按四档 (<0.15 / 0.15-0.30 /
   0.30-0.75 / ≥0.75) 帧数占比。
2. **平滑权重分布**：直接把 confidence 喂给 smoothConfidenceWeight，看权重
   均值 / p25 / p50 / p75 / p95 —— 判断当前"事实上"被 1€ Filter 平等吸收的
   低权重帧比重。
3. **低置信度帧的连续长度分布 (run-length)**：conf < 0.30 的连续段长度直方图。
   长段（≥3 帧）意味着 1€ Filter 会持续被低置信度信号拽偏，短段（1~2 帧）
   影响有限。P0 despike 已经处理 3~5 帧窗内的孤立尖峰，本诊断能量化 despike
   之外的"多帧低置信度片段"。
4. **P4-A 插值帧标记**：conf ≤ 0.30 且非零的帧可能是 P4-A 注入的插值样本
   (confidenceDecay=0.5, cap=0.30)。汇总这类样本的数量。

局限
----
JSON 里的 `confidence` 是 PoseSmoother 处理完成后的值。P0 despike 保留原
confidence（[PoseSmoother.swift#L175](Sources/FallLineCore/PoseSmoother.swift#L175)
的 `replace` 函数），1€ Filter 也保留原 confidence
([PoseSmoother.swift#L395](Sources/FallLineCore/PoseSmoother.swift#L395))。
唯一会写 confidence 的是 P4-A 插值 (imputeSeries)，写入值 ≤ 0.30。所以
JSON 里出现 conf ≤ 0.30 的样本有两种来源：(1) Vision 原始检测低置信度、
(2) P4-A 插值。本诊断合并统计，不区分——目的是量化 1€ Filter 见到的"事实
低信任信号"总量，两种来源都会污染滤波状态。

用法
----
    python3 scripts/confidence_smoothing_audit.py [--json testvideo/*.json]

无副作用：不写任何非 stdout 的文件。

对齐
----
- 阈值区间与 [AnalysisReliability](Sources/FallLineCore/Utilities.swift#L95-L119)
  的 softConfidenceFloor (0.15) / softConfidenceCeiling (0.75) /
  minimumPoseScoreConfidence (0.30) 严格一致。
"""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# 与 Sources/FallLineCore/Utilities.swift 严格对齐的常量
# ---------------------------------------------------------------------------

SOFT_FLOOR = 0.15
SOFT_CEILING = 0.75
MIN_POSE_SCORE_CONF = 0.30
LOW_RUN_CONF_THRESHOLD = MIN_POSE_SCORE_CONF  # 用于 run-length 定义


def smooth_confidence_weight(conf: float) -> float:
    """PoseSmoother 下游用的 conf → 权重曲线（Anipose-inspired 二次）。"""
    if conf <= SOFT_FLOOR:
        return 0.0
    if conf >= SOFT_CEILING:
        return 1.0
    normalized = (conf - SOFT_FLOOR) / (SOFT_CEILING - SOFT_FLOOR)
    return normalized * normalized


# ---------------------------------------------------------------------------
# 要采集的信号（PoseSmoother.filterMetric 覆盖的所有 angleFilters/coordFilters 键）
# ---------------------------------------------------------------------------

# 只统计角度类信号；坐标类（hipCenter/ankleCenter 等）为辅信号，用于对照
ANGLE_SIGNALS = [
    "leftKneeBendAngle",
    "rightKneeBendAngle",
    "leftCalfLeanAngle",
    "rightCalfLeanAngle",
    "bodyLeanAngle",
    "leftBodyLeanAngle",
    "rightBodyLeanAngle",
]

COORD_SIGNALS = [
    "centerOfGravity",  # 位置比值，与角度分开归类
]


def find_corpus_jsons(root: Path) -> list[Path]:
    """定位 testvideo/*.json（不含子目录快照，只看主 corpus）。"""
    return sorted((root / "testvideo").glob("*.json"))


# ---------------------------------------------------------------------------
# 帧级读取
# ---------------------------------------------------------------------------


def collect_confidence_series(
    frames: list[dict[str, Any]], key: str
) -> list[float | None]:
    """从 frames[*].bodyPose[key].confidence 抽取时间序列，缺失记为 None。"""
    out: list[float | None] = []
    for f in frames:
        bp = f.get("bodyPose")
        if not isinstance(bp, dict):
            out.append(None)
            continue
        metric = bp.get(key)
        if not isinstance(metric, dict):
            out.append(None)
            continue
        conf = metric.get("confidence")
        if not isinstance(conf, (int, float)):
            out.append(None)
            continue
        out.append(float(conf))
    return out


def bucket_distribution(series: list[float | None]) -> dict[str, int]:
    """按四档统计帧数占比。missing = value 为 None（该信号在这一帧不存在）。"""
    buckets = {
        "<0.15": 0,       # smoothConfidenceWeight = 0
        "0.15-0.30": 0,   # 极低权重段（含 P4-A 插值上限）
        "0.30-0.75": 0,   # 中段（现在被 1€ Filter 平等吸收 → 主要污染源）
        ">=0.75": 0,      # 满贡献段
        "missing": 0,
    }
    for c in series:
        if c is None:
            buckets["missing"] += 1
        elif c < SOFT_FLOOR:
            buckets["<0.15"] += 1
        elif c < MIN_POSE_SCORE_CONF:
            buckets["0.15-0.30"] += 1
        elif c < SOFT_CEILING:
            buckets["0.30-0.75"] += 1
        else:
            buckets[">=0.75"] += 1
    return buckets


def weight_stats(series: list[float | None]) -> dict[str, float]:
    """把每帧 confidence 喂 smoothConfidenceWeight，返回权重的分位数。"""
    weights = [smooth_confidence_weight(c) for c in series if c is not None]
    if not weights:
        return {}
    weights_sorted = sorted(weights)
    n = len(weights_sorted)
    return {
        "count": float(n),
        "mean": statistics.mean(weights_sorted),
        "p25": weights_sorted[int(n * 0.25)],
        "p50": weights_sorted[int(n * 0.50)],
        "p75": weights_sorted[int(n * 0.75)],
        "p95": weights_sorted[min(int(n * 0.95), n - 1)],
    }


def low_conf_run_lengths(series: list[float | None], threshold: float) -> list[int]:
    """统计 confidence < threshold 的连续段长度（None 视为不达标，参与连段）。"""
    runs: list[int] = []
    current = 0
    for c in series:
        low = c is None or c < threshold
        if low:
            current += 1
        else:
            if current > 0:
                runs.append(current)
                current = 0
    if current > 0:
        runs.append(current)
    return runs


def run_length_histogram(runs: list[int]) -> dict[str, int]:
    hist = {"1": 0, "2": 0, "3-5": 0, "6-10": 0, ">10": 0}
    for r in runs:
        if r == 1:
            hist["1"] += 1
        elif r == 2:
            hist["2"] += 1
        elif r <= 5:
            hist["3-5"] += 1
        elif r <= 10:
            hist["6-10"] += 1
        else:
            hist[">10"] += 1
    return hist


# ---------------------------------------------------------------------------
# 汇总输出
# ---------------------------------------------------------------------------


def audit_one_video(path: Path) -> dict[str, Any]:
    with path.open() as f:
        data = json.load(f)
    frames: list[dict[str, Any]] = data.get("frames", []) or []
    total = len(frames)
    duration = data.get("duration", 0.0)

    per_signal: dict[str, dict[str, Any]] = {}
    for key in ANGLE_SIGNALS + COORD_SIGNALS:
        series = collect_confidence_series(frames, key)
        buckets = bucket_distribution(series)
        weights = weight_stats(series)
        runs = low_conf_run_lengths(series, LOW_RUN_CONF_THRESHOLD)
        per_signal[key] = {
            "buckets": buckets,
            "weight_stats": weights,
            "run_lengths": {
                "count": len(runs),
                "max": max(runs) if runs else 0,
                "mean": statistics.mean(runs) if runs else 0.0,
                "hist": run_length_histogram(runs),
            },
        }

    # 汇总（对所有角度信号合并统计一份"整体画像"）
    combined_series: list[float | None] = []
    for key in ANGLE_SIGNALS:
        combined_series.extend(collect_confidence_series(frames, key))
    combined_buckets = bucket_distribution(combined_series)
    combined_weights = weight_stats(combined_series)

    return {
        "path": str(path),
        "total_frames": total,
        "duration": duration,
        "combined_angle_buckets": combined_buckets,
        "combined_angle_weight_stats": combined_weights,
        "per_signal": per_signal,
    }


def format_pct(n: int, total: int) -> str:
    if total <= 0:
        return "  0.0%"
    return f"{100.0 * n / total:5.1f}%"


def print_report(reports: list[dict[str, Any]]) -> None:
    print("=" * 78)
    print("Confidence-Aware Smoothing Audit (只读)")
    print("=" * 78)
    print()
    print("阈值来源：Sources/FallLineCore/Utilities.swift")
    print(f"  softConfidenceFloor   = {SOFT_FLOOR}")
    print(f"  softConfidenceCeiling = {SOFT_CEILING}")
    print(f"  minimumPoseScoreConfidence (run-length 判定) = {MIN_POSE_SCORE_CONF}")
    print()

    # ---- 每份 JSON 的整体画像 ----
    print("-" * 78)
    print("Section 1. 每份视频的整体（角度信号合并）置信度画像")
    print("-" * 78)
    print(f"{'video':<28}{'frms':>6}{'<0.15':>10}{'0.15-0.30':>12}"
          f"{'0.30-0.75':>12}{'>=0.75':>10}{'miss':>8}  w_mean p50 p95")
    for r in reports:
        b = r["combined_angle_buckets"]
        w = r["combined_angle_weight_stats"]
        total = sum(b.values())
        name = Path(r["path"]).name
        w_summary = ""
        if w:
            w_summary = f"  {w['mean']:.2f} {w['p50']:.2f} {w['p95']:.2f}"
        print(
            f"{name:<28}{r['total_frames']:>6}"
            f"{format_pct(b['<0.15'], total):>10}"
            f"{format_pct(b['0.15-0.30'], total):>12}"
            f"{format_pct(b['0.30-0.75'], total):>12}"
            f"{format_pct(b['>=0.75'], total):>10}"
            f"{format_pct(b['missing'], total):>8}"
            f"{w_summary}"
        )
    print()

    # ---- 每份 JSON 的低置信度 run-length ----
    print("-" * 78)
    print("Section 2. 低置信度连续段长度（conf < 0.30，按信号）")
    print("-" * 78)
    print(f"{'video':<12}{'signal':<24}{'runs':>5}{'max':>5}"
          f"{'mean':>7}{'r=1':>6}{'r=2':>6}{'r=3-5':>8}"
          f"{'r=6-10':>8}{'r>10':>7}")
    for r in reports:
        name = Path(r["path"]).stem
        for key in ANGLE_SIGNALS + COORD_SIGNALS:
            sig = r["per_signal"][key]
            rl = sig["run_lengths"]
            hist = rl["hist"]
            print(
                f"{name:<12}{key:<24}"
                f"{rl['count']:>5}{rl['max']:>5}{rl['mean']:>7.1f}"
                f"{hist['1']:>6}{hist['2']:>6}"
                f"{hist['3-5']:>8}{hist['6-10']:>8}{hist['>10']:>7}"
            )
        print()

    # ---- 结论提示 ----
    print("-" * 78)
    print("Section 3. 结论量化提示")
    print("-" * 78)
    print("""
关键读数：
  A. 0.30-0.75 段占比：1€ Filter 现在完全平等吸收这段样本。若占比 >30%，
     confidence-aware smoothing 的收益上限就在这里。
  B. <0.15 段占比：现在下游权重直接归 0（等于被 mask），但 1€ Filter 状态
     依然被这些样本更新（除非 value 是 None）——这是最直接的"污染源"。
  C. run-length ≥3 的连续段：P0 despike（3 帧窗）无法覆盖，1€ Filter 会持续
     被拽偏。若这种段在某个信号上 >5% 帧数，confidence-aware 的价值最高。
""")


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--json",
        nargs="*",
        type=Path,
        help="显式指定要审计的 JSON。缺省扫描 testvideo/*.json（不含子目录快照）。",
    )
    args = parser.parse_args()

    if args.json:
        paths = [p for p in args.json if p.exists()]
    else:
        root = Path(__file__).resolve().parent.parent
        paths = find_corpus_jsons(root)

    if not paths:
        raise SystemExit("未找到任何 JSON。请先跑 `swift run FallLineCLI testvideo/N.MP4` 生成。")

    reports = [audit_one_video(p) for p in paths]
    print_report(reports)


if __name__ == "__main__":
    main()
