#!/usr/bin/env python3
"""低端分档可分性审计：推坡初级 vs 平行雏形中级。

背景（WORK_LOG 2026-09-16 Boundary Batch 1/2）：7 片教练判初级的样本被
edge-evidence cap 62 硬地板顶进中级带（60-65），而 4 片真"中级雏形"样本同样落在
60-65。bestThird 聚合器扫描（bestthird_aggregator_audit.py，18 种聚合器）已证明
聚合器选择不是成因。本脚本回答：**当前 2D Vision 特征空间里，是否存在任何单维阈值
或双维合取规则能分开这两类**。

方法：
1. 从帧级 JSON 提取姿态维度 / skiMetrics / flow / 时长 / 时间序列结构特征
   （光流行进方向、带符号倒伏换弯、膝-髋节律自相关、犁式站姿宽度）。
2. 对 11 片边界样本（7 初级 + 4 中级雏形）做标准化。
3. 1D：枚举每个特征的最优阈值与准确率 / 间隔 margin。
4. 2D：枚举所有特征对的轴对齐合取规则，找能否完全分开且留 margin。

结论只依赖 CLI 产出的帧级 JSON，可复现。
"""

from __future__ import annotations

import argparse
import itertools
import json
import math
from pathlib import Path

import importlib.util

_HERE = Path(__file__).resolve()
ROOT = _HERE.parents[1]
_spec = importlib.util.spec_from_file_location(
    "bta", ROOT / "scripts/bestthird_aggregator_audit.py"
)
bta = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bta)

MIN_POSE_CNF = bta.MIN_POSE_CNF
MIN_SKI_CNF = 0.35

# 7 片教练判"初级"（被 62 地板顶进中级带）+ 4 片教练判"中级雏形"（同 60-65 带）
BEGINNER = ["BND2_LB", "BND2_L6", "BND2_L5", "BND2_L4", "BND2_L3", "BND2_L2", "BND2_L1"]
EMERGING = ["BND_L1", "BND_L2", "BND_L3", "BND2_LM"]
BOUNDARY = BEGINNER + EMERGING


def num(x):
    if isinstance(x, dict):
        return x.get("value"), x.get("confidence", 1.0)
    return x, 1.0


def smooth(xs, win=5):
    n, r, h = len(xs), [], win // 2
    for i in range(n):
        lo, hi = max(0, i - h), min(n, i + h + 1)
        r.append(sum(xs[lo:hi]) / (hi - lo))
    return r


def resample(series, dt=0.2):
    if len(series) < 2:
        return [v for _, v in series]
    t0, t1 = series[0][0], series[-1][0]
    out, i, n, k = [], 0, len(series), t0
    while k <= t1 + 1e-9:
        while i < n - 1 and abs(series[i + 1][0] - k) < abs(series[i][0] - k):
            i += 1
        out.append(series[i][1])
        k += dt
    return out


def autocorr_peak(x, dt=0.2, minp=1.5, maxp=8.0):
    if len(x) < 8:
        return 0.0, 0.0
    m = sum(x) / len(x)
    x = [z - m for z in x]
    var = sum(z * z for z in x)
    if var == 0:
        return 0.0, 0.0
    n = len(x)
    lo, hi = int(minp / dt), int(min(maxp / dt, n // 2))
    best, blag = -2.0, 0
    for lag in range(lo, hi + 1):
        c = sum(x[i] * x[i - lag] for i in range(lag, n)) / var
        if c > best:
            best, blag = c, lag
    return best, blag * dt


def wrap180(d):
    return (d + 180) % 360 - 180


def extract_features(alias: str, rel: str) -> dict:
    d = bta.load(rel)
    entries, frames = bta.reliable_entries(d)
    scores = [s for s, _, _ in entries]
    dur = bta.sampled_duration([f["time"] for f in frames])
    sm = d["summary"]

    feat: dict = {}
    feat["wmean"] = bta.agg_wmean(entries)
    feat["bestThird"] = bta.agg_top_third(entries)
    feat["median"] = bta.agg_median(entries)
    srt = sorted(scores)
    feat["p67"] = srt[min(len(srt) - 1, int(round(0.67 * (len(srt) - 1))))]
    feat["below60frac"] = 100.0 * sum(1 for s in scores if s < 60) / len(scores)
    feat["duration"] = dur
    feat["stability"] = sm["stabilityScore"]
    feat["coherence"] = sm.get("flowMotionCoherence") or 0
    feat["smoothness"] = sm.get("flowVelocitySmoothness") or 0

    # 姿态子维度（加权）
    dims = {
        "knee": "kneeBendScore",
        "calf": "calfLeanScore",
        "gravity": "gravityScore",
        "sym": "symmetryScore",
    }
    acc = {k: [] for k in dims}
    edgeq, press = [], []
    for f in frames:
        ps = f["poseScore"]
        for k, field in dims.items():
            c = ps.get(field.replace("Score", "Confidence"))
            if c is not None and c >= MIN_POSE_CNF:
                acc[k].append((ps[field], max(0.001, bta.smooth_w(c))))
        ski = f.get("skiMetrics")
        if ski:
            if ski.get("edgeQualityConfidence", 0) >= MIN_SKI_CNF:
                edgeq.append((ski["edgeQualityScore"],
                              max(0.001, bta.smooth_w(ski["edgeQualityConfidence"]))))
            pc = ski.get("pressureSupportConfidence")
            if pc is not None and pc >= MIN_SKI_CNF:
                press.append((ski["pressureSupportScore"],
                              max(0.001, bta.smooth_w(pc))))
    for k in dims:
        feat[k] = bta.wavg(acc[k]) if acc[k] else float("nan")
    feat["edgeQuality"] = bta.wavg(edgeq) if edgeq else float("nan")
    feat["pressure"] = bta.wavg(press) if press else float("nan")

    # ---- 时间序列结构特征 ----
    lean_signed, lat, knee_ang, pts = [], [], [], []
    ankle_w, knee_w, hip_w, knock = [], [], [], []
    for f in d["frames"]:
        bp = f.get("bodyPose") or {}
        if not bp.get("detected"):
            continue
        v, c = num(bp.get("signedBodyLeanAngle"))
        if v is not None and c >= MIN_POSE_CNF:
            lean_signed.append((f["time"], v))
        hx, hc = num(bp.get("hipCenterX"))
        ax, ac = num(bp.get("ankleCenterX"))
        if hx is not None and ax is not None and min(hc, ac) >= MIN_POSE_CNF:
            lat.append((f["time"], hx - ax))
        lk, lkc = num(bp.get("leftKneeBendAngle"))
        rk, rkc = num(bp.get("rightKneeBendAngle"))
        if lk is not None and rk is not None and min(lkc, rkc) >= MIN_POSE_CNF:
            knee_ang.append((f["time"], (lk + rk) / 2))
        cx, cc = num(bp.get("bodyCenterX"))
        cy, _ = num(bp.get("bodyCenterY"))
        if cx is not None and cc >= MIN_POSE_CNF:
            pts.append((f["time"], cx, cy))

        def p(name):
            q = bp.get(name)
            if isinstance(q, dict) and q.get("x") is not None and q.get("confidence", 1) >= MIN_POSE_CNF:
                return q["x"], q["confidence"]
            return None

        la, ra = p("leftAnklePoint"), p("rightAnklePoint")
        lkp, rkp = p("leftKneePoint"), p("rightKneePoint")
        lhp, rhp = p("leftHipPoint"), p("rightHipPoint")
        aw = abs(la[0] - ra[0]) if la and ra else None
        kw = abs(lkp[0] - rkp[0]) if lkp and rkp else None
        hw = abs(lhp[0] - rhp[0]) if lhp and rhp else None
        if aw:
            ankle_w.append((aw, min(la[1], ra[1])))
        if kw:
            knee_w.append((kw, min(lkp[1], rkp[1])))
        if hw:
            hip_w.append((hw, min(lhp[1], rhp[1])))
        if aw and kw and aw > 1e-6:
            knock.append(1.0 if kw < 0.8 * aw else 0.0)

    # 带符号倒伏换弯次数（去均值 + 滞后）
    lean_signed.sort()
    ls = smooth([v for _, v in lean_signed], 5) if lean_signed else []
    if ls:
        m = sum(ls) / len(ls)
        side, swaps, hyst, cover = 0, 0, 8.0, 0
        for v in [z - m for z in ls]:
            if v > hyst and side < 0:
                swaps += 1
            if v < -hyst and side > 0:
                swaps += 1
            if v > hyst:
                side = 1
            elif v < -hyst:
                side = -1
            if abs(v) > hyst:
                cover += 1
        span = lean_signed[-1][0] - lean_signed[0][0] or 1
        feat["leanSwapsPer10s"] = swaps / (span / 10)
        feat["leanTiltFrac"] = 100.0 * cover / len(ls)
    else:
        feat["leanSwapsPer10s"] = float("nan")
        feat["leanTiltFrac"] = float("nan")

    # 节律自相关
    lat.sort()
    knee_ang.sort()
    lac, _ = autocorr_peak(smooth(resample(lat), 5))
    kac, _ = autocorr_peak(smooth(resample(knee_ang), 5))
    feat["latAutoCorr"] = lac
    feat["kneeAutoCorr"] = kac

    # 犁式站姿
    feat["knockKneeFrac"] = 100.0 * sum(knock) / len(knock) if knock else float("nan")
    awm = bta.wavg(ankle_w) if ankle_w else float("nan")
    hwm = bta.wavg(hip_w) if hip_w else float("nan")
    kwm = bta.wavg(knee_w) if knee_w else float("nan")
    feat["ankleOverHip"] = awm / hwm if hwm else float("nan")
    feat["kneeOverAnkle"] = kwm / awm if awm else float("nan")

    # 光流行进方向噪声（travelAngle std，低置信度手机片已知不可靠，纳入以示完整）
    ang = []
    for fr in (d.get("boardAnalysis") or {}).get("frames") or []:
        k = fr.get("kinematics") or {}
        if k.get("travelAngle") is not None:
            ang.append(k["travelAngle"])
    if ang:
        m = sum(ang) / len(ang)
        feat["travelAngleStd"] = math.sqrt(sum((z - m) ** 2 for z in ang) / len(ang))
    else:
        feat["travelAngleStd"] = float("nan")

    # turnAnalysis 段数 / edgeSignal
    ta = d.get("turnAnalysis") or {}
    feat["turnSegments"] = len(ta.get("segments") or [])
    sig = [fr.get("edgeSignal") for fr in (ta.get("frames") or [])
           if fr.get("edgeSignal") is not None and fr.get("confidence", 0) >= MIN_SKI_CNF]
    feat["edgeSignalMean"] = sum(sig) / len(sig) if sig else float("nan")

    return feat


def standardize(matrix, names):
    stats = {}
    for j, name in enumerate(names):
        col = [row[j] for row in matrix if not math.isnan(row[j])]
        mu = sum(col) / len(col)
        sd = math.sqrt(sum((z - mu) ** 2 for z in col) / len(col)) or 1.0
        stats[name] = (mu, sd)
    out = []
    for row in matrix:
        out.append([
            (z - stats[name][0]) / stats[name][1] if not math.isnan(z) else 0.0
            for z, name in zip(row, names)
        ])
    return out


def main():
    clip_of = {alias: (rel, coach) for alias, rel, coach in bta.CLIPS}
    names, matrix, labels = [], [], []
    raw = {}
    for alias in BOUNDARY:
        rel, _ = clip_of[alias]
        raw[alias] = extract_features(alias, rel)
    names = list(next(iter(raw.values())).keys())
    for alias in BOUNDARY:
        matrix.append([raw[alias][n] for n in names])
        labels.append(0 if alias in BEGINNER else 1)

    Z = standardize(matrix, names)

    print(f"样本：{len(BEGINNER)} 初级 vs {len(EMERGING)} 中级雏形\n")

    # 1D 最优阈值
    print("== 1D 单特征最优阈值（标准化空间）==")
    print(f"{'feature':16s} {'方向':6s} {'准确率':>6s} {'间隔margin':>10s}  误分样本")
    best1 = None
    for j, name in enumerate(names):
        col = [Z[i][j] for i in range(len(Z))]
        for direction in ("初级低", "初级高"):
            correct_flags = []
            for i in range(len(Z)):
                pred0 = col[i] < 0 if direction == "初级低" else col[i] > 0
                pred = 0 if pred0 else 1
                correct_flags.append(pred == labels[i])
            acc = sum(correct_flags) / len(labels)
            # 最优阈值 margin：两类在该维度的中心间隔（标准化）
            g0 = [col[i] for i in range(len(Z)) if labels[i] == 0]
            g1 = [col[i] for i in range(len(Z)) if labels[i] == 1]
            sep = (sum(g0) / len(g0)) - (sum(g1) / len(g1))
            if direction == "初级高":
                sep = -sep
            wrong = [BOUNDARY[i] for i, ok in enumerate(correct_flags) if not ok]
            key = (acc, sep)
            if best1 is None or key > best1[0]:
                best1 = (key, name, direction, wrong)
            if acc >= 10 / 11:
                print(f"{name:16s} {direction:6s} {acc*100:5.1f}% {sep:10.2f}  {','.join(wrong)}")
    (acc, sep), name, direction, wrong = best1
    print(f"\n最强单特征：{name}（{direction}）acc={acc*100:.1f}% margin={sep:.2f}σ 误分={','.join(wrong)}")

    # 2D 轴对齐合取：是否存在 (fa 阈值) AND (fb 阈值) 完全分开两类
    print("\n== 2D 特征对矩形规则搜索（轴对齐合取，11/11 全对） ==")
    found = 0
    best2 = None
    for ia, ib in itertools.combinations(range(len(names)), 2):
        for da in (-1, 1):
            for db in (-1, 1):
                u = [da * Z[i][ia] for i in range(len(Z))]
                v = [db * Z[i][ib] for i in range(len(Z))]
                # anchor=0 初级在矩形内（合取判初级）；anchor=1 中级在矩形内（析取判初级）
                for anchor, label_inside, label_out in ((0, "初级", "中级"), (1, "中级", "初级")):
                    tu = max(u[i] for i in range(len(Z)) if labels[i] == anchor)
                    tv = max(v[i] for i in range(len(Z)) if labels[i] == anchor)
                    gaps, violators = [], []
                    for i in range(len(Z)):
                        if labels[i] == anchor:
                            continue
                        g = max(u[i] - tu, v[i] - tv)
                        gaps.append(g)
                        if g < 0:
                            violators.append(BOUNDARY[i])
                    margin = min(gaps) if gaps else -1
                    if not violators:
                        found += 1
                        if best2 is None or margin > best2[0]:
                            best2 = (margin, names[ia], names[ib], da, db, label_inside)
                        if found <= 12:
                            print(f"  [{label_inside}⊂矩形] {('低' if da<0 else '高')}{names[ia]} & "
                                  f"{('低' if db<0 else '高')}{names[ib]}  margin={margin:.2f}σ")
    if found == 0:
        print("  无任何特征对的轴对齐矩形规则（合取或析取）能完全分开两类（2D 不可分）。")
    else:
        m, na, nb, da, db, lab = best2
        print(f"  共 {found} 个可分规则；最强 margin={m:.2f}σ "
              f"（{lab}⊂ {('低' if da<0 else '高')}{na} & {('低' if db<0 else '高')}{nb}）")

    # 打印原始特征矩阵供人工核对
    print("\n== 原始特征矩阵 ==")
    hdr = "alias      " + "".join(f"{n[:9]:>10s}" for n in names)
    print(hdr)
    for alias in BOUNDARY:
        tag = "初级" if alias in BEGINNER else "中级"
        cells = "".join(
            f"{raw[alias][n]:10.2f}" if not math.isnan(raw[alias][n]) else f"{'-':>10s}"
            for n in names
        )
        print(f"{alias:10s} {cells}  {tag}")


# ==========================================================================
# Gate-G2（ADR-004，§12.15 S4）：板轴刃线连续性时序信号裁决
# ==========================================================================

TRAJ_FEATURES = [
    "stableWindowRate",
    "longestStableRunSeconds",
    "stableFrameCoverage",
    "stableRunMeanSeconds",
    "foldCrossingRate",
]


def _load_traj_clip(path: Path) -> dict:
    d = json.loads(path.read_text())
    bt = (d.get("summary") or {}).get("boardTrajectory") or {}
    frames = d.get("frames") or []
    far = sum(
        1 for f in frames
        if (f.get("boardEdgeObservation") or {}).get("status") == "farShot"
    )
    feats = {k: bt.get(k, float("nan")) for k in TRAJ_FEATURES}
    feats["farShotFrac"] = far / len(frames) if frames else float("nan")
    feats["foldCrossingRate"] = feats["foldCrossingRate"] or 0.0
    return feats


def _mean_std(xs):
    n = len(xs)
    mu = sum(xs) / n
    sd = math.sqrt(sum((z - mu) ** 2 for z in xs) / n)
    return mu, sd


def _linreg_resid(xs, ys):
    """y 对 x 的最小二乘回归残差。"""
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx == 0:
        return [0.0] * n
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    slope = sxy / sxx
    intercept = my - slope * mx
    return [y - (slope * x + intercept) for x, y in zip(xs, ys)]


def _corr(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    sx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    sy = math.sqrt(sum((y - my) ** 2 for y in ys))
    return cov / (sx * sy) if sx and sy else 0.0


def _zspace(values, names, idxs):
    """对 idxs 子集逐特征标准化（用子集统计），返回 {alias: [z...]}。"""
    z = {}
    for j, name in enumerate(names):
        col = [values[i][j] for i in idxs]
        mu, sd = _mean_std(col)
        sd = sd or 1.0
        for i in idxs:
            z.setdefault(i, []).append((values[i][j] - mu) / sd)
    return z


def _eval_contrast(title, aliases, pos_set, values, names):
    """对一组样本做 1D margin / 最优阈值 / LOOCV；返回最佳结果描述。"""
    idxs = list(range(len(aliases)))
    pos = [i for i in idxs if aliases[i] in pos_set]
    neg = [i for i in idxs if aliases[i] not in pos_set]
    if not pos or not neg:
        print(f"\n== {title} == 标签不全，跳过")
        return None

    z = _zspace(values, names, idxs)
    print(f"\n== {title}（{len(pos)} 刻滑/正 vs {len(neg)} 负，n={len(idxs)}）==")
    print(f"{'feature':24s} {'marginσ':>8s} {'全样本acc':>9s} {'LOOCV':>7s} {'专业误伤':>8s}")

    best = None
    for j, name in enumerate(names):
        gp = [z[i][j] for i in pos]
        gn = [z[i][j] for i in neg]
        margin = (sum(gp) / len(gp)) - (sum(gn) / len(gn))
        # 阈值取两簇中点（标准化空间），正类应在高侧；若方向相反 margin 为负
        thr = ((sum(gp) / len(gp)) + (sum(gn) / len(gn))) / 2
        correct = []
        for i in idxs:
            pred_pos = z[i][j] > thr
            correct.append(pred_pos == (i in pos))
        acc = sum(correct) / len(idxs)

        # LOOCV：fold 内重算均值/std 与阈值
        loo_ok = 0
        for h in idxs:
            tr = [i for i in idxs if i != h]
            col = [values[i][j] for i in tr]
            mu, sd = _mean_std(col)
            sd = sd or 1.0
            tp = [i for i in tr if i in pos]
            tn = [i for i in tr if i not in pos]
            mp = sum((values[i][j] - mu) / sd for i in tp) / len(tp)
            mn = sum((values[i][j] - mu) / sd for i in tn) / len(tn)
            t = (mp + mn) / 2
            zh = (values[h][j] - mu) / sd
            pred_pos = zh > t
            if pred_pos == (h in pos):
                loo_ok += 1
        loo = loo_ok / len(idxs)

        fp_pro = sum(1 for i in pos if not correct[i])  # 专业档被判负（误伤）
        key = (margin, acc, loo)
        if best is None or key > best[0]:
            best = (key, name, fp_pro)
        if name == "farShotFrac":
            continue
        print(f"{name:24s} {margin:8.2f} {acc*100:8.1f}% {loo*100:6.1f}% {fp_pro:8d}")

    (margin, acc, loo), bname, fp_pro = best
    print(f"-> 最强：{bname} margin={margin:.2f}σ acc={acc*100:.1f}% "
          f"LOOCV={loo*100:.1f}% 专业误伤={fp_pro}")
    return margin, acc, loo, bname, fp_pro


def _camera_residual(title, aliases, pos_set, values, names):
    """景别/机位混淆核对：特征对 farShotFrac 的相关与去趋势残差 margin。"""
    idxs = list(range(len(aliases)))
    pos = [i for i in idxs if aliases[i] in pos_set]
    neg = [i for i in idxs if aliases[i] not in pos]
    far = [values[i][names.index("farShotFrac")] for i in idxs]
    print(f"\n-- 景别混淆核对：{title} --")
    print(f"{'feature':24s} {'corr(far)':>10s} {'残差marginσ':>12s} {'方向':>6s}")
    rows = []
    for j, name in enumerate(names):
        if name == "farShotFrac":
            continue
        ys = [values[i][j] for i in idxs]
        corr = _corr(far, ys)
        resid = _linreg_resid(far, ys)
        rp = [resid[i] for i in pos]
        rn = [resid[i] for i in neg]
        _, sd = _mean_std(resid)
        sd = sd or 1.0
        rmargin = ((sum(rp) / len(rp)) - (sum(rn) / len(rn))) / sd
        rows.append((name, corr, rmargin))
        print(f"{name:24s} {corr:10.2f} {rmargin:12.2f} "
              f"{'正确' if rmargin > 0 else '反转'}")
    return rows


def trajectory_gate(traj_dir: Path):
    probe_spec = importlib.util.spec_from_file_location(
        "g1probe", ROOT / "scripts" / "board_edge_gate_g1_probe.py")
    g1 = importlib.util.module_from_spec(probe_spec)
    probe_spec.loader.exec_module(g1)

    group_of = {alias: group for alias, group, _ in g1.CLIPS}
    high = {a for a, g in group_of.items() if g == "high"}

    aliases, values = [], []
    for alias, _, _ in g1.CLIPS:
        p = traj_dir / f"{alias}.json"
        if not p.exists():
            continue
        f = _load_traj_clip(p)
        aliases.append(alias)
        values.append([f[k] for k in TRAJ_FEATURES + ["farShotFrac"]])
    names = TRAJ_FEATURES + ["farShotFrac"]
    missing = [a for a, _, _ in g1.CLIPS if a not in aliases]
    print(f"已加载 {len(aliases)} 片；缺 {len(missing)}：{','.join(missing)}")

    # 全组分布速览（foldCrossingRate / farShot）
    print("\n== 分组连续性速览 ==")
    for gname in ("high", "mid", "low"):
        members = [i for i, a in enumerate(aliases) if group_of.get(a) == gname]
        if not members:
            continue
        j = names.index("stableWindowRate")
        k = names.index("foldCrossingRate")
        swr = sum(values[i][j] for i in members) / len(members)
        fold = sum(values[i][k] for i in members) / len(members)
        print(f"  {gname:4s} n={len(members):2d}  mean stableWindowRate={swr:.3f} "
              f"mean foldCrossingRate={fold:.3f}")

    # 主口径：已确认刻滑（high）vs 初级（low）
    low = {a for a, g in group_of.items() if g == "low"}
    hl_aliases = [a for a in aliases if a in high or a in low]
    hl_values = [values[aliases.index(a)] for a in hl_aliases]
    r_hl = _eval_contrast("主口径：已确认刻滑 high vs 初级 low",
                          hl_aliases, high, hl_values, names)
    _camera_residual("high vs low", hl_aliases, high, hl_values, names)

    # 对照口径：原低端 11 片（推坡初级 vs 中级雏形）
    if all((traj_dir / f"{a}.json").exists() for a in BOUNDARY):
        b_aliases = list(BOUNDARY)
        b_values = [values[aliases.index(a)] for a in b_aliases]
        emerging_set = set(EMERGING)
        r_b = _eval_contrast("对照：推坡初级 vs 中级雏形（原低端 11 片）",
                             b_aliases, emerging_set, b_values, names)
        _camera_residual("低端11片", b_aliases, emerging_set, b_values, names)
    else:
        r_b = None
        print("\n对照低端 11 片 JSON 不全，跳过")

    # ---- Gate-G2 裁决 ----
    print("\n" + "=" * 60)
    print("Gate-G2 裁决（margin≥1.5σ 且 LOOCV≥90%，方向正确，专业零误伤）")
    verdict = "NO-GO"
    if r_hl is not None:
        margin, acc, loo, bname, fp_pro = r_hl
        cond = (margin >= 1.5 and loo >= 0.90 and fp_pro == 0)
        print(f"主口径 high vs low：margin={margin:.2f}σ LOOCV={loo*100:.1f}% "
              f"误伤={fp_pro} 特征={bname} -> {'达标' if cond else '不达标'}")
        if cond:
            verdict = "GO"
    if r_b is not None:
        margin, acc, loo, bname, fp_pro = r_b
        print(f"对照低端11片：margin={margin:.2f}σ LOOCV={loo*100:.1f}% "
              f"特征={bname}（参考，不单独决定 GO）")
    print(f"==> {verdict}")
    print("=" * 60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--trajectory", action="store_true",
                        help="Gate-G2：读 boardTrajectory 刃线连续性特征做 margin/LOOCV/景别残差裁决")
    parser.add_argument("--trajectory-dir",
                        default="outputs/board_edge_p2/trajectory_json")
    args = parser.parse_args()
    if args.trajectory:
        trajectory_gate(Path(args.trajectory_dir))
    else:
        main()
