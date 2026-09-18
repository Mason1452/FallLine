#!/usr/bin/env python3
"""bestThird 选择偏差修正：离线聚合器模拟。

复现 VideoAnalyzer.generateSummary 的封顶链路（stable baseline / edge evidence /
edgeQuality / board / duration caps + flow factor），唯一可替换环节是
"可靠帧 -> uncappedAverage" 的聚合函数，量化不同聚合器在 25 片人眼标注集上的
档位命中与边界 margin。

只依赖 CLI 产出的帧级 JSON（含 poseScore / skiMetrics / boardAnalysis / summary）。
"""

from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# ---- 生产常量（与 Sources/FallLineCore 对齐）----
MIN_POSE_CNF = 0.30
SOFT_FLOOR, SOFT_CEIL = 0.15, 0.75

EDGE_LOW_X, EDGE_HIGH_X, EDGE_LOW_Y = 30.0, 42.0, 62.0
EQ_LOW_X, EQ_HIGH_X, EQ_LOW_Y = 57.0, 61.0, 72.0
BOARD_CNF, BOARD_DURATION, BOARD_CAP = 0.7, 10.0, 62.0
DUR_SPARSE, DUR_LIMITED, DUR_FULL = 5.0, 8.0, 12.0

STABLE_REL_DUR, STABLE_PLATEAU_DUR = 12.0, 5.0

# flow
COH_BOOST_T, COH_BOOST = 70.0, 0.05
SMOOTH_PEN_T, SMOOTH_PEN = 40.0, 0.05
BOARD_GATE_CNF, LOW_SCORE_PROTECT = 0.30, 60.0

# ---- 25 片人眼标注集（alias, 文件名, 桶, 教练档位 band）----
# band: 0 初级<60 / 1 中级[60,70) / 2 中偏上[70,80) / 3 高质量[80,88) / 4 专业>=88
CLIPS = [
    ("BND_HI1", "middle/9714be3aba73f5f94130750c2a15d381.MP4", 3),
    ("BND_HI2", "middle/4f9ec73b994b63b0775ccfb7a8ef7e6f.MP4", 4),
    ("BND_HI3", "middle/b343b317a6689df373085ec85e042480.MP4", 3),
    ("BND_M1", "middle/v0200fg10000d318sovog65g16lolm8g.MP4", 2),
    ("BND_M2", "middle/v0200fg10000coc7bcrc77u875h9q7sg.MP4", 1),
    ("BND_M3", "middle/v0300fg10000d6fe0nnog65jmdun29vg.MP4", 1),
    ("BND_M4", "middle/v0d00fg10000cu3omkvog65r22seg0t0.MP4", 2),
    ("BND_L1", "middle/v1e00fgi0000d5bksdfog65irrhr4bog.MP4", 1),
    ("BND_L2", "middle/v0300fg10000d5h313fog65nermuqklg.MP4", 1),
    ("BND_L3", "middle/v2800fgi0000d54jhefog65lbfdhma2g.MP4", 1),
    ("BND2_TOP", "good/v1e00fgi0000d2bufenog65temc6sh70.MP4", 4),
    ("BND2_H4", "good/v0200fg10000d6mln8vog65kajcq52dg.MP4", 4),
    ("BND2_H3", "good/v2800fgi0000d7o00ufog65t0ran4h1g.MP4", 4),
    ("BND2_H2", "good/v0300fg10000d7h0ckfog65nmsn20jqg.MP4", 4),
    ("BND2_H1", "good/v1e00fgi0000d5utfk7og65q1chsrq8g.MP4", 4),
    ("BND2_H0", "good/86ae42724c8349913703af0f4140f6d2.MP4", 4),
    ("BND2_GM", "good/d63bfbf8978cf8a962f613a489a14420.MP4", 2),
    ("BND2_LB", "bad/v0300fg10000cusoptnog65pkehng280.MP4", 0),
    ("BND2_L6", "bad/v0200fg10000d6olrffog65vrste5qqg.MOV", 0),
    ("BND2_LM", "bad/v0200fg10000d7nnh5vog65i52ermgog.MP4", 1),
    ("BND2_L5", "bad/v0300fg10000d664l37og65t6pnbois0.MOV", 0),
    ("BND2_L4", "bad/v1e00fgi0000cv786ffog65rtmm48gmg.MOV", 0),
    ("BND2_L3", "bad/v2800fgi0000d4v24r7og65oi0fmka5g.MP4", 0),
    ("BND2_L2", "bad/v0d00fg10000ctm0ufvog65rqb97g2p0.MP4", 0),
    ("BND2_L1", "bad/v0d00fg10000csgr6inog65n8mlpg2m0.MP4", 0),
]

BAND_NAME = ["初级", "中级", "中偏上", "高质量", "专业"]
BAND_EDGES = [60.0, 70.0, 80.0, 88.0]


def band_of(score: float) -> int:
    for i, e in enumerate(BAND_EDGES):
        if score < e:
            return i
    return 4


def clamp(x, lo, hi):
    return max(lo, min(hi, x))


def smooth_w(c: float) -> float:
    n = clamp((c - SOFT_FLOOR) / (SOFT_CEIL - SOFT_FLOOR), 0, 1)
    return n * n


def wavg(pairs) -> float:
    tw = sum(w for _, w in pairs)
    return sum(v * w for v, w in pairs) / tw if tw else 0.0


def wmedian(pairs) -> float:
    s = sorted(pairs, key=lambda p: p[0])
    tw = sum(w for _, w in s)
    acc, h = 0.0, tw / 2
    for v, w in s:
        acc += w
        if acc >= h:
            return v
    return s[-1][0]


def median(vals) -> float:
    s = sorted(vals)
    return s[len(s) // 2]


def sample_interval(times) -> float:
    ds = sorted(b - a for a, b in zip(times, times[1:]) if b - a > 0)
    return ds[len(ds) // 2] if ds else 1.0


def sampled_duration(times) -> float:
    s = sorted(times)
    iv = sample_interval(s)
    return max(s[-1] - s[0] + iv, iv)


def duration_cap(d: float) -> float:
    def ramp(x, x0, x1, y0, y1):
        return y0 + (x - x0) / (x1 - x0) * (y1 - y0)
    if d < DUR_SPARSE:
        return 55.0
    if d < DUR_SPARSE + 0.5:
        return ramp(d, DUR_SPARSE, DUR_SPARSE + 0.5, 55, 65)
    if d < DUR_LIMITED:
        return 65.0
    if d < DUR_LIMITED + 0.5:
        return ramp(d, DUR_LIMITED, DUR_LIMITED + 0.5, 65, 78)
    if d < DUR_FULL:
        return 78.0
    if d < DUR_FULL + 0.5:
        return ramp(d, DUR_FULL, DUR_FULL + 0.5, 78, 100)
    return 100.0


# ---- 聚合器库：entries = [(score, weight_raw_conf, time)] ----
def agg_top_third(entries, frac=1 / 3):
    k = max(1, math.ceil(len(entries) * frac))
    sel = sorted(entries, key=lambda e: -e[0])[:k]
    return wavg([(s, w) for s, w, _ in sel])


def agg_wmean(entries, *_):
    return wavg([(s, w) for s, w, _ in entries])


def agg_median(entries, *_):
    return median([s for s, _, _ in entries])


def agg_wmedian(entries, *_):
    return wmedian([(s, w) for s, w, _ in entries])


def agg_top_half(entries, *_):
    return agg_top_third(entries, 0.5)


def agg_top_quarter(entries, *_):
    return agg_top_third(entries, 0.25)


def make_blend(alpha, other=agg_wmean):
    def f(entries, *_):
        return alpha * agg_top_third(entries) + (1 - alpha) * other(entries)
    f.__name__ = f"blend{int(alpha * 100):02d}"
    return f


def agg_p67(entries, *_):
    # 67 分位（不加权），等价"典型最好时刻但不取窗均值"
    s = sorted(x[0] for x in entries)
    i = min(len(s) - 1, int(round(0.67 * (len(s) - 1))))
    return s[i]


def agg_top_third_durblend(entries, *_):
    # top1/3 与全片均值 0.4/0.6 混合（dur-aware 见 make_blend 的别名）
    return 0.4 * agg_top_third(entries) + 0.6 * agg_wmean(entries)


def make_headroom(k):
    """uncapped = wmean + k*(top33 - wmean)。
    k=1 等价旧 bestThird；k=0 等价全片加权均值。给典型水平留出但限制偶然高分。"""
    def f(entries, *_):
        m = agg_wmean(entries)
        return m + k * (agg_top_third(entries) - m)
    f.__name__ = f"headroom{int(round(k * 100)):02d}"
    return f


def make_trimmed(p_lo, p_hi):
    """去掉两端分位后的加权均值（p 为比例）。"""
    def f(entries, *_):
        s = sorted(entries, key=lambda e: e[0])
        n = len(s)
        lo = int(round(p_lo * n))
        hi = n - int(round(p_hi * n))
        sel = s[lo:hi] or s
        return wavg([(x[0], x[1]) for x in sel])
    f.__name__ = f"trim{int(p_lo * 100):02d}{int(p_hi * 100):02d}"
    return f


AGGREGATORS = [
    ("baseline_top33", agg_top_third),
    ("wmean", agg_wmean),
    ("median", agg_median),
    ("wmedian", agg_wmedian),
    ("top50", agg_top_half),
    ("top25", agg_top_quarter),
    ("p67", agg_p67),
    ("blend25", make_blend(0.25)),
    ("blend40", agg_top_third_durblend),
    ("blend50", make_blend(0.50)),
    ("blend75", make_blend(0.75)),
    ("headroom25", make_headroom(0.25)),
    ("headroom40", make_headroom(0.40)),
    ("headroom50", make_headroom(0.50)),
    ("headroom60", make_headroom(0.60)),
    ("trim10_33", make_trimmed(0.10, 0.33)),
    ("trim20_33", make_trimmed(0.20, 0.33)),
    ("trim25_33", make_trimmed(0.25, 0.33)),
]


def load(rel: str) -> dict:
    p = ROOT / "video" / Path(rel).with_suffix(".json")
    return json.loads(p.read_text())


def reliable_entries(data):
    scored, times = [], []
    for f in data["frames"]:
        ps = f.get("poseScore")
        bp = f.get("bodyPose", {})
        if ps and bp.get("detected"):
            scored.append((f["time"], ps, f))
    rel = [(t, ps, f) for t, ps, f in scored if ps["totalConfidence"] >= MIN_POSE_CNF]
    pool = rel if rel else scored
    entries = [(ps["totalScore"], max(0.01, ps["totalConfidence"]), t) for t, ps, _ in pool]
    frames = [f for _, _, f in pool]
    return entries, frames


def stable_baseline(entries, stability) -> float | None:
    if sampled_duration([t for _, _, t in entries]) < STABLE_REL_DUR or stability < 85:
        return None
    raw = wavg([(s, smooth_w(w)) for s, w, _ in entries])
    best = max(s for s, _, _ in entries)
    if not (raw < 65 and best >= 75 and best - raw >= 15):
        return None
    floor = best - 6
    cur, plateaus = [], []
    for s, w, t in entries:
        if s >= floor:
            cur.append((s, w, t))
        elif cur:
            plateaus.append(cur)
            cur = []
    if cur:
        plateaus.append(cur)
    if not plateaus:
        return None
    plateau = max(plateaus, key=len)
    pdur = sampled_duration([t for _, _, t in plateau])
    if pdur < STABLE_PLATEAU_DUR:
        return None
    total = sampled_duration([t for _, _, t in entries])
    cov = pdur / total
    if cov < 0.18:
        return None
    pavg = wavg([(s, smooth_w(w)) for s, w, _ in plateau])
    if pavg >= 75 and pavg > raw:
        return pavg
    return None


def edge_evidence_cap(frames) -> float:
    vals = []
    for f in frames:
        ps = f["poseScore"]
        if ps["calfLeanConfidence"] >= MIN_POSE_CNF:
            vals.append((ps["calfLeanScore"], max(0.001, smooth_w(ps["calfLeanConfidence"]))))
    if not vals:
        return 65.0
    e = wavg(vals)
    if e < EDGE_LOW_X:
        return EDGE_LOW_Y
    if e < EDGE_HIGH_X:
        return EDGE_LOW_Y + (e - EDGE_LOW_X) / (EDGE_HIGH_X - EDGE_LOW_X) * (100 - EDGE_LOW_Y)
    return 100.0


def edge_quality_cap(frames, stability) -> float:
    vals = []
    n = len(frames)
    stab_cnf = min(1.0, n / 5.0)
    for f in frames:
        sm = f.get("skiMetrics")
        if not sm:
            # 极端兜底（理论上 JSON 都带）
            continue
        vals.append((sm["edgeQualityScore"], max(0.001, smooth_w(sm["edgeQualityConfidence"]))))
    if not vals:
        return 100.0
    e = wavg(vals)
    _ = stab_cnf
    if e < EQ_LOW_X:
        return EQ_LOW_Y
    if e < EQ_HIGH_X:
        return EQ_LOW_Y + (e - EQ_LOW_X) / (EQ_HIGH_X - EQ_LOW_X) * (100 - EQ_LOW_Y)
    return 100.0


def board_cap(frames, data) -> float | None:
    s = (data.get("boardAnalysis") or {}).get("summary")
    if not s or s.get("averageSideslipAngle") is None:
        return None
    dur = sampled_duration([f["time"] for f in frames])
    if s["confidence"] < BOARD_CNF and dur < BOARD_DURATION:
        return BOARD_CAP
    return None


def flow_factor(data, capped: float) -> float:
    sm = data["summary"]
    if (sm.get("flowFramePairsUsed") or 0) < 2:
        return 1.0
    coh = sm.get("flowMotionCoherence") or 0
    smo = sm.get("flowVelocitySmoothness") or 0
    bc = ((data.get("boardAnalysis") or {}).get("summary") or {}).get("confidence", 1.0)
    mod = 1.0
    if coh > COH_BOOST_T:
        mod += COH_BOOST
    if 0 < smo < SMOOTH_PEN_T:
        mod -= SMOOTH_PEN
    gate = bc < BOARD_GATE_CNF
    if capped < LOW_SCORE_PROTECT:
        gate = False
    if gate:
        mod = min(mod, 1.0)
    return clamp(mod, 0.87, 1.13)


def simulate(data, agg_fn):
    """所有 cap（edge/edgeQuality/board/duration）与稳定刻滑基线都只依赖帧分数，
    与聚合器选择无关；因此固定封顶线就是 JSON 的 evidenceCappedScore。
    备选聚合器只会把 uncapped 往下拉：pre_flow = min(uncapped', evidenceCapped_orig)。
    """
    entries, frames = reliable_entries(data)
    stability = data["summary"]["stabilityScore"]
    sb = stable_baseline(entries, stability)
    uncapped = max(agg_fn(entries), sb or 0)
    ceiling = data["summary"].get("evidenceCappedScore") or uncapped
    capped = min(uncapped, ceiling)
    final = clamp(capped * flow_factor(data, capped), 0, 100)
    return final, uncapped, sb is not None


def main():
    rows = []
    for alias, rel, coach in CLIPS:
        data = load(rel)
        actual = data["summary"]["averageScore"]
        res = {}
        for name, fn in AGGREGATORS:
            final, uncapped, baseline_hit = simulate(data, fn)
            res[name] = final
        rows.append((alias, coach, actual, res, data))

    # 校验 baseline 聚合器复现生产分数
    print("== baseline 复现校验（sim vs JSON averageScore） ==")
    worst = 0.0
    for alias, coach, actual, res, _ in rows:
        d = abs(res["baseline_top33"] - actual)
        worst = max(worst, d)
        flag = "⚠️" if d > 1.5 else " "
        print(f"{flag} {alias:10s} sim={res['baseline_top33']:6.2f} json={actual:6.2f} Δ={d:5.2f}")
    print(f"max Δ = {worst:.2f}\n")

    # 逐聚合器档位命中
    print("== 聚合器档位命中（25 片，教练人眼） ==")
    header = f"{'aggregator':16s} {'hit':>4s} {'±1内':>5s} {'低估':>4s} {'高估':>4s} {'最差档':>6s} {'MAE':>6s} {'越界MAE':>7s}"
    print(header)
    band_lo = [0.0, 60.0, 70.0, 80.0, 88.0]
    band_hi = [60.0, 70.0, 80.0, 88.0, 101.0]

    def band_dist(score, coach):
        if score < band_lo[coach]:
            return band_lo[coach] - score
        if score >= band_hi[coach]:
            return score - (band_hi[coach] - 0.01)
        return 0.0

    scored = {}
    for name, _ in AGGREGATORS:
        exact = within = under = over = 0
        worst_band_delta = 0
        sae = bdist_sum = 0.0
        for alias, coach, actual, res, _ in rows:
            sc = res[name]
            b = band_of(sc)
            db = b - coach
            worst_band_delta = max(worst_band_delta, abs(db))
            sae += abs(sc - (band_lo[coach] + band_hi[coach]) / 2)
            bdist_sum += band_dist(sc, coach)
            if db == 0:
                exact += 1
            if abs(db) <= 1:
                within += 1
            if db < 0:
                under += 1
            if db > 0:
                over += 1
        scored[name] = (exact, within, under, over, worst_band_delta)
        print(f"{name:16s} {exact:4d} {within:5d} {under:4d} {over:4d} {worst_band_delta:6d} "
              f"{sae / len(rows):6.2f} {bdist_sum / len(rows):7.2f}")

    # 低端关键样本明细
    focus = ["BND2_LB", "BND2_L6", "BND2_LM", "BND2_L5", "BND2_L4",
             "BND2_L3", "BND2_L2", "BND2_L1",
             "BND_L1", "BND_L2", "BND_L3", "BND_M2", "BND_M3",
             "BND_M1", "BND_M4", "BND2_GM"]
    print("\n== 低端/边界样本终分明细 ==")
    print(f"{'alias':10s} {'coach':6s} " + " ".join(f"{n[:9]:>9s}" for n, _ in AGGREGATORS))
    rdict = {r[0]: r for r in rows}
    for alias in focus:
        a, coach, actual, res, _ = rdict[alias]
        cells = " ".join(f"{res[n]:9.1f}" for n, _ in AGGREGATORS)
        mark = "" if band_of(res["baseline_top33"]) == coach else " ←当前错"
        print(f"{alias:10s} {BAND_NAME[coach]:6s} {cells}{mark}")

    # 高端保护明细
    print("\n== 高端样本终分明细（防误伤） ==")
    for alias in ["BND2_TOP", "BND2_H4", "BND2_H3", "BND2_H2", "BND2_H1",
                  "BND2_H0", "BND_HI1", "BND_HI2", "BND_HI3"]:
        a, coach, actual, res, _ = rdict[alias]
        cells = " ".join(f"{res[n]:9.1f}" for n, _ in AGGREGATORS)
        print(f"{alias:10s} {BAND_NAME[coach]:6s} {cells}")

    # 低端机理诊断：raw 分布与封顶来源
    print("\n== 低端机理诊断（wmean / top33 / evidenceCapped / 最终分 / <60帧占比） ==")
    print(f"{'alias':10s} {'n':>4s} {'wmean':>6s} {'top33':>6s} {'capped':>7s} {'final':>6s} {'<60%':>6s} {'cap来源(估)':s}")
    for alias in ["BND2_LB", "BND2_L6", "BND2_LM", "BND2_L5", "BND2_L4",
                  "BND2_L3", "BND2_L2", "BND2_L1",
                  "BND_L1", "BND_L2", "BND_L3", "BND_M2", "BND_M3"]:
        _, coach, actual, res, data = rdict[alias]
        entries, frames = reliable_entries(data)
        wm = agg_wmean(entries)
        t3 = agg_top_third(entries)
        cap = data["summary"].get("evidenceCappedScore", float("nan"))
        below60 = 100.0 * sum(1 for s, _, _ in entries if s < 60) / len(entries)
        rel_dur = sampled_duration([f["time"] for f in frames])
        caps = {
            "edge": edge_evidence_cap(frames),
            "edgeQ": edge_quality_cap(frames, data["summary"]["stabilityScore"]),
            "dur": duration_cap(rel_dur),
        }
        bcap = board_cap(frames, data)
        if bcap is not None:
            caps["board"] = bcap
        binding = min(caps, key=lambda k: caps[k])
        capstr = " ".join(f"{k}{v:.0f}" for k, v in sorted(caps.items(), key=lambda kv: kv[1]))
        print(f"{alias:10s} {len(entries):4d} {wm:6.1f} {t3:6.1f} {cap:7.1f} {actual:6.1f} "
              f"{below60:6.1f} →{binding} [{capstr}]")

    # 输出 machine-readable TSV
    out = ROOT / "outputs/bestthird_rerun/aggregator_scores.tsv"
    with out.open("w") as fh:
        fh.write("alias\tcoach\tcoachBand\tactual\t" + "\t".join(n for n, _ in AGGREGATORS) + "\n")
        for alias, coach, actual, res, _ in rows:
            fh.write(f"{alias}\t{BAND_NAME[coach]}\t{coach}\t{actual:.2f}\t"
                     + "\t".join(f"{res[n]:.3f}" for n, _ in AGGREGATORS) + "\n")
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
