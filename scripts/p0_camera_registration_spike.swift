// p0_camera_registration_spike.swift
// Phase 0 候选 C1：相邻帧纯平移配准 → 相机/背景运动，供踝轨迹去相机补偿。
//
// VNTranslationalImageRegistrationRequest(source=frame_i, target=frame_{i+1})
// 返回 alignmentTransform（CGAffineTransform，Vision 图像坐标，左下原点 y 向上，单位 px）：
// 同一背景点满足 target_pos ≈ source_pos + (tx,ty)，即背景在画面中的位移 = (tx,ty)。
// 雪面相对位移（补偿后）= 踝画面位移 − (tx,ty)/帧尺寸（符号与 ankleCenter 归一化坐标一致）。
//
// 帧严格按 JSON frames[].time 用 AVAssetImageGenerator 精确抽取（与踝点同一帧），
// 降采样到长边 480 加速配准；逐对配准，失败/大跳变输出 regOK=0。
//
// 输出 TSV：outputs/edge_spike/p0_camera_motion.tsv
//   alias fi t cdx cdy mag regOK frameW frameH
// 运行：swift scripts/p0_camera_registration_spike.swift

import AppKit
import Foundation
import Vision
import AVFoundation

let OUT_TSV = "outputs/edge_spike/p0_camera_motion.tsv"
let MAX_EDGE = 480
let MAX_JUMP = 0.35   // 单帧相机位移 > 35% 图宽视为配准异常（摇镜/切点），标 regOK=0

let CLIPS: [(alias: String, rel: String)] = [
    ("BND2_LB", "bad/v0300fg10000cusoptnog65pkehng280.MP4"),
    ("BND2_L6", "bad/v0200fg10000d6olrffog65vrste5qqg.MOV"),
    ("BND2_L5", "bad/v0300fg10000d664l37og65t6pnbois0.MOV"),
    ("BND2_L4", "bad/v1e00fgi0000cv786ffog65rtmm48gmg.MOV"),
    ("BND2_L3", "bad/v2800fgi0000d4v24r7og65oi0fmka5g.MP4"),
    ("BND2_L2", "bad/v0d00fg10000ctm0ufvog65rqb97g2p0.MP4"),
    ("BND2_L1", "bad/v0d00fg10000csgr6inog65n8mlpg2m0.MP4"),
    ("BND_L1", "middle/v1e00fgi0000d5bksdfog65irrhr4bog.MP4"),
    ("BND_L2", "middle/v0300fg10000d5h313fog65nermuqklg.MP4"),
    ("BND_L3", "middle/v2800fgi0000d54jhefog65lbfdhma2g.MP4"),
    ("BND2_LM", "bad/v0200fg10000d7nnh5vog65i52ermgog.MP4"),
]

struct F: Decodable { let time: Double?
    let bodyPose: BP?
    struct BP: Decodable { let detected: Bool?
        let ankleCenterX: P?; let ankleCenterY: P?
        struct P: Decodable { let confidence: Double? } } }
struct Doc: Decodable { let frames: [F]? }

func downsampled(_ cg: CGImage) -> CGImage {
    let longEdge = max(cg.width, cg.height)
    guard longEdge > MAX_EDGE else { return cg }
    let s = Double(MAX_EDGE) / Double(longEdge)
    let w = max(1, Int(Double(cg.width) * s)), h = max(1, Int(Double(cg.height) * s))
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return cg }
    ctx.interpolationQuality = .medium
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage() ?? cg
}

var out: [String] = ["alias\tfi\tt\tcdx\tcdy\tmag\tregOK\tframeW\tframeH"]

for c in CLIPS {
    let jsonPath = "video/\((c.rel as NSString).deletingPathExtension).json"
    guard let data = FileManager.default.contents(atPath: jsonPath),
          let doc = try? JSONDecoder().decode(Doc.self, from: data),
          let frames = doc.frames else {
        print("[\(c.alias)] json fail"); continue
    }
    // 取踝点有效帧（与 pathshape audit 同口径 MIN_CNF=0.30）
    var times: [(fi: Int, t: Double)] = []
    for (i, f) in frames.enumerated() {
        guard f.bodyPose?.detected == true, let t = f.time,
              let cx = f.bodyPose?.ankleCenterX?.confidence,
              let cy = f.bodyPose?.ankleCenterY?.confidence,
              min(cx, cy) >= 0.30 else { continue }
        times.append((i, t))
    }
    guard times.count >= 4 else {
        print("[\(c.alias)] valid frames \(times.count) < 4"); continue
    }

    let asset = AVURLAsset(url: URL(fileURLWithPath: "video/\(c.rel)"))
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero

    var prev: CGImage?
    var prevFi = -1
    var prevW = 0, prevH = 0
    var okCount = 0, pairCount = 0

    for (fi, t) in times {
        let cm = CMTime(seconds: t, preferredTimescale: 600)
        var cg: CGImage?
        do { cg = try gen.copyCGImage(at: cm, actualTime: nil) } catch { cg = nil }
        guard let raw = cg else {
            out.append("\(c.alias)\t\(fi)\t\(String(format: "%.3f", t))\t0\t0\t0\t0\t0\t0")
            prev = nil; continue
        }
        let ds = downsampled(raw)
        if let p = prev {
            pairCount += 1
            let req = VNTranslationalImageRegistrationRequest(targetedCGImage: ds)
            let handler = VNImageRequestHandler(cgImage: p, options: [:])
            var cdx = 0.0, cdy = 0.0, mag = 0.0, ok = 0
            do {
                try handler.perform([req])
                if let obs = req.results?.first {
                    let tr = obs.alignmentTransform
                    cdx = tr.tx / Double(prevW)
                    cdy = tr.ty / Double(prevH)
                    mag = hypot(cdx, cdy)
                    if mag <= MAX_JUMP { ok = 1; okCount += 1 }
                }
            } catch { }
            out.append("\(c.alias)\t\(prevFi)\t\(String(format: "%.3f", t))\t" +
                       "\(String(format: "%.5f", cdx))\t\(String(format: "%.5f", cdy))\t" +
                       "\(String(format: "%.5f", mag))\t\(ok)\t\(prevW)\t\(prevH)")
        }
        prev = ds; prevFi = fi; prevW = ds.width; prevH = ds.height
    }
    print("[\(c.alias)] valid=\(times.count) pairs=\(pairCount) regOK=\(okCount) " +
          "(\(pairCount > 0 ? String(format: "%.0f%%", 100 * Double(okCount) / Double(pairCount)) : "-"))")
}

try? out.joined(separator: "\n").write(toFile: OUT_TSV, atomically: true, encoding: .utf8)
print("wrote \(OUT_TSV) lines=\(out.count - 1)")
