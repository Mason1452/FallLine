#!/usr/bin/env python3
"""Phase 0 候选 C1：相机运动补偿后的踝轨迹弯形可分性评估。

读 p0_camera_registration_spike.swift 产出的 p0_camera_motion.tsv
（相邻有效帧的纯平移配准 cdx/cdy，归一化到帧尺寸，仅用 regOK=1 的对），
从 JSON 取踝轨迹（5fps、MIN_CNF=0.30，与 edge_spike_pathshape_audit 同口径），
逐对相减得到雪面相对位移：
    rx_i = (x_{i+1}-x_i) - cdx_i（宽归一）
    ry_i = (y_{i+1}-y_i) - cdy_i（高归一；x/y 各按自身轴归一，与原指标一致）
在"配准成功的连续段"上重算 straightness/turnPerLen/turnStd/curvMed，
并与裸轨迹（同一段、不补偿）对照，输出两类 within-set margin（|μ差|/合并σ）。

用法：python3 scripts/p0_compensated_pathshape_audit.py
"""
from __future__ import annotations

import csv
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MOTION = ROOT / "outputs/edge_spike/p0_camera_motion.tsv"
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


def load_motion() -> dict[str, dict[int, tuple[float, float, int]]]:
    m: dict[str, dict[int, tuple[float, float, int]]] = {}
    with MOTION.open() as f:
        for r in csv.DictReader(f, delimiter="\t"):
            m.setdefault(r["alias"], {})[int(r["fi"])] = (
                float(r["cdx"]), float(r["cdy"]), int(r["regOK"]))
    return m


def track(rel: str):
    d = json.loads((ROOT / "video" / Path(rel).with_suffix(".json")).read_text())
    fi, ts, xs, ys = [], [], [], []
    for i, fr in enumerate(d["frames"]):
        bp = fr.get("bodyPose") or {}
        cx, cy = bp.get("ankleCenterX"), bp.get("ankleCenterY")
        if not cx or not cy:
            continue
        if min(cx.get("confidence", 0), cy.get("confidence", 0)) < MIN_CNF:
            continue
        fi.append(i); ts.append(fr["time"]); xs.append(cx["value"]); ys.append(cy["value"])
    return np.array(fi), np.array(ts), np.array(xs), np.array(ys)


def smooth5(v):
    if len(v) < 5:
        return v
    return np.convolve(np.pad(v, 2, mode="edge"), np.ones(5) / 5, mode="valid")


def shape_metrics(dx, dy):
    """dx/dy: 逐段位移（可含断点掩码为 False）。返回弯形指标。"""
    step = np.hypot(dx, dy)
    path_len = step.sum()
    if path_len < 1e-6:
        return None
    # 直度：位移向量和的模 / 路径长
    net = np.hypot(dx.sum(), dy.sum())
    straight = net / path_len
    heading = np.degrees(np.arctan2(dy, dx))
    dh = np.diff(heading)
    dh = (dh + 180) % 360 - 180
    turn_per_len = float(np.abs(dh).sum() / path_len)
    turn_std = float(np.std(dh))
    keep = step[1:] > 1e-4
    curv = np.abs(dh[keep]) / step[1:][keep]
    curv_med = float(np.median(curv)) if keep.any() else 0.0
    return dict(pathLen=float(path_len), straight=float(straight),
                turnPerLen=turn_per_len, turnStd=turn_std, curvMed=curv_med)


def per_video(alias: str, rel: str, motion: dict):
    fi, t, x, y = track(rel)
    if len(t) < 8:
        return None
    x, y = smooth5(x), smooth5(y)
    mot = motion.get(alias, {})

    # 逐相邻有效帧段：取配准（regOK=1）才纳入补偿后轨迹；裸轨迹用同样的段以保证可比
    raw_dx, raw_dy, comp_dx, comp_dy = [], [], [], []
    reg_ok, pairs = 0, 0
    for k in range(len(fi) - 1):
        a = int(fi[k])
        m = mot.get(a)
        if m is None:
            continue
        pairs += 1
        if m[2] != 1:
            continue
        reg_ok += 1
        dx = float(x[k + 1] - x[k]); dy = float(y[k + 1] - y[k])
        raw_dx.append(dx); raw_dy.append(dy)
        comp_dx.append(dx - m[0]); comp_dy.append(dy - m[1])
    raw_dx, raw_dy = np.array(raw_dx), np.array(raw_dy)
    comp_dx, comp_dy = np.array(comp_dx), np.array(comp_dy)
    raw = shape_metrics(raw_dx, raw_dy)
    comp = shape_metrics(comp_dx, comp_dy)
    return dict(n=len(t), pairs=pairs, regOK=reg_ok,
                regRate=round(reg_ok / max(pairs, 1), 2),
                camMag=round(float(np.median(np.hypot(comp_dx - raw_dx, comp_dy - raw_dy))) if len(comp_dx) else 0, 4),
                raw=raw, comp=comp)


def margin(vals_b, vals_e):
    b = np.array(vals_b, float); e = np.array(vals_e, float)
    b = b[~np.isnan(b)]; e = e[~np.isnan(e)]
    if len(b) < 2 or len(e) < 2:
        return float("nan")
    s = np.sqrt((b.var(ddof=1) + e.var(ddof=1)) / 2)
    return abs(b.mean() - e.mean()) / s if s > 1e-9 else float("inf")


def main():
    motion = load_motion()
    clips = [("beginner",) + c for c in BEGINNER] + [("emerging",) + c for c in EMERGING]
    results = {}
    print(f"{'group':9}{'alias':9}{'n':>4}{'pairs':>6}{'regOK':>6}{'rate':>6}{'camMag':>8}"
          f"{'  tStd raw→comp':>16}{'curv raw→comp':>17}{'straight r→c':>15}")
    for group, alias, rel in clips:
        r = per_video(alias, rel, motion)
        if r is None:
            print(f"{group:9}{alias:9}  insufficient")
            continue
        results[alias] = (group, r)
        rw, cp = r["raw"], r["comp"]
        print(f"{group:9}{alias:9}{r['n']:>4}{r['pairs']:>6}{r['regOK']:>6}{r['regRate']:>6}"
              f"{r['camMag']:>8}"
              f"{rw['turnStd']:>7.1f}→{cp['turnStd']:<7.1f}"
              f"{rw['curvMed']:>7.0f}→{cp['curvMed']:<7.0f}"
              f"{rw['straight']:>6.2f}→{cp['straight']:<5.2f}")

    print("\n=== 两类 within-set margin（|μbeginner−μemerging| / pooled σ），越大越可分 ===")
    print(f"{'metric':12}{'raw':>8}{'compensated':>13}{'delta':>8}")
    keys = ["turnStd", "curvMed", "turnPerLen", "straight", "pathLen"]
    for k in keys:
        rb = [v["raw"][k] for g, v in results.values() if g == "beginner"]
        re_ = [v["raw"][k] for g, v in results.values() if g == "emerging"]
        cb = [v["comp"][k] for g, v in results.values() if g == "beginner"]
        ce = [v["comp"][k] for g, v in results.values() if g == "emerging"]
        mr, mc = margin(rb, re_), margin(cb, ce)
        flag = "  ↑" if mc > mr + 0.05 else ("  ↓" if mc < mr - 0.05 else "")
        print(f"{k:12}{mr:>8.2f}{mc:>13.2f}{mc - mr:>+8.2f}{flag}")
    print("\nGate-G0 C 路判定参考：补偿后 margin 较裸轨迹提升 ≥0.5σ 才视为相机补偿带来增益。")


if __name__ == "__main__":
    main()
