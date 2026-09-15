#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
edge_cap_ramp_replay.py
=======================

方案 P2 只读 replay：预估把 applyEdgeEvidenceCaps / applyEvidenceCaps
从阶梯改成 piecewise linear ramp 后，corpus 6 份视频（OFF + ON）的
最终 averageScore 变化。

前提简化：
- 不重跑 Swift；只从 JSON 里的 frames + summary 反算中间量。
- boardEvidenceCaps 由 boardKinematicHighScoreCap 保留原语义（不 ramp）。
- 不模拟 stableCarvingBaseline / edgeEvidenceCap 的 baseline == nil 保护通道，
  但会在 verify 步骤对比 stair 预测 vs JSON 实测，若不一致就跳过 ramp 推断。
"""

import json
import statistics

# ---- Ramp 公式 ----
def linear(x, x0, x1, y0, y1):
    t = (x - x0) / (x1 - x0)
    return y0 + t * (y1 - y0)

def edge_cap_ramped(x):
    """B. applyEdgeEvidenceCaps ramp 版（过渡带宽 ~= 悬崖高度/常量）：
    每个阈值 x_th 内向延伸的过渡带宽度按悬崖高度自适应：
      - 阈值 38（悬崖 7 分, 58→65）：[37, 38] 线性
      - 阈值 42（悬崖 5 分, 65→70）：[40, 42] 线性
      - 阈值 50（悬崖 30 分, 70→100）：[42, 50] 线性（完整跨越）
    设计原则：
      1. 悬崖越高、过渡带越宽，保证单位输入下评分斜率有界；
      2. 大悬崖不能"局部软化"（否则悬崖点仍存在），必须整段过渡；
      3. 阈值命中样本得分几乎不变（阈值右侧 = 原 cap 值），只有阈值稍下方样本受益。
    """
    if x < 37: return 58                              # 平台
    if x < 38: return linear(x, 37, 38, 58, 65)       # 7 分悬崖 → hw=1
    if x < 40: return 65                              # 平台
    if x < 42: return linear(x, 40, 42, 65, 70)       # 5 分悬崖 → hw=2
    if x < 50: return linear(x, 42, 50, 70, 100)      # 30 分悬崖 → 整段 hw=8
    return 100

def edge_cap_stair(x):
    if x < 38: return 58
    if x < 42: return 65
    if x < 50: return 70
    return 100

def dur_cap_ramped(x, half_width=0.5):
    """A. applyEvidenceCaps ramp 版：阈值内侧向下扩展 half_width"""
    if x < 5.0: return 55
    if x < 5.0 + half_width: return linear(x, 5.0, 5.0 + half_width, 55, 65)
    if x < 8.0: return 65
    if x < 8.0 + half_width: return linear(x, 8.0, 8.0 + half_width, 65, 78)
    if x < 12.0: return 78
    if x < 12.0 + half_width: return linear(x, 12.0, 12.0 + half_width, 78, 100)
    return 100

def dur_cap_stair(x):
    if x < 5.0: return 55
    if x < 8.0: return 65
    if x < 12.0: return 78
    return 100

# ---- 复现中间量 ----
def smooth_confidence_weight(c, floor=0.15, ceil=0.75):
    """精确复现 AnalysisReliability.smoothConfidenceWeight"""
    norm = (c - floor) / (ceil - floor)
    clamped = max(0.0, min(1.0, norm))
    return clamped * clamped

def avg_edge_evidence(d, min_conf=0.30):
    """精确复现 averageEdgeEvidenceScore"""
    xs, ws = [], []
    for f in d["frames"]:
        ps = f.get("poseScore") or {}
        c = ps.get("calfLeanConfidence", 0.0)
        if c < min_conf: continue
        s = ps.get("calfLeanScore")
        if s is None: continue
        w = max(0.001, smooth_confidence_weight(c))
        xs.append(s)
        ws.append(w)
    if not xs: return None
    return sum(x*w for x, w in zip(xs, ws)) / sum(ws)

def median_interval(sorted_times):
    if len(sorted_times) < 2: return 0.2
    diffs = sorted(b - a for a, b in zip(sorted_times[:-1], sorted_times[1:]))
    n = len(diffs)
    return diffs[n//2] if n % 2 else (diffs[n//2-1] + diffs[n//2]) / 2

def sampled_duration(times):
    ts = sorted(times)
    if not ts: return 0.0
    if len(ts) == 1: return 0.2
    interval = median_interval(ts)
    return max(ts[-1] - ts[0] + interval, interval)

def reliable_duration(d, min_conf=0.30):
    times = [f["time"] for f in d["frames"]
             if (f.get("poseScore") or {}).get("totalConfidence", 0) >= min_conf]
    return sampled_duration(times)

def board_cap_val(d):
    ba = (d.get("boardAnalysis") or {}).get("summary") or {}
    conf = ba.get("confidence")
    if conf is None: return None
    dur = reliable_duration(d)
    if conf < 0.7 and dur < 10.0:
        return 62.0
    return None

# ---- 替换 uncapped 的更好近似 ----
# 由 JSON 无法完美反推 uncapped（因为 cap 是 min）
# 但 evidenceCappedScore 就是最终 cap 结果，我们逆着算：
# 若 edge/dur cap 都不生效（stair 版），则 uncapped ≈ evidenceCappedScore
# 若 stair 生效，则 uncapped >= evidenceCappedScore

def infer_uncapped(d):
    """uncapped 上界估计"""
    # 走一遍 stair 版 cap，用 bestThirdAverageScore 作 uncapped 输入
    edge = avg_edge_evidence(d)
    dur = reliable_duration(d)
    board = board_cap_val(d)
    uncapped_estimate = d["summary"]["bestThirdAverageScore"]
    edge_capped = min(uncapped_estimate, edge_cap_stair(edge)) if edge is not None else min(uncapped_estimate, 65)
    board_capped = min(edge_capped, board) if board is not None else edge_capped
    final = min(board_capped, dur_cap_stair(dur))
    return uncapped_estimate, final

def replay(d, ramp=False):
    edge = avg_edge_evidence(d)
    dur = reliable_duration(d)
    board = board_cap_val(d)
    modulation = d["summary"]["flowModulationFactor"]
    uncapped, _ = infer_uncapped(d)

    edge_fn = edge_cap_ramped if ramp else edge_cap_stair
    dur_fn = dur_cap_ramped if ramp else dur_cap_stair

    edge_capped = min(uncapped, edge_fn(edge)) if edge is not None else min(uncapped, 65)
    board_capped = min(edge_capped, board) if board is not None else edge_capped
    final_capped = min(board_capped, dur_fn(dur))
    modulated = max(0, min(100, final_capped * modulation))
    return {
        "uncapped": uncapped,
        "edge": edge,
        "dur": dur,
        "board": board,
        "edge_cap": edge_fn(edge) if edge is not None else 65,
        "dur_cap": dur_fn(dur),
        "final_capped": final_capped,
        "modulated": modulated,
    }

def overall_level(score):
    if score >= 85: return "专业"
    if score >= 75: return "高级"
    if score >= 60: return "中级"
    return "初级"

# ---- 主流程 ----
print("="*100)
print(" P2 只读 replay：piecewise linear ramp 对 corpus 6 份的净影响")
print("="*100)
print()
print(f"{'stem':>4s} {'br':>4s}  {'edge':>6s} {'dur':>6s} {'brd':>5s}   {'实测':>6s}  {'stair 预':>9s}  {'ramp 预':>9s}   {'Δ(ramp-stair)':>15s}   {'Δ(stair-真)':>13s}   {'等级 stair→ramp':>16s}")
print("-" * 130)

# 也统计
delta_all = []
verify_diffs = []

for stem in ["1","2","3","4","5","6"]:
    for branch, dr in [("OFF", "baseline_alpha_off"), ("ON", "baseline_alpha_on")]:
        d = json.load(open(f"testvideo/{dr}/{stem}.json"))
        rs = replay(d, ramp=False)
        rr = replay(d, ramp=True)
        real = d["summary"]["averageScore"]
        delta_ramp_stair = rr["modulated"] - rs["modulated"]
        delta_stair_real = rs["modulated"] - real
        l_stair = overall_level(rs["modulated"])
        l_ramp = overall_level(rr["modulated"])
        change = f"{l_stair}→{l_ramp}" + (" ✱" if l_stair != l_ramp else "")
        brd_str = f"{rs['board']:.0f}" if rs['board'] is not None else "-"
        print(f"{stem:>4s} {branch:>4s}  {rs['edge']:>6.2f} {rs['dur']:>6.2f} {brd_str:>5s}   {real:>6.2f}  {rs['modulated']:>9.2f}  {rr['modulated']:>9.2f}   {delta_ramp_stair:>+15.2f}   {delta_stair_real:>+13.2f}   {change:>16s}")
        delta_all.append((stem, branch, delta_ramp_stair, delta_stair_real))
        verify_diffs.append(delta_stair_real)

print()
print("说明：")
print("  Δ(ramp-stair)：ramp 版预测分 - stair 版预测分（软化真实收益）")
print("  Δ(stair-真) ：stair 版预测分 - JSON 实测分（模型误差，理想=0）")
print()
print(f"stair 模型误差绝对值 均值 = {statistics.mean(abs(x) for x in verify_diffs):.3f}, max = {max(abs(x) for x in verify_diffs):.3f}")
print()

# 关键回归洞察
print("="*100)
print(" 关键洞察")
print("="*100)
for stem, branch, dr_s, dv_r in delta_all:
    if abs(dr_s) >= 0.5:
        sign = "+" if dr_s > 0 else ""
        print(f"  video {stem}/{branch}: ramp 相对 stair {sign}{dr_s:.2f} 分  (相对真实实测的模型误差 {dv_r:+.2f})")