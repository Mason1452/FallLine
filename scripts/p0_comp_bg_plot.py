#!/usr/bin/env python3
"""背景掩膜版补偿轨迹接触图：outputs/edge_spike/p0_comp_track_sheet_bg.png"""
from __future__ import annotations
import csv, json
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
MOTION = ROOT / "outputs/edge_spike/p0_camera_motion_bg.tsv"
OUT = ROOT / "outputs/edge_spike/p0_comp_track_sheet_bg.png"
MIN_CNF = 0.30
CLIPS = [
    ("BND2_LB", "bad/v0300fg10000cusoptnog65pkehng280.MP4", "beginner"),
    ("BND2_L6", "bad/v0200fg10000d6olrffog65vrste5qqg.MOV", "beginner"),
    ("BND2_L5", "bad/v0300fg10000d664l37og65t6pnbois0.MOV", "beginner"),
    ("BND2_L4", "bad/v1e00fgi0000cv786ffog65rtmm48gmg.MOV", "beginner"),
    ("BND2_L3", "bad/v2800fgi0000d4v24r7og65oi0fmka5g.MP4", "beginner"),
    ("BND2_L2", "bad/v0d00fg10000ctm0ufvog65rqb97g2p0.MP4", "beginner"),
    ("BND2_L1", "bad/v0d00fg10000csgr6inog65n8mlpg2m0.MP4", "beginner"),
    ("BND_L1", "middle/v1e00fgi0000d5bksdfog65irrhr4bog.MP4", "emerging"),
    ("BND_L2", "middle/v0300fg10000d5h313fog65nermuqklg.MP4", "emerging"),
    ("BND_L3", "middle/v2800fgi0000d54jhefog65lbfdhma2g.MP4", "emerging"),
    ("BND2_LM", "bad/v0200fg10000d7nnh5vog65i52ermgog.MP4", "emerging"),
]


def load_motion():
    m = {}
    with MOTION.open() as f:
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
        if not cx or not cy: continue
        if min(cx.get("confidence", 0), cy.get("confidence", 0)) < MIN_CNF: continue
        fi.append(i); xs.append(cx["value"]); ys.append(cy["value"])
    return np.array(fi), np.array(xs), np.array(ys)


def smooth5(v):
    if len(v) < 5: return v
    return np.convolve(np.pad(v, 2, mode="edge"), np.ones(5) / 5, mode="valid")


def cum_segs(fi, x, y, mot):
    segs = [[(0.0, 0.0)]]
    for k in range(len(fi) - 1):
        m = mot.get(int(fi[k]))
        dx = float(x[k + 1] - x[k]); dy = float(y[k + 1] - y[k])
        if m is None or m[2] != 1:
            segs.append([(0.0, 0.0)]); continue
        px, py = segs[-1][-1]
        segs[-1].append((px + dx - m[0], py + dy - m[1]))
    return segs


def main():
    motion = load_motion()
    n = len(CLIPS)
    fig, axes = plt.subplots(n, 2, figsize=(8, 2.15 * n), squeeze=False)
    for r, (alias, rel, grp) in enumerate(CLIPS):
        fi, x, y = track(rel)
        x, y = smooth5(x), smooth5(y)
        mot = motion.get(alias, {})
        color = "#d62728" if grp == "beginner" else "#1f77b4"
        # raw
        ax = axes[r][0]
        segs = [[(0.0, 0.0)]]
        for k in range(len(fi) - 1):
            px, py = segs[-1][-1]
            segs[-1].append((px + float(x[k+1]-x[k]), py + float(y[k+1]-y[k])))
        for s in segs:
            ax.plot([p[0] for p in s], [-p[1] for p in s], color=color, lw=1.2)
        ax.set_aspect("equal"); ax.set_xticks([]); ax.set_yticks([]); ax.grid(alpha=0.2)
        # bg-compensated
        ax = axes[r][1]
        segs = cum_segs(fi, x, y, mot)
        allx = [p[0] for s in segs for p in s]; ally = [p[1] for s in segs for p in s]
        for s in segs:
            ax.plot([p[0] for p in s], [-p[1] for p in s], color=color, lw=1.2)
        if allx:
            pad = max(0.01, (max(allx)-min(allx)+max(ally)-min(ally))*0.25)
            ax.set_xlim(min(allx)-pad, max(allx)+pad)
            ax.set_ylim(-max(ally)-pad, -min(ally)+pad)
        ax.set_aspect("equal"); ax.set_xticks([]); ax.set_yticks([]); ax.grid(alpha=0.2)
        if r == 0:
            axes[0][0].set_title("raw ankle path", fontsize=10)
            axes[0][1].set_title("bg-mask compensated", fontsize=10)
        axes[r][0].set_ylabel(f"{alias}\n{grp}", fontsize=8, rotation=0, labelpad=42, va="center")
    plt.tight_layout(h_pad=0.4)
    plt.savefig(OUT, dpi=110, bbox_inches="tight")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
