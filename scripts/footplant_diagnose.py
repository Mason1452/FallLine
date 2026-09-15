#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
footplant_diagnose.py
=====================

Foot-Plant Stabilisation 可行性诊断（只诊断，不改生产代码）。

背景
----
P8-A (2026-09-08) 实测主 corpus 6 份全部 sideslip 42-53°（含已确认刻滑样本），
判定为 ~40-50° 系统偏差，因此退役 sideslip 高分 cap。本脚本检验借鉴
perfanalysis/pose2sim "Foot-Plant Stabilisation" 的修复思路：
在低速（脚稳定滑行 / 切换支撑）窗口锚定脚踝，用窗口内稳定的板身角修正
行进方向，能否收敛该系统偏差。

数据（全部来自已生成的 testvideo/*.json，无需重新跑 Vision）
-----------------------------------------------------------
- boardAnalysis.frames[].observation.centerX/Y : 脚踝中心归一化坐标（板身锚点）
- boardAnalysis.frames[].kinematics           : boardAngle/travelAngle/sideslipAngle/conf
- frames[].skiMetrics.edgeQualityScore        : 立刃质量的独立判据（按 time 对齐）
boardAnalysis 帧在部分视频稀疏/不连续（v4 仅 25 帧、v3 有 1.6s 断档），
因此瞬时速度按相邻 boardAnalysis 帧的真实 Δt 归一化为「归一化位移/秒」。

分析
----
1. 逐帧速度 v = |Δ(ankleCenter)| / Δt；vA/vB 速度分桶（默认阈值 0.05/s、0.15/s）。
2. 核心检验——速度与板身角稳定性的关系：
   低速帧的 boardAngle 帧间跳动是否更小（foot-plant 时板身指向更可信）。
3. 核心检验——速度与 sideslip 的关系：
   刻滑样本（v2/v3/v6，edgeQuality 高）在低速窗口 sideslip 是否反而收敛到小角度；
   若低速帧 sideslip 依旧 40°+，则 foot-plant 锚定无法修复系统偏差（No-Go）。
4. boardAngle vs travelAngle 一致性：分别在低速/高速桶内统计
   axisAngleDifference，定位 40-50° 偏差主要来自哪一侧（板身角 or 行进方向）。
5. 输出每视频低速段 run 列表（持续帧数），供后续锚定算法设计参考。

用法
----
    python3 scripts/footplant_diagnose.py                # 主 corpus 6 份
    python3 scripts/footplant_diagnose.py testvideo/1.json
    python3 scripts/footplant_diagnose.py --slow 0.05 --fast 0.15
"""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTVIDEO = ROOT / "testvideo"
DEFAULT_JSONS = [TESTVIDEO / f"{i}.json" for i in range(1, 7)]


def axis_angle_diff(a: float, b: float) -> float:
    """复刻 BoardDirectionAnalyzer.axisAngleDifference（°），范围 [0,90]。"""
    raw = abs((a - b + 180.0) % 360.0 - 180.0)
    return 180.0 - raw if raw > 90.0 else raw


def pct(values, q):
    if not values:
        return float("nan")
    s = sorted(values)
    i = max(0, min(len(s) - 1, int(round(q * (len(s) - 1)))))
    return s[i]


def load_frames(path: Path):
    data = json.loads(path.read_text())
    edge_by_time = {}
    for f in data.get("frames", []):
        sm = f.get("skiMetrics") or {}
        if "edgeQualityScore" in sm:
            edge_by_time[f["time"]] = sm["edgeQualityScore"]

    recs = []
    for bf in data.get("boardAnalysis", {}).get("frames", []):
        obs = bf.get("observation") or {}
        kin = bf.get("kinematics")
        if obs.get("centerX") is None:
            continue
        recs.append({
            "time": bf["time"],
            "ax": obs["centerX"],
            "ay": obs["centerY"],
            "board": kin["boardAngle"] if kin else None,
            "travel": kin["travelAngle"] if kin else None,
            "slip": kin["sideslipAngle"] if kin else None,
            "conf": kin["confidence"] if kin else None,
            "edge": edge_by_time.get(bf["time"]),
        })
    return recs


def enrich_speed(recs):
    """按真实 Δt 计算每帧到下一帧的归一化速度（/秒）。"""
    for i, r in enumerate(recs):
        if i + 1 >= len(recs):
            r["speed"] = None
            r["board_jump"] = None
            continue
        n = recs[i + 1]
        dt = n["time"] - r["time"]
        if dt <= 0:
            r["speed"] = None
        else:
            d = ((n["ax"] - r["ax"]) ** 2 + (n["ay"] - r["ay"]) ** 2) ** 0.5
            r["speed"] = d / dt
        if r["board"] is not None and n["board"] is not None:
            r["board_jump"] = axis_angle_diff(r["board"], n["board"])
        else:
            r["board_jump"] = None


def summarize_bucket(rows, label):
    def col(key):
        return [r[key] for r in rows if isinstance(r.get(key), (int, float))]

    speeds = col("speed")
    slips = col("slip")
    jumps = col("board_jump")
    diffs = [axis_angle_diff(r["board"], r["travel"])
             for r in rows if r.get("board") is not None and r.get("travel") is not None]
    edges = col("edge")
    confs = col("conf")
    print(f"  [{label}] n={len(rows)}")
    if speeds:
        print(f"    speed(归一化/s)  mean={statistics.fmean(speeds):.4f} "
              f"p50={pct(speeds,.5):.4f} p90={pct(speeds,.9):.4f}")
    if jumps:
        print(f"    boardAngle 帧跳  mean={statistics.fmean(jumps):.2f}° "
              f"p50={pct(jumps,.5):.2f}° p90={pct(jumps,.9):.2f}°")
    if diffs:
        print(f"    board-travel 夹角 mean={statistics.fmean(diffs):.2f}° "
              f"p50={pct(diffs,.5):.2f}° p90={pct(diffs,.9):.2f}°")
    if slips:
        print(f"    sideslipAngle    mean={statistics.fmean(slips):.2f}° "
              f"p50={pct(slips,.5):.2f}° p90={pct(slips,.9):.2f}°")
    if edges:
        print(f"    edgeQualityScore mean={statistics.fmean(edges):.1f} "
              f"p50={pct(edges,.5):.1f}")
    if confs:
        print(f"    kinematic conf   mean={statistics.fmean(confs):.3f}")
    return {"n": len(rows), "slips": slips, "diffs": diffs, "jumps": jumps,
            "edges": edges}


def slow_runs(rows, min_len=2):
    """列出连续低速段（帧索引 run），供锚定算法设计参考。"""
    runs = []
    start = None
    for i, r in enumerate(rows):
        if r.get("slow"):
            if start is None:
                start = i
        else:
            if start is not None and i - start >= min_len:
                runs.append((start, i - 1))
            start = None
    if start is not None and len(rows) - start >= min_len:
        runs.append((start, len(rows) - 1))
    return runs


def diagnose(path: Path, slow_th: float, fast_th: float):
    recs = load_frames(path)
    enrich_speed(recs)
    for r in recs:
        sp = r.get("speed")
        r["slow"] = sp is not None and sp <= slow_th
        r["fast"] = sp is not None and sp >= fast_th

    print("=" * 74)
    print(f"{path.name}  （boardAnalysis 帧={len(recs)}，slow≤{slow_th}/s，fast≥{fast_th}/s）")
    print("=" * 74)
    kin_rows = [r for r in recs if r.get("slip") is not None]
    slow_rows = [r for r in kin_rows if r["slow"]]
    mid_rows = [r for r in kin_rows if not r["slow"] and not r["fast"]]
    fast_rows = [r for r in kin_rows if r["fast"]]

    b_slow = summarize_bucket(slow_rows, "低速 foot-plant 候选")
    summarize_bucket(mid_rows, "中速")
    b_fast = summarize_bucket(fast_rows, "高速")
    summarize_bucket(kin_rows, "全部有运动学帧")

    runs = slow_runs(recs)
    if runs:
        desc = ", ".join(
            f"{recs[a]['time']:.1f}-{recs[b]['time']:.1f}s({b - a + 1}帧)"
            for a, b in runs[:6]
        )
        more = f"  等 {len(runs)} 段" if len(runs) > 6 else ""
        print(f"  连续低速段: {desc}{more}")

    # 核心假设判定
    verdict_bits = []
    if b_slow["slips"] and b_fast["slips"]:
        ms, mf = statistics.fmean(b_slow["slips"]), statistics.fmean(b_fast["slips"])
        verdict_bits.append(f"低速 sideslip {ms:.1f}° vs 高速 {mf:.1f}°（Δ={ms - mf:+.1f}°）")
    if b_slow["jumps"] and b_fast["jumps"]:
        js, jf = statistics.fmean(b_slow["jumps"]), statistics.fmean(b_fast["jumps"])
        verdict_bits.append(f"低速 board 帧跳 {js:.1f}° vs 高速 {jf:.1f}°")
    return verdict_bits


def main():
    ap = argparse.ArgumentParser(description="Foot-Plant Stabilisation 可行性诊断")
    ap.add_argument("inputs", nargs="*", type=Path, help="JSON 路径（默认主 corpus 6 份）")
    ap.add_argument("--slow", type=float, default=0.05, help="低速阈值（归一化位移/秒）")
    ap.add_argument("--fast", type=float, default=0.15, help="高速阈值（归一化位移/秒）")
    args = ap.parse_args()

    paths = args.inputs or DEFAULT_JSONS
    missing = [p for p in paths if not p.exists()]
    if missing:
        raise SystemExit(f"❌ 缺少: {', '.join(map(str, missing))}")

    all_bits = {}
    for p in paths:
        all_bits[p.name] = diagnose(p, args.slow, args.fast)

    print("\n" + "#" * 74)
    print("跨视频核心对照（foot-plant 假设：低速窗口应 sideslip 更小、board 更稳）")
    print("#" * 74)
    for name, bits in all_bits.items():
        print(f"{name}: " + ("；".join(bits) if bits else "低速/高速样本不足"))


if __name__ == "__main__":
    main()
