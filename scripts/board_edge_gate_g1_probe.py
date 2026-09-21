#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
board_edge_gate_g1_probe.py
===========================

Gate-G1（观测器工程质量）三合一探针。2026-09-20 ADR-002 后升级为 v3 主判定 + v2 对照。

对边界集每片跑三轮 CLI：
  A. `--board-edge` (第 1 次)
  B. `--board-edge` (第 2 次，判 bit-identical，含 fallbackAxis 全字段)
  C. 基线（不加 flag，算耗时增幅）

对每片给出：
  - **覆盖率三口径**：raw = status=board；effective_v2 = board + fallback≥0.30（历史对照）；
    effective_v3 = board + fallback≥0.40（ADR-002 生产默认）。
    Gate-G1 v3 按片级可用性判定：v3-B eff≥25% 片占比≥60%；或 v3-A 帧加权可用性≥40。
  - **确定性**：A vs B 逐帧全字段（含 fallbackAxis）bit-identical。
  - **性能**：wall-clock A vs C，增幅 ≤30%。

用法：
  swift build -c release
  python3 scripts/board_edge_gate_g1_probe.py                 # 44 片全跑
  python3 scripts/board_edge_gate_g1_probe.py ONLY=BND_L1
  python3 scripts/board_edge_gate_g1_probe.py -n 3
  python3 scripts/board_edge_gate_g1_probe.py --build
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASE_BIN = ROOT / ".build" / "release" / "FallLineCLI"

# §4.4 标注集（44 片全部已判）：alias, group, relpath
# group 口径：high=专业/高质量刻滑档，mid=中级/中级偏上，low=初级（第三批 2026-09-19 按接触表回填）。
CLIPS: list[tuple[str, str, str]] = [
    # ---- BND* (11 片) ----
    ("BND_HI1", "high",  "video/middle/9714be3aba73f5f94130750c2a15d381.MP4"),
    ("BND_HI2", "high",  "video/middle/4f9ec73b994b63b0775ccfb7a8ef7e6f.MP4"),
    ("BND_HI3", "high",  "video/middle/b343b317a6689df373085ec85e042480.MP4"),
    ("BND_M1",  "mid",   "video/middle/v0200fg10000d318sovog65g16lolm8g.MP4"),
    ("BND_M2",  "mid",   "video/middle/v0200fg10000coc7bcrc77u875h9q7sg.MP4"),
    ("BND_M3",  "mid",   "video/middle/v0300fg10000d6fe0nnog65jmdun29vg.MP4"),
    ("BND_M4",  "mid",   "video/middle/v0d00fg10000cu3omkvog65r22seg0t0.MP4"),
    ("BND_L1",  "mid",   "video/middle/v1e00fgi0000d5bksdfog65irrhr4bog.MP4"),
    ("BND_L2",  "mid",   "video/middle/v0300fg10000d5h313fog65nermuqklg.MP4"),
    ("BND_L3",  "mid",   "video/middle/v2800fgi0000d54jhefog65lbfdhma2g.MP4"),
    # ---- BND2_* (14 片) ----
    ("BND2_TOP", "high", "video/good/v1e00fgi0000d2bufenog65temc6sh70.MP4"),
    ("BND2_H4",  "high", "video/good/v0200fg10000d6mln8vog65kajcq52dg.MP4"),
    ("BND2_H3",  "high", "video/good/v2800fgi0000d7o00ufog65t0ran4h1g.MP4"),
    ("BND2_H2",  "high", "video/good/v0300fg10000d7h0ckfog65nmsn20jqg.MP4"),
    ("BND2_H1",  "high", "video/good/v1e00fgi0000d5utfk7og65q1chsrq8g.MP4"),
    ("BND2_H0",  "high", "video/good/86ae42724c8349913703af0f4140f6d2.MP4"),
    ("BND2_GM",  "high", "video/good/d63bfbf8978cf8a962f613a489a14420.MP4"),
    ("BND2_LB",  "low",  "video/bad/v0300fg10000cusoptnog65pkehng280.MP4"),
    ("BND2_L6",  "low",  "video/bad/v0200fg10000d6olrffog65vrste5qqg.MOV"),
    ("BND2_LM",  "low",  "video/bad/v0200fg10000d7nnh5vog65i52ermgog.MP4"),
    ("BND2_L5",  "low",  "video/bad/v0300fg10000d664l37og65t6pnbois0.MOV"),
    ("BND2_L4",  "low",  "video/bad/v1e00fgi0000cv786ffog65rtmm48gmg.MOV"),
    ("BND2_L3",  "low",  "video/bad/v2800fgi0000d4v24r7og65oi0fmka5g.MP4"),
    ("BND2_L2",  "low",  "video/bad/v0d00fg10000ctm0ufvog65rqb97g2p0.MP4"),
    ("BND2_L1",  "low",  "video/bad/v0d00fg10000csgr6inog65n8mlpg2m0.MP4"),
    # ---- CAND_* 第三批 19 片（档位已按教练接触表回填，2026-09-19）----
    ("CAND_G01", "high", "video/good/0946ed384e732c357a3d55fac77426c0.MP4"),
    ("CAND_G02", "high", "video/good/3134552bed78447b9f7ba8e2003ce678.MP4"),
    ("CAND_G03", "high", "video/good/3e6f37fe76521781506c19c02c1b97ed.MP4"),
    ("CAND_G04", "high", "video/good/5382da0c825e30518ab376505cbcfaf2.MOV"),
    ("CAND_G05", "high", "video/good/641efed02be271b6d9f014c97d1f8ae0.MOV"),
    ("CAND_G06", "high", "video/good/9ed0bb6c707fc47fce153cee3dcd365e.MP4"),
    ("CAND_G07", "high", "video/good/v0200fg10000d7r0017og65qoh1vgeg0.MP4"),
    ("CAND_G08", "high", "video/good/v2800fgi0000d6m0mk7og65qamcvgf80.MP4"),
    ("CAND_M01", "low",  "video/middle/1c5771fc7dd1ea546eb5bc3e4e01bc48.MP4"),
    ("CAND_M02", "mid",  "video/middle/4a7dfe960f07ac14b06bbd8de3d38aa4.MP4"),
    ("CAND_M03", "high", "video/middle/96001e37e76be9ef6cf7a65e73efcac4.MP4"),
    ("CAND_M04", "mid",  "video/middle/992f063b79d27b96b471e44a48d8465e.MP4"),
    ("CAND_M05", "high", "video/middle/a7791a475a244c938dd0815e89b1dec5.MP4"),
    ("CAND_M06", "mid",  "video/middle/ccfd9967aa6d3ab5abd04fb8991872c7.MOV"),
    ("CAND_M07", "mid",  "video/middle/v0200fg10000d2tcts7og65t6h63ua2g.MP4"),
    ("CAND_M08", "mid",  "video/middle/v0200fg10000d6a4i57og65mkjkcdpu0.MP4"),
    ("CAND_M09", "low",  "video/middle/v0300fg10000d4oq6avog65ihr8qf550.MP4"),
    ("CAND_M10", "high", "video/middle/v2800fgi0000d5ehg1vog65tinkepgl0.MP4"),
    ("CAND_B01", "mid",  "video/bad/0b7522e9db823b910ac67727aea726da.MP4"),
]

GATE_G1_RAW_COVERAGE = 0.60          # v1 理想覆盖率（观察项）
GATE_G1_PERF_HEADROOM = 0.30
GATE_G1_V2_CLIP_COV = 30.0            # v2 片级 effCov% 门槛
GATE_G1_V2_CLIP_RATIO = 0.60          # v2 达标片占比门槛
GATE_G1_V2_WEIGHTED = 40.0            # v2 帧加权可用性门槛
GATE_G1_V2_WEIGHTED_CAP = 60.0        # Σ min(effCov%, 该 cap)·f/F，spec §6
FALLBACK_CONFIDENCE_FLOOR_V2 = 0.30   # v2 对照口径（历史）
# v3（ADR-002，2026-09-20）：精度优先的可用性闸门
GATE_G1_V3_CLIP_COV = 25.0            # v3 片级 effCov% 门槛（v2 的 30 → 25）
GATE_G1_V3_CLIP_RATIO = 0.60          # v3 达标片占比门槛（与 v2 一致）
GATE_G1_V3_WEIGHTED = 40.0            # v3 帧加权可用性门槛（与 v2-A 一致）
GATE_G1_V3_WEIGHTED_CAP = 60.0        # 同 v2 权威口径
FALLBACK_CONFIDENCE_FLOOR_V3 = 0.40   # v3 生产默认（ankleOnly + floor 0.40）
FALLBACK_CONFIDENCE_FLOOR = FALLBACK_CONFIDENCE_FLOOR_V3  # 与 BoardEdgeConfig v3 对齐


def build_release() -> None:
    print("swift build --configuration release ...", flush=True)
    proc = subprocess.run(
        ["swift", "build", "--configuration", "release"],
        cwd=ROOT,
    )
    if proc.returncode != 0:
        sys.exit("release 构建失败")


def run_cli(video_abs: Path, board_edge: bool) -> tuple[dict, float]:
    """在独立 tmp 目录 symlink 视频后执行 CLI；返回 (json, wall-clock 秒)。"""
    workdir = Path(tempfile.mkdtemp(prefix="beg1_"))
    try:
        link = workdir / video_abs.name
        link.symlink_to(video_abs.resolve())
        args: list[str] = [str(RELEASE_BIN)]
        if board_edge:
            args.append("--board-edge")
        args.append(str(link))
        t0 = time.perf_counter()
        proc = subprocess.run(
            args, cwd=workdir,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE, text=True,
        )
        dt = time.perf_counter() - t0
        if proc.returncode != 0:
            tail = (proc.stderr or "")[-600:]
            raise RuntimeError(f"CLI 退出码 {proc.returncode}\n{tail}")
        json_path = workdir / (video_abs.stem + ".json")
        with open(json_path) as f:
            data = json.load(f)
        return data, dt
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def coverage(data: dict) -> tuple[int, int, int, int, dict]:
    """(board_frames, effective_v2_frames, effective_v3_frames, total_frames, status_hist)。
    effective_v2 = board + fallback≥FLOOR_V2（0.30，历史对照口径）；
    effective_v3 = board + fallback≥FLOOR_V3（0.40，ADR-002 生产默认）。"""
    frames = data.get("frames") or []
    hist: dict[str, int] = {}
    board = 0
    effective_v2 = 0
    effective_v3 = 0
    for fr in frames:
        obs = fr.get("boardEdgeObservation") or {}
        st = obs.get("status") or "missing"
        hist[st] = hist.get(st, 0) + 1
        if st == "board":
            board += 1
            effective_v2 += 1
            effective_v3 += 1
        elif st == "fallback":
            fb = obs.get("fallbackAxis") or {}
            conf = fb.get("confidence") or 0
            if conf >= FALLBACK_CONFIDENCE_FLOOR_V2:
                effective_v2 += 1
            if conf >= FALLBACK_CONFIDENCE_FLOOR_V3:
                effective_v3 += 1
    return board, effective_v2, effective_v3, len(frames), hist


def _canonical(obs: dict | None) -> str:
    return json.dumps(obs, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def frames_equal(a_frames: list, b_frames: list) -> tuple[int, int, int, str | None]:
    """对比两轮的 boardEdgeObservation 整个对象（含 fallbackAxis 全子字段）。
    returns (n_pair, n_status_same, n_full_bit_same, first_diff_desc)。"""
    n = min(len(a_frames), len(b_frames))
    n_status = 0
    n_full = 0
    first_diff = None
    for i in range(n):
        oa = a_frames[i].get("boardEdgeObservation")
        ob = b_frames[i].get("boardEdgeObservation")
        if (oa or {}).get("status") == (ob or {}).get("status"):
            n_status += 1
        if _canonical(oa) == _canonical(ob):
            n_full += 1
        elif first_diff is None:
            first_diff = f"frame#{i}: {_canonical(oa)} vs {_canonical(ob)}"
    return n, n_status, n_full, first_diff


def probe_clip(alias: str, group: str, rel: str) -> dict | None:
    video = ROOT / rel
    if not video.exists():
        print(f"[{alias}] MISS {rel}", flush=True)
        return None
    print(f"[{alias:>8s}] ({group}) …", flush=True, end=" ")
    try:
        d_a, t_a = run_cli(video, board_edge=True)
        d_b, t_b = run_cli(video, board_edge=True)
        d_c, t_c = run_cli(video, board_edge=False)
    except RuntimeError as exc:
        print(f"FAIL {exc}", flush=True)
        return None
    board_a, eff_v2_a, eff_v3_a, total_a, hist_a = coverage(d_a)
    _, _, _, total_b, _ = coverage(d_b)
    _, _, _, total_c, _ = coverage(d_c)
    n_pair, n_status, n_full, first_diff = frames_equal(d_a["frames"], d_b["frames"])
    perf_ratio = t_a / t_c if t_c > 0 else float("nan")
    raw_pct = board_a / total_a if total_a else 0.0
    eff_v2_pct = eff_v2_a / total_a if total_a else 0.0
    eff_v3_pct = eff_v3_a / total_a if total_a else 0.0
    print(
        f"raw={raw_pct*100:5.1f}%  effV2={eff_v2_pct*100:5.1f}%  effV3={eff_v3_pct*100:5.1f}%  "
        f"bit-same={n_full}/{n_pair}  "
        f"perf={t_a:5.2f}s vs {t_c:5.2f}s (+{(perf_ratio-1)*100:+.1f}%)",
        flush=True,
    )
    if first_diff:
        print(f"           first_diff: {first_diff}", flush=True)
    return {
        "alias": alias, "group": group, "path": rel,
        "totalFrames": total_a,
        "boardFrames": board_a,
        "effectiveFramesV2": eff_v2_a,
        "effectiveFramesV3": eff_v3_a,
        "rawCoverage": raw_pct,
        "effCoverageV2": eff_v2_pct,
        "effCoverageV3": eff_v3_pct,
        "statusHist": hist_a,
        "totalFramesA": total_a, "totalFramesB": total_b, "totalFramesC": total_c,
        "bitIdenticalFrames": n_full,
        "statusOnlySameFrames": n_status,
        "pairFrames": n_pair,
        "firstDiff": first_diff,
        "wallTimeA": t_a, "wallTimeB": t_b, "wallTimeC": t_c,
        "perfRatio": perf_ratio,
    }


def summarize(results: list[dict]) -> None:
    if not results:
        print("\n(no results)")
        return
    print("\n" + "=" * 78)
    print(" 汇总（Gate-G1 三合一，v2 对照 + v3 主判定）")
    print("=" * 78)
    total_board = sum(r["boardFrames"] for r in results)
    total_eff_v2 = sum(r["effectiveFramesV2"] for r in results)
    total_eff_v3 = sum(r["effectiveFramesV3"] for r in results)
    total_frames = sum(r["totalFrames"] for r in results)
    raw_cov = total_board / total_frames if total_frames else 0.0
    eff_v2_cov = total_eff_v2 / total_frames if total_frames else 0.0
    eff_v3_cov = total_eff_v3 / total_frames if total_frames else 0.0
    print(f"  raw board 覆盖率   : {total_board}/{total_frames} = {raw_cov*100:.2f}%  (v1 观察项)")
    print(f"  eff v2 覆盖率      : {total_eff_v2}/{total_frames} = {eff_v2_cov*100:.2f}%  "
          f"(board + fallback≥{FALLBACK_CONFIDENCE_FLOOR_V2:.2f}，历史对照)")
    print(f"  eff v3 覆盖率      : {total_eff_v3}/{total_frames} = {eff_v3_cov*100:.2f}%  "
          f"(board + fallback≥{FALLBACK_CONFIDENCE_FLOOR_V3:.2f}，ADR-002 生产默认)")

    # ---- Gate-G1 v2（历史对照口径） ----
    clips_pass_v2 = [r for r in results if r["effCoverageV2"] * 100 >= GATE_G1_V2_CLIP_COV]
    clip_ratio_v2 = len(clips_pass_v2) / len(results)
    v2_criterion_a = clip_ratio_v2 >= GATE_G1_V2_CLIP_RATIO
    weighted_usability_v2 = sum(
        min(r["effCoverageV2"] * 100, GATE_G1_V2_WEIGHTED_CAP) * r["totalFrames"]
        for r in results
    ) / total_frames if total_frames else 0.0
    v2_criterion_b = weighted_usability_v2 >= GATE_G1_V2_WEIGHTED
    print(f"  --- Gate-G1 v2（历史对照，ADR-001 已 FAIL 记录）---")
    print(f"  v2-A: 片级 effCov≥{GATE_G1_V2_CLIP_COV:.0f}% 占比 "
          f"{len(clips_pass_v2)}/{len(results)} = {clip_ratio_v2*100:.1f}%  "
          f"(门槛 ≥{GATE_G1_V2_CLIP_RATIO*100:.0f}%) → {'PASS' if v2_criterion_a else 'FAIL'}")
    print(f"  v2-B: 帧加权可用性 {weighted_usability_v2:.2f}  "
          f"(门槛 ≥{GATE_G1_V2_WEIGHTED:.0f}) → {'PASS' if v2_criterion_b else 'FAIL'}")
    print(f"  v2 总判定: {'PASS' if (v2_criterion_a or v2_criterion_b) else 'FAIL'}"
          f"（A/B 二选一，未含 GT 精度小闸门）")

    # ---- Gate-G1 v3（ADR-002 主判定口径） ----
    clips_pass_v3 = [r for r in results if r["effCoverageV3"] * 100 >= GATE_G1_V3_CLIP_COV]
    clip_ratio_v3 = len(clips_pass_v3) / len(results)
    v3_criterion_a = clip_ratio_v3 >= GATE_G1_V3_CLIP_RATIO
    weighted_usability_v3 = sum(
        min(r["effCoverageV3"] * 100, GATE_G1_V3_WEIGHTED_CAP) * r["totalFrames"]
        for r in results
    ) / total_frames if total_frames else 0.0
    v3_criterion_b = weighted_usability_v3 >= GATE_G1_V3_WEIGHTED
    print(f"  --- Gate-G1 v3（ADR-002 主判定，2026-09-20）---")
    print(f"  v3-B: 片级 effCov≥{GATE_G1_V3_CLIP_COV:.0f}% 占比 "
          f"{len(clips_pass_v3)}/{len(results)} = {clip_ratio_v3*100:.1f}%  "
          f"(门槛 ≥{GATE_G1_V3_CLIP_RATIO*100:.0f}%) → {'PASS' if v3_criterion_a else 'FAIL'}")
    print(f"  v3-A: 帧加权可用性 {weighted_usability_v3:.2f}  "
          f"(门槛 ≥{GATE_G1_V3_WEIGHTED:.0f}) → {'PASS' if v3_criterion_b else 'FAIL'}")
    print(f"  v3 总判定: {'PASS' if (v3_criterion_a or v3_criterion_b) else 'FAIL'}"
          f"（A/B 二选一；前置 GT 准入 ≥90% 已在 §12.11/§12.12 分别验证）")

    total_bit_pair = sum(r["pairFrames"] for r in results)
    total_bit_ok = sum(r["bitIdenticalFrames"] for r in results)
    print(f"  bit-identical  : {total_bit_ok}/{total_bit_pair} 帧 "
          f"({'PASS' if total_bit_ok == total_bit_pair else 'FAIL'})")
    with_diff = [r for r in results if r["firstDiff"]]
    if with_diff:
        print(f"    非确定片 {len(with_diff)}/{len(results)}:")
        for r in with_diff:
            print(f"      {r['alias']:>8s}  first_diff: {r['firstDiff']}")
    perf_ratios = [r["perfRatio"] for r in results if r["perfRatio"] == r["perfRatio"]]
    if perf_ratios:
        avg = statistics.fmean(perf_ratios)
        p95 = max(perf_ratios)
        p50 = statistics.median(perf_ratios)
        print(f"  性能开/关比值  : avg={avg:.3f}  median={p50:.3f}  max={p95:.3f}  "
              f"(Gate-G1 门槛 ≤{1 + GATE_G1_PERF_HEADROOM:.2f}) "
              f"→ {'PASS' if avg <= 1 + GATE_G1_PERF_HEADROOM else 'FAIL'}")

    print("\n  单片明细（raw/effV2/effV3 cov% / bit-ok / perf±%）")
    print(f"  {'alias':>8s}  {'grp':>4s}  {'frames':>6s}  {'raw%':>6s}  {'effV2%':>7s}  {'effV3%':>7s}  "
          f"{'bit-ok':>10s}  {'A_sec':>6s}  {'C_sec':>6s}  {'perf±%':>7s}")
    for r in sorted(results, key=lambda x: (-x["effCoverageV3"], x["alias"])):
        print(f"  {r['alias']:>8s}  {r['group']:>4s}  {r['totalFrames']:>6d}  "
              f"{r['rawCoverage']*100:>5.1f}%  {r['effCoverageV2']*100:>6.1f}%  "
              f"{r['effCoverageV3']*100:>6.1f}%  "
              f"{r['bitIdenticalFrames']:>4d}/{r['pairFrames']:>4d}  "
              f"{r['wallTimeA']:>6.2f}  {r['wallTimeC']:>6.2f}  "
              f"{(r['perfRatio']-1)*100:>+6.1f}%")


def main() -> None:
    ap = argparse.ArgumentParser(description="Gate-G1 覆盖率 / 确定性 / 性能 探针")
    ap.add_argument("selectors", nargs="*",
                    help="过滤：ONLY=alias1,alias2 或直接给别名")
    ap.add_argument("-n", "--limit", type=int, default=0,
                    help="仅跑前 N 片（0=全跑）")
    ap.add_argument("--build", action="store_true", help="先 swift build -c release")
    args = ap.parse_args()

    if args.build:
        build_release()
    if not RELEASE_BIN.exists():
        sys.exit(f"未找到 {RELEASE_BIN}，请先 swift build -c release 或加 --build")

    only: set[str] | None = None
    for sel in args.selectors:
        if sel.startswith("ONLY="):
            only = set(sel[len("ONLY="):].split(","))
        else:
            only = set(sel.split(","))
    clips = CLIPS
    if only is not None:
        clips = [c for c in CLIPS if c[0] in only]
        missing = only - {c[0] for c in clips}
        if missing:
            print(f"warn: 未知别名 {sorted(missing)}", flush=True)
    if args.limit and args.limit > 0:
        clips = clips[: args.limit]
    print(f"→ 跑 {len(clips)} 片；每片 CLI × 3 次（board-edge×2 + 基线×1）")
    print(f"→ RELEASE_BIN = {RELEASE_BIN}")

    results: list[dict] = []
    for alias, group, rel in clips:
        r = probe_clip(alias, group, rel)
        if r:
            results.append(r)
    summarize(results)


if __name__ == "__main__":
    main()
