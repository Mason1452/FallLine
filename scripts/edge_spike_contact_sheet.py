#!/usr/bin/env python3
"""刃线/轨迹检测立项 spike · 第 0 步：雪板可见性接触表。

对 11 片低端边界样本（7 教练判初级 + 4 真中级雏形）按时间均匀抽 4 帧，
拼接带 alias/时间戳标签的接触表，回答刃线检测的第一前提：
雪板在竖屏画面里到底占多少像素、是否稳定可见、脚踝以下是否入镜。

全分辨率帧另存 FRAME_DIR（默认 /tmp/edge_spike/frames），供后续 Vision
contour / foreground mask / CoreML spike 复用；接触表写到
outputs/edge_spike/contact_sheet_<group>.jpg 供人工查看。

用法：python3 scripts/edge_spike_contact_sheet.py
依赖：ffmpeg/ffprobe（/opt/homebrew/bin 或 PATH）、Pillow。
"""

from __future__ import annotations

import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
FRAME_DIR = Path("/tmp/edge_spike/frames")
OUT_DIR = ROOT / "outputs/edge_spike"

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

N_FRAMES = 4
TAPS = [0.2, 0.4, 0.6, 0.8]
THUMB_W = 270


def find_tool(name: str) -> str:
    p = Path("/opt/homebrew/bin") / name
    return str(p) if p.exists() else name


def probe_duration(ffprobe: str, video: Path) -> float:
    out = subprocess.run(
        [ffprobe, "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", str(video)],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    return float(out)


def extract_frame(ffmpeg: str, video: Path, t: float, dest: Path) -> bool:
    if dest.exists():
        return True
    r = subprocess.run(
        [ffmpeg, "-v", "error", "-ss", f"{t:.2f}", "-i", str(video),
         "-frames:v", "1", "-q:v", "2", str(dest)],
        capture_output=True,
    )
    return r.returncode == 0 and dest.exists()


def main() -> None:
    ffprobe, ffmpeg = find_tool("ffprobe"), find_tool("ffmpeg")
    FRAME_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for group, clips in (("beginner", BEGINNER), ("emerging", EMERGING)):
        tiles: list[Image.Image] = []
        tile_h = 0
        for alias, rel in clips:
            video = ROOT / "video" / rel
            dur = probe_duration(ffprobe, video)
            for i, frac in enumerate(TAPS):
                t = dur * frac
                raw = FRAME_DIR / f"{alias}_t{i}.jpg"
                extract_frame(ffmpeg, video, t, raw)
                im = Image.open(raw).convert("RGB")
                w, h = im.size
                th = round(h * THUMB_W / w)
                im = im.resize((THUMB_W, th))
                tile_h = th
                band = Image.new("RGB", (THUMB_W, th + 22), (20, 20, 20))
                band.paste(im, (0, 22))
                d = ImageDraw.Draw(band)
                d.text((4, 4), f"{alias} t={t:.1f}s", fill=(255, 255, 120))
                tiles.append(band)

        cols = N_FRAMES
        rows = len(clips)
        sheet = Image.new(
            "RGB",
            (cols * THUMB_W, rows * (tile_h + 22)),
            (0, 0, 0),
        )
        for idx, tile in enumerate(tiles):
            r, c = divmod(idx, cols)
            sheet.paste(tile, (c * THUMB_W, r * (tile_h + 22)))
        out = OUT_DIR / f"contact_sheet_{group}.jpg"
        sheet.save(out, quality=88)
        print(f"wrote {out}  ({sheet.size[0]}x{sheet.size[1]})")


if __name__ == "__main__":
    main()
