#!/usr/bin/env python3
"""
flow_gating_replay.py

Replay Flow Modulation Edge-Confidence Gating (2026-09-15 v2) 门控的静态推演：
- 输入：testvideo/ 下各 baseline 目录中的 *.json（VideoAnalyzer 输出）
- 门控信号：boardAnalysis.summary.confidence (== boardKinematicConfidence)
- 门控规则：若 boardConfidence < gate_threshold，则 flow modulation factor 上限锁死为 1.0（禁上行、保下行）
- 输出：主 corpus 6 份的评分/档位对照 + 阈值敏感度扫描 + 历史 baseline 稳定性统计

用法示例：
    python3 scripts/flow_gating_replay.py                                       # 默认主 corpus + 主阈值 0.30
    python3 scripts/flow_gating_replay.py --thresholds 0.20 0.25 0.30 0.35 0.40  # 阈值扫描
    python3 scripts/flow_gating_replay.py --baselines edgefirst_c40 review_tick4 baseline_alpha_on
"""

import argparse
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTVIDEO = ROOT / "testvideo"

DEFAULT_MAIN = "_edgefirst_c40"
DEFAULT_BASELINES = [
    "_edgefirst_c40",
    "_review_tick4",
    "baseline_alpha_on",
    "baseline_alpha_off",
    "_p1_baseline",
    "_b_3d_baseline",
    "_c_2d",
]

def load_summary(json_path: Path):
    with open(json_path, "r") as f:
        d = json.load(f)
    summary = d.get("summary") or {}
    board = (d.get("boardAnalysis") or {}).get("summary") or {}
    return {
        "path": json_path,
        "averageScore": summary.get("averageScore"),
        "rawPoseAverageScore": summary.get("rawPoseAverageScore"),
        "bestThirdAverageScore": summary.get("bestThirdAverageScore"),
        "evidenceCappedScore": summary.get("evidenceCappedScore"),
        "flowModulationFactor": summary.get("flowModulationFactor"),
        "motionCoherence": summary.get("flowMotionCoherence"),
        "velocitySmoothness": summary.get("flowVelocitySmoothness"),
        "edgeQualityConfidence": summary.get("averageEdgeQualityConfidence"),
        "boardConfidence": board.get("confidence"),
    }

def gated_factor(coh, sm, boardC, gate=0.30, allow_downward_gate=False):
    """门控后 factor（重现 spec §4.3 的 computeModulation(5-param)）"""
    if coh is None or sm is None or boardC is None:
        return None
    mod = 1.0
    if coh > 70: mod += 0.05
    if 0 < sm < 40: mod -= 0.05
    if boardC < gate:
        # 上行加成钳制
        mod = min(mod, 1.0)
        if allow_downward_gate:
            mod = max(mod, 1.0)  # 若也 gate 下行，则完全归 1
    return max(0.87, min(1.13, mod))

def overall_level(score):
    if score is None: return "-"
    if score >= 85: return "专业"
    if score >= 75: return "高级"
    if score >= 60: return "中级"
    return "初级"

def apply_gate_score(rec, gate):
    """对单条 JSON 记录预测门控后综合分（复用 evidenceCappedScore × gated factor）"""
    cap = rec["evidenceCappedScore"]
    if cap is None:
        return None, None
    new_factor = gated_factor(
        rec["motionCoherence"], rec["velocitySmoothness"], rec["boardConfidence"], gate=gate
    )
    if new_factor is None:
        return cap, rec["flowModulationFactor"]
    return max(0.0, min(100.0, cap * new_factor)), new_factor

def format_row(rec, gate):
    stem = rec["path"].stem
    predicted, gfactor = apply_gate_score(rec, gate)
    delta = None
    if predicted is not None and rec["averageScore"] is not None:
        delta = predicted - rec["averageScore"]
    gate_hit = "✓" if rec["boardConfidence"] is not None and rec["boardConfidence"] < gate else "✗"
    kill = "✓" if (gate_hit == "✓" and rec["flowModulationFactor"] and rec["flowModulationFactor"] > 1.0) else " "
    return (
        f"{stem:>4s} "
        f"{fmt(rec['boardConfidence'], '{:.3f}'):>7s} "
        f"{fmt(rec['edgeQualityConfidence'], '{:.3f}'):>7s} "
        f"{fmt(rec['motionCoherence'], '{:.2f}'):>7s} "
        f"{fmt(rec['velocitySmoothness'], '{:.2f}'):>7s} "
        f"{fmt(rec['flowModulationFactor'], '×{:.3f}'):>8s} "
        f"→ {fmt(gfactor, '×{:.3f}'):>7s}   "
        f"{fmt(rec['averageScore'], '{:.2f}'):>7s} → {fmt(predicted, '{:.2f}'):>7s} "
        f"({fmt(delta, '{:+.2f}'):>7s})  "
        f"{overall_level(rec['averageScore']):>2s}→{overall_level(predicted):>2s} "
        f"  gate:{gate_hit}  kill:{kill}"
    )

def fmt(v, spec):
    if v is None: return "-"
    return spec.format(v)

def print_main_corpus(main_records, gate):
    print(f"\n{'='*140}")
    print(f" 主 corpus ({DEFAULT_MAIN}) · gate={gate}")
    print(f"{'='*140}")
    print(f"{'stem':>4s} {'boardC':>7s} {'edgeC':>7s} {'coh':>7s} {'vs':>7s} {'factor':>8s}   {'gated':>7s}   {'当前':>7s} → {'门控后':>7s} ({'Δ':>7s})  {'档位':>5s}   gate/kill")
    total_delta = 0
    for rec in main_records:
        print(format_row(rec, gate))
        cap = rec["evidenceCappedScore"]
        if cap is not None:
            predicted, _ = apply_gate_score(rec, gate)
            if predicted is not None and rec["averageScore"] is not None:
                total_delta += predicted - rec["averageScore"]
    print(f"\n累计 Δ (综合分总变化): {total_delta:+.2f}")

def threshold_sensitivity(main_records, thresholds):
    print(f"\n{'='*100}")
    print(f" 阈值敏感度扫描 (主 corpus 6 份)")
    print(f"{'='*100}")
    header = f"{'gate':>6s} " + " ".join(f"{rec['path'].stem:>7s}" for rec in main_records) + f"  {'累计Δ':>7s}  {'kill数':>5s}  {'跨档':>5s}"
    print(header)
    for gate in thresholds:
        cells = []
        total_delta = 0
        kill_count = 0
        cross_level = 0
        for rec in main_records:
            predicted, gfactor = apply_gate_score(rec, gate)
            if predicted is None or rec["averageScore"] is None:
                cells.append("     -  ")
                continue
            delta = predicted - rec["averageScore"]
            total_delta += delta
            if delta < -0.01: kill_count += 1
            if overall_level(rec["averageScore"]) != overall_level(predicted):
                cross_level += 1
                cells.append(f"{delta:+6.2f}†")
            else:
                cells.append(f"{delta:+7.2f}")
        row = f"{gate:>6.2f}  " + " ".join(cells) + f"  {total_delta:+7.2f}  {kill_count:>5d}  {cross_level:>5d}"
        print(row)
    print("\n(dagger = 跨档位边界)")

def baseline_scan(baselines, gate):
    print(f"\n{'='*160}")
    print(f" 跨 baseline 稳定性 (gate={gate}, 检查历史 corpus flow gate 触发情况)")
    print(f"{'='*160}")
    print(f"{'baseline':>22s} {'stem':>4s} {'boardC':>7s} {'当前 factor':>11s}  {'gate?':>5s}  {'kill?':>5s}  {'当前分':>7s} → {'预测分':>7s} ({'Δ':>7s})")
    trigger_stats = {}
    kill_stats = {}
    for base in baselines:
        base_dir = TESTVIDEO / base
        if not base_dir.exists():
            continue
        trigger_stats[base] = 0
        kill_stats[base] = 0
        for stem in ["1", "2", "3", "4", "5", "6"]:
            p = base_dir / f"{stem}.json"
            if not p.exists(): continue
            rec = load_summary(p)
            predicted, gfactor = apply_gate_score(rec, gate)
            gate_hit = rec["boardConfidence"] is not None and rec["boardConfidence"] < gate
            kill = gate_hit and rec["flowModulationFactor"] and rec["flowModulationFactor"] > 1.0
            if gate_hit: trigger_stats[base] += 1
            if kill: kill_stats[base] += 1
            delta = (predicted - rec["averageScore"]) if predicted is not None and rec["averageScore"] is not None else None
            print(
                f"{base:>22s} {stem:>4s} "
                f"{fmt(rec['boardConfidence'], '{:.3f}'):>7s} "
                f"{fmt(rec['flowModulationFactor'], '×{:.3f}'):>11s}  "
                f"{'✓' if gate_hit else ' ':>5s}  {'✓' if kill else ' ':>5s}  "
                f"{fmt(rec['averageScore'], '{:.2f}'):>7s} → "
                f"{fmt(predicted, '{:.2f}'):>7s} "
                f"({fmt(delta, '{:+.2f}'):>7s})"
            )
        print()
    print("汇总（gate 触发 / 有效 kill）：")
    for base in baselines:
        if base in trigger_stats:
            print(f"  {base:>22s}: trigger={trigger_stats[base]}, kill={kill_stats[base]}")

def video1_protection_analysis(main_records, gate):
    print(f"\n{'='*100}")
    print(f" video 1 保护方案对比 (R1 缓解措施)")
    print(f"{'='*100}")
    rec = next((r for r in main_records if r["path"].stem == "1"), None)
    if rec is None:
        print("  未找到 video 1 数据")
        return
    print(f"  当前: averageScore={rec['averageScore']:.2f}, rawPose={rec['rawPoseAverageScore']:.2f}, evidenceCapped={rec['evidenceCappedScore']:.2f}")
    print(f"  boardC={rec['boardConfidence']:.3f}, flowFactor={rec['flowModulationFactor']:.3f}")
    print()
    # 方案 (a) 直接门控：无保护
    predicted, _ = apply_gate_score(rec, gate)
    print(f"  方案 (a) 无保护:            {rec['averageScore']:.2f} → {predicted:.2f} ({(predicted-rec['averageScore']):+.2f})  档位: {overall_level(rec['averageScore'])} → {overall_level(predicted)}")
    # 方案 (b) rawPose >= 60 AND 触发才门控
    if rec["rawPoseAverageScore"] < 60:
        print(f"  方案 (b) rawPose>=60 AND: {rec['averageScore']:.2f} → {rec['averageScore']:.2f} (+0.00)  档位: {overall_level(rec['averageScore'])} → {overall_level(rec['averageScore'])} (保护生效: rawPose={rec['rawPoseAverageScore']:.2f} < 60)")
    # 方案 (c) evidenceCapped >= 60 AND 触发才门控
    if rec["evidenceCappedScore"] < 60:
        print(f"  方案 (c) evidenceCap>=60 AND: {rec['averageScore']:.2f} → {rec['averageScore']:.2f} (+0.00)  档位: {overall_level(rec['averageScore'])} → {overall_level(rec['averageScore'])} (保护生效: capped={rec['evidenceCappedScore']:.2f} < 60)")
    # 检查 v4/v6 是否仍被 kill（保护副作用）
    print()
    print("  保护副作用检查（v4/v6 需继续被 gate）:")
    for target in ["4", "6"]:
        r = next((x for x in main_records if x["path"].stem == target), None)
        if r is None: continue
        b_ok = r["rawPoseAverageScore"] >= 60
        c_ok = r["evidenceCappedScore"] >= 60
        print(f"    v{target}: rawPose={r['rawPoseAverageScore']:.2f} (b保护{'关闭' if b_ok else '触发'}) evidenceCapped={r['evidenceCappedScore']:.2f} (c保护{'关闭' if c_ok else '触发'})")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--thresholds", nargs="+", type=float,
                        default=[0.20, 0.25, 0.28, 0.30, 0.32, 0.35, 0.40, 0.50])
    parser.add_argument("--baselines", nargs="+", default=DEFAULT_BASELINES)
    parser.add_argument("--gate", type=float, default=0.30)
    parser.add_argument("--corpus-dir", default=DEFAULT_MAIN)
    args = parser.parse_args()

    main_dir = TESTVIDEO / args.corpus_dir
    main_records = []
    for stem in ["1", "2", "3", "4", "5", "6"]:
        p = main_dir / f"{stem}.json"
        if p.exists():
            main_records.append(load_summary(p))

    print_main_corpus(main_records, args.gate)
    threshold_sensitivity(main_records, args.thresholds)
    baseline_scan(args.baselines, args.gate)
    video1_protection_analysis(main_records, args.gate)

if __name__ == "__main__":
    main()
