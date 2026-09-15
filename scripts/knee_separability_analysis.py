#!/usr/bin/env python3
"""§4.2 可分性分析（只读，不改评分）。

背景：spec 的 knee 动态加权（knee<75 -> w.knee +0.10 / w.calf -0.10）在真实
样本上方向相反（MID_FP1: knee=74 > calf=47，转移反而加分），且无法区分
GOOD_A（教练=专业）与 MID_ACC7（教练=中级）。本脚本系统枚举可用特征，
检验是否存在**可辩护的单维阈值或双维合取规则**，把"中级下压组"压到 <75
同时保护"专业保留组"。

用法：
    python3 scripts/knee_separability_analysis.py
输出：
    1) 各样本特征矩阵
    2) 单维阈值规则的完美分离枚举（若存在）
    3) 双维合取（AND）规则枚举
    4) 结论
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REVIEW = ROOT / "outputs" / "calibration_review_20260915"
TESTVIDEO = ROOT / "testvideo"

# 角色：
#   keep   = 教练标注专业，须保护高分
#   carve  = 已确认刻滑样本（AGENTS.md 主 corpus），虽无数字锚点但须保护
#   press  = middle accepted（教练认定中级，当前上迁，须下压）
#   fp     = 教练明确 over-scored
#   observe= 主 corpus 其余（本就 ≤72，只观测）
LABELS = {
    "GOOD_A":   ("keep", 94.1, REVIEW),
    "MID_ACC8": ("keep", 85.3, REVIEW),
    "v2":       ("carve", None, TESTVIDEO),
    "v3":       ("carve", None, TESTVIDEO),
    "v6":       ("carve", None, TESTVIDEO),
    "BAD_ACC":  ("press", 65.0, REVIEW),
    "MID_FP1":  ("fp", None, REVIEW),
    "MID_FP2":  ("fp", None, REVIEW),
    "MID_ACC1": ("press", None, REVIEW),
    "MID_ACC2": ("press", None, REVIEW),
    "MID_ACC3": ("press", None, REVIEW),
    "MID_ACC4": ("press", None, REVIEW),
    "MID_ACC5": ("press", None, REVIEW),
    "MID_ACC6": ("press", None, REVIEW),
    "MID_ACC7": ("press", None, REVIEW),
    "v1":       ("observe", None, TESTVIDEO),
    "v4":       ("observe", None, TESTVIDEO),
    "v5":       ("observe", None, TESTVIDEO),
}


def load(alias: str, directory: Path) -> dict:
    d = json.loads((directory / f"{alias}.json").read_text())
    sk = d.get("skiMetrics", {})
    sm = d.get("summary", {})
    ba = d.get("boardAnalysis", {}).get("summary", {})
    co = d.get("centerOfMassAnalysis", {})
    return {
        "edgeQuality":      sk.get("edgeQualityScore"),
        "edgeCnf":          sk.get("edgeQualityConfidence"),
        "pressure":         sk.get("pressureSupportScore"),
        "pressureCnf":      sk.get("pressureSupportConfidence"),
        "foreAft":          sk.get("foreAftSupportScore"),
        "foreAftCnf":       sk.get("foreAftSupportConfidence"),
        "carvingCnf":       ba.get("carvingConfidence"),
        "boardCnf":         ba.get("confidence"),
        "sideslip":         ba.get("averageSideslipAngle"),
        "cogFit":           co.get("cogStageFitScore"),
        "cogCnf":           co.get("confidence"),
        "rawPose":          sm.get("rawPoseAverageScore"),
        "bestThird":        sm.get("bestThirdAverageScore"),
        "evidenceCapped":   sm.get("evidenceCappedScore"),
        "coherence":        sm.get("flowMotionCoherence"),
        "velSmooth":        sm.get("flowVelocitySmoothness"),
        "stability":        sm.get("stabilityScore"),
        "scoreConsistency": sm.get("scoreConsistencyScore"),
        "scoreStd":         sm.get("scoreStdDev"),
        "flowMod":          sm.get("flowModulationFactor"),
        "duration":         d.get("duration"),
    }


FEATURES = [
    "edgeQuality", "edgeCnf", "pressure", "pressureCnf", "foreAft", "foreAftCnf",
    "carvingCnf", "boardCnf", "sideslip", "cogFit", "cogCnf",
    "rawPose", "bestThird", "evidenceCapped", "coherence", "velSmooth",
    "stability", "scoreConsistency", "scoreStd", "flowMod", "duration",
]


def fmt(v) -> str:
    if v is None:
        return "  -  "
    if isinstance(v, float):
        return f"{v:6.1f}"
    return f"{v:>6}"


def main() -> None:
    def file_alias(a: str, directory: Path) -> str:
        return a.lstrip("v") if directory is TESTVIDEO else a

    data = {a: load(file_alias(a, directory), directory)
            for a, (_, _, directory) in LABELS.items()}

    protect = [a for a, (c, _, _) in LABELS.items() if c in ("keep", "carve")]
    press = [a for a, (c, _, _) in LABELS.items() if c in ("press", "fp")]
    observe = [a for a, (c, _, _) in LABELS.items() if c == "observe"]

    # ---- 1. 特征矩阵（只展示两个关键分离轴）----
    print("=" * 100)
    print("1) 关键分离轴（P=protect 须放行 · X=press/fp 须下压 · o=observe）")
    print("=" * 100)
    print(f"{'alias':<10}{'role':<9}{'edgeQuality':>12}{'pressure':>11}{'bestThird':>11}")
    for a in LABELS:
        role = LABELS[a][0]
        r = data[a]
        print(f"{a:<10}{role:<9}{fmt(r['edgeQuality']):>12}{fmt(r['pressure']):>11}"
              f"{fmt(r['bestThird']):>11}")
    print("\nPROTECT =", protect)
    print("PRESS   =", press)

    # ---- 2. 析取放行规则（核心）+ 可行阈值域网格搜索 ----
    #   release 当且仅当 edgeQuality >= Te OR pressure >= Tp；否则 cap。
    print("\n" + "=" * 100)
    print("2) 析取放行规则（edge>=Te OR pressure>=Tp -> 放行；否则 cap）")
    print("=" * 100)

    def classifies(Te: float, Tp: float) -> bool:
        protect_ok = all(data[a]["edgeQuality"] >= Te or data[a]["pressure"] >= Tp
                         for a in protect)
        press_ok = all(data[a]["edgeQuality"] < Te and data[a]["pressure"] < Tp
                       for a in press)
        return protect_ok and press_ok

    # 理论可行域边界
    Te_lo = max(data[a]["edgeQuality"] for a in press)   # Te 须 > 此值
    Te_hi = min(data[a]["edgeQuality"] for a in protect  # Te 须 <= 此值
                if data[a]["edgeQuality"] >= Te_lo)
    Tp_lo = max(data[a]["pressure"] for a in press)
    Tp_hi = min(data[a]["pressure"] for a in protect
                if data[a]["pressure"] >= Tp_lo)
    print(f"  edge 阈值可行域：     Te ∈ ({Te_lo:.2f}, {Te_hi:.2f}]   宽 {Te_hi - Te_lo:.2f}")
    print(f"  pressure 阈值可行域： Tp ∈ ({Tp_lo:.2f}, {Tp_hi:.2f}]   宽 {Tp_hi - Tp_lo:.2f}")
    print("  （注：两阈值并非独立——须用同组 (Te,Tp) 同时满足，故下方做网格搜索）")

    feasible = []
    Te_c, Tp_c = None, None
    step = 0.1
    te = Te_lo + step
    while te <= Te_hi:
        tp = Tp_lo + step
        while tp <= Tp_hi:
            if classifies(te, tp):
                feasible.append((te, tp))
            tp += step
        te += step

    if feasible:
        # 选“居中”阈值：离四个极值都尽量远，最大化抗噪 margin
        Te_c, Tp_c = min(feasible, key=lambda t:
                         min(t[0] - Te_lo, Te_hi - t[0],
                             t[1] - Tp_lo, Tp_hi - t[1]) * -1)
        # 取可行域的几何中心附近
        Te_c = round((Te_lo + Te_hi) / 2 / step) * step
        Tp_c = round((Tp_lo + Tp_hi) / 2 / step) * step
        if not classifies(Te_c, Tp_c):
            Te_c, Tp_c = feasible[len(feasible) // 2]
        print(f"\n  ✅ 可行 (Te,Tp) 组合数：{len(feasible)}（网格步长 {step}）")
        print(f"  推荐居中阈值： Te = {Te_c:.1f}   Tp = {Tp_c:.1f}")
        margin = min(Te_c - Te_lo, Te_hi - Te_c, Tp_c - Tp_lo, Tp_hi - Tp_c)
        print(f"  最小单边 margin： {margin:.2f}（对测量噪声的鲁棒性）")
    else:
        print("\n  ❌ 不存在可完美分离的 (Te,Tp)。")
        return

    print("\n  PROTECT 校验：")
    for a in protect:
        e, p = data[a]["edgeQuality"], data[a]["pressure"]
        via = []
        if e >= Te_c:
            via.append(f"edge {e:.1f}≥{Te_c:.1f}")
        if p >= Tp_c:
            via.append(f"pressure {p:.1f}≥{Tp_c:.1f}")
        print(f"    ✅ {a:<10} {' / '.join(via)}")
    print("  PRESS 命中：")
    for a in press:
        e, p = data[a]["edgeQuality"], data[a]["pressure"]
        print(f"    ✅ {a:<10} edge={e:6.1f}  pressure={p:6.1f}")

    # ---- 3. 最终分模拟（cap 是 min，绝不抬分）----
    print("\n" + "=" * 100)
    print(f"3) 最终分模拟（命中且 >72 才压到 72，cap 是 min 不抬分；再乘 flowMod）")
    print("=" * 100)
    CAP = 72.0
    print(f"{'alias':<10}{'role':<9}{'capped?':>9}{'current':>9}{'simulated':>11}")
    for a in LABELS:
        r = data[a]
        hit = r["edgeQuality"] < Te_c and r["pressure"] < Tp_c
        capped_base = min(r["evidenceCapped"], CAP) if hit else r["evidenceCapped"]
        flow = r["flowMod"] or 1.0
        sim = min(100, capped_base * flow)
        cur = (r["evidenceCapped"] or 0) * flow
        print(f"{a:<10}{LABELS[a][0]:<9}{('YES' if hit else 'no'):>9}"
              f"{cur:9.1f}{sim:11.1f}")


if __name__ == "__main__":
    main()
