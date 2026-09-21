#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
board_edge_fallback_temporal_spike.py
=====================================

方向 D 离线 spike（spec §12.11 下一步「候选 D：时序累积」）：把 fallback pick
从「单帧散点」升级为「前向 W 帧滑窗 + 中位滤波 + IQR 稳定性门控」，看能否把
[0.30, 0.40) 低置信桶散点角度误差压掉，同时守住 v2-A/B 可用性数字。

- **数据源**：完全复用 [board_edge_fallback_gt_gate.py](./board_edge_fallback_gt_gate.py)
  已产出的 `outputs/board_edge_p2/fallback_gt_cache.json`（每片 44 片 × N 帧的
  {st, ba(board GT), a=[ang,cnf], k=[ang,cnf]}）；不重跑 CLI、不改生产代码。
- **窗口口径**：对第 f 帧，窗口 = [f-W+1 .. f]（右闭前向），仅收集 pick 策略
  在非 NO_FB_TRIGGER (board/rejectPosture/disabled) 状态帧上得到、且 conf ≥ floor
  的候选。窗口通过条件：候选数 ≥ ceil(W/2) 且 IQR(angles) ≤ stab_iqr。
- **GT 评估**：对本来是 board 的帧 f（有 ba），用窗口 [f-W .. f-1]（**不含 f 本身**，
  模拟"如果这帧走 fallback，前向窗口聚合会得到什么角"）；聚合通过后与 ba 比误差。
- **v2 指标**：effCov = board 帧数 + 窗口通过帧数（不重叠）；v2-A/B 沿用 gate_g1_probe
  的常量与 cap 值。
- **短片风险**：全 44 片帧数 ≥ 55，W ∈ {5,7} 无缺样；脚本仍保留 `MIN_COUNT` 判定
  并索引"窗口内候选不足" 帧占比作诊断。

用法：
  python3 scripts/board_edge_fallback_temporal_spike.py               # 默认扫描
  python3 scripts/board_edge_fallback_temporal_spike.py ONLY=BND_HI1  # 单片
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from board_edge_gate_g1_probe import (  # noqa: E402
    GATE_G1_V2_CLIP_COV,
    GATE_G1_V2_CLIP_RATIO,
    GATE_G1_V2_WEIGHTED,
    GATE_G1_V2_WEIGHTED_CAP,
)
from board_edge_fallback_gt_gate import (  # noqa: E402
    CACHE_PATH,
    ERR_THRESHOLD,
    NO_FB_TRIGGER,
    pick_ankle_only,
    pick_ankle_preferred,
    pick_confmax,
)

POLICIES = {
    "confMax": pick_confmax,
    "anklePreferred": pick_ankle_preferred,
    "ankleOnly": pick_ankle_only,
}

WINDOWS = [1, 5, 7]           # 1 用作 baseline（等价单帧 GT gate）
IQR_GATES = [5.0, 8.0, 999.0] # 999 = 关闭稳定性门控（仅 count）
FLOORS = [0.30, 0.35, 0.40]


def to_pick_pair(fr: dict, pick_fn):
    """从缓存帧字段还原 (ankle, knee, pick)。"""
    ankle = ({"angle": fr["a"][0], "confidence": fr["a"][1]} if fr.get("a") else None)
    knee = ({"angle": fr["k"][0], "confidence": fr["k"][1]} if fr.get("k") else None)
    pick = pick_fn(ankle, knee)
    if pick is None:
        return None
    src = "ankle" if (ankle and pick["confidence"] == ankle["confidence"]) else "knee"
    return {"angle": pick["angle"], "confidence": pick["confidence"], "src": src}


def build_candidates(frames: list, pick_fn, floor: float) -> list:
    """返回与 frames 等长的 list；元素为 pick dict 或 None。
    只在非 NO_FB_TRIGGER 帧且 pick.conf ≥ floor 时保留。"""
    out = []
    for fr in frames:
        st = fr.get("st")
        if st in NO_FB_TRIGGER:
            out.append(None)
            continue
        pick = to_pick_pair(fr, pick_fn)
        if pick is None or pick["confidence"] < floor:
            out.append(None)
            continue
        out.append(pick)
    return out


def _iqr(values: list[float]) -> float:
    if len(values) < 2:
        return 0.0
    s = sorted(values)
    n = len(s)
    q1 = s[int(0.25 * (n - 1))]
    q3 = s[int(0.75 * (n - 1))]
    return q3 - q1


def aggregate(window: list) -> dict | None:
    """window: list of pick dict (无 None，调用方已过滤)。"""
    if not window:
        return None
    angles = [p["angle"] for p in window]
    conf = statistics.median([p["confidence"] for p in window])
    med = statistics.median(angles)
    iqr = _iqr(angles)
    # 源多数派
    counts = {"ankle": 0, "knee": 0}
    for p in window:
        counts[p["src"]] += 1
    src = "ankle" if counts["ankle"] >= counts["knee"] else "knee"
    return {"angle": med, "confidence": conf, "iqr": iqr, "src": src, "n": len(window)}


def window_pass(agg: dict | None, window_size: int, iqr_gate: float) -> bool:
    if agg is None:
        return False
    min_count = math.ceil(window_size / 2)
    if agg["n"] < min_count:
        return False
    if agg["iqr"] > iqr_gate:
        return False
    return True


def evaluate(snapshots: dict, policy_name: str, floor: float,
             window: int, iqr_gate: float) -> dict:
    pick_fn = POLICIES[policy_name]
    total_frames = 0
    total_board = 0
    total_effective = 0
    errors: list[float] = []
    src_errors = {"ankle": [], "knee": []}
    gt_pairs = 0        # 有 GT 的 board 帧数
    gt_agg_pass = 0     # 有 GT 且窗口通过的帧数
    clip_rows = []      # [(n_total, n_board, n_effective, effCov%)]
    low_conf_shortfall = 0  # 因候选数不足被拒的帧
    stab_reject = 0     # 因 IQR 超门被拒的帧

    for alias, snap in snapshots.items():
        frames = snap["frames"]
        n_tot = len(frames)
        cands = build_candidates(frames, pick_fn, floor)
        board_n = 0
        eff_n = 0
        for f, fr in enumerate(frames):
            st = fr.get("st")
            if st == "board":
                board_n += 1
                # GT 评估：用 f 之前 W 帧的候选（不含 f 本身）
                lo = max(0, f - window)
                win = [c for c in cands[lo:f] if c is not None]
                agg = aggregate(win)
                if fr.get("ba") is not None:
                    gt_pairs += 1
                    if window_pass(agg, window, iqr_gate):
                        gt_agg_pass += 1
                        err = abs(agg["angle"] - fr["ba"])
                        errors.append(err)
                        src_errors[agg["src"]].append(err)
                continue
            if st in NO_FB_TRIGGER:
                continue  # rejectPosture / disabled 不参与 effCov
            # 非 board 帧：这一帧本身可能会走 fallback；用 [f-W+1..f] 前向窗口聚合
            lo = max(0, f - window + 1)
            win = [c for c in cands[lo: f + 1] if c is not None]
            agg = aggregate(win)
            if agg is None or agg["n"] < math.ceil(window / 2):
                low_conf_shortfall += 1
                continue
            if agg["iqr"] > iqr_gate:
                stab_reject += 1
                continue
            eff_n += 1
        total_frames += n_tot
        total_board += board_n
        total_effective += board_n + eff_n
        eff_pct = (board_n + eff_n) / n_tot * 100 if n_tot else 0.0
        clip_rows.append((alias, n_tot, board_n, board_n + eff_n, eff_pct))

    within = sum(1 for e in errors if e <= ERR_THRESHOLD)
    within_pct = within / len(errors) * 100 if errors else 0.0
    med_err = statistics.median(errors) if errors else float("nan")

    weighted = 0.0
    clips_pass = 0
    for _alias, n_tot, _board_n, _eff_abs, eff_pct in clip_rows:
        if eff_pct >= GATE_G1_V2_CLIP_COV:
            clips_pass += 1
        weighted += min(eff_pct, GATE_G1_V2_WEIGHTED_CAP) * n_tot
    v2a = clips_pass / len(clip_rows) * 100 if clip_rows else 0.0
    v2b = weighted / total_frames if total_frames else 0.0
    eff_cov = total_effective / total_frames * 100 if total_frames else 0.0

    return {
        "policy": policy_name, "floor": floor, "W": window, "iqr": iqr_gate,
        "gtPairs": gt_pairs, "gtPass": gt_agg_pass,
        "gtCoverage": (gt_agg_pass / gt_pairs * 100) if gt_pairs else 0.0,
        "errN": len(errors), "medErr": med_err, "within12": within_pct,
        "srcAnkleN": len(src_errors["ankle"]),
        "srcKneeN": len(src_errors["knee"]),
        "medErrAnkle": statistics.median(src_errors["ankle"]) if src_errors["ankle"] else float("nan"),
        "within12Ankle": (sum(1 for e in src_errors["ankle"] if e <= ERR_THRESHOLD) / len(src_errors["ankle"]) * 100) if src_errors["ankle"] else 0.0,
        "medErrKnee": statistics.median(src_errors["knee"]) if src_errors["knee"] else float("nan"),
        "within12Knee": (sum(1 for e in src_errors["knee"] if e <= ERR_THRESHOLD) / len(src_errors["knee"]) * 100) if src_errors["knee"] else 0.0,
        "effCov": eff_cov, "v2A": v2a, "v2B": v2b,
        "clipsPass": clips_pass, "clipsTotal": len(clip_rows),
        "shortfall": low_conf_shortfall, "stabReject": stab_reject,
        "clipRows": clip_rows,
    }


def print_row(r: dict) -> None:
    gt_ok = (not math.isnan(r["medErr"])
             and r["medErr"] <= ERR_THRESHOLD
             and r["within12"] >= 90.0)
    v2_ok = (r["v2A"] >= GATE_G1_V2_CLIP_RATIO * 100
             or r["v2B"] >= GATE_G1_V2_WEIGHTED)
    verdict = "GO" if (gt_ok and v2_ok) else ("v2过/GT?" if v2_ok else ("GT过/v2?" if gt_ok else "no"))
    iqr = "∞" if r["iqr"] >= 900 else f"{r['iqr']:.0f}"
    print(f"  {r['policy']:>13s}  floor={r['floor']:.2f}  W={r['W']}  IQR≤{iqr:>3s}  "
          f"GTn={r['errN']:>4d}/{r['gtPairs']:>4d}  "
          f"med={r['medErr']:5.2f}°  ≤12°={r['within12']:5.1f}%  "
          f"effCov={r['effCov']:5.2f}%  v2A={r['v2A']:5.1f}%({r['clipsPass']:>2}/{r['clipsTotal']})  "
          f"v2B={r['v2B']:5.2f}  {verdict}")


def main() -> None:
    ap = argparse.ArgumentParser(description="fallback 时序累积 spike (方向 D)")
    ap.add_argument("selectors", nargs="*",
                    help="过滤：ONLY=alias1,alias2 或直接给别名")
    ap.add_argument("--windows", default=",".join(str(w) for w in WINDOWS),
                    help="窗口大小逗号分隔，默认 1,5,7")
    ap.add_argument("--iqrs", default=",".join(str(i) for i in IQR_GATES),
                    help="IQR 门控逗号分隔（度），999=关闭；默认 5,8,999")
    ap.add_argument("--floors", default=",".join(str(f) for f in FLOORS),
                    help="pair floor 逗号分隔；默认 0.30,0.35,0.40")
    ap.add_argument("--policies", default=",".join(POLICIES.keys()),
                    help="策略逗号分隔；默认三者全跑")
    args = ap.parse_args()

    if not CACHE_PATH.exists():
        sys.exit(f"未找到缓存 {CACHE_PATH}；请先跑 board_edge_fallback_gt_gate.py 生成")
    cache = json.loads(CACHE_PATH.read_text())
    snapshots = cache.get("clips", {})

    only: set[str] | None = None
    for sel in args.selectors:
        if sel.startswith("ONLY="):
            only = set(sel[len("ONLY="):].split(","))
        else:
            only = set(sel.split(","))
    if only is not None:
        snapshots = {a: s for a, s in snapshots.items() if a in only}

    windows = [int(w) for w in args.windows.split(",") if w.strip()]
    iqrs = [float(i) for i in args.iqrs.split(",") if i.strip()]
    floors = [float(f) for f in args.floors.split(",") if f.strip()]
    policies = [p.strip() for p in args.policies.split(",") if p.strip()]
    for p in policies:
        if p not in POLICIES:
            sys.exit(f"未知策略 {p}；可选 {list(POLICIES)}")

    n_tot_frames = sum(len(s["frames"]) for s in snapshots.values())
    n_board = sum(1 for s in snapshots.values() for f in s["frames"] if f.get("st") == "board")
    print(f"→ 样本 {len(snapshots)} 片 / {n_tot_frames} 帧；board {n_board}；"
          f"windows={windows} iqrs={iqrs} floors={floors} policies={policies}")
    print("=" * 106)
    print("  policy         floor      W   IQR gate  GT hits           med err   ≤12°      effCov  v2-A            v2-B    判定")

    all_rows: list[dict] = []
    for pn in policies:
        for f in floors:
            for w in windows:
                for iqr in iqrs:
                    r = evaluate(snapshots, pn, f, w, iqr)
                    all_rows.append(r)
                    print_row(r)

    # ---- 最优候选选取（同时满足 GT + v2 才算 GO；否则依次按 GT 达标、v2 达标排序）----
    gos = [r for r in all_rows
           if r["errN"] and r["medErr"] <= ERR_THRESHOLD
           and r["within12"] >= 90 and (r["v2A"] >= GATE_G1_V2_CLIP_RATIO * 100
                                        or r["v2B"] >= GATE_G1_V2_WEIGHTED)]
    print("\n" + "-" * 106)
    if gos:
        gos.sort(key=lambda r: (-r["effCov"], -r["within12"], r["floor"]))
        print(f"GO 组合 {len(gos)}：")
        for r in gos[:5]:
            print_row(r)
    else:
        print("无 GO 组合（GT 全过 + v2 有一项过）。")
        # 输出 GT 过但 v2 差最少的 top 3，与 v2 过但 GT 差最少的 top 3
        gt_ok = [r for r in all_rows if r["errN"] and r["medErr"] <= ERR_THRESHOLD and r["within12"] >= 90]
        gt_ok.sort(key=lambda r: -max(r["v2A"] / (GATE_G1_V2_CLIP_RATIO * 100), r["v2B"] / GATE_G1_V2_WEIGHTED))
        if gt_ok:
            print("  GT 达标，v2 最接近门槛的组合：")
            for r in gt_ok[:3]:
                print_row(r)
        v2_ok = [r for r in all_rows if r["v2A"] >= GATE_G1_V2_CLIP_RATIO * 100 or r["v2B"] >= GATE_G1_V2_WEIGHTED]
        v2_ok.sort(key=lambda r: -r["within12"])
        if v2_ok:
            print("  v2 达标，准入精度最接近的组合：")
            for r in v2_ok[:3]:
                print_row(r)

    # ---- 短片窗口缺样风险 ----
    print("\n短片窗口缺样风险：")
    for w in windows:
        short = [(a, len(s["frames"])) for a, s in snapshots.items() if len(s["frames"]) < w]
        print(f"  W={w}: 帧数 < W 的片 {len(short)}" + (f" -> {short}" if short else ""))


if __name__ == "__main__":
    main()
