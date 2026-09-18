#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
board_edge_reason_audit.py
==========================

Phase 2 起步 3：Gate-G1 覆盖率 FAIL 归因——按 `BoardEdgeStatus` 枚举做分片直方图，
定位 §12.5 里 811/4146 = 19.56% 中"哪一门控贡献了最多拒绝帧"。

区别于 `board_edge_gate_g1_probe.py`：
- 单轮 CLI，不做 bit-identical / 耗时对比（那两项已 PASS，不用重跑）；
- 输出**每种 status 的帧数分布**（board / farShot / rejectVertical / rejectLength
  / rejectBlob / rejectOwnership / rejectPosture / ankleLowCnf / noAxis / noMask /
  disabled），全集总账 + per-clip + 分档位（high/mid/low）三层聚合；
- 目标是给 spec §12.5 下一步（放宽 farShot / rejectVertical 或重定义门槛）
  提供数据基础。

用法：
  python3 scripts/board_edge_reason_audit.py            # 25 片全跑
  python3 scripts/board_edge_reason_audit.py ONLY=BND_L1
  python3 scripts/board_edge_reason_audit.py -n 3       # 前 3 片
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASE_BIN = ROOT / ".build" / "release" / "FallLineCLI"

# 与 board_edge_gate_g1_probe.py 同源；保留同一份 CLIPS 便于对齐。
# group=tbd 的 19 片为第三批待回填片（calibration_anchors.md Batch 3）。
CLIPS: list[tuple[str, str, str]] = [
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
    ("BND2_L1", "low", "video/bad/v0d00fg10000csgr6inog65n8mlpg2m0.MP4"),
    # ---- CAND_* 第三批 19 片（group=tbd 待回填）----
    ("CAND_G01", "tbd", "video/good/0946ed384e732c357a3d55fac77426c0.MP4"),
    ("CAND_G02", "tbd", "video/good/3134552bed78447b9f7ba8e2003ce678.MP4"),
    ("CAND_G03", "tbd", "video/good/3e6f37fe76521781506c19c02c1b97ed.MP4"),
    ("CAND_G04", "tbd", "video/good/5382da0c825e30518ab376505cbcfaf2.MOV"),
    ("CAND_G05", "tbd", "video/good/641efed02be271b6d9f014c97d1f8ae0.MOV"),
    ("CAND_G06", "tbd", "video/good/9ed0bb6c707fc47fce153cee3dcd365e.MP4"),
    ("CAND_G07", "tbd", "video/good/v0200fg10000d7r0017og65qoh1vgeg0.MP4"),
    ("CAND_G08", "tbd", "video/good/v2800fgi0000d6m0mk7og65qamcvgf80.MP4"),
    ("CAND_M01", "tbd", "video/middle/1c5771fc7dd1ea546eb5bc3e4e01bc48.MP4"),
    ("CAND_M02", "tbd", "video/middle/4a7dfe960f07ac14b06bbd8de3d38aa4.MP4"),
    ("CAND_M03", "tbd", "video/middle/96001e37e76be9ef6cf7a65e73efcac4.MP4"),
    ("CAND_M04", "tbd", "video/middle/992f063b79d27b96b471e44a48d8465e.MP4"),
    ("CAND_M05", "tbd", "video/middle/a7791a475a244c938dd0815e89b1dec5.MP4"),
    ("CAND_M06", "tbd", "video/middle/ccfd9967aa6d3ab5abd04fb8991872c7.MOV"),
    ("CAND_M07", "tbd", "video/middle/v0200fg10000d2tcts7og65t6h63ua2g.MP4"),
    ("CAND_M08", "tbd", "video/middle/v0200fg10000d6a4i57og65mkjkcdpu0.MP4"),
    ("CAND_M09", "tbd", "video/middle/v0300fg10000d4oq6avog65ihr8qf550.MP4"),
    ("CAND_M10", "tbd", "video/middle/v2800fgi0000d5ehg1vog65tinkepgl0.MP4"),
    ("CAND_B01", "tbd", "video/bad/0b7522e9db823b910ac67727aea726da.MP4"),
]

# 与 [BoardEdgeStatus](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L594-L617) 完整对齐。
STATUS_ORDER = [
    "board",
    "farShot", "rejectVertical", "rejectLength", "rejectBlob",
    "rejectOwnership", "rejectPosture",
    "ankleLowCnf", "noAxis", "noMask", "disabled",
]


def run_cli(video_abs: Path) -> dict:
    workdir = Path(tempfile.mkdtemp(prefix="beg1r_"))
    try:
        link = workdir / video_abs.name
        link.symlink_to(video_abs.resolve())
        proc = subprocess.run(
            [str(RELEASE_BIN), "--board-edge", str(link)],
            cwd=workdir,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE, text=True,
        )
        if proc.returncode != 0:
            tail = (proc.stderr or "")[-600:]
            raise RuntimeError(f"CLI 退出码 {proc.returncode}\n{tail}")
        json_path = workdir / (video_abs.stem + ".json")
        with open(json_path) as f:
            return json.load(f)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def status_hist(data: dict) -> tuple[Counter, int]:
    frames = data.get("frames") or []
    c: Counter = Counter()
    for fr in frames:
        obs = fr.get("boardEdgeObservation") or {}
        st = obs.get("status") or "missing"
        c[st] += 1
    return c, len(frames)


def format_hist(c: Counter, total: int) -> str:
    parts = []
    for st in STATUS_ORDER:
        n = c.get(st, 0)
        if n > 0:
            pct = n / total * 100 if total else 0.0
            parts.append(f"{st}={n}({pct:.0f}%)")
    extras = [k for k in c if k not in STATUS_ORDER]
    for k in sorted(extras):
        n = c[k]
        pct = n / total * 100 if total else 0.0
        parts.append(f"{k}={n}({pct:.0f}%)")
    return "  ".join(parts) if parts else "(empty)"


def probe_clip(alias: str, group: str, rel: str) -> dict | None:
    video = ROOT / rel
    if not video.exists():
        print(f"[{alias}] MISS {rel}", flush=True)
        return None
    try:
        data = run_cli(video)
    except RuntimeError as exc:
        print(f"[{alias}] FAIL {exc}", flush=True)
        return None
    hist, total = status_hist(data)
    print(f"[{alias:>8s}] ({group:>4s}) frames={total:>4d}  {format_hist(hist, total)}",
          flush=True)
    return {"alias": alias, "group": group, "path": rel,
            "totalFrames": total, "hist": dict(hist)}


def summarize(results: list[dict]) -> None:
    if not results:
        print("\n(no results)")
        return
    print("\n" + "=" * 78)
    print(" 汇总（Gate-G1 reason 分布 audit）")
    print("=" * 78)

    total_agg: Counter = Counter()
    group_agg: dict[str, Counter] = defaultdict(Counter)
    group_frames: dict[str, int] = defaultdict(int)
    total_frames = 0
    for r in results:
        for k, v in r["hist"].items():
            total_agg[k] += v
            group_agg[r["group"]][k] += v
        group_frames[r["group"]] += r["totalFrames"]
        total_frames += r["totalFrames"]

    print(f"\n全集（{len(results)} 片 / {total_frames} 帧）status 分布：")
    for st in STATUS_ORDER:
        n = total_agg.get(st, 0)
        if n == 0:
            continue
        pct = n / total_frames * 100 if total_frames else 0.0
        print(f"  {st:>16s} : {n:>5d}  ({pct:5.2f}%)")

    print("\n按档位（high/mid/low，tbd=待回填单列不混入）分布：")
    header = ["group", "frames"] + STATUS_ORDER
    widths = [6, 7] + [max(9, len(s) + 1) for s in STATUS_ORDER]
    print("  " + "  ".join(f"{h:>{w}s}" for h, w in zip(header, widths)))
    group_order = [g for g in ("high", "mid", "low", "tbd") if g in group_frames]
    group_order += [g for g in group_frames if g not in group_order]
    for g in group_order:
        tf = group_frames.get(g, 0)
        row = [g, str(tf)]
        for st in STATUS_ORDER:
            n = group_agg[g].get(st, 0)
            pct = n / tf * 100 if tf else 0.0
            row.append(f"{n}({pct:.0f}%)")
        print("  " + "  ".join(f"{v:>{w}s}" for v, w in zip(row, widths)))

    # Top-3 拒绝原因（board / disabled 除外）
    reject_keys = [k for k in total_agg if k not in ("board", "disabled")]
    top = sorted(reject_keys, key=lambda k: -total_agg[k])[:5]
    print("\nTop-5 拒绝路径（全集口径）：")
    for k in top:
        n = total_agg[k]
        pct = n / total_frames * 100 if total_frames else 0.0
        print(f"  {k:>16s} : {n:>5d}  ({pct:5.2f}%)")

    print("\n每片最大拒绝路径：")
    print(f"  {'alias':>8s}  {'grp':>4s}  {'frames':>6s}  {'top-reject':>16s}  {'n':>5s}  {'pct':>6s}")
    for r in sorted(results, key=lambda x: (x["group"], x["alias"])):
        rej = {k: v for k, v in r["hist"].items() if k not in ("board", "disabled")}
        if not rej:
            top_key, top_n = "(pure board/disabled)", 0
        else:
            top_key = max(rej, key=lambda k: rej[k])
            top_n = rej[top_key]
        pct = top_n / r["totalFrames"] * 100 if r["totalFrames"] else 0.0
        print(f"  {r['alias']:>8s}  {r['group']:>4s}  {r['totalFrames']:>6d}  "
              f"{top_key:>16s}  {top_n:>5d}  {pct:>5.1f}%")


def main() -> None:
    ap = argparse.ArgumentParser(description="Gate-G1 reason 分布 audit")
    ap.add_argument("selectors", nargs="*",
                    help="过滤：ONLY=alias1,alias2 或直接给别名")
    ap.add_argument("-n", "--limit", type=int, default=0,
                    help="仅跑前 N 片（0=全跑）")
    args = ap.parse_args()

    if not RELEASE_BIN.exists():
        sys.exit(f"未找到 {RELEASE_BIN}，请先 swift build -c release")

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
    print(f"→ 跑 {len(clips)} 片；每片 CLI × 1 次（--board-edge，单轮）")
    print(f"→ RELEASE_BIN = {RELEASE_BIN}")

    results: list[dict] = []
    for alias, group, rel in clips:
        r = probe_clip(alias, group, rel)
        if r:
            results.append(r)
    summarize(results)


if __name__ == "__main__":
    main()
