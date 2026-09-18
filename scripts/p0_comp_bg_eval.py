#!/usr/bin/env python3
"""Phase 0 C1-r2：背景掩膜配准评估 —— 与全图配准对比 + 补偿轨迹弯形可分性。

1) 每片两版相机向量差异（中位数、相关），量化主体锁定是否解除；
2) 背景版补偿后弯形 margin vs 裸轨迹 vs 全图补偿；
3) 写背景版补偿轨迹接触表数据（供 p0_comp_pathshape_plot_bg.py 出图）。
"""
from __future__ import annotations

import csv
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
FULL = ROOT / "outputs/edge_spike/p0_camera_motion.tsv"
BG = ROOT / "outputs/edge_spike/p0_camera_motion_bg.tsv"
MIN_CNF = 0.30

BEGINNER = [
    ("BND2_LB", "bad/v0300fg10000cusoptnog65pkehng280.MP4"),
    ("BND2_L6", "bad/v0200fg10000d6olrffog65vrste5qqg.MOV"),
    ("BND2_L5", "bad/v0300fg10000d664l37og65t6pnbois0.MOV"),
    ("BND2_L4", "bad/v1e00fgi0000cv786ffog65rtmm48gmg.MOV"),
    ("BND2_L3", "bad/v2800fgi0000d4v24r7og65oi0fmka5g.MP4"),
    ("BND2_L2", "bad/v0d00fg10000ctm0ufvog65rqb97g2p0.MP4"),
    ("BND2_L1", "bad/v0d00fg10000csgr6inog65n8mlpg2m0.MP4"),
]
EMERGING = [
    ("BND_L1", "middle/v1e00fgi0000d5bksdfog65irrhr4bog.MP4"),
    ("BND_L2", "middle/v0300fg10000d5h313fog65nermuqklg.MP4"),
    ("BND_L3", "middle/v2800fgi0000d54jhefog65lbfdhma2g.MP4"),
    ("BND2_LM", "bad/v0200fg10000d7nnh5vog65i52ermgog.MP4"),
]


def load_tsv(p):
    m = {}
    with p.open() as f:
        for r in csv.DictReader(f, delimiter="\t"):
            m.setdefault(r["alias"], {})[int(r["fi"])] = (
                float(r["cdx"]), float(r["cdy"]), int(r["regOK"]))
    return m


def track(rel):
    d = json.loads((ROOT / "video" / Path(rel).with_suffix(".json")).read_text())
    fi, xs, ys = [], [], []
    for i, fr in enumerate(d["frames"]):
        bp = fr.get("bodyPose") or {}
        cx, cy = bp.get("ankleCenterX"), bp.get("ankleCenterY")
        if not cx or not cy:
            continue
        if min(cx.get("confidence", 0), cy.get("confidence", 0)) < MIN_CNF:
            continue
        fi.append(i); xs.append(cx["value"]); ys.append(cy["value"])
    return np.array(fi), np.array(xs), np.array(ys)


def smooth5(v):
    if len(v) < 5:
        return v
    return np.convolve(np.pad(v, 2, mode="edge"), np.ones(5) / 5, mode="valid")


def shape(dx, dy):
    step = np.hypot(dx, dy)
    L = step.sum()
    if L < 1e-6:
        return None
    straight = np.hypot(dx.sum(), dy.sum()) / L
    heading = np.degrees(np.arctan2(dy, dx))
    dh = np.diff(heading); dh = (dh + 180) % 360 - 180
    keep = step[1:] > 1e-4
    curv = np.abs(dh[keep]) / step[1:][keep]
    return dict(pathLen=float(L), straight=float(straight),
                turnPerLen=float(np.abs(dh).sum() / L),
                turnStd=float(np.std(dh)),
                curvMed=float(np.median(curv)) if keep.any() else 0.0)


def per_video(rel, fi, x, y, mot):
    raw_dx, raw_dy, cmp_dx, cmp_dy = [], [], [], []
    for k in range(len(fi) - 1):
        m = mot.get(int(fi[k]))
        if m is None or m[2] != 1:
            continue
        dx = float(x[k + 1] - x[k]); dy = float(y[k + 1] - y[k])
        raw_dx.append(dx); raw_dy.append(dy)
        cmp_dx.append(dx - m[0]); cmp_dy.append(dy - m[1])
    return shape(np.array(raw_dx), np.array(raw_dy)), shape(np.array(cmp_dx), np.array(cmp_dy))


def margin(b, e):
    b, e = np.array(b, float), np.array(e, float)
    b, e = b[~np.isnan(b)], e[~np.isnan(e)]
    if len(b) < 2 or len(e) < 2:
        return float("nan")
    s = np.sqrt((b.var(ddof=1) + e.var(ddof=1)) / 2)
    return abs(b.mean() - e.mean()) / s if s > 1e-9 else float("inf")


def main():
    full, bg = load_tsv(FULL), load_tsv(BG)
    clips = [("beginner",) + c for c in BEGINNER] + [("emerging",) + c for c in EMERGING]

    print("=== 全图 vs 背景掩膜：相机向量差异（仅取两版都 regOK 的对） ===")
    print(f"{'alias':9}{'group':9}{'n':>5}{'median |Δ|':>11}{'corr x':>9}{'corr y':>9}")
    for group, alias, rel in clips:
        ff, bb = full.get(alias, {}), bg.get(alias, {})
        fx, fy, bx, by = [], [], [], []
        for k, v in ff.items():
            if k in bb and v[2] == 1 and bb[k][2] == 1:
                fx.append(v[0]); fy.append(v[1]); bx.append(bb[k][0]); by.append(bb[k][1])
        fx, fy, bx, by = map(np.array, (fx, fy, bx, by))
        d = np.hypot(fx - bx, fy - by)
        cx = np.corrcoef(fx, bx)[0, 1] if len(fx) > 2 else float("nan")
        cy = np.corrcoef(fy, by)[0, 1] if len(fy) > 2 else float("nan")
        print(f"{alias:9}{group:9}{len(fx):>5}{np.median(d):>11.4f}{cx:>9.2f}{cy:>9.2f}")

    res = {}
    for group, alias, rel in clips:
        fi, x, y = track(rel)
        x, y = smooth5(x), smooth5(y)
        raw, cmp_bg = per_video(rel, fi, x, y, bg.get(alias, {}))
        _, cmp_full = per_video(rel, fi, x, y, full.get(alias, {}))
        res[alias] = (group, raw, cmp_full, cmp_bg)

    print("\n=== turnStd / curvMed / straight 三种口径对照 ===")
    print(f"{'group':9}{'alias':9}{'tStd raw/full/bg':>22}{'curv raw/full/bg':>24}{'straight r/f/b':>20}")
    for alias, (g, r, cf, cb) in res.items():
        print(f"{g:9}{alias:9}"
              f"{r['turnStd']:>7.1f}/{cf['turnStd']:>5.1f}/{cb['turnStd']:<5.1f}  "
              f"{r['curvMed']:>7.0f}/{cf['curvMed']:>5.0f}/{cb['curvMed']:<5.0f}  "
              f"{r['straight']:>5.2f}/{cf['straight']:>4.2f}/{cb['straight']:<4.2f}")

    print("\n=== within-set margin：raw / 全图补偿 / 背景补偿 ===")
    print(f"{'metric':12}{'raw':>7}{'full':>7}{'bg':>7}")
    for k in ["turnStd", "curvMed", "turnPerLen", "straight", "pathLen"]:
        vals = []
        for idx in (1, 2, 3):
            b = [v[idx][k] for v in res.values() if v[0] == "beginner"]
            e = [v[idx][k] for v in res.values() if v[0] == "emerging"]
            vals.append(margin(b, e))
        print(f"{k:12}{vals[0]:>7.2f}{vals[1]:>7.2f}{vals[2]:>7.2f}")


if __name__ == "__main__":
    main()
