#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
repeatability_probe.py
======================

评分确定性探针（对标 SportsReflector 公开的 Form Score Repeatability 方法：
同一视频分析 N 次，统计综合分 SD / range）。

背景：
    VideoAnalyzer 用 withThrowingTaskGroup 并发跑帧分析，跨次运行的线程
    调度 + Vision 熔断时机 + 浮点归约顺序理论上都可能引入非确定性。
    本探针把"评分确定性"变成可量化指标，作为后续调优的 baseline。

方法：
    对每份视频执行 N 次全新 CLI 进程（每次独立临时目录 + symlink，不污染
    testvideo/），读取产物 JSON，抽取评分链路关键字段：
      - averageScore            最终综合分
      - rawPoseAverageScore     原始姿态均分
      - bestThirdAverageScore   最佳前 1/3
      - evidenceCappedScore     证据封顶后
      - flowModulationFactor    光流系数
      - scoreStdDev             视频内帧分 SD（对照组）
      - board.confidence        走刃证据置信度
      - totalFrames / flowFramePairsUsed
    统计 mean / sample-SD / min / max / range / 唯一值个数；
    另对剔除 videoPath 后的 JSON 算 SHA256，判定是否 bit-level 确定性。
    --deep 时逐帧对比 score 数组，报告首个分歧帧，便于定位非确定性来源。

用法：
    python3 scripts/repeatability_probe.py                         # 主 corpus 6 份 × 10 次
    python3 scripts/repeatability_probe.py -n 3 testvideo/1.MP4    # 单份 × 3 次（冒烟）
    python3 scripts/repeatability_probe.py --build                 # 先 swift build -c release
    python3 scripts/repeatability_probe.py --deep --keep-workdir   # 排查分歧帧 + 保留产物

无副作用：默认每次运行后删除临时目录；仅 stdout 输出。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASE_BIN = ROOT / ".build" / "release" / "FallLineCLI"
TESTVIDEO = ROOT / "testvideo"

DEFAULT_VIDEOS = [TESTVIDEO / f"{i}.MP4" for i in range(1, 7)]

METRIC_PATHS = {
    "averageScore": ("summary", "averageScore"),
    "rawPoseAverageScore": ("summary", "rawPoseAverageScore"),
    "bestThirdAverageScore": ("summary", "bestThirdAverageScore"),
    "evidenceCappedScore": ("summary", "evidenceCappedScore"),
    "flowModulationFactor": ("summary", "flowModulationFactor"),
    "scoreStdDev": ("summary", "scoreStdDev"),
    "flowFramePairsUsed": ("summary", "flowFramePairsUsed"),
    "boardConfidence": ("boardAnalysis", "summary", "confidence"),
    "carvingConfidence": ("boardAnalysis", "summary", "carvingConfidence"),
}


def build_release() -> None:
    print("🔧 swift build -c release ...", flush=True)
    proc = subprocess.run(
        ["swift", "build", "--configuration", "release"], cwd=ROOT
    )
    if proc.returncode != 0:
        sys.exit("❌ release 构建失败")


def run_once(binary: Path, video: Path, keep: bool, work_root: Path | None):
    """单次全新 CLI 运行，返回 (data_dict, frame_scores, json_hash_ignoring_path)。"""
    workdir = Path(tempfile.mkdtemp(prefix="rep_", dir=work_root))
    try:
        link = workdir / video.name
        link.symlink_to(video.resolve())
        proc = subprocess.run(
            [str(binary), str(link)],
            cwd=workdir,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        if proc.returncode != 0:
            tail = (proc.stderr or "")[-800:]
            raise RuntimeError(f"CLI 退出码 {proc.returncode}\n{tail}")
        json_path = workdir / (video.stem + ".json")
        if not json_path.exists():
            raise RuntimeError(f"未找到产物 {json_path}")
        with open(json_path) as f:
            data = json.load(f)
        frame_scores = [
            (fr.get("poseScore") or {}).get("totalScore")
            for fr in data.get("frames", [])
        ]
        fingerprint = dict(data)
        fingerprint.pop("videoPath", None)
        digest = hashlib.sha256(
            json.dumps(fingerprint, sort_keys=True, ensure_ascii=False).encode()
        ).hexdigest()
        return data, frame_scores, digest
    finally:
        if not keep:
            shutil.rmtree(workdir, ignore_errors=True)


def extract(data: dict) -> dict[str, float | int | None]:
    out: dict[str, float | int | None] = {"totalFrames": data.get("totalFrames")}
    for name, path in METRIC_PATHS.items():
        node = data
        for key in path:
            node = (node or {}).get(key) if isinstance(node, dict) else None
        out[name] = node
    return out


def fmt_stats(values: list) -> str:
    nums = [v for v in values if isinstance(v, (int, float))]
    if not nums:
        return "无数据"
    mean = statistics.fmean(nums)
    sd = statistics.stdev(nums) if len(nums) > 1 else 0.0
    uniq = len({round(v, 6) if isinstance(v, float) else v for v in nums})
    return (
        f"mean={mean:.3f} sd={sd:.4f} min={min(nums):.3f} max={max(nums):.3f} "
        f"range={max(nums) - min(nums):.3f} uniq={uniq}/{len(nums)}"
    )


def probe_video(binary, video: Path, n: int, deep: bool, keep: bool,
                work_root) -> dict:
    print(f"\n=== {video.name} × {n} 次 ===", flush=True)
    runs: list[dict] = []
    digests: list[str] = []
    frame_series: list[list] = []
    for i in range(1, n + 1):
        data, frame_scores, digest = run_once(binary, video, keep, work_root)
        runs.append(extract(data))
        digests.append(digest)
        frame_series.append(frame_scores)
        print(f"  run {i:2d}: averageScore={runs[-1]['averageScore']}", flush=True)

    result = {"video": video.name, "runs": runs}
    print(f"  JSON 指纹（剔除 videoPath）唯一值: {len(set(digests))}/{n}")
    for metric in ["averageScore", "rawPoseAverageScore", "bestThirdAverageScore",
                   "evidenceCappedScore", "flowModulationFactor", "scoreStdDev",
                   "boardConfidence", "carvingConfidence", "flowFramePairsUsed",
                   "totalFrames"]:
        values = [r[metric] for r in runs]
        print(f"  {metric:24s} {fmt_stats(values)}")

    if deep:
        baseline = frame_series[0]
        first_diff = None
        diff_runs = 0
        for idx, series in enumerate(frame_series[1:], start=2):
            diffs = [
                j for j, (a, b) in enumerate(zip(baseline, series))
                if a != b
            ]
            if diffs:
                diff_runs += 1
                if first_diff is None:
                    first_diff = (idx, diffs[0], len(diffs), len(baseline))
        if first_diff is None:
            print("  --deep: 逐帧 score 完全一致 ✅")
        else:
            idx, frame, ndiff, total = first_diff
            print(
                f"  --deep: {diff_runs}/{n - 1} 次运行存在帧级分歧；"
                f"首次 run{idx} frame#{frame}（该次共 {ndiff}/{total} 帧不同）"
            )
        result["frameLevelDeterministic"] = first_diff is None
    result["deterministic"] = len(set(digests)) == 1
    return result


def main() -> None:
    ap = argparse.ArgumentParser(description="评分确定性 repeatability 探针")
    ap.add_argument("videos", nargs="*", type=Path, help="视频路径（默认主 corpus 6 份）")
    ap.add_argument("-n", "--runs", type=int, default=10, help="每份视频重复次数（默认 10）")
    ap.add_argument("--build", action="store_true", help="先执行 swift build -c release")
    ap.add_argument("--deep", action="store_true", help="逐帧 score 对比，定位首个分歧帧")
    ap.add_argument("--keep-workdir", action="store_true", help="保留临时目录与产物（调试）")
    args = ap.parse_args()

    if args.build:
        build_release()
    if not RELEASE_BIN.exists():
        sys.exit(f"❌ 未找到 {RELEASE_BIN}，请先运行：swift build -c release（或加 --build）")

    videos = args.videos or DEFAULT_VIDEOS
    missing = [v for v in videos if not v.exists()]
    if missing:
        sys.exit(f"❌ 视频不存在: {', '.join(str(m) for m in missing)}")

    work_root = ROOT / ".repeatability_work" if args.keep_workdir else None
    if work_root:
        work_root.mkdir(exist_ok=True)

    results = []
    for video in videos:
        results.append(
            probe_video(RELEASE_BIN, video, args.runs, args.deep,
                        args.keep_workdir, work_root)
        )

    print("\n" + "=" * 68)
    print(f"汇总（N={args.runs}，对标 SportsReflector 公开基线 ±3.0 pts）")
    print("=" * 68)
    print(f"{'视频':<12}{'mean':>9}{'SD':>9}{'range':>9}  确定性")
    worst_sd = 0.0
    for res in results:
        scores = [r["averageScore"] for r in res["runs"]
                  if isinstance(r["averageScore"], (int, float))]
        mean = statistics.fmean(scores)
        sd = statistics.stdev(scores) if len(scores) > 1 else 0.0
        rng = max(scores) - min(scores)
        worst_sd = max(worst_sd, sd)
        det = "bit-identical ✅" if res["deterministic"] else "存在非确定性 ⚠️"
        print(f"{res['video']:<12}{mean:>9.2f}{sd:>9.3f}{rng:>9.3f}  {det}")
    print(f"\n最大跨次 SD = {worst_sd:.3f} pts；"
          f"判定: {'PASS（SD ≤ 3.0）' if worst_sd <= 3.0 else 'FAIL（SD > 3.0）'}")


if __name__ == "__main__":
    main()
