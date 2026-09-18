#!/usr/bin/env python3
"""刃线/轨迹检测立项 spike · 雪面轨迹脊线方向一致性（go/no-go 信号探针）。

物理假设：
- 刻滑/平行弯在雪面留下平行、连续的弧形刃痕 → ROI 内梯度方向集中于
  1-2 个主峰（垂直于脊线），方向熵低、峰能量高。
- 推坡/犁式/搓雪留下发散沟痕 + 雪渣雪雾，或压实光板雪面 → 梯度方向
  各向同性（熵高、峰能量低）或双斜向犁沟。

纯 numpy 实现（不依赖 OpenCV）：在脚踝下方/前方近场雪面 ROI 内做 Sobel，
统计梯度方向直方图的熵与主峰能量。每片样本取接触表同款 4 个时间点，
脚踝坐标从帧级 JSON 取最近邻可靠帧。

这是立项可行性探针，不是检测器：只回答"方向性脊线信号在两类间是否可观测
地分离"。若连离线、手工选 ROI 的理想条件都分不开，生产级检测无从谈起。

用法：python3 scripts/edge_spike_trajectory_audit.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
FRAME_DIR = Path("/tmp/edge_spike/frames")
TAPS = [0.2, 0.4, 0.6, 0.8]
MIN_CNF = 0.30
NBINS = 24  # 方向直方图（180° 无向，每 bin 7.5°）

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


def nearest_ankle(d: dict, t_target: float) -> tuple[float, float] | None:
    best = None
    for fr in d["frames"]:
        bp = fr.get("bodyPose") or {}
        cx, cy = bp.get("ankleCenterX"), bp.get("ankleCenterY")
        if not cx or not cy:
            continue
        if min(cx.get("confidence", 0), cy.get("confidence", 0)) < MIN_CNF:
            continue
        dt = abs(fr["time"] - t_target)
        if best is None or dt < best[0]:
            best = (dt, cx["value"], cy["value"])
    if best is None:
        return None
    return best[1], best[2]


def sobel(gray: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    g = gray.astype(np.float32)
    kx = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], np.float32)
    ky = kx.T
    pad = np.pad(g, 1)
    H, W = g.shape
    gx = np.zeros_like(g)
    gy = np.zeros_like(g)
    for dy in range(3):
        for dx in range(3):
            win = pad[dy:dy + H, dx:dx + W]
            gx += win * kx[dy, dx]
            gy += win * ky[dy, dx]
    return gx, gy


def ridge_metrics(im: np.ndarray, ax: float, ay: float) -> dict | None:
    """脚踝下方近场雪面 ROI（Vision 归一化坐标，原点左下）。

    ROI：以踝 x 为水平中心取 ±18% 宽；纵向取踝下 4%~30%（脚到近场雪面）。
    板身/刚滑过轨迹都落在这条带上，避开天空/人体上半身/远场。
    """
    H, W = im.shape[:2]
    px, py = ax * W, (1 - ay) * H  # 转图像坐标（原点左上）
    x0, x1 = int(max(0, px - 0.18 * W)), int(min(W, px + 0.18 * W))
    y0, y1 = int(py + 0.04 * H), int(min(H, py + 0.30 * H))
    if x1 - x0 < 24 or y1 - y0 < 24:
        return None
    roi = im[y0:y1, x0:x1]
    gray = (0.299 * roi[..., 0] + 0.587 * roi[..., 1] + 0.114 * roi[..., 2])
    gx, gy = sobel(gray)
    mag = np.hypot(gx, gy)
    strong = mag > np.percentile(mag, 70)
    if strong.sum() < 30:
        return None
    # 无向梯度方向 0..180°（脊线方向 = 梯度方向 +90°，无向下一致性等价）
    ang = (np.degrees(np.arctan2(gy[strong], gx[strong])) % 180.0)
    hist, _ = np.histogram(ang, bins=NBINS, range=(0, 180), weights=mag[strong])
    p = hist / max(hist.sum(), 1e-9)
    nz = p[p > 0]
    entropy = float(-(nz * np.log(nz)).sum() / math.log(NBINS))  # 归一化 0..1
    # 主峰能量：折叠双峰（刃痕两侧边缘，相差 180° 已折叠；弧痕近似平行取最大单 bin）
    peak = float(p.max())
    # 方向集中度：最大 3 相邻 bin 占比（平滑脊线方向接近）
    k = 3
    rolled = np.concatenate([p[-k // 2 + 1:], p, p[:k // 2]])
    conv = np.convolve(rolled, np.ones(k) / k, mode="valid")
    peak3 = float(conv.max())
    edge_density = float(strong.mean())
    return {"entropy": entropy, "peak": peak, "peak3": peak3,
            "edgeDensity": edge_density, "roiH": y1 - y0, "roiW": x1 - x0}


def measure(alias: str, rel: str) -> dict:
    d = load(rel)
    dur = d.get("duration") or d["frames"][-1]["time"]
    ms = []
    for i, frac in enumerate(TAPS):
        f = FRAME_DIR / f"{alias}_t{i}.jpg"
        if not f.exists():
            continue
        ank = nearest_ankle(d, dur * frac)
        if ank is None:
            continue
        im = np.asarray(Image.open(f).convert("RGB"))
        m = ridge_metrics(im, ank[0], ank[1])
        if m:
            ms.append(m)
    if not ms:
        return {"alias": alias, "frames": 0}
    agg = lambda k: round(float(np.mean([m[k] for m in ms])), 3)
    return {"alias": alias, "frames": len(ms),
            "entropy": agg("entropy"), "peak3": agg("peak3"),
            "peak": agg("peak"), "edgeDensity": agg("edgeDensity")}


def main() -> None:
    hdr = ("group", "alias", "frames", "entropy_down", "peak3_up", "peak_up", "edgeDensity")
    print("\t".join(hdr))
    for group, clips in (("beginner", BEGINNER), ("emerging", EMERGING)):
        for alias, rel in clips:
            r = measure(alias, rel)
            print("\t".join([
                group, alias, str(r.get("frames", "")),
                str(r.get("entropy", "")), str(r.get("peak3", "")),
                str(r.get("peak", "")), str(r.get("edgeDensity", "")),
            ]))
    print()
    print("读法：刻滑平行弧 → 脊线方向集中 → entropy 低、peak3 高；")
    print("      犁式/搓雪/雪雾/光板 → 方向分散或无强边 → entropy 高、peak3 低。")


if __name__ == "__main__":
    main()
