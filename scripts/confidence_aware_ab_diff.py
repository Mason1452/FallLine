#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
confidence_aware_ab_diff.py
===========================

方案 α（confidence-aware smoothing）主 corpus A/B 对照报告脚本（只读）。

用法
----
    python3 scripts/confidence_aware_ab_diff.py

前置条件
--------
需要 `scripts/alpha_ab_run.sh` 已跑完，且以下目录都各含 6 份 JSON：
- testvideo/baseline_alpha_off/{1..6}.json      # 旧行为
- testvideo/baseline_alpha_on/{1..6}.json       # confidence-aware ON

对比维度
--------
从每份 JSON 的 `summary` 抽取核心量化指标：
  * averageScore                    # 全视频对外展示的最终分
  * rawPoseAverageScore             # 未经证据封顶的原始姿态均值
  * bestThirdAverageScore           # 前 1/3 高光均值（评价"上限"）
  * evidenceCappedScore             # 证据封顶后的分（边/板/时长综合）
  * flowModulationFactor            # 光流三指标合成调制系数 (0.87~1.13)
  * flowMotionCoherence             # 光流方向一致性 (0~100)
  * flowVelocitySmoothness          # 光流速度平滑度 (0~100)
  * flowDirectionalStability        # 光流方向稳定性 (0~100)
  * stabilityScore                  # 姿态稳定性分 (0~100)
  * scoreStdDev                     # 分数波动标准差
  * scoreConsistencyScore           # 分数一致性分
  * overallLevel                    # 中文等级标签

以及顶层：
  * centerOfMassAnalysis.mainIssue  # 顶层重心主问题标签（P9-B 已加确定性排序）
  * turnAnalysis.segments 数         # 转弯段数量
  * highlightMoments 数              # 高光片段数量

回归风险量化
-----------
针对每个指标输出:
  * OFF (baseline) 值
  * ON  (aware)   值
  * Δ = ON - OFF
  * |Δ| 是否 > 阈值（averageScore ≥ 3 分算显著）

无副作用：不写文件、不改任何生产代码。
"""

from __future__ import annotations

import json
import statistics
from pathlib import Path
from typing import Any


REPO = Path(__file__).resolve().parent.parent
OFF_DIR = REPO / "testvideo" / "baseline_alpha_off"
ON_DIR = REPO / "testvideo" / "baseline_alpha_on"

VIDEO_STEMS = ["1", "2", "3", "4", "5", "6"]

# 数值指标（float 类型）+ 打印格式
NUMERIC_FIELDS: list[tuple[str, str, str, float]] = [
    # (json key, label, format, significant delta threshold)
    ("averageScore",             "对外分 avg",       "%6.2f", 3.0),
    ("rawPoseAverageScore",      "原始姿态均值",     "%6.2f", 3.0),
    ("bestThirdAverageScore",    "前1/3 均值",       "%6.2f", 3.0),
    ("evidenceCappedScore",      "证据封顶分",       "%6.2f", 3.0),
    ("stabilityScore",           "稳定性分",         "%6.2f", 3.0),
    ("scoreStdDev",              "分数 stddev",     "%6.2f", 2.0),
    ("scoreConsistencyScore",    "一致性分",         "%6.2f", 3.0),
    ("flowModulationFactor",     "光流调制系数",     "%6.3f", 0.02),
    ("flowMotionCoherence",      "光流一致性",       "%6.2f", 3.0),
    ("flowVelocitySmoothness",   "光流速度平滑",     "%6.2f", 3.0),
    ("flowDirectionalStability", "光流方向稳定",     "%6.2f", 3.0),
]

# 字符串指标
STRING_FIELDS: list[tuple[str, str]] = [
    ("overallLevel", "等级标签"),
]


def load(path: Path) -> dict[str, Any]:
    with path.open() as f:
        return json.load(f)


def fmt(v: float | None, spec: str) -> str:
    if v is None:
        return "  --  "
    return spec % v


def cell_delta(v_off: float, v_on: float, spec: str) -> str:
    delta = v_on - v_off
    sign = "+" if delta > 0 else ("" if delta < 0 else " ")
    return f"{sign}{spec % delta}"


def main() -> None:
    if not OFF_DIR.exists() or not ON_DIR.exists():
        raise SystemExit(f"缺失快照目录：{OFF_DIR} 或 {ON_DIR}\n请先跑 scripts/alpha_ab_run.sh")

    # 逐份 JSON 加载
    pairs: list[tuple[str, dict[str, Any], dict[str, Any]]] = []
    for stem in VIDEO_STEMS:
        off = load(OFF_DIR / f"{stem}.json")
        on  = load(ON_DIR  / f"{stem}.json")
        pairs.append((stem, off, on))

    # ---- Section 1. 每份视频的数值指标 OFF vs ON ----
    print("=" * 100)
    print(" 方案 α confidence-aware A/B 主 corpus 对照")
    print("=" * 100)
    print()

    for key, label, spec, _thresh in NUMERIC_FIELDS:
        print(f"### {label} ({key})")
        print()
        print(f"| video | OFF   | ON    | Δ (ON-OFF) |")
        print(f"|-------|-------|-------|------------|")
        for stem, off, on in pairs:
            v_off = off["summary"].get(key)
            v_on  = on["summary"].get(key)
            if v_off is None or v_on is None:
                print(f"|   {stem}   |  --   |  --   |     --     |")
                continue
            print(f"|   {stem}   | {fmt(v_off, spec)} | {fmt(v_on, spec)} | {cell_delta(v_off, v_on, spec)} |")
        # 汇总 mean / max|Δ|
        deltas = [
            on["summary"][key] - off["summary"][key]
            for _, off, on in pairs
            if off["summary"].get(key) is not None and on["summary"].get(key) is not None
        ]
        if deltas:
            mean_delta = statistics.mean(deltas)
            max_abs = max(abs(d) for d in deltas)
            print(f"|  --   |  --   |  --   | mean={mean_delta:+.3f}, max|Δ|={max_abs:.3f} |")
        print()

    # ---- Section 2. 字符串指标 ----
    print()
    print("=" * 100)
    print(" 字符串指标（等级 / 主问题标签）")
    print("=" * 100)
    print()

    for key, label in STRING_FIELDS:
        print(f"### {label} ({key})")
        print()
        print(f"| video | OFF                     | ON                      | 变更 |")
        print(f"|-------|-------------------------|-------------------------|------|")
        for stem, off, on in pairs:
            v_off = off["summary"].get(key, "-")
            v_on  = on["summary"].get(key, "-")
            changed = "✱" if v_off != v_on else " "
            print(f"|   {stem}   | {v_off:<23} | {v_on:<23} |  {changed}   |")
        print()

    # 顶层 centerOfMassAnalysis.mainIssue（P9-B 守护点）
    print(f"### 顶层重心主问题（centerOfMassAnalysis.mainIssue，P9-B 稳定性守护）")
    print()
    print(f"| video | OFF                     | ON                      | 变更 |")
    print(f"|-------|-------------------------|-------------------------|------|")
    for stem, off, on in pairs:
        v_off = (off.get("centerOfMassAnalysis") or {}).get("mainIssue", "-")
        v_on  = (on.get("centerOfMassAnalysis") or {}).get("mainIssue", "-")
        changed = "✱" if v_off != v_on else " "
        print(f"|   {stem}   | {v_off:<23} | {v_on:<23} |  {changed}   |")
    print()

    # 转弯段数量
    print(f"### 转弯段数量（turnAnalysis.segments count）")
    print()
    print(f"| video | OFF | ON  | Δ   |")
    print(f"|-------|-----|-----|-----|")
    for stem, off, on in pairs:
        seg_off = len((off.get("turnAnalysis") or {}).get("segments") or [])
        seg_on  = len((on.get("turnAnalysis") or {}).get("segments") or [])
        print(f"|   {stem}   | {seg_off:>3d} | {seg_on:>3d} | {seg_on - seg_off:+3d} |")
    print()

    # 高光片段数量
    print(f"### 高光片段数量（highlightMoments count）")
    print()
    print(f"| video | OFF | ON  | Δ   |")
    print(f"|-------|-----|-----|-----|")
    for stem, off, on in pairs:
        h_off = len(off.get("highlightMoments") or [])
        h_on  = len(on.get("highlightMoments") or [])
        print(f"|   {stem}   | {h_off:>3d} | {h_on:>3d} | {h_on - h_off:+3d} |")
    print()

    # ---- Section 3. 关键回归风险快照 ----
    print()
    print("=" * 100)
    print(" 关键回归风险快照（averageScore + 阈值告警）")
    print("=" * 100)
    print()
    print("规则：averageScore |Δ| ≥ 3.0 触发 ⚠️；stabilityScore |Δ| ≥ 3.0 触发 ⚠️；等级标签变化触发 ⚠️")
    print()
    print("| video | ΔavgScore | Δstab   | 等级 OFF→ON      | 风险 |")
    print("|-------|-----------|---------|------------------|------|")
    for stem, off, on in pairs:
        avg_off  = off["summary"]["averageScore"]
        avg_on   = on["summary"]["averageScore"]
        stab_off = off["summary"]["stabilityScore"]
        stab_on  = on["summary"]["stabilityScore"]
        level_off = off["summary"]["overallLevel"]
        level_on  = on["summary"]["overallLevel"]

        d_avg = avg_on - avg_off
        d_stab = stab_on - stab_off
        level_change = level_off != level_on

        flags: list[str] = []
        if abs(d_avg) >= 3.0:
            flags.append("avg")
        if abs(d_stab) >= 3.0:
            flags.append("stab")
        if level_change:
            flags.append("level")
        risk = "⚠️ " + ",".join(flags) if flags else "  "

        print(f"|   {stem}   | {d_avg:+9.2f} | {d_stab:+7.2f} | {level_off:<8}→{level_on:<8} | {risk} |")
    print()
    print("说明：Δ = ON - OFF。正数 = confidence-aware 抬高，负数 = confidence-aware 压低。")


if __name__ == "__main__":
    main()
