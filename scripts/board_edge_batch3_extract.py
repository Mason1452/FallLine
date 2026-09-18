#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
board_edge_batch3_extract.py
===========================

Phase 2 扩边界集第三批：对 [p2_candidate_contact_sheets.swift CLIPS] 的 19 片候选
跑当前 release 基线 CLI（默认关，与前两批同一口径），从 JSON 提取算法列：

  - 综合分       : summary.averageScore（四舍五入）
  - edge(conf)   : 顶层 skiMetrics.edgeQualityScore / .edgeQualityConfidence
  - pressure     : 顶层 skiMetrics.pressureSupportScore
  - calf         : 可靠姿态帧 poseScore.calfLeanScore 按 totalConfidence 加权
                   （口径 = StageClassifier.averageSubScores）
  - knee         : 同上 kneeBendScore
  - sideslip/cnf : boardAnalysis.summary.averageSideslipAngle / .carvingConfidence
  - 时长 / 帧    : duration / totalFrames

输出 Markdown 表行（档位 / 刻滑 / 备注留空，等教练看接触表回填），并把每片 JSON
留在 outputs/board_edge_p2/batch3_json/ 供探针离线复用。

用法：
  python3 scripts/board_edge_batch3_extract.py                 # 19 片全跑
  python3 scripts/board_edge_batch3_extract.py ONLY=CAND_G01   # 指定片
  python3 scripts/board_edge_batch3_extract.py -n 3
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELEASE_BIN = ROOT / ".build" / "release" / "FallLineCLI"
OUT_JSON = ROOT / "outputs" / "board_edge_p2" / "batch3_json"

# 与 scripts/p2_candidate_contact_sheets.swift CLIPS 完全一致（alias, rel, hint, hintScore）
CLIPS: list[tuple[str, str, str, int]] = [
    ("CAND_G01", "good/0946ed384e732c357a3d55fac77426c0.MP4", "中偏上/高质量", 73),
    ("CAND_G02", "good/3134552bed78447b9f7ba8e2003ce678.MP4", "中偏上", 72),
    ("CAND_G03", "good/3e6f37fe76521781506c19c02c1b97ed.MP4", "高质量", 83),
    ("CAND_G04", "good/5382da0c825e30518ab376505cbcfaf2.MOV", "中偏上", 72),
    ("CAND_G05", "good/641efed02be271b6d9f014c97d1f8ae0.MOV", "中偏上", 77),
    ("CAND_G06", "good/9ed0bb6c707fc47fce153cee3dcd365e.MP4", "中偏上", 75),
    ("CAND_G07", "good/v0200fg10000d7r0017og65qoh1vgeg0.MP4", "专业(GOOD_A)", 89),
    ("CAND_G08", "good/v2800fgi0000d6m0mk7og65qamcvgf80.MP4", "中偏上", 78),
    ("CAND_M01", "middle/1c5771fc7dd1ea546eb5bc3e4e01bc48.MP4", "中级", 67),
    ("CAND_M02", "middle/4a7dfe960f07ac14b06bbd8de3d38aa4.MP4", "中偏上", 73),
    ("CAND_M03", "middle/96001e37e76be9ef6cf7a65e73efcac4.MP4", "专业", 85),
    ("CAND_M04", "middle/992f063b79d27b96b471e44a48d8465e.MP4", "初级", 55),
    ("CAND_M05", "middle/a7791a475a244c938dd0815e89b1dec5.MP4", "中偏上", 74),
    ("CAND_M06", "middle/ccfd9967aa6d3ab5abd04fb8991872c7.MOV", "中级", 68),
    ("CAND_M07", "middle/v0200fg10000d2tcts7og65t6h63ua2g.MP4", "初级", 58),
    ("CAND_M08", "middle/v0200fg10000d6a4i57og65mkjkcdpu0.MP4", "中偏上", 76),
    ("CAND_M09", "middle/v0300fg10000d4oq6avog65ihr8qf550.MP4", "中级", 60),
    ("CAND_M10", "middle/v2800fgi0000d5ehg1vog65tinkepgl0.MP4", "中偏上", 77),
    ("CAND_B01", "bad/0b7522e9db823b910ac67727aea726da.MP4", "初级/中级", 70),
]

MIN_POSE_CNF = 0.30


def run_cli(video: Path) -> dict:
    workdir = Path(tempfile.mkdtemp(prefix="b3_"))
    try:
        link = workdir / video.name
        link.symlink_to(video.resolve())
        proc = subprocess.run(
            [str(RELEASE_BIN), str(link)],
            cwd=workdir,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE, text=True,
        )
        if proc.returncode != 0:
            raise RuntimeError(f"CLI 退出码 {proc.returncode}\n{(proc.stderr or '')[-600:]}")
        json_path = workdir / (video.stem + ".json")
        return json.loads(json_path.read_text())
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def reliable_scores(data: dict) -> list[dict]:
    scored = [f.get("poseScore") for f in data["frames"] if f.get("poseScore")]
    reliable = [s for s in scored if s.get("totalConfidence", 0) >= MIN_POSE_CNF]
    return reliable or scored


def conf_weighted(scores: list[dict], key: str) -> float:
    pairs = [(s.get(key, 0), max(0.01, s.get("totalConfidence", 0))) for s in scores]
    tw = sum(w for _, w in pairs)
    return sum(v * w for v, w in pairs) / tw if tw else 0.0


def extract(alias: str, rel: str) -> dict:
    video = ROOT / "video" / rel
    if not video.exists():
        raise RuntimeError(f"MISS video/{rel}")
    data = run_cli(video)
    (OUT_JSON / f"{alias}.json").write_text(json.dumps(data, ensure_ascii=False))

    sm = data.get("skiMetrics") or {}
    bas = (data.get("boardAnalysis") or {}).get("summary") or {}
    scores = reliable_scores(data)
    return {
        "alias": alias,
        "file": Path(rel).name,
        "bucket": Path(rel).parts[0],
        "score": round(data["summary"]["averageScore"]),
        "edge": sm.get("edgeQualityScore", 0),
        "edgeCnf": sm.get("edgeQualityConfidence", 0),
        "pressure": sm.get("pressureSupportScore", 0),
        "calf": conf_weighted(scores, "calfLeanScore"),
        "knee": conf_weighted(scores, "kneeBendScore"),
        "sideslip": bas.get("averageSideslipAngle"),
        "carvingCnf": bas.get("carvingConfidence"),
        "duration": data.get("duration", 0),
        "frames": data.get("totalFrames", 0),
    }


def row_md(r: dict) -> str:
    sideslip = f"{r['sideslip']:.0f}°" if r["sideslip"] is not None else "—"
    cnf = f"{r['carvingCnf']:.0f}%" if r["carvingCnf"] is not None else "—"
    return (
        f"| {r['alias']} | `{r['file']}` ({r['bucket']}) | {r['score']} | "
        f"{r['edge']:.1f} ({r['edgeCnf']:.2f}) | {r['pressure']:.1f} | "
        f"{r['calf']:.1f} | {r['knee']:.1f} | {sideslip} / {cnf} | "
        f"{r['duration']:.0f}s | __________ | __________ | |"
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("selectors", nargs="*")
    ap.add_argument("-n", "--limit", type=int, default=0)
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
    if args.limit:
        clips = clips[: args.limit]

    OUT_JSON.mkdir(parents=True, exist_ok=True)
    rows = []
    for alias, rel, _hint, _hs in clips:
        print(f"[{alias}] …", flush=True, end=" ")
        try:
            r = extract(alias, rel)
        except RuntimeError as exc:
            print(f"FAIL {exc}", flush=True)
            continue
        rows.append(r)
        print(f"score={r['score']} edge={r['edge']:.1f} calf={r['calf']:.1f} "
              f"knee={r['knee']:.1f}", flush=True)

    print("\n" + "\n".join(row_md(r) for r in rows))


if __name__ == "__main__":
    main()
