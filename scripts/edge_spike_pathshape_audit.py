#!/usr/bin/env python3
"""刃线/轨迹检测立项 spike · 脚踝轨迹弯形（运动学路线，不依赖看见板）。

物理区分点：
- 推坡/犁式初级：速度方向反复横切坡线、轨迹为折线/之字，频繁急停急转——
  单位路径长度的转角大、路径直度低（来回摆动）、速度方向分布双峰/均匀。
- 平行雏形/刻滑：连续 C/S 弧，速度方向平滑单调扫过一个弯——
  单位路径转角小而持续、轨迹平滑、方向变化率低、弯弧曲率连续。

数据：帧级 JSON 的 ankleCenterX/Y（Vision 归一化，5fps），无需看见雪板，
远景跟拍片同样可用。本探针只测"去掉平滑预处理的原始 2D 轨迹形状"在两类
间是否可分；相机运动是已知混杂因素（不下雪面/相机补偿结论）。

用法：python3 scripts/edge_spike_pathshape_audit.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
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


def load(rel: str) -> dict:
    return json.loads((ROOT / "video" / Path(rel).with_suffix(".json")).read_text())


def track(d: dict):
    ts, xs, ys = [], [], []
    for fr in d["frames"]:
        bp = fr.get("bodyPose") or {}
        cx, cy = bp.get("ankleCenterX"), bp.get("ankleCenterY")
        if not cx or not cy:
            continue
        if min(cx.get("confidence", 0), cy.get("confidence", 0)) < MIN_CNF:
            continue
        ts.append(fr["time"])
        xs.append(cx["value"])
        ys.append(cy["value"])
    return np.array(ts), np.array(xs), np.array(ys)


def smooth5(v):
    if len(v) < 5:
        return v
    k = np.ones(5) / 5
    return np.convolve(np.pad(v, 2, mode="edge"), k, mode="valid")


def metrics(rel: str) -> dict:
    d = load(rel)
    t, x, y = track(d)
    if len(t) < 8:
        return {}
    x, y = smooth5(x), smooth5(y)
    dx, dy = np.diff(x), np.diff(y)
    step = np.hypot(dx, dy)
    path_len = step.sum()
    if path_len < 1e-6:
        return {}
    net_disp = np.hypot(x[-1] - x[0], y[-1] - y[0])
    straightness = net_disp / path_len  # 近 1=直线，低=来回摆动/弯多
    heading = np.degrees(np.arctan2(dy, dx))
    # 相邻步向变化（缠绕到 [-180,180]）
    dh = np.diff(heading)
    dh = (dh + 180) % 360 - 180
    turn_per_len = float(np.abs(dh).sum() / path_len)        # 单位路径总转角
    turn_rate_std = float(np.std(dh))                        # 转角抖动（急转 vs 平滑）
    # 速度方向绝对曲率中位数（瞬时 |dh|/步长）
    keep = step[1:] > 1e-4
    curv = np.abs(dh[keep]) / step[1:][keep]
    curv_med = float(np.median(curv)) if keep.any() else 0.0
    # 运动时长覆盖（秒）
    span = float(t[-1] - t[0])
    return {
        "n": len(t),
        "spanS": round(span, 1),
        "straight": round(straightness, 3),
        "turnPerLen": round(turn_per_len, 1),
        "turnStd": round(turn_rate_std, 1),
        "curvMed": round(curv_med, 1),
        "pathLen": round(float(path_len), 3),
    }


def main() -> None:
    hdr = ("group", "alias", "n", "spanS", "straight↑", "turnPerLen↓",
           "turnStd↓", "curvMed↓", "pathLen")
    print("\t".join(hdr))
    for group, clips in (("beginner", BEGINNER), ("emerging", EMERGING)):
        for alias, rel in clips:
            m = metrics(rel)
            print("\t".join([group, alias] + [str(m.get(k, "")) for k in
                  ("n", "spanS", "straight", "turnPerLen", "turnStd", "curvMed", "pathLen")]))
    print()
    print("读法：推坡/犁式 → 之字折线：straight 低、turnPerLen/turnStd/curvMed 高；")
    print("      平行雏形 → 连续弧：straight 低（也弯）但 turnStd/curvMed 低（平滑无急转）。")
    print("      关键分离轴预期是 turnStd / curvMed（急转抖动），不是 straightness。")


if __name__ == "__main__":
    main()
