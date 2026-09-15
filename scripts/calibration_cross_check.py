#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
calibration_cross_check.py
==========================

对 outputs/calibration_review_20260915/*.md（12 教练锚点 + 可选主 corpus
testvideo/{1..6}.md）做交叉核对，输出：

  §1  原始数据表（综合分 / edge / calf / knee / lean / gravity / sym / flow / gated）
  §2  档位一致性（vs 教练锚点或 vs 期望档）
  §3  数值 Δ（对有精确锚点分数的样本）
  §4  维度相关性（Pearson r，识别哪一维主导综合分）
  §5  分数分布直方图
  §6  文案-分数自洽性快速扫描（"主要问题" 出现 3 条负面时综合分是否 ≥80）

用途：
  1. 每次修改评分逻辑（sigmoid c / 权重 / edge cap）后回放此脚本，
     直接观察 §2/§3/§4 的偏差是否收敛；
  2. 扩样本时把 aliases.txt 和 EXPECTED 表扩充即可复用。

不重跑 CLI；只读 md 报告。若要重新跑分析，先执行：
  cd outputs/calibration_review_20260915
  for a in ...; do ../../.build/release/FallLineCLI "$a.MP4" > "$a.log" 2>&1; done
"""

from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REVIEW_DIR = ROOT / "outputs" / "calibration_review_20260915"
CORPUS_DIR = ROOT / "testvideo"

# 教练锚点期望档（源自 annotations/calibration_anchors.md 2026-05-04/05 快照）
EXPECTED = {
    "GOOD_A":   ("专业档 [88+]",       94.1, "good accepted-current, 应保持专业档"),
    "MID_ACC1": ("中级 [60,70)",       None, "middle accepted"),
    "MID_ACC2": ("中级 [60,70)",       None, "middle accepted"),
    "MID_ACC3": ("中级 [60,70)",       None, "middle accepted"),
    "MID_ACC4": ("中级 [60,70)",       None, "middle accepted"),
    "MID_ACC5": ("中级 [60,70)",       None, "middle accepted"),
    "MID_ACC6": ("中级 [60,70)",       None, "middle accepted"),
    "MID_ACC7": ("中级 [60,70)",       None, "middle accepted"),
    "MID_ACC8": ("专业档 [88+]",       85.3, "top-middle accepted-current"),
    "MID_FP1":  ("中级偏下 [50,60)",   None, "over-scored, 腿太直"),
    "MID_FP2":  ("中级偏下 [50,60)",   None, "over-scored, 单帧异常"),
    "BAD_ACC":  ("中级 [60,70)",       65.0, "top-bad accepted-current"),
}

TIER_ORDER = [
    "初级 [<50]",
    "中级偏下 [50,60)",
    "中级 [60,70)",
    "中级偏上 [70,80)",
    "高质量档 [80,88)",
    "专业档 [88+]",
]

def tier(s: int) -> str:
    if s >= 88: return TIER_ORDER[5]
    if s >= 80: return TIER_ORDER[4]
    if s >= 70: return TIER_ORDER[3]
    if s >= 60: return TIER_ORDER[2]
    if s >= 50: return TIER_ORDER[1]
    return TIER_ORDER[0]


def extract(alias: str, path: Path, anchor: float | None = None,
            label: str = "") -> dict:
    text = path.read_text(encoding="utf-8")

    def rx(pattern: str, default: str = "0") -> str:
        m = re.search(pattern, text)
        return m.group(1) if m else default

    # "3 条负面主要问题" 简易扫描：抓 "主要问题" 段内 "• " 起始行
    neg_lines = 0
    in_issues = False
    for ln in text.splitlines():
        if "主要问题" in ln:
            in_issues = True
            continue
        if in_issues:
            if ln.strip().startswith("•"):
                neg_lines += 1
            elif ln.strip() and not ln.startswith(" ") and not ln.startswith("\t"):
                in_issues = False

    return {
        "alias": alias,
        "label": label,
        "anchor": anchor,
        "score": int(rx(r"综合评分：(\d+)/100")),
        "raw": float(rx(r"原始均分 ([\d.]+)")),
        "bestThird": float(rx(r"最佳前1/3 ([\d.]+)")),
        "evCapped": float(rx(r"证据封顶后 ([\d.]+)")),
        "flow": float(rx(r"光流系数 ×([\d.]+)", "1.0")),
        "gated": "走刃证据不足" in text,
        "edge": int(rx(r"走刃质量 (\d+)/100")),
        "calf": int(rx(r"小腿倾斜 (\d+)/100")),
        "knee": int(rx(r"膝盖弯曲 (\d+)/100")),
        "lean": int(rx(r"身体前倾 (\d+)/100")),
        "gravity": int(rx(r"重心高度旧分 (\d+)/100")),
        "sym": int(rx(r"动作对称 (\d+)/100")),
        "stage": rx(r"阶段：([^\n]+)").strip(),
        "issue_lines": neg_lines,
    }


def pearson(xs: list[float], ys: list[float]) -> float:
    n = len(xs)
    if n == 0:
        return 0.0
    mx, my = sum(xs) / n, sum(ys) / n
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den = (sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys)) ** 0.5
    return num / den if den else 0.0


def load_all() -> tuple[list[dict], list[dict]]:
    corpus = [
        extract(f"v{i}", CORPUS_DIR / f"{i}.md", label="(主 corpus)")
        for i in range(1, 7)
    ]
    anchors = [
        extract(a, REVIEW_DIR / f"{a}.md", anchor=EXPECTED[a][1], label=EXPECTED[a][2])
        for a in EXPECTED
    ]
    return corpus, anchors


def print_section_1(rows: list[dict]) -> None:
    print("=" * 100)
    print("§1  原始数据表")
    print("=" * 100)
    print(f"{'alias':<9} {'anchor':>6} {'score':>5} {'edge':>4} {'calf':>4} {'knee':>4} "
          f"{'flow':>5} {'stage':<40}")
    print("-" * 100)
    for r in rows:
        anc = f"{r['anchor']:.1f}" if r["anchor"] else "  — "
        gated = "★" if r["gated"] else " "
        print(f"{r['alias']:<9} {anc:>6} {r['score']:>5} {r['edge']:>4} "
              f"{r['calf']:>4} {r['knee']:>4} ×{r['flow']:.2f}{gated} "
              f"{r['stage'][:38]}")
    print("★ = flowModulationGated=true")


def print_section_2(anchors: list[dict]) -> None:
    print()
    print("=" * 100)
    print("§2  档位一致性（vs 教练锚点）")
    print("=" * 100)
    mismatches_up: list[str] = []
    mismatches_down: list[str] = []
    matches: list[str] = []
    print(f"{'alias':<9} {'当前档':<20} {'期望档':<20}  {'一致':>4}  note")
    print("-" * 100)
    for r in anchors:
        exp_tier, _, note = EXPECTED[r["alias"]]
        cur = tier(r["score"])
        ok = cur == exp_tier
        arrow = "✅"
        if not ok:
            if TIER_ORDER.index(cur) > TIER_ORDER.index(exp_tier):
                mismatches_up.append(r["alias"])
                arrow = "⬆️"
            else:
                mismatches_down.append(r["alias"])
                arrow = "⬇️"
        else:
            matches.append(r["alias"])
        print(f"{r['alias']:<9} {cur:<20} {exp_tier:<20}  {arrow:>4}  {note}")

    print()
    total = len(anchors)
    mis = len(mismatches_up) + len(mismatches_down)
    print(f"  一致：{len(matches):>2}/{total}  {matches}")
    print(f"  上迁：{len(mismatches_up):>2}/{total}  {mismatches_up}")
    print(f"  下迁：{len(mismatches_down):>2}/{total}  {mismatches_down}")
    print(f"  不一致率：{100 * mis / total:.1f}%")


def print_section_3(anchors: list[dict]) -> None:
    print()
    print("=" * 100)
    print("§3  数值 Δ（对有精确锚点分数的样本）")
    print("=" * 100)
    for r in anchors:
        if r["anchor"] is None:
            continue
        d = r["score"] - r["anchor"]
        arrow = "⬆️" if d > 0 else ("⬇️" if d < 0 else "→")
        print(f"  {r['alias']:<10} anchor {r['anchor']:>5.1f}  → now {r['score']:>2}  "
              f"Δ={d:+5.1f}  {arrow}")


def print_section_4(rows: list[dict]) -> None:
    print()
    print("=" * 100)
    print("§4  维度相关性（Pearson r vs 综合分）")
    print("=" * 100)
    ys = [r["score"] for r in rows]
    for dim in ("edge", "calf", "knee", "lean", "gravity", "sym"):
        xs = [r[dim] for r in rows]
        r_val = pearson(xs, ys)
        bar = "█" * int(round(abs(r_val) * 20))
        print(f"  {dim:<8} r = {r_val:+.3f}   {bar}")
    print("  提示：r > 0.9 表示该维度几乎完全主导综合分（需引入多维护栏）")


def print_section_5(rows: list[dict]) -> None:
    print()
    print("=" * 100)
    print("§5  分数分布直方图")
    print("=" * 100)
    buckets = [("<60", 0), ("60-69", 0), ("70-79", 0), ("80-87", 0), ("88+", 0)]
    for r in rows:
        s = r["score"]
        if s < 60: buckets[0] = (buckets[0][0], buckets[0][1] + 1)
        elif s < 70: buckets[1] = (buckets[1][0], buckets[1][1] + 1)
        elif s < 80: buckets[2] = (buckets[2][0], buckets[2][1] + 1)
        elif s < 88: buckets[3] = (buckets[3][0], buckets[3][1] + 1)
        else: buckets[4] = (buckets[4][0], buckets[4][1] + 1)
    for name, count in buckets:
        bar = "█" * count
        print(f"  {name:<6} {count:>2}  {bar}")
    total = sum(c for _, c in buckets)
    hi = buckets[3][1] + buckets[4][1]
    print(f"  ≥80 占比：{hi}/{total} = {100 * hi / total:.1f}%")


def print_section_6(rows: list[dict]) -> None:
    print()
    print("=" * 100)
    print("§6  文案-分数自洽性扫描（3+ 条主要问题时综合分是否 ≥80）")
    print("=" * 100)
    print("  ❌ = 报告说 3 条负面但综合分 ≥80（自相矛盾）")
    print("  ⚠️  = 2 条负面且综合分 ≥80")
    print("  ✅ = 其他自洽情形")
    print()
    print(f"{'alias':<9} {'issues':>7} {'score':>6}  status")
    print("-" * 60)
    for r in rows:
        marker = "✅"
        if r["issue_lines"] >= 3 and r["score"] >= 80:
            marker = "❌"
        elif r["issue_lines"] == 2 and r["score"] >= 80:
            marker = "⚠️ "
        print(f"{r['alias']:<9} {r['issue_lines']:>7} {r['score']:>6}  {marker}")


def main() -> int:
    if not REVIEW_DIR.exists():
        print(f"missing: {REVIEW_DIR}", file=sys.stderr)
        return 1
    corpus, anchors = load_all()
    all_rows = corpus + anchors
    print_section_1(all_rows)
    print_section_2(anchors)
    print_section_3(anchors)
    print_section_4(all_rows)
    print_section_5(all_rows)
    print_section_6(all_rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
