#!/usr/bin/env python3
"""按 p0_board_axis_dense.tsv 的 tSec，用 ffmpeg 从原视频抽帧，
拼 5×2 大图（300×533/帧）+ ROI/主轴/指标标注，供逐帧人工 GT。
输出 outputs/edge_spike/gt_sheets/<alias>.jpg 与抽帧目录 /tmp/p0gt/<alias>/
"""
from __future__ import annotations
import csv, subprocess, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
TSV = ROOT / "outputs/edge_spike/p0_board_axis_dense.tsv"
FRAMEDIR = Path("/tmp/p0gt")
OUTDIR = ROOT / "outputs/edge_spike/gt_sheets"
FW, FH = 300, 533
LABH = 66
PAD = 8

CLIPS = {
    "BND2_LB": "bad/v0300fg10000cusoptnog65pkehng280.MP4",
    "BND2_L6": "bad/v0200fg10000d6olrffog65vrste5qqg.MOV",
    "BND2_L5": "bad/v0300fg10000d664l37og65t6pnbois0.MOV",
    "BND2_L4": "bad/v1e00fgi0000cv786ffog65rtmm48gmg.MOV",
    "BND2_L3": "bad/v2800fgi0000d4v24r7og65oi0fmka5g.MP4",
    "BND2_L2": "bad/v0d00fg10000ctm0ufvog65rqb97g2p0.MP4",
    "BND2_L1": "bad/v0d00fg10000csgr6inog65n8mlpg2m0.MP4",
    "BND_L1": "middle/v1e00fgi0000d5bksdfog65irrhr4bog.MP4",
    "BND_L2": "middle/v0300fg10000d5h313fog65nermuqklg.MP4",
    "BND_L3": "middle/v2800fgi0000d54jhefog65lbfdhma2g.MP4",
    "BND2_LM": "bad/v0200fg10000d7nnh5vog65i52ermgog.MP4",
}

try:
    FONT = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 13)
    FONTB = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 15)
except Exception:
    FONT = ImageFont.load_default(); FONTB = FONT


def read_rows():
    rows = {}
    with TSV.open() as f:
        for r in csv.DictReader(f, delimiter="\t"):
            rows.setdefault(r["alias"], []).append(r)
    return rows


def extract(alias, rel, rows):
    d = FRAMEDIR / alias; d.mkdir(parents=True, exist_ok=True)
    for r in rows:
        tap = r["tap"]; out = d / f"{tap}.jpg"
        if out.exists() and out.stat().st_size > 1000:
            continue
        cmd = ["ffmpeg", "-y", "-ss", r["tSec"], "-i", str(ROOT / "video" / rel),
               "-frames:v", "1", "-q:v", "3", str(out), "-loglevel", "error"]
        subprocess.run(cmd, check=False)


def sheet(alias, rows):
    cols, rowsN = 5, 2
    W = cols * (FW + PAD) + PAD
    H = rowsN * (FH + LABH + PAD) + PAD
    canvas = Image.new("RGB", (W, H), (22, 24, 28))
    dr = ImageDraw.Draw(canvas)
    for r in rows:
        tap = int(r["tap"])
        col, row = tap % cols, tap // cols
        x0 = PAD + col * (FW + PAD); y0 = PAD + row * (FH + LABH + PAD)
        fp = FRAMEDIR / alias / f"{tap}.jpg"
        if fp.exists():
            im = Image.open(fp).convert("RGB").resize((FW, FH))
            canvas.paste(im, (x0, y0))
        ankx, anky = float(r["ankX"]), float(r["ankY"])
        # ROI：位图坐标（y 向下）
        rx = x0 + int((ankx - 0.24) * FW); rw = int(0.48 * FW)
        ry = y0 + int((1 - (anky - 0.01)) * FH); rh = int(0.15 * FH)
        dr.rectangle([rx, ry - rh, rx + rw, ry], outline=(255, 217, 51), width=2)
        ang = float(r["angleDeg"])
        if ang >= 0:
            cxA = x0 + ankx * FW
            cyA = y0 + (1 - (anky - 0.085)) * FH
            half = min(float(r["axisLen"]) * FW / 2, FW * 0.3)
            rad = -math.radians(ang)
            dx = math.cos(rad) * half; dy = math.sin(rad) * half
            ok = r["verdict"] == "board"
            colr = (51, 230, 90) if ok else (255, 40, 50)
            dr.line([cxA - dx, cyA - dy, cxA + dx, cyA + dy], fill=colr, width=4)
        v = r["verdict"]
        vc = (51, 230, 90) if v == "board" else (255, 120, 60)
        dr.text((x0 + 4, y0 + FH + 2), f"#{tap} {v}", font=FONTB, fill=vc)
        dr.text((x0 + 4, y0 + FH + 22),
                f"cnf={float(r['ankCnf']):.2f} subj={float(r['subjFrac']):.3f}",
                font=FONT, fill=(225, 235, 245))
        dr.text((x0 + 4, y0 + FH + 42),
                f"ang={ang if ang < 0 else round(ang)} "
                f"e={float(r['elong']):.1f} L={float(r['axisLen']):.2f}",
                font=FONT, fill=(225, 235, 245))
    out = OUTDIR / f"{alias}.jpg"
    canvas.save(out, quality=86)
    return out


def main():
    OUTDIR.mkdir(parents=True, exist_ok=True)
    allrows = read_rows()
    for alias, rel in CLIPS.items():
        rows = allrows[alias]
        extract(alias, rel, rows)
        p = sheet(alias, rows)
        print("wrote", p)


if __name__ == "__main__":
    main()
