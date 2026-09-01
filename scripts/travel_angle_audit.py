#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
travel_angle_audit.py
=====================

只读扫描仓库内所有 AnalysisOutput JSON，量化 travelAngle → sideslip → cap 链路的行为：

    corpus:
      - testvideo/1..6.json                  (主要产物，最新)
      - testvideo/_b_3d_baseline/1..6.json   (3D baseline 快照)
      - testvideo/_c_2d/1..6.json            (2D 快照)
      - testvideo/_p1_baseline/1..6.json     (p1 baseline 快照)

    对每份 JSON 输出：
      - 总帧数 / 板身分析帧数
      - travelAngle / sideslipAngle 均值与分布
      - carvingConfidence 均值 + 高置信度帧占比
      - boardAnalysis.summary.confidence（Core 用来判定 cap 的字段，非帧级均值）
      - 是否满足 cap 判定门槛：summary.confidence ≥ 0.7 && kinematicDuration ≥ 5.0s
      - predictedCap: 判定条件满足时的 cap 值（none / 70(sideslip≥30) / 58(sideslip≥45) / 62(低置信度短片)）
      - effectiveCap: cap 实际生效（cap < evidenceCappedScore）时的 cap 值，否则 None
      - summary.rawPoseAverageScore vs evidenceCappedScore 的实际差值

    汇总输出：
      - predictedCap 触发率  (判定条件满足)
      - effectiveCap 触发率  (实际压低分数)
      - 各 cap 分类下 raw→capped 分数降幅分布
      - 低置信度但仍被 cap 的样本（潜在误判候选）
      - sideslip 波动过大候选（travelAngle 抖动放大）

用法：
    python3 scripts/travel_angle_audit.py

无副作用：不写任何非 stdout 的文件。

注：
    与 Core [applyBoardEvidenceCaps](Sources/FallLineCore/VideoAnalyzer.swift#L469-L477) +
    [boardKinematicHighScoreCap](Sources/FallLineCore/Utilities.swift#L215-L242) 严格对齐。
    reliable_duration 用 `data.duration` 近似（Core 用 reliablePoseDuration，
    需要访问帧级 pose confidence，JSON 未直接暴露；对本 corpus 影响可忽略——
    kinematicDuration 通常已经是主要门槛）。
"""

from __future__ import annotations

import json
import math
import statistics
from pathlib import Path
from typing import Any


# 与 Core Utilities.swift 严格保持一致的阈值
CONF_THRESHOLD_FOR_HIGH_SCORE = 0.7
MIN_KINEMATIC_DURATION = 5.0
SHORT_CLIP_DURATION = 10.0
HIGH_SIDESLIP_ANGLE = 30.0
DOMINANT_SIDESLIP_ANGLE = 45.0
HIGH_SIDESLIP_SCORE_CAP = 70.0
DOMINANT_SIDESLIP_SCORE_CAP = 58.0
LOW_BOARD_EVIDENCE_CAP = 62.0


def find_all_analysis_jsons(root: Path) -> list[Path]:
    """定位所有 testvideo/*.json（含子目录 baseline 快照）。"""
    candidates: list[Path] = []
    tv = root / "testvideo"
    if tv.exists():
        for p in tv.rglob("*.json"):
            candidates.append(p)
    return sorted(candidates)


def kinematic_stats(frames: list[dict[str, Any]]) -> dict[str, Any]:
    """从 boardAnalysis.frames 计算聚合指标（口径与 Core 一致）。"""
    kins = [f.get("kinematics") for f in frames if isinstance(f.get("kinematics"), dict)]
    if not kins:
        return {"count": 0}

    def _extract(key: str) -> list[float]:
        vals = []
        for k in kins:
            v = k.get(key)
            if isinstance(v, (int, float)) and math.isfinite(v):
                vals.append(float(v))
        return vals

    travel = _extract("travelAngle")
    sideslip = _extract("sideslipAngle")
    carving = _extract("carvingConfidence")
    conf = _extract("confidence")

    times = [f.get("time") for f in frames if isinstance(f.get("time"), (int, float))]
    kinematic_duration = (max(times) - min(times)) if len(times) >= 2 else 0.0

    def _mean(xs: list[float]) -> float | None:
        return statistics.fmean(xs) if xs else None

    high_carving_ratio = (
        sum(1 for c in carving if c >= 60) / len(carving) if carving else None
    )
    high_conf_ratio = (
        sum(1 for c in conf if c >= 0.7) / len(conf) if conf else None
    )

    return {
        "count": len(kins),
        "kinematicDuration": kinematic_duration,
        "avgTravelAngle": _mean(travel),
        "avgSideslipAngle": _mean(sideslip),
        "avgCarvingConfidence": _mean(carving),
        "avgObservationConfidence": _mean(conf),
        "highCarvingRatio": high_carving_ratio,
        "highConfidenceRatio": high_conf_ratio,
        "sideslipStd": statistics.pstdev(sideslip) if len(sideslip) > 1 else None,
        "travelStd": statistics.pstdev(travel) if len(travel) > 1 else None,
    }


def predicted_cap(
    board_summary_conf: float | None,
    stats: dict[str, Any],
    reliable_duration: float,
    has_stable_baseline: bool,
) -> tuple[float | None, str]:
    """
    严格复现 Core boardKinematicHighScoreCap 的分支逻辑，返回 (cap, 理由)。

    与实际 Core 的差异：
    - Core 使用 `boardAnalysis.summary.confidence`（这里通过 board_summary_conf 传入）
    - Core 用 reliablePoseDuration 判定短片，本函数用 data.duration 近似
    - Core 在有 stableBaseline 时完全跳过 cap（[applyBoardEvidenceCaps#L474](Sources/FallLineCore/VideoAnalyzer.swift#L474)）
    """
    if has_stable_baseline:
        return (None, "stable_baseline_present_skip_cap")

    sideslip = stats.get("avgSideslipAngle")
    duration = stats.get("kinematicDuration", 0.0)

    if sideslip is None:
        return (None, "no_sideslip")

    if board_summary_conf is None or board_summary_conf < CONF_THRESHOLD_FOR_HIGH_SCORE:
        if reliable_duration < SHORT_CLIP_DURATION:
            return (LOW_BOARD_EVIDENCE_CAP, "low_confidence_short_clip → 62")
        return (None, "low_confidence_long_clip_no_cap")

    if duration < MIN_KINEMATIC_DURATION:
        return (None, "duration_too_short")

    if sideslip >= DOMINANT_SIDESLIP_ANGLE:
        return (DOMINANT_SIDESLIP_SCORE_CAP, f"sideslip {sideslip:.1f}° ≥ 45° → 58")
    if sideslip >= HIGH_SIDESLIP_ANGLE:
        return (HIGH_SIDESLIP_SCORE_CAP, f"sideslip {sideslip:.1f}° ≥ 30° → 70")
    return (None, f"sideslip {sideslip:.1f}° < 30° no_cap")


def audit_one(path: Path) -> dict[str, Any]:
    try:
        with path.open() as f:
            data = json.load(f)
    except Exception as e:
        return {"file": str(path), "error": str(e)}

    duration = float(data.get("duration") or 0.0)
    summary = data.get("summary") or {}
    board = data.get("boardAnalysis") or {}
    board_summary = board.get("summary") or {}
    board_frames = board.get("frames") or []
    stats = kinematic_stats(board_frames)

    # Core 用 boardAnalysis.summary.confidence 而不是帧级平均——严格对齐 Utilities.swift#L222
    board_summary_conf = board_summary.get("confidence")
    has_stable_baseline = "stableCarvingBaseline" in summary

    cap_value, cap_reason = predicted_cap(
        board_summary_conf=board_summary_conf,
        stats=stats,
        reliable_duration=duration,
        has_stable_baseline=has_stable_baseline,
    )

    raw = summary.get("rawPoseAverageScore")
    capped = summary.get("evidenceCappedScore")
    final = summary.get("averageScore")

    # effectiveCap: Core 里 applyBoardEvidenceCaps 用 min(score, cap)，
    # 只有 cap < 输入 score 时 cap 才真的生效。
    # 输入 score 是 evidenceCappedScore（cap 层是链路最后一步）。
    effective_cap: float | None = None
    effective_delta: float | None = None
    if cap_value is not None and isinstance(capped, (int, float)):
        if cap_value < capped:
            effective_cap = cap_value
            effective_delta = capped - cap_value

    delta_raw_to_capped = None
    if isinstance(raw, (int, float)) and isinstance(capped, (int, float)):
        delta_raw_to_capped = raw - capped

    return {
        "file": str(path),  # 稍后由 main 转成相对路径
        "duration": duration,
        "totalFrames": data.get("totalFrames"),
        "boardFrameCount": stats.get("count"),
        "kinematicDuration": stats.get("kinematicDuration"),
        "avgTravelAngle": stats.get("avgTravelAngle"),
        "avgSideslipAngle": stats.get("avgSideslipAngle"),
        "sideslipStd": stats.get("sideslipStd"),
        "travelStd": stats.get("travelStd"),
        "avgCarvingConfidence": stats.get("avgCarvingConfidence"),
        "avgObservationConfidence": stats.get("avgObservationConfidence"),
        "boardSummaryConfidence": board_summary_conf,
        "hasStableBaseline": has_stable_baseline,
        "highCarvingRatio": stats.get("highCarvingRatio"),
        "highConfidenceRatio": stats.get("highConfidenceRatio"),
        "predictedCap": cap_value,
        "capReason": cap_reason,
        "effectiveCap": effective_cap,
        "effectiveCapDelta": effective_delta,
        "rawPoseAverageScore": raw,
        "evidenceCappedScore": capped,
        "averageScore": final,
        "deltaRawToCapped": delta_raw_to_capped,
        "overallLevel": summary.get("overallLevel"),
    }


def _fmt(v: Any, w: int = 8, prec: int = 2) -> str:
    if v is None:
        return "-".rjust(w)
    if isinstance(v, float):
        return f"{v:{w}.{prec}f}"
    return str(v).rjust(w)


def print_table(rows: list[dict[str, Any]]) -> None:
    print("\n== 每份 JSON 明细 ==")
    header = (
        f"{'file':<40} {'dur':>6} {'kDur':>6} "
        f"{'travel':>8} {'sideslp':>8} {'sstd':>6} "
        f"{'carv':>6} {'sumCf':>6} {'hCarv%':>6} {'hCnf%':>6} "
        f"{'pcap':>5} {'ecap':>5} {'raw':>5} {'capd':>5} {'avg':>5} {'Δeff':>5}"
    )
    print(header)
    print("-" * len(header))
    for r in rows:
        pcap = f"{r['predictedCap']:.0f}" if isinstance(r["predictedCap"], (int, float)) else "-"
        ecap = f"{r['effectiveCap']:.0f}" if isinstance(r["effectiveCap"], (int, float)) else "-"
        print(
            f"{r['file'][:40]:<40} "
            f"{_fmt(r['duration'], 6, 1)} "
            f"{_fmt(r['kinematicDuration'], 6, 1)} "
            f"{_fmt(r['avgTravelAngle'], 8, 1)} "
            f"{_fmt(r['avgSideslipAngle'], 8, 1)} "
            f"{_fmt(r['sideslipStd'], 6, 1)} "
            f"{_fmt(r['avgCarvingConfidence'], 6, 1)} "
            f"{_fmt(r['boardSummaryConfidence'], 6, 2)} "
            f"{_fmt((r['highCarvingRatio'] or 0)*100, 6, 0)} "
            f"{_fmt((r['highConfidenceRatio'] or 0)*100, 6, 0)} "
            f"{pcap:>5} "
            f"{ecap:>5} "
            f"{_fmt(r['rawPoseAverageScore'], 5, 0)} "
            f"{_fmt(r['evidenceCappedScore'], 5, 0)} "
            f"{_fmt(r['averageScore'], 5, 0)} "
            f"{_fmt(r['effectiveCapDelta'], 5, 1)}"
        )
    print(
        "\n列说明: pcap=predictedCap (判定条件满足), "
        "ecap=effectiveCap (cap < capd 才生效), "
        "Δeff=capd-effectiveCap (cap 实际压低的分数)"
    )


def summarize(rows: list[dict[str, Any]]) -> None:
    total = len(rows)
    predicted = [r for r in rows if r["predictedCap"] is not None]
    effective = [r for r in rows if r["effectiveCap"] is not None]
    print(f"\n== 汇总 ==")
    print(f"总样本数: {total}")
    print(
        f"predictedCap 触发数: {len(predicted)}  ({len(predicted)/total*100:.1f}%)  "
        f"[判定条件满足，但 cap 值可能 ≥ evidenceCappedScore 而不实际生效]"
    )
    print(
        f"effectiveCap 触发数: {len(effective)}  ({len(effective)/total*100:.1f}%)  "
        f"[cap 实际压低了 evidenceCappedScore，与 Core 生产行为一致]"
    )

    if effective:
        deltas = [r["effectiveCapDelta"] for r in effective if r["effectiveCapDelta"] is not None]
        if deltas:
            print(
                f"effectiveCap 平均压低: {statistics.fmean(deltas):.1f} 分  "
                f"(最大 {max(deltas):.1f} / 最小 {min(deltas):.1f})"
            )

    if not predicted:
        return

    by_reason: dict[str, list[dict[str, Any]]] = {}
    for r in predicted:
        reason_key = r["capReason"].split(" ")[0]
        by_reason.setdefault(reason_key, []).append(r)
    for reason, rs in by_reason.items():
        print(f"\n  分类 [{reason}] {len(rs)} 样本:")
        for r in rs:
            eff_marker = "★" if r["effectiveCap"] is not None else " "
            print(
                f"   {eff_marker}{r['file']:<40} sideslip={_fmt(r['avgSideslipAngle'],6,1)}° "
                f"sumCnf={_fmt(r['boardSummaryConfidence'],6,2)} "
                f"pcap={_fmt(r['predictedCap'],4,0)}  "
                f"capd={_fmt(r['evidenceCappedScore'],5,0)}  "
                f"avg={_fmt(r['averageScore'],5,0)}  raw={_fmt(r['rawPoseAverageScore'],5,0)}"
            )
    print("\n  ★ 表示 cap 实际生效（cap < evidenceCappedScore）")

    # 潜在误判候选：置信度低于当前 cap 阈值但仍被 cap 到某个值（含低置信度短片分支）
    suspects = [
        r for r in predicted
        if (r["boardSummaryConfidence"] or 0) < CONF_THRESHOLD_FOR_HIGH_SCORE
        and r["effectiveCap"] is not None
    ]
    if suspects:
        print(f"\n== 潜在误判候选（sumCnf<{CONF_THRESHOLD_FOR_HIGH_SCORE} 且 effectiveCap 生效）: {len(suspects)} ==")
        for r in suspects:
            print(
                f"    {r['file']} sumCnf={r['boardSummaryConfidence']:.2f} "
                f"sideslip={r['avgSideslipAngle']:.1f}° effectiveCap={r['effectiveCap']:.0f}"
            )

    # sideslip 高波动候选：sstd > 25° 表示逐帧极不稳定
    volatile = [r for r in rows if (r["sideslipStd"] or 0) > 25]
    if volatile:
        print(f"\n== sideslip 波动过大候选（sstd>25°，travelAngle 抖动放大）: {len(volatile)} ==")
        for r in volatile:
            print(
                f"    {r['file']} sstd={r['sideslipStd']:.1f}° "
                f"travelStd={_fmt(r['travelStd'],6,1)}° "
                f"avg sideslip={r['avgSideslipAngle']:.1f}°"
            )


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
        # 简化文件路径显示为相对根路径的形式
        r["file"] = str(p.relative_to(root))
        rows.append(r)

    print_table(rows)
    summarize(rows)


if __name__ == "__main__":
    main()
