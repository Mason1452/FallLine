#!/usr/bin/env python3
"""Phase 0 Gate-G0：踝轨迹弯形判推坡 vs 平行雏形的 LOO 可行性判定。

11 片边界集（7 beginner / 4 emerging），三口径（raw / 全图补偿 / 背景掩膜补偿），
标准化特征 + 留一交叉验证（LOO），测试单特征与双特征组合的泛化错误数。
n=11 很小，只允许 ≤2 特征，防止过拟合；结论按错误数而非训练误差。
"""
from __future__ import annotations
import csv, json, itertools
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
FEATS = ["straight", "turnStd", "turnPerLen", "curvMed", "pathLen"]


def load_tsv(name):
    m = {}
    with (ROOT / name).open() as f:
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


def shape(dx, dy):
    step = np.hypot(dx, dy); L = step.sum()
    if L < 1e-6: return None
    heading = np.degrees(np.arctan2(dy, dx))
    dh = np.diff(heading); dh = (dh + 180) % 360 - 180
    keep = step[1:] > 1e-4
    return dict(pathLen=float(L), straight=float(np.hypot(dx.sum(), dy.sum()) / L),
                turnPerLen=float(np.abs(dh).sum() / L), turnStd=float(np.std(dh)),
                curvMed=float(np.median(np.abs(dh[keep]) / step[1:][keep])) if keep.any() else 0.0)


def video_features(rel, mot):
    fi, x, y = track(rel)
    x, y = smooth5(x), smooth5(y)
    out = {}
    # raw：所有相邻对；comp：仅 regOK=1
    for mode in ("raw", "comp"):
        dxs, dys = [], []
        for k in range(len(fi) - 1):
            dx = float(x[k+1] - x[k]); dy = float(y[k+1] - y[k])
            if mode == "comp":
                m = mot.get(int(fi[k]))
                if m is None or m[2] != 1: continue
                dx -= m[0]; dy -= m[1]
            dxs.append(dx); dys.append(dy)
        out[mode] = shape(np.array(dxs), np.array(dys))
    return out


def zscore_fit_apply(train_X, test_X):
    mu = train_X.mean(0); sd = train_X.std(0); sd[sd < 1e-9] = 1
    return (train_X - mu) / sd, (test_X - mu) / sd


def loo_errors(X, y, feats_idx):
    X = X[:, feats_idx]
    errs = []
    for i in range(len(y)):
        tr = np.arange(len(y)) != i
        Xtr, Xte = zscore_fit_apply(X[tr], X[i:i+1])
        ytr = y[tr]
        # 岭回归（λ=2），截距；输出类概率
        A = np.column_stack([np.ones(len(Xtr)), Xtr])
        lam = np.eye(A.shape[1]) * 2.0; lam[0, 0] = 0
        w = np.linalg.solve(A.T @ A + lam, A.T @ ytr)
        p = 1 / (1 + np.exp(-(w[0] + Xte @ w[1:])))
        pred = 1 if p[0] >= 0.5 else 0
        if pred != y[i]:
            errs.append(i)
    return errs


def main():
    full = load_tsv("outputs/edge_spike/p0_camera_motion.tsv")
    bg = load_tsv("outputs/edge_spike/p0_camera_motion_bg.tsv")
    clips = [(a, r, 0) for a, r in BEGINNER] + [(a, r, 1) for a, r in EMERGING]
    names, y = [], np.array([c[2] for c in clips])
    feats_by_mode = {"raw": [], "full": [], "bg": []}
    for alias, rel, _ in clips:
        names.append(alias)
        vf = video_features(rel, bg.get(alias, {}))
        vf_full = video_features(rel, full.get(alias, {}))
        feats_by_mode["raw"].append([vf["raw"][k] for k in FEATS])
        feats_by_mode["full"].append([vf_full["comp"][k] for k in FEATS])
        feats_by_mode["bg"].append([vf["comp"][k] for k in FEATS])

    for mode in ("raw", "full", "bg"):
        X = np.array(feats_by_mode[mode])
        print(f"\n===== 口径 {mode} =====")
        print("类别均值 (B / E):")
        for j, k in enumerate(FEATS):
            b, e = X[y == 0, j], X[y == 1, j]
            print(f"  {k:10} B={b.mean():8.2f}  E={e.mean():8.2f}  方向={'E低' if e.mean()<b.mean() else 'E高'}")
        best = []
        for r in (1, 2):
            for combo in itertools.combinations(range(len(FEATS)), r):
                errs = loo_errors(X, y, list(combo))
                label = "+".join(FEATS[i] for i in combo)
                best.append((len(errs), label, [names[i] for i in errs]))
        best.sort(key=lambda z: (z[0], z[1]))
        print("LOO 错误数（前 8）：")
        for nerr, label, en in best[:8]:
            print(f"  {nerr}/11  {label:28} 错分: {en}")


if __name__ == "__main__":
    main()
