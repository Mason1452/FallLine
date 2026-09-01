#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
stability_audit.py
==================

只读扫描 testvideo/ 下所有 AnalysisOutput JSON，量化算法稳定性 4 层贡献：

    P0 - 帧间关节抖动
         逐帧 leftKneeBendAngle / rightKneeBendAngle / bodyLeanAngle
         的相邻差绝对值 std，反映 Vision 关节输出的原始噪声
         被 PoseScorer 放大成分数抖动的程度

    P1 - 置信度阈值阶跃
         boardAnalysis.summary.confidence 分布中落在 [0.55, 0.85]
         过渡窗口的样本占比，反映当前 0.7 硬阈值造成的阶跃风险

    P2 - flow modulation 倍增器
         summary.flowModulationFactor 相对 1.0 的偏移量，
         以及 flowDirectionalStability / flowVelocitySmoothness / flowMotionCoherence
         塌陷为 0 的样本比例（FlowMetricsCalculator 已知的降级模式）

    P3 - sideslip 帧间跳动
         boardAnalysis.frames[i].kinematics.sideslipAngle 相邻差绝对值中位数
         已经作为 audit 一部分存在，这里做归一化拿来对比

汇总输出：
    - 每层贡献分（0-100，越高越是主要抖动贡献者）
    - 4 层排序，锁定"先改哪一层"

用法：
    python3 scripts/stability_audit.py

无副作用：不写任何非 stdout 的文件。
"""

from __future__ import annotations

import json
import math
import statistics
from pathlib import Path
from typing import Any


CONF_CENTER = 0.7
CONF_WINDOW = 0.15
CONF_LOW = CONF_CENTER - CONF_WINDOW
CONF_HIGH = CONF_CENTER + CONF_WINDOW


def find_all_analysis_jsons(root: Path) -> list[Path]:
    tv = root / "testvideo"
    return sorted(tv.rglob("*.json")) if tv.exists() else []


def _extract_angle_series(frames: list[dict[str, Any]], key: str) -> list[float]:
    out = []
    for f in frames:
        bp = f.get("bodyPose") or {}
        v = bp.get(key)
        if isinstance(v, dict):
            val = v.get("value")
            if isinstance(val, (int, float)) and math.isfinite(val):
                out.append(float(val))
    return out


def _adjacent_abs_diff(series: list[float]) -> list[float]:
    if len(series) < 2:
        return []
    return [abs(series[i] - series[i - 1]) for i in range(1, len(series))]


def p0_joint_jitter(frames: list[dict[str, Any]]) -> dict[str, float | None]:
    """
    P0: 关节角度逐帧抖动
    - 用相邻差绝对值的 median 反映"典型帧间跳动量"（对离群鲁棒）
    - 再折算到最终分数：knee 深度惩罚 4pts/10°
    """
    knee_l = _adjacent_abs_diff(_extract_angle_series(frames, "leftKneeBendAngle"))
    knee_r = _adjacent_abs_diff(_extract_angle_series(frames, "rightKneeBendAngle"))
    lean = _adjacent_abs_diff(_extract_angle_series(frames, "bodyLeanAngle"))
    calf_l = _adjacent_abs_diff(_extract_angle_series(frames, "leftCalfLeanAngle"))
    calf_r = _adjacent_abs_diff(_extract_angle_series(frames, "rightCalfLeanAngle"))

    def _median_or_none(xs: list[float]) -> float | None:
        return statistics.median(xs) if xs else None

    knee_jitter_all = knee_l + knee_r
    calf_jitter_all = calf_l + calf_r

    knee_med = _median_or_none(knee_jitter_all)
    lean_med = _median_or_none(lean)
    calf_med = _median_or_none(calf_jitter_all)

    return {
        "kneeAdjDiffMedian": knee_med,
        "leanAdjDiffMedian": lean_med,
        "calfAdjDiffMedian": calf_med,
        "kneeAdjDiffP90": statistics.quantiles(knee_jitter_all, n=10)[-1] if len(knee_jitter_all) >= 10 else None,
    }


def p1_threshold_proximity(board_summary_conf: float | None) -> dict[str, Any]:
    """
    P1: 置信度处于阈值过渡窗口的距离
    - 如果 conf 落在 [0.55, 0.85]，本视频的分数就对相机微移动/光照敏感
    """
    if board_summary_conf is None:
        return {"inTransitionWindow": False, "distanceToThreshold": None}
    in_window = CONF_LOW <= board_summary_conf <= CONF_HIGH
    return {
        "inTransitionWindow": in_window,
        "distanceToThreshold": abs(board_summary_conf - CONF_CENTER),
    }


def p2_flow_modulation(summary: dict[str, Any]) -> dict[str, Any]:
    """
    P2: flow modulation 倍增器的抖动贡献
    - flowModulationFactor 相对 1.0 的偏移（每 1% 偏移直接乘到最终分数上）
    - 三个 flow 子指标塌陷为 0 的情况：任意一个 = 0 就是降级信号
    """
    factor = summary.get("flowModulationFactor")
    coh = summary.get("flowMotionCoherence")
    stab = summary.get("flowDirectionalStability")
    smooth = summary.get("flowVelocitySmoothness")

    offset_from_1 = abs(factor - 1.0) if isinstance(factor, (int, float)) else None

    degradations: list[str] = []
    if stab == 0:
        degradations.append("directionalStability=0")
    if smooth == 0:
        degradations.append("velocitySmoothness=0")
    if coh == 0:
        degradations.append("motionCoherence=0")

    return {
        "flowModOffset": offset_from_1,
        "flowModPercent": (offset_from_1 * 100) if offset_from_1 is not None else None,
        "degradations": degradations,
        "isDegraded": len(degradations) > 0,
    }


def p3_sideslip_jitter(board_frames: list[dict[str, Any]]) -> dict[str, float | None]:
    """
    P3: sideslip 帧间跳动
    """
    series = []
    for f in board_frames:
        k = f.get("kinematics") or {}
        v = k.get("sideslipAngle")
        if isinstance(v, (int, float)) and math.isfinite(v):
            series.append(float(v))
    diffs = _adjacent_abs_diff(series)
    return {
        "sideslipAdjDiffMedian": statistics.median(diffs) if diffs else None,
        "sideslipAdjDiffP90": statistics.quantiles(diffs, n=10)[-1] if len(diffs) >= 10 else None,
        "sideslipStd": statistics.pstdev(series) if len(series) > 1 else None,
    }


def normalize(value: float | None, benchmark_lo: float, benchmark_hi: float) -> float | None:
    """把原始指标线性映射到 0-100 贡献分（超出边界截断）。"""
    if value is None:
        return None
    if benchmark_hi <= benchmark_lo:
        return 0.0
    x = (value - benchmark_lo) / (benchmark_hi - benchmark_lo)
    return max(0.0, min(100.0, x * 100.0))


def audit_one(path: Path) -> dict[str, Any]:
    try:
        with path.open() as f:
            data = json.load(f)
    except Exception as e:
        return {"file": str(path), "error": str(e)}

    summary = data.get("summary") or {}
    board = data.get("boardAnalysis") or {}
    board_summary = board.get("summary") or {}
    board_frames = board.get("frames") or []
    frames = data.get("frames") or []

    p0 = p0_joint_jitter(frames)
    p1 = p1_threshold_proximity(board_summary.get("confidence"))
    p2 = p2_flow_modulation(summary)
    p3 = p3_sideslip_jitter(board_frames)

    # 归一化贡献分（基准区间是经验值，反映"多少算大"）
    # P0: 关节角 median adj diff → 0° 无抖动 / 15° 严重抖动
    p0_score = normalize(p0["kneeAdjDiffMedian"], 0, 15)
    # P1: 距 0.7 阈值 < 0.15 视为窗口内，距离越近贡献越大
    if p1["inTransitionWindow"]:
        p1_score = 100.0 * (1 - (p1["distanceToThreshold"] or 0) / CONF_WINDOW)
    else:
        p1_score = 0.0
    # P2: flowMod 偏离 1.0 每 15% → 满分（对应约 ±13% 修正接近上限）
    p2_score = normalize(p2["flowModOffset"], 0, 0.15)
    if p2["isDegraded"]:
        # 塌陷加权：任意子指标 = 0 已经是明显降级
        p2_score = max(p2_score or 0, 50 + 20 * len(p2["degradations"]))
    # P3: sideslip adj diff median → 0° / 20° 严重
    p3_score = normalize(p3["sideslipAdjDiffMedian"], 0, 20)

    return {
        "file": str(path),
        "totalFrames": len(frames),
        "boardFrames": len(board_frames),
        # 原始指标
        "kneeAdjDiffMedian": p0["kneeAdjDiffMedian"],
        "leanAdjDiffMedian": p0["leanAdjDiffMedian"],
        "calfAdjDiffMedian": p0["calfAdjDiffMedian"],
        "kneeAdjDiffP90": p0["kneeAdjDiffP90"],
        "boardConf": board_summary.get("confidence"),
        "inTransitionWindow": p1["inTransitionWindow"],
        "distToThreshold": p1["distanceToThreshold"],
        "flowModFactor": summary.get("flowModulationFactor"),
        "flowModPercent": p2["flowModPercent"],
        "flowDegradations": p2["degradations"],
        "sideslipAdjDiffMedian": p3["sideslipAdjDiffMedian"],
        "sideslipAdjDiffP90": p3["sideslipAdjDiffP90"],
        "stabilityScore": summary.get("stabilityScore"),
        "scoreStdDev": summary.get("scoreStdDev"),
        "averageScore": summary.get("averageScore"),
        # 贡献分
        "p0Score": p0_score,
        "p1Score": p1_score,
        "p2Score": p2_score,
        "p3Score": p3_score,
    }


def _fmt(v: Any, w: int = 6, prec: int = 1) -> str:
    if v is None:
        return "-".rjust(w)
    if isinstance(v, bool):
        return ("Y" if v else "N").rjust(w)
    if isinstance(v, float):
        return f"{v:{w}.{prec}f}"
    return str(v).rjust(w)


def print_table(rows: list[dict[str, Any]]) -> None:
    print("\n== 每份 JSON 稳定性指标明细 ==")
    header = (
        f"{'file':<40} "
        f"{'kJit':>5} {'lJit':>5} {'cJit':>5} "
        f"{'conf':>5} {'win?':>4} "
        f"{'fMod':>5} {'degd':>4} "
        f"{'ssJt':>5} "
        f"{'stab':>5} {'sStd':>5} {'avg':>4} "
        f"| {'P0':>4} {'P1':>4} {'P2':>4} {'P3':>4}"
    )
    print(header)
    print("-" * len(header))
    for r in rows:
        deg_count = len(r["flowDegradations"])
        print(
            f"{r['file'][:40]:<40} "
            f"{_fmt(r['kneeAdjDiffMedian'], 5, 1)} "
            f"{_fmt(r['leanAdjDiffMedian'], 5, 1)} "
            f"{_fmt(r['calfAdjDiffMedian'], 5, 1)} "
            f"{_fmt(r['boardConf'], 5, 2)} "
            f"{_fmt(r['inTransitionWindow'], 4)} "
            f"{_fmt(r['flowModFactor'], 5, 2)} "
            f"{_fmt(deg_count, 4)} "
            f"{_fmt(r['sideslipAdjDiffMedian'], 5, 1)} "
            f"{_fmt(r['stabilityScore'], 5, 1)} "
            f"{_fmt(r['scoreStdDev'], 5, 1)} "
            f"{_fmt(r['averageScore'], 4, 0)} "
            f"| {_fmt(r['p0Score'], 4, 0)} {_fmt(r['p1Score'], 4, 0)} "
            f"{_fmt(r['p2Score'], 4, 0)} {_fmt(r['p3Score'], 4, 0)}"
        )
    print(
        "\n列说明: kJit=knee相邻差中位数° lJit=lean° cJit=calf° "
        "conf=boardConf win?=是否在0.55-0.85窗口 fMod=flowModFactor "
        "degd=flow子指标塌陷数 ssJt=sideslip相邻差中位数° "
        "stab=stabilityScore sStd=scoreStdDev "
        "P0~P3=各层贡献分(0-100)"
    )


def summarize(rows: list[dict[str, Any]]) -> None:
    total = len(rows)
    print(f"\n== 汇总：4 层稳定性贡献排序 ==")
    print(f"总样本数: {total}\n")

    def _mean_score(key: str) -> float:
        vals = [r[key] for r in rows if r[key] is not None]
        return statistics.fmean(vals) if vals else 0.0

    scores = {
        "P0 关节角帧间抖动 (median knee adj diff)": _mean_score("p0Score"),
        "P1 置信度落在阈值窗口": _mean_score("p1Score"),
        "P2 flow modulation 倍增器 (含塌陷加权)": _mean_score("p2Score"),
        "P3 sideslip 帧间跳动": _mean_score("p3Score"),
    }
    ordered = sorted(scores.items(), key=lambda x: -x[1])
    print("平均贡献分排序（越高越是主要抖动源）：")
    for i, (name, s) in enumerate(ordered, 1):
        bar = "█" * int(s / 2)
        print(f"  {i}. {name}: {s:.1f}  {bar}")

    # 分位数辅助判断
    p0_vals = sorted([r["kneeAdjDiffMedian"] for r in rows if r["kneeAdjDiffMedian"] is not None])
    if p0_vals:
        print(f"\nP0 关节抖动分布 (kneeAdjDiffMedian, °):")
        print(f"  min={p0_vals[0]:.2f} / median={statistics.median(p0_vals):.2f} / "
              f"max={p0_vals[-1]:.2f}")

    p1_hits = [r for r in rows if r["inTransitionWindow"]]
    print(f"\nP1 命中阈值窗口 [{CONF_LOW}, {CONF_HIGH}] 的样本: "
          f"{len(p1_hits)}/{total} ({len(p1_hits)/total*100:.0f}%)")
    for r in p1_hits:
        print(f"    {Path(r['file']).name} boardConf={r['boardConf']:.3f}")

    p2_degraded = [r for r in rows if r["flowDegradations"]]
    print(f"\nP2 flow 子指标塌陷为 0 的样本: "
          f"{len(p2_degraded)}/{total} ({len(p2_degraded)/total*100:.0f}%)")
    from collections import Counter
    all_degs = Counter()
    for r in p2_degraded:
        for d in r["flowDegradations"]:
            all_degs[d] += 1
    for name, cnt in all_degs.most_common():
        print(f"    {name}: {cnt} 样本")

    p2_offsets = [r["flowModPercent"] for r in rows if r["flowModPercent"] is not None]
    if p2_offsets:
        print(f"\nP2 flowModFactor 相对 1.0 偏移分布 (%):")
        print(f"  min={min(p2_offsets):.1f} / median={statistics.median(p2_offsets):.1f} / "
              f"max={max(p2_offsets):.1f}")

    p3_vals = sorted([r["sideslipAdjDiffMedian"] for r in rows if r["sideslipAdjDiffMedian"] is not None])
    if p3_vals:
        print(f"\nP3 sideslip 帧间跳动分布 (sideslipAdjDiffMedian, °):")
        print(f"  min={p3_vals[0]:.2f} / median={statistics.median(p3_vals):.2f} / "
              f"max={p3_vals[-1]:.2f}")


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    files = find_all_analysis_jsons(root)
    if not files:
        print("no analysis JSON found under testvideo/")
        return
    print(f"扫描到 {len(files)} 份 AnalysisOutput JSON\n")

    rows: list[dict[str, Any]] = []
    for p in files:
        r = audit_one(p)
        if "error" in r:
            print(f"! {p}: {r['error']}")
            continue
        r["file"] = str(p.relative_to(root))
        rows.append(r)

    print_table(rows)
    summarize(rows)


if __name__ == "__main__":
    main()
