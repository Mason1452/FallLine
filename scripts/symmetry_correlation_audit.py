#!/usr/bin/env python3
"""§4.5 动作对称负相关排查（只读，不改评分）。

复核发现 symmetryScore 与综合分 Pearson r = -0.657（其它五维皆强正相关）。
本脚本：
  1. 提取每样本聚合 symmetryScore 并复算 r
  2. 把对称性拆成 knee / calf / lean 三个子分量（各自 |L-R| 角度差 -> 分），
     分别求与最终分的 r，定位负相关来自哪个子维度
  3. 检验假设：立刃越深（edgeQuality 越高）是否天然左右更不对称
     （刻滑弯外腿伸展承压、内腿折叠，本就应有角度差）
  4. 检查现有硬 cap（sym<45 -> 综合<=72）是否误伤保护样本
  5. 给出是否需要归一化 / 退役的判断依据
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REVIEW = ROOT / "outputs" / "calibration_review_20260915"
TESTVIDEO = ROOT / "testvideo"

MIN_CNF = 0.30

SOURCES = (
    [(p.stem, p) for p in sorted(REVIEW.glob("*.json"))]
    + [(f"v{p.stem}", p) for p in sorted(TESTVIDEO.glob("[0-9].json"))]
)


def subscore(diff: float) -> float:
    return max(0.0, 100.0 - (diff / 5.0) * 10.0)


def pearson(xs, ys) -> float:
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    vx = sum((x - mx) ** 2 for x in xs)
    vy = sum((y - my) ** 2 for y in ys)
    if vx == 0 or vy == 0:
        return float("nan")
    return cov / math.sqrt(vx * vy)


def clip_stats(path: Path) -> dict | None:
    d = json.loads(path.read_text())
    frames = d.get("frames", [])
    sm = d.get("summary", {})
    edge = d.get("skiMetrics", {}).get("edgeQualityScore")

    sym_vals, knee_vals, calf_vals, lean_vals = [], [], [], []
    knee_diff, calf_diff, lean_diff = [], [], []
    for fr in frames:
        ps = fr.get("poseScore") or {}
        bp = fr.get("bodyPose") or {}
        if ps.get("symmetryConfidence", 0) >= MIN_CNF:
            sym_vals.append(ps.get("symmetryScore"))
        def val(x):
            if x is None:
                return None
            if isinstance(x, dict):
                return x.get("value")
            return x
        lk, rk = val(bp.get("leftKneeBendAngle")), val(bp.get("rightKneeBendAngle"))
        lc, rc = val(bp.get("leftCalfLeanAngle")), val(bp.get("rightCalfLeanAngle"))
        ll, rl = val(bp.get("leftBodyLeanAngle")), val(bp.get("rightBodyLeanAngle"))
        if lk is not None and rk is not None:
            df = abs(lk - rk); knee_diff.append(df); knee_vals.append(subscore(df))
        if lc is not None and rc is not None:
            df = abs(lc - rc); calf_diff.append(df); calf_vals.append(subscore(df))
        if ll is not None and rl is not None:
            df = abs(ll - rl); lean_diff.append(df); lean_vals.append(subscore(df))

    def avg(v):
        return sum(v) / len(v) if v else None

    final = (sm.get("evidenceCappedScore") or 0) * (sm.get("flowModulationFactor") or 1.0)
    return {
        "sym": avg(sym_vals),
        "kneeSym": avg(knee_vals), "calfSym": avg(calf_vals), "leanSym": avg(lean_vals),
        "kneeDiff": avg(knee_diff), "calfDiff": avg(calf_diff), "leanDiff": avg(lean_diff),
        "edge": edge, "final": final,
        "nSym": len(sym_vals),
    }


def f(v, w=6):
    return "  -  " if v is None else f"{v:>{w}.1f}"


def main() -> None:
    stats = {}
    for alias, p in SOURCES:
        st = clip_stats(p)
        if st and st["sym"] is not None:
            stats[alias] = st

    # ---- 1. 表：最终分 vs 对称总分 + 三子分量 + edge ----
    print("=" * 118)
    print("1) 每样本：最终分 · 对称总分 · knee/calf/lean 子分量 · edgeQuality")
    print("=" * 118)
    print(f"{'alias':<10}{'final':>7}{'sym':>7}{'kneeSym':>9}{'calfSym':>9}"
          f"{'leanSym':>9}{'kneeDiff':>10}{'calfDiff':>10}{'edge':>7}")
    order = sorted(stats, key=lambda a: stats[a]["final"])
    for a in order:
        s = stats[a]
        print(f"{a:<10}{f(s['final'],7)}{f(s['sym'])} {f(s['kneeSym'],7)} "
              f"{f(s['calfSym'],7)} {f(s['leanSym'],7)} {f(s['kneeDiff'],8)} "
              f"{f(s['calfDiff'],8)}{f(s['edge'])}")

    # ---- 2. 各对称分量与最终分的 Pearson r ----
    print("\n" + "=" * 118)
    print("2) Pearson r（对称指标 vs 最终分）")
    print("=" * 118)
    fin = [s["final"] for s in stats.values()]
    for key in ["sym", "kneeSym", "calfSym", "leanSym"]:
        pairs = [(s[key], s["final"]) for s in stats.values() if s[key] is not None]
        r = pearson([x for x, _ in pairs], [y for _, y in pairs])
        print(f"  r(final, {key:<8}) = {r:+.3f}   n={len(pairs)}")

    # ---- 3. 假设检验：edgeQuality 与对称性是否负相关 ----
    print("\n" + "=" * 118)
    print("3) Pearson r（edgeQuality vs 对称指标）——负值=立刃越深越不对称")
    print("=" * 118)
    for key in ["sym", "kneeSym", "calfSym", "leanSym"]:
        pairs = [(s["edge"], s[key]) for s in stats.values()
                 if s["edge"] is not None and s[key] is not None]
        r = pearson([x for x, _ in pairs], [y for _, y in pairs])
        print(f"  r(edge, {key:<8}) = {r:+.3f}   n={len(pairs)}")

    # ---- 4. 硬 cap (sym<45 -> final<=72) 触发检查 ----
    print("\n" + "=" * 118)
    print("4) 硬 cap（sym<45 -> 综合<=72）触发样本")
    print("=" * 118)
    for a in order:
        s = stats[a]
        if s["sym"] is not None and s["sym"] < 45:
            print(f"  ⚠ {a:<10} sym={s['sym']:.1f}  final={s['final']:.1f}")
    print("  （保护样本 GOOD_A / MID_ACC8 / v2 / v3 / v6 是否在上方？若在=误伤）")


if __name__ == "__main__":
    main()
