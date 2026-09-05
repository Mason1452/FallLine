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

    P0b (探针，未落地) - lean / centerOfGravity 抖动
         bodyLeanAngle (20% 权重) 与 centerOfGravity (20% 权重) 在
         PoseSmoother.despikeJointAngles 中未被覆盖，本项衡量若扩展 despike
         是否有价值：
           - leanAdjDiffMedian → p0bLeanScore (基准 0-15°)
           - cogAdjDiffMedian  → p0bCogScore  (基准 0-0.15)
           - Go/No-Go 规则：mean 贡献分 >= 30 且 命中率 >= 50%
         数据满足条件时才推 P0b (扩展 despike 目标集)，避免过早优化

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
    - 4 + 2 (P0b) 层排序，锁定"先改哪一层"
    - P0b Go/No-Go 决策段：给出是否扩展 despike 的明确结论

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
    - P0-A (2026-09-01) 已对 knee/calf 加 3 帧中位数去尖峰，本项衡量残留量
    - P0b 探针 (2026-09-03) 新增 bodyLean / centerOfGravity 覆盖率评估，
      两者在 PoseScorer 中分别占 20% + 20% 权重，未纳入 despike
    """
    knee_l = _adjacent_abs_diff(_extract_angle_series(frames, "leftKneeBendAngle"))
    knee_r = _adjacent_abs_diff(_extract_angle_series(frames, "rightKneeBendAngle"))
    lean = _adjacent_abs_diff(_extract_angle_series(frames, "bodyLeanAngle"))
    calf_l = _adjacent_abs_diff(_extract_angle_series(frames, "leftCalfLeanAngle"))
    calf_r = _adjacent_abs_diff(_extract_angle_series(frames, "rightCalfLeanAngle"))
    cog = _adjacent_abs_diff(_extract_angle_series(frames, "centerOfGravity"))

    def _median_or_none(xs: list[float]) -> float | None:
        return statistics.median(xs) if xs else None

    def _p90_or_none(xs: list[float]) -> float | None:
        return statistics.quantiles(xs, n=10)[-1] if len(xs) >= 10 else None

    knee_jitter_all = knee_l + knee_r
    calf_jitter_all = calf_l + calf_r

    # P0b 尖峰计数：与 medianWindow 触发条件保持同数量级
    #   lean 尖峰阈值 15°：Vision 单帧掉点常见幅度
    #   cog  尖峰阈值 0.10：归一化 hipRatio 的 10%，映射到 gravityScore 约 10 分/帧
    lean_spike_count = sum(1 for v in lean if v > 15.0)
    cog_spike_count = sum(1 for v in cog if v > 0.10)

    # P0bC 深度探针 (2026-09-05)：单纯的 median/spike 无法区分
    #   (a) 孤立尖峰 —— 3 帧 median 就能压掉
    #   (b) 短簇跳动 —— 需要 window=5，但会伤连续 turn 峰值
    #   (c) 长时漂移 —— despike 无效，需要重构 hipRatio 计算
    # 引入 3 组特征：
    #   cogSpikeMaxCluster / cogSpikeClusterLens: 相邻尖峰帧簇长度分布
    #   cogRawRange / cogRawStd: 全序 raw 值分布，判断是否漂移
    #   gravityImpactedFrames: cog > 0.75 (gravityScore < 32.5) 的帧数，
    #     反映 cog 抖动是否落入实际扣分区
    cog_series = _extract_angle_series(frames, "centerOfGravity")
    spike_positions = [i for i, v in enumerate(cog) if v > 0.10]
    cluster_lens: list[int] = []
    if spike_positions:
        cur = [spike_positions[0]]
        for idx in spike_positions[1:]:
            if idx == cur[-1] + 1:
                cur.append(idx)
            else:
                cluster_lens.append(len(cur))
                cur = [idx]
        cluster_lens.append(len(cur))
    gravity_impacted = sum(1 for v in cog_series if v > 0.75)

    return {
        "kneeAdjDiffMedian": _median_or_none(knee_jitter_all),
        "leanAdjDiffMedian": _median_or_none(lean),
        "leanAdjDiffP90": _p90_or_none(lean),
        "leanSpikeCount": lean_spike_count,
        "calfAdjDiffMedian": _median_or_none(calf_jitter_all),
        "cogAdjDiffMedian": _median_or_none(cog),
        "cogAdjDiffP90": _p90_or_none(cog),
        "cogSpikeCount": cog_spike_count,
        "cogSpikeMaxCluster": max(cluster_lens) if cluster_lens else 0,
        "cogSpikeClusterLens": cluster_lens,
        "cogRawRange": (max(cog_series) - min(cog_series)) if cog_series else None,
        "cogRawStd": statistics.pstdev(cog_series) if len(cog_series) > 1 else None,
        "gravityImpactedFrames": gravity_impacted,
        "cogFrameCount": len(cog_series),
        "kneeAdjDiffP90": _p90_or_none(knee_jitter_all),
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
    # P0b 探针（未落地）：lean / cog 的抖动贡献分
    #   lean: 0° 无抖 / 15° 严重（与 knee 同基准，两者都以角度衡量）
    #   cog:  0 / 0.15 严重（cog 归一化到 [0,1]，0.15 相当于 hipRatio 15% 波动）
    p0b_lean_score = normalize(p0["leanAdjDiffMedian"], 0, 15)
    p0b_cog_score = normalize(p0["cogAdjDiffMedian"], 0, 0.15)
    # P1: 距 0.7 阈值 < 0.15 视为窗口内，距离越近贡献越大
    if p1["inTransitionWindow"]:
        p1_score = 100.0 * (1 - (p1["distanceToThreshold"] or 0) / CONF_WINDOW)
    else:
        p1_score = 0.0
    # P2: 实际损害 = flowMod 偏离 1.0（越大越是活跃的抖动源）
    # 2026-09-01 熔断落地后：塌陷双 0 会让 flowMod 保持 1.0，本项自动归零；
    # 单个塌陷仍可能通过其他分支产生偏离，用它反映"熔断后实际残留的调制损害"
    p2_score = normalize(p2["flowModOffset"], 0, 0.13)
    # P2 塌陷风险单独记录（不叠加到主贡献分，作为诊断参考）
    p2_degrade_risk = 50 + 20 * len(p2["degradations"]) if p2["isDegraded"] else 0
    # P3: sideslip adj diff median → 0° / 20° 严重
    p3_score = normalize(p3["sideslipAdjDiffMedian"], 0, 20)

    return {
        "file": str(path),
        "totalFrames": len(frames),
        "boardFrames": len(board_frames),
        # 原始指标
        "kneeAdjDiffMedian": p0["kneeAdjDiffMedian"],
        "leanAdjDiffMedian": p0["leanAdjDiffMedian"],
        "leanAdjDiffP90": p0["leanAdjDiffP90"],
        "leanSpikeCount": p0["leanSpikeCount"],
        "calfAdjDiffMedian": p0["calfAdjDiffMedian"],
        "cogAdjDiffMedian": p0["cogAdjDiffMedian"],
        "cogAdjDiffP90": p0["cogAdjDiffP90"],
        "cogSpikeCount": p0["cogSpikeCount"],
        "cogSpikeMaxCluster": p0["cogSpikeMaxCluster"],
        "cogSpikeClusterLens": p0["cogSpikeClusterLens"],
        "cogRawRange": p0["cogRawRange"],
        "cogRawStd": p0["cogRawStd"],
        "gravityImpactedFrames": p0["gravityImpactedFrames"],
        "cogFrameCount": p0["cogFrameCount"],
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
        "p0bLeanScore": p0b_lean_score,
        "p0bCogScore": p0b_cog_score,
        "p1Score": p1_score,
        "p2Score": p2_score,
        "p2DegradeRisk": p2_degrade_risk,
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
        f"{'kJit':>5} {'lJit':>5} {'cJit':>5} {'cogJ':>6} "
        f"{'conf':>5} {'win?':>4} "
        f"{'fMod':>5} {'degd':>4} "
        f"{'ssJt':>5} "
        f"{'stab':>5} {'sStd':>5} {'avg':>4} "
        f"| {'P0':>4} {'P0bL':>4} {'P0bC':>4} {'P1':>4} {'P2':>4} {'P3':>4}"
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
            f"{_fmt(r['cogAdjDiffMedian'], 6, 3)} "
            f"{_fmt(r['boardConf'], 5, 2)} "
            f"{_fmt(r['inTransitionWindow'], 4)} "
            f"{_fmt(r['flowModFactor'], 5, 2)} "
            f"{_fmt(deg_count, 4)} "
            f"{_fmt(r['sideslipAdjDiffMedian'], 5, 1)} "
            f"{_fmt(r['stabilityScore'], 5, 1)} "
            f"{_fmt(r['scoreStdDev'], 5, 1)} "
            f"{_fmt(r['averageScore'], 4, 0)} "
            f"| {_fmt(r['p0Score'], 4, 0)} "
            f"{_fmt(r['p0bLeanScore'], 4, 0)} {_fmt(r['p0bCogScore'], 4, 0)} "
            f"{_fmt(r['p1Score'], 4, 0)} "
            f"{_fmt(r['p2Score'], 4, 0)} {_fmt(r['p3Score'], 4, 0)}"
        )
    print(
        "\n列说明: kJit=knee相邻差中位数° lJit=lean° cJit=calf° cogJ=cog相邻差中位数 "
        "conf=boardConf win?=是否在0.55-0.85窗口 fMod=flowModFactor "
        "degd=flow子指标塌陷数 ssJt=sideslip相邻差中位数° "
        "stab=stabilityScore sStd=scoreStdDev "
        "P0=knee抖动 P0bL=lean抖动 P0bC=cog抖动 P1~P3=各层贡献分(0-100)"
    )


def summarize(rows: list[dict[str, Any]]) -> None:
    total = len(rows)
    print(f"\n== 汇总：4 层稳定性贡献排序 ==")
    print(f"总样本数: {total}\n")

    def _mean_score(key: str) -> float:
        vals = [r[key] for r in rows if r[key] is not None]
        return statistics.fmean(vals) if vals else 0.0

    scores = {
        "P0  关节角帧间抖动 (knee median)": _mean_score("p0Score"),
        "P0b lean 抖动 (未 despike, 20% 权重)": _mean_score("p0bLeanScore"),
        "P0b cog  抖动 (未 despike, 20% 权重)": _mean_score("p0bCogScore"),
        "P1  置信度落在阈值窗口": _mean_score("p1Score"),
        "P2  flow modulation 实际损害 (|flowMod-1.0|)": _mean_score("p2Score"),
        "P3  sideslip 帧间跳动": _mean_score("p3Score"),
    }
    ordered = sorted(scores.items(), key=lambda x: -x[1])
    print("平均贡献分排序（越高越是主要抖动源）：")
    for i, (name, s) in enumerate(ordered, 1):
        bar = "█" * int(s / 2)
        print(f"  {i}. {name}: {s:.1f}  {bar}")

    p2_risk = _mean_score("p2DegradeRisk")
    print(f"\n[诊断参考] P2 flow 塌陷风险（塌陷率×子指标数，与实际损害独立）: {p2_risk:.1f}")
    print("           塌陷风险 = flow 内部降级发生率；主贡献分 = 熔断后实际影响到分数的部分")

    # 分位数辅助判断
    p0_vals = sorted([r["kneeAdjDiffMedian"] for r in rows if r["kneeAdjDiffMedian"] is not None])
    if p0_vals:
        print(f"\nP0 关节抖动分布 (kneeAdjDiffMedian, °):")
        print(f"  min={p0_vals[0]:.2f} / median={statistics.median(p0_vals):.2f} / "
              f"max={p0_vals[-1]:.2f}")

    # P0b 探针输出：bodyLean / centerOfGravity 抖动分布
    lean_vals = sorted([r["leanAdjDiffMedian"] for r in rows if r["leanAdjDiffMedian"] is not None])
    cog_vals = sorted([r["cogAdjDiffMedian"] for r in rows if r["cogAdjDiffMedian"] is not None])
    lean_spikes = sum(r["leanSpikeCount"] for r in rows if r["leanSpikeCount"] is not None)
    cog_spikes = sum(r["cogSpikeCount"] for r in rows if r["cogSpikeCount"] is not None)
    if lean_vals:
        print(f"\nP0b lean 抖动分布 (leanAdjDiffMedian, °):")
        print(f"  min={lean_vals[0]:.2f} / median={statistics.median(lean_vals):.2f} / "
              f"max={lean_vals[-1]:.2f}  (spike>15° 总数: {lean_spikes})")
    if cog_vals:
        print(f"\nP0b cog  抖动分布 (cogAdjDiffMedian):")
        print(f"  min={cog_vals[0]:.3f} / median={statistics.median(cog_vals):.3f} / "
              f"max={cog_vals[-1]:.3f}  (spike>0.10 总数: {cog_spikes})")

    # ---- P0b Go/No-Go 决策 -------------------------------------------------
    #   触发条件：mean 贡献分 >= 30 且 命中率 >= 50%
    #   命中定义：单样本贡献分 > 30 视为命中
    #   贡献分基准：lean 0~15°、cog 0~0.15，见 audit_one() 里 normalize() 调用
    print(f"\n== P0b Go/No-Go 决策规则 ==")
    print(f"  规则：mean(p0bScore) >= 30 且 命中率 >= 50%（单样本 > 30）→ 推荐扩展 despike")
    for label, key in (("lean", "p0bLeanScore"), ("cog ", "p0bCogScore")):
        vals = [r[key] for r in rows if r[key] is not None]
        if not vals:
            print(f"  P0b {label}: no data")
            continue
        mean_score = statistics.fmean(vals)
        hits = [v for v in vals if v > 30]
        hit_rate = len(hits) / len(vals) * 100
        gate = mean_score >= 30 and hit_rate >= 50
        verdict = "→ 推 P0b" if gate else "→ 维持现状"
        print(f"  P0b {label}: mean={mean_score:5.1f} / 命中率={hit_rate:4.0f}%"
              f" ({len(hits)}/{len(vals)})  {verdict}")

    # ---- P0bC 深度探针 (2026-09-05) --------------------------------------
    #   区分 cog 抖动的三种形态，指导 despike 策略选择：
    #     (a) 孤立尖峰       → 3 帧 median 就足够
    #     (b) 短簇 (2~4 帧)  → 3 帧 median 削减一半，5 帧 median 边际收益小
    #     (c) 长簇 / 漂移    → despike 无效，需重构 hipRatio 计算
    #   同时看 gravityImpactedFrames：cog > 0.75 才落到实际扣分区
    print(f"\n== P0bC 深度探针：cog 抖动形态学 ==")
    header_pc = (
        f"  {'file':<38} {'nCog':>4} {'#spk':>4} {'maxCl':>5} "
        f"{'range':>6} {'std':>6} {'gImp':>4}"
    )
    print(header_pc)
    print("  " + "-" * (len(header_pc) - 2))
    for r in rows:
        print(
            f"  {r['file'][:38]:<38} "
            f"{_fmt(r.get('cogFrameCount'), 4, 0)} "
            f"{_fmt(r.get('cogSpikeCount'), 4, 0)} "
            f"{_fmt(r.get('cogSpikeMaxCluster'), 5, 0)} "
            f"{_fmt(r.get('cogRawRange'), 6, 3)} "
            f"{_fmt(r.get('cogRawStd'), 6, 3)} "
            f"{_fmt(r.get('gravityImpactedFrames'), 4, 0)}"
        )
    print(
        "\n  列说明: nCog=cog 有效帧数  #spk=cog 相邻差>0.10 尖峰数  maxCl=最长连续尖峰簇长度\n"
        "         range=cog raw 全序极差  std=raw 标准差  gImp=cog>0.75 落入 gravityScore<32.5 惩罚区帧数"
    )

    # 汇总形态分类：只看主 corpus（testvideo/N.json，不含 _baseline / _c_2d 等对照目录）
    main_rows = [r for r in rows if Path(r["file"]).parent.name == "testvideo"]
    if main_rows:
        drift_samples = [r for r in main_rows if (r.get("cogRawStd") or 0) > 0.08]
        cluster_samples = [r for r in main_rows if (r.get("cogSpikeMaxCluster") or 0) >= 3]
        gravity_samples = [r for r in main_rows if (r.get("gravityImpactedFrames") or 0) > 0]
        print(f"\n  主 corpus ({len(main_rows)} 段) 形态分类:")
        print(f"    cogRawStd > 0.08       (可能漂移): {len(drift_samples)}/{len(main_rows)}"
              f" [{', '.join(Path(r['file']).stem for r in drift_samples) or '-'}]")
        print(f"    maxCluster >= 3        (需 5 帧窗?): {len(cluster_samples)}/{len(main_rows)}"
              f" [{', '.join(Path(r['file']).stem for r in cluster_samples) or '-'}]")
        print(f"    gravityImpacted > 0    (落入惩罚区): {len(gravity_samples)}/{len(main_rows)}"
              f" [{', '.join(Path(r['file']).stem for r in gravity_samples) or '-'}]")
        # P0c 决策规则
        need_p0c = len(cluster_samples) >= len(main_rows) / 2 or len(gravity_samples) >= 2
        drift_dominant = len(drift_samples) >= len(main_rows) / 2
        print(f"\n  P0c 决策：")
        if drift_dominant:
            print(f"    多数段 cog raw std > 0.08：抖动包含长时漂移分量，despike 收益有限。")
            print(f"    建议：先重构 hipRatio 计算 (BoardDirectionAnalyzer/PoseMetrics)，")
            print(f"          而不是加 despike。")
        elif need_p0c:
            print(f"    尖峰簇 >= 3 帧占多数段 或 落入 gravity 惩罚区 —— 推荐落 P0c cog despike。")
            max_cl = max((r.get("cogSpikeMaxCluster") or 0) for r in main_rows)
            print(f"    最长 cluster = {max_cl} 帧 → 建议 window = "
                  f"{'5 帧' if max_cl >= 3 else '3 帧'}。")
        else:
            print(f"    cog 抖动多为孤立尖峰 (簇长 < 3)，3 帧 median 即可；")
            print(f"    但 gravity 惩罚区帧数 < 2，实际扣分影响小 → 维持现状。")

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
