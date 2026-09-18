#!/usr/bin/env python3
"""刃线/轨迹检测立项 spike · 板身 ROI 可行性量化。

从 11 片边界样本的帧级 JSON 读脚踝关键点（Vision 归一化坐标，原点左下、
y 向上），量化"板身检测"的物理可行性：

1. ankleBelowY：脚踝到画面底边的纵向余量（板身下沿空间，归一化）。
2. stanceWidth：左右踝同时可见时的归一化间距（单板站姿/板长方向的像素代理）。
3. ankleCnf：脚踝置信度，判有效帧占比。
4. poseY：人物在画面中的纵向位置（脚踝 y 本身），区分"远拍大全景"与"跟拍近景"。

板身物理尺寸：单板长约 135-165cm，站姿宽约板长的 1/3；板在脚下、沿脚尖方向
延伸。ROI 高度（立刃侧视）通常只有板长的 0.15-0.3。本脚本输出的是检测窗口
在 720x1280 帧里的真实像素预算。

用法：python3 scripts/edge_spike_roi_audit.py
"""

from __future__ import annotations

import json
import statistics as st
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

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

FRAME_H = 1280
BOARD_LONG_PROXY = 0.55  # 单板板长 ≈ 身高的 ~0.85；这里用画面宽的粗估上限
MIN_CNF = 0.30


def pct(xs, q):
    if not xs:
        return float("nan")
    s = sorted(xs)
    return s[min(len(s) - 1, int(round(q * (len(s) - 1))))]


def load(rel: str) -> dict:
    return json.loads((ROOT / "video" / Path(rel).with_suffix(".json")).read_text())


def measure(alias: str, rel: str) -> dict:
    d = load(rel)
    frames = d["frames"]
    n = len(frames)
    below, ankle_y, stance, cnf = [], [], [], []
    two_ankle = 0
    for fr in frames:
        bp = fr.get("bodyPose") or {}
        if not bp.get("detected"):
            continue
        la, ra = bp.get("leftAnklePoint"), bp.get("rightAnklePoint")
        cy = bp.get("ankleCenterY") or {}
        cx = bp.get("ankleCenterX") or {}
        yv, cv = cy.get("value"), cy.get("confidence", 0)
        if yv is None or cv < MIN_CNF:
            continue
        ankle_y.append(yv)
        below.append(1.0 - yv)  # Vision 原点左下：脚下到下边缘
        cnf.append(cv)
        if la and ra and la.get("confidence", 0) >= MIN_CNF and ra.get("confidence", 0) >= MIN_CNF:
            two_ankle += 1
            stance.append(abs(la["x"] - ra["x"]))
    return {
        "alias": alias,
        "n": n,
        "valid%": round(100 * len(ankle_y) / max(n, 1), 1),
        "belowMed": round(pct(below, 0.5), 3),
        "belowPx": round(pct(below, 0.5) * FRAME_H),
        "belowP10Px": round(pct(below, 0.1) * FRAME_H),
        "ankleYmed": round(pct(ankle_y, 0.5), 3),
        "ankleCnf": round(st.median(cnf), 2) if cnf else 0,
        "twoAnkle%": round(100 * two_ankle / max(len(ankle_y), 1), 1),
        "stanceWpx": round(pct(stance, 0.5) * 720) if stance else None,
    }


def main() -> None:
    rows = [measure(a, r) for a, r in BEGINNER + EMERGING]
    hdr = ("alias", "n", "valid%", "belowMed", "belowPx", "belowP10Px",
           "ankleYmed", "ankleCnf", "twoAnkle%", "stanceWpx")
    print("\t".join(hdr))
    for r in rows:
        print("\t".join(str(r[k]) for k in hdr))
    print()
    print("belowPx   = 脚踝到画面底边的纵向像素（板身/近场雪面检测窗口高度预算）")
    print("belowP10Px= 该余量的 10 分位（最紧的 10% 帧还有多少像素）")
    print("stanceWpx = 双踝间距像素（两踝同时可见帧的中位数；单板多只检出单踝中心）")


if __name__ == "__main__":
    main()
