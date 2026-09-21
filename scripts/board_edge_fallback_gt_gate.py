#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
board_edge_fallback_gt_gate.py
==============================

fallback 降级链路自身的 GT 精度小闸门（spec §12.9 第 3 条 / §12.10 下一步①）。

思路：生产链路 `--board-edge` 单轮跑 CLI（确定性已证，无需多轮），
以主检测 board 帧的 PCA 板轴角作为参照 GT，与「同帧若走降级会合成的
踝对/膝对轴角」配对，量化：
  ① 角度中位绝对误差 ≤ 12°；
  ② 准入精度（误差 ≤12° 帧占比）≥ 90%；
  ③ bit-identical（由 gate_g1_probe 已 PASS，本脚本不重复）。

脚本内用 Python 从 bodyPose 关键点精确复现 BoardEdgeDetector.synthesizeFallback；
先在 JSON 真实 .fallback 帧上交叉验证复现正确（角度/置信度/源逐位对齐），
再用于 board 帧的反事实配对。支持三种选择策略对照（confMax=生产现状 /
anklePreferred=踝优先膝兜底 / ankleOnly=纯踝），输出分源、置信度分桶与
floor 扫描，直接给出 floor + 策略校准建议及该组合下 v2-A/B 的重判结果。

CLI 结果缓存到 outputs/board_edge_p2/fallback_gt_cache.json（.gitignore），
换策略/floor 重算无需重跑 CLI；缓存按视频与 release binary 的 mtime/size 失效。

用法：
  python3 scripts/board_edge_fallback_gt_gate.py            # 44 片
  python3 scripts/board_edge_fallback_gt_gate.py ONLY=BND2_L1,CAND_M04
  python3 scripts/board_edge_fallback_gt_gate.py -n 5
  python3 scripts/board_edge_fallback_gt_gate.py --refresh  # 强制重跑 CLI
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
    CLIPS,
    GATE_G1_V2_CLIP_COV,
    GATE_G1_V2_CLIP_RATIO,
    GATE_G1_V2_WEIGHTED,
    GATE_G1_V2_WEIGHTED_CAP,
    RELEASE_BIN,
    run_cli,
)

PAIR_CNF_FLOOR = 0.30          # fallbackPairConfidenceFloor
KNEE_WEIGHT = 0.60             # fallbackKneeWeight
GEOM_SCALE = 12.0              # fallbackGeometryScale
ERR_THRESHOLD = 12.0           # GT 误差门（度）
ANGLE_TOL = 1e-6               # 交叉验证容差

FLOOR_SCAN = [0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60, 0.70]
CNF_BUCKETS = [(0.30, 0.40), (0.40, 0.50), (0.50, 0.70), (0.70, 1.01)]

NO_FB_TRIGGER = {"board", "rejectPosture", "disabled"}

CACHE_PATH = (
    Path(__file__).resolve().parent.parent
    / "outputs" / "board_edge_p2" / "fallback_gt_cache.json"
)


def pair_axis(p1: dict | None, p2: dict | None, weight: float) -> dict | None:
    """复现 BoardEdgeDetector.fallbackAxis（不施加合成 confidence floor，
    只过点置信度 floor + 间距门），便于 floor 扫描。"""
    if not p1 or not p2:
        return None
    point_cnf = (p1["confidence"] + p2["confidence"]) / 2
    if point_cnf < PAIR_CNF_FLOOR:
        return None
    dx = p2["x"] - p1["x"]
    dy = p2["y"] - p1["y"]
    distance = math.hypot(dx, dy)
    if distance <= 0.001:
        return None
    geom = min(1.0, max(0.0, distance * GEOM_SCALE))
    cnf = point_cnf * geom * weight
    degrees = abs(math.degrees(math.atan2(dy, dx)))
    if degrees > 90:
        degrees = 180 - degrees
    return {"angle": degrees, "confidence": cnf}


def frame_pairs(pose: dict) -> tuple[dict | None, dict | None]:
    ankle = pair_axis(pose.get("leftAnklePoint"), pose.get("rightAnklePoint"), 1.0)
    knee = pair_axis(pose.get("leftKneePoint"), pose.get("rightKneePoint"), KNEE_WEIGHT)
    return ankle, knee


def pick_confmax(ankle: dict | None, knee: dict | None) -> dict | None:
    if ankle and knee:
        return ankle if ankle["confidence"] >= knee["confidence"] else knee
    return ankle or knee


def pick_ankle_preferred(ankle: dict | None, knee: dict | None) -> dict | None:
    if ankle and ankle["confidence"] >= 0.40:
        return ankle
    return knee or ankle


def pick_ankle_only(ankle: dict | None, knee: dict | None) -> dict | None:
    return ankle


POLICIES = {
    "confMax": pick_confmax,
    "anklePreferred": pick_ankle_preferred,
    "ankleOnly": pick_ankle_only,
}


def pct(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    i = min(len(s) - 1, int(round(q * (len(s) - 1))))
    return s[i]


def error_stats(errors: list[float]) -> dict:
    if not errors:
        return {"n": 0}
    within = sum(1 for e in errors if e <= ERR_THRESHOLD)
    return {
        "n": len(errors),
        "median": statistics.median(errors),
        "mean": statistics.fmean(errors),
        "p90": pct(errors, 0.90),
        "max": max(errors),
        "within12": within / len(errors) * 100,
    }


def fmt_stats(s: dict) -> str:
    if not s.get("n"):
        return "n=0"
    return (f"n={s['n']:>4d}  med={s['median']:5.2f}°  mean={s['mean']:5.2f}°  "
            f"p90={s['p90']:5.2f}°  max={s['max']:5.2f}°  "
            f"≤12°={s['within12']:5.1f}%")


def file_sig(path: Path) -> dict:
    st = path.stat()
    return {"mtime": int(st.st_mtime), "size": st.st_size}


def collect(clips, refresh: bool):
    """返回 {alias: {"sig":..., "frames":[{"st":status,"a":[ang,cnf]|None,
    "k":[ang,cnf]|None}]}}，优先读缓存。"""
    cache: dict = {"clips": {}}
    if CACHE_PATH.exists() and not refresh:
        try:
            cache = json.loads(CACHE_PATH.read_text())
        except (ValueError, OSError):
            cache = {"clips": {}}

    bin_sig = file_sig(Path(RELEASE_BIN))
    result = {}
    n_run = 0
    for alias, group, rel in clips:
        video = Path(rel)
        if not video.is_absolute():
            video = Path(__file__).resolve().parent.parent / video
        if not video.exists():
            print(f"[{alias:>14s}] MISS")
            continue
        sig = {"video": file_sig(video), "bin": bin_sig}
        cached = cache.get("clips", {}).get(alias)
        if cached and cached.get("sig") == sig:
            result[alias] = cached
            continue

        data, _ = run_cli(video, board_edge=True)
        frames = []
        xfail = 0
        for fr in data.get("frames") or []:
            obs = fr.get("boardEdgeObservation") or {}
            st = obs.get("status")
            ankle, knee = frame_pairs(fr.get("bodyPose") or {})
            if st == "fallback":
                fb = obs.get("fallbackAxis") or {}
                pick = pick_confmax(ankle, knee)
                ok = (
                    pick is not None
                    and abs(pick["angle"] - fb.get("axisAngle", -999)) < ANGLE_TOL
                    and abs(pick["confidence"] - fb.get("confidence", -999)) < 1e-6
                )
                if not ok:
                    xfail += 1
            frames.append({
                "st": st,
                "ba": obs.get("axisAngle"),
                "a": [ankle["angle"], ankle["confidence"]] if ankle else None,
                "k": [knee["angle"], knee["confidence"]] if knee else None,
            })
        if xfail:
            print(f"[{alias:>14s}] xcheck FAIL ×{xfail}")
        result[alias] = {"sig": sig, "frames": frames}
        n_run += 1
        print(f"[{alias:>14s}] run ({len(frames)} 帧)", flush=True)

    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    CACHE_PATH.write_text(json.dumps({"clips": result}, ensure_ascii=False))
    print(f"→ CLI 实跑 {n_run} 片，其余 {len(result) - n_run} 片命中缓存；缓存已写 {CACHE_PATH.name}")
    return result


def evaluate_policy(name: str, pick_fn, snapshots: dict) -> None:
    total_frames = total_board = total_fb = 0
    sel = []
    sel_ankle = []
    sel_knee = []
    all_ankle = []
    all_knee = []
    clip_rows = []

    for alias, snap in snapshots.items():
        frames = snap["frames"]
        total_frames += len(frames)
        board_n = 0
        pick_confs: list = []
        for fr in frames:
            st = fr["st"]
            ankle = {"angle": fr["a"][0], "confidence": fr["a"][1]} if fr["a"] else None
            knee = {"angle": fr["k"][0], "confidence": fr["k"][1]} if fr["k"] else None
            pick = pick_fn(ankle, knee)
            pick_confs.append(
                pick["confidence"] if (pick and st not in NO_FB_TRIGGER) else None
            )
            if st == "fallback":
                total_fb += 1
            if st == "board":
                total_board += 1
                board_n += 1
                ba = fr.get("ba")
                if ba is None:
                    continue
                if ankle:
                    all_ankle.append((abs(ankle["angle"] - ba), ankle["confidence"]))
                if knee:
                    all_knee.append((abs(knee["angle"] - ba), knee["confidence"]))
                if pick:
                    src = "ankle" if (ankle and pick["confidence"] == ankle["confidence"]) else "knee"
                    row = (abs(pick["angle"] - ba), pick["confidence"], src)
                    sel.append(row)
                    (sel_ankle if src == "ankle" else sel_knee).append(row)
        clip_rows.append((alias, len(frames), board_n, pick_confs))

    print("\n" + "#" * 94)
    print(f"# 策略 {name}")
    print("#" * 94)
    print(f"样本：{len(snapshots)} 片 / {total_frames} 帧；board {total_board}；生产 .fallback {total_fb}")

    s_all = error_stats([e for e, _, _ in sel])
    print(f"\n①② 选中轴总体：{fmt_stats(s_all)}")
    print(f"   选踝 {len(sel_ankle)} 帧" + (
        ("：" + fmt_stats(error_stats([e for e, _, _ in sel_ankle]))) if sel_ankle else ""))
    print(f"   选膝 {len(sel_knee)} 帧" + (
        ("：" + fmt_stats(error_stats([e for e, _, _ in sel_knee]))) if sel_knee else ""))
    print(f"   参考·全踝对：{fmt_stats(error_stats([e for e, _ in all_ankle]))}")
    print(f"   参考·全膝对：{fmt_stats(error_stats([e for e, _ in all_knee]))}")

    print(f"\n置信度分桶（选中轴）：")
    for lo, hi in CNF_BUCKETS:
        es = [e for e, c, _ in sel if lo <= c < hi]
        print(f"  [{lo:.2f},{hi:.2f})  {fmt_stats(error_stats(es))}")

    print(f"\nfloor 扫描（有效帧 = board + 选中合成 conf≥floor）：")
    print(f"  {'floor':>5s}  {'effCov%':>8s}  {'v2-A':>14s}  {'v2-B':>6s}  "
          f"{'GTn':>5s}  {'GT med':>7s}  {'≤12°%':>7s}  闸门")
    tf_all = sum(r[1] for r in clip_rows)
    for floor in FLOOR_SCAN:
        total_eff = clips_pass = 0
        weighted = 0.0
        for alias, n_tot, bn, confs in clip_rows:
            fb_eff = sum(1 for c in confs if c is not None and c >= floor)
            eff = bn + fb_eff
            total_eff += eff
            eff_pct = eff / n_tot * 100 if n_tot else 0
            if eff_pct >= GATE_G1_V2_CLIP_COV:
                clips_pass += 1
            weighted += min(eff_pct, GATE_G1_V2_WEIGHTED_CAP) * n_tot
        eff_cov = total_eff / tf_all * 100 if tf_all else 0
        v2a = clips_pass / len(clip_rows) * 100 if clip_rows else 0
        v2b = weighted / tf_all if tf_all else 0
        gt = [e for e, c, _ in sel if c >= floor]
        gs = error_stats(gt)
        gmed = gs.get("median", float("nan"))
        gw = gs.get("within12", 0)
        v2_ok = v2a >= GATE_G1_V2_CLIP_RATIO * 100 or v2b >= GATE_G1_V2_WEIGHTED
        gt_ok = gs.get("n", 0) > 0 and gmed <= ERR_THRESHOLD and gw >= 90
        verdict = "GO" if (v2_ok and gt_ok) else ("v2过/GT?" if v2_ok else "no")
        print(f"  {floor:5.2f}  {eff_cov:7.2f}%  {v2a:5.1f}%({clips_pass:>2}/{len(clip_rows)})  "
              f"{v2b:6.2f}  {gs.get('n', 0):5d}  {gmed:6.2f}°  {gw:6.1f}%  {verdict}")

    g1 = s_all.get("median", 99) <= 12
    g2 = s_all.get("within12", 0) >= 90
    print(f"\n小闸门：①中位 {s_all.get('median', 0):.2f}° {'PASS' if g1 else 'FAIL'}；"
          f"②准入 {s_all.get('within12', 0):.1f}% {'PASS' if g2 else 'FAIL'}；"
          f"③bit PASS → 总判定 {'PASS' if g1 and g2 else 'FAIL'}")


def main() -> None:
    ap = argparse.ArgumentParser(description="fallback GT 精度小闸门")
    ap.add_argument("selectors", nargs="*")
    ap.add_argument("-n", "--limit", type=int, default=0)
    ap.add_argument("--refresh", action="store_true", help="忽略缓存重跑 CLI")
    args = ap.parse_args()

    only: set[str] | None = None
    for sel in args.selectors:
        if sel.startswith("ONLY="):
            only = set(sel[len("ONLY="):].split(","))
        else:
            only = set(sel.split(","))
    clips = CLIPS
    if only is not None:
        clips = [c for c in CLIPS if c[0] in only]
    if args.limit:
        clips = clips[: args.limit]

    print(f"→ 目标 {len(clips)} 片（每片 CLI ×1，--board-edge；确定性已证）")
    snapshots = collect(clips, refresh=args.refresh)

    for pname, pfn in POLICIES.items():
        evaluate_policy(pname, pfn, snapshots)


if __name__ == "__main__":
    main()
