// p0_camera_registration_bg_spike.swift
// Phase 0 候选 C1-r2：背景掩膜纯平移配准（修复全图配准在跟拍/大主体时锁滑手的伪影）。
//
// 做法：每帧同帧跑 VNDetectHumanBodyPoseRequest 取关键点包围盒（外扩 8%），
// 框内像素用框外灰度均值填充、框边 10px 羽化，使人体区域对配准梯度贡献≈0，
// VNTranslationalImageRegistrationRequest 只对齐雪面/背景。
// 输出：outputs/edge_spike/p0_camera_motion_bg.tsv（列与全图版一致，另加 boxW/boxH/boxFillMean）。
//
// 运行：swift scripts/p0_camera_registration_bg_spike.swift

import Foundation
import Vision
import AVFoundation
import CoreGraphics
import ImageIO

let OUT_TSV = "outputs/edge_spike/p0_camera_motion_bg.tsv"
let MAX_EDGE = 480
let MAX_JUMP = 0.35
let FEATHER = 10.0
let JOINT_MIN_CNF: Float = 0.20

let JOINTS: [VNHumanBodyPoseObservation.JointName] = [
    .nose, .neck, .leftShoulder, .rightShoulder,
    .leftElbow, .rightElbow, .leftWrist, .rightWrist,
    .leftHip, .rightHip, .leftKnee, .rightKnee,
    .leftAnkle, .rightAnkle,
]

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
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
    ctx.interpolationQuality = .medium
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage() ?? cg
}

// 人体关键点包围盒（Vision 归一化坐标，左下原点）→ 降采样位图像素矩形（左上原点）
func poseBox(_ cg: CGImage) -> (CGRect, Bool) {
    let req = VNDetectHumanBodyPoseRequest()
    let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
    do { try handler.perform([req]) } catch { return (.zero, false) }
    guard let obs = req.results?.first else { return (.zero, false) }
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0
    var found = false
    for j in JOINTS {
        guard let p = try? obs.recognizedPoint(j), p.confidence >= JOINT_MIN_CNF else { continue }
        found = true
        minX = Swift.min(minX, Double(p.location.x)); maxX = Swift.max(maxX, Double(p.location.x))
        minY = Swift.min(minY, Double(p.location.y)); maxY = Swift.max(maxY, Double(p.location.y))
    }
    guard found else { return (.zero, false) }
    let bw = maxX - minX, bh = maxY - minY
    minX = max(0, minX - bw * 0.08); maxX = min(1, maxX + bw * 0.08)
    minY = max(0, minY - bh * 0.08); maxY = min(1, maxY + bh * 0.08)
    // Vision y 向上 → 位图 y 向下
    let px = CGRect(x: minX * Double(cg.width),
                    y: (1 - maxY) * Double(cg.height),
                    width: (maxX - minX) * Double(cg.width),
                    height: (maxY - minY) * Double(cg.height))
    return (px.integral, true)
}

// 灰度图（8-bit），人体框内填框外均值、框边羽化
func maskedGray(_ cg: CGImage, _ box: CGRect) -> (CGImage, Double, Double, Double) {
    let w = cg.width, h = cg.height
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return (cg, 0, 0, 0)
    }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let buf = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return (cg, 0, 0, 0) }
    let bx0 = max(0, Int(box.minX)), bx1 = min(w, Int(box.maxX))
    let by0 = max(0, Int(box.minY)), by1 = min(h, Int(box.maxY))
    // 框外灰度均值
    var sum: Double = 0, cnt: Double = 0
    for y in 0..<h {
        for x in 0..<w {
            if x >= bx0 && x < bx1 && y >= by0 && y < by1 { continue }
            let i = (y * w + x) * 4
            sum += Double(buf[i]) * 0.299 + Double(buf[i + 1]) * 0.587 + Double(buf[i + 2]) * 0.114
            cnt += 1
        }
    }
    let mean = cnt > 0 ? UInt8(max(0, min(255, sum / cnt))) : 128
    for y in by0..<by1 {
        for x in bx0..<bx1 {
            // 羽化权重：到框边归一化距离
            let dxEdge = Double(min(x - bx0, bx1 - 1 - x))
            let dyEdge = Double(min(y - by0, by1 - 1 - y))
            let d = min(dxEdge, dyEdge)
            let alpha = d < FEATHER ? d / FEATHER : 1.0  // 0=框边(保留原图),1=框心(全填均值)
            let i = (y * w + x) * 4
            let mix: (Int) -> UInt8 = { v in
                UInt8(max(0, min(255, Double(v) * (1 - alpha) + Double(mean) * alpha)))
            }
            buf[i] = mix(Int(buf[i])); buf[i + 1] = mix(Int(buf[i + 1])); buf[i + 2] = mix(Int(buf[i + 2]))
        }
    }
    let out = ctx.makeImage() ?? cg
    return (out, Double(bx1 - bx0) / Double(w), Double(by1 - by0) / Double(h), Double(mean) / 255)
}

var out: [String] = ["alias\tfi\tt\tcdx\tcdy\tmag\tregOK\tframeW\tframeH\tboxW\tboxH\tmean"]

for c in CLIPS {
    let jsonPath = "video/\((c.rel as NSString).deletingPathExtension).json"
    guard let data = FileManager.default.contents(atPath: jsonPath),
          let doc = try? JSONDecoder().decode(Doc.self, from: data),
          let frames = doc.frames else {
        print("[\(c.alias)] json fail"); continue
    }
    var times: [(fi: Int, t: Double)] = []
    for (i, f) in frames.enumerated() {
        guard f.bodyPose?.detected == true, let t = f.time,
              let cx = f.bodyPose?.ankleCenterX?.confidence,
              let cy = f.bodyPose?.ankleCenterY?.confidence,
              min(cx, cy) >= 0.30 else { continue }
        times.append((i, t))
    }
    guard times.count >= 4 else { print("[\(c.alias)] valid frames < 4"); continue }

    let asset = AVURLAsset(url: URL(fileURLWithPath: "video/\(c.rel)"))
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero

    var prevMasked: CGImage?
    var prevFi = -1, prevW = 0, prevH = 0
    var prevBox: (bw: Double, bh: Double, mean: Double) = (0, 0, 0)
    var okCount = 0, pairCount = 0, poseFail = 0

    for (fi, t) in times {
        let cm = CMTime(seconds: t, preferredTimescale: 600)
        var cg: CGImage?
        do { cg = try gen.copyCGImage(at: cm, actualTime: nil) } catch { cg = nil }
        guard let raw = cg else {
            out.append("\(c.alias)\t\(fi)\t\(String(format: "%.3f", t))\t0\t0\t0\t0\t0\t0\t0\t0\t0")
            prevMasked = nil; continue
        }
        let ds = downsampled(raw)
        let (box, boxOK) = poseBox(ds)
        guard boxOK else {
            poseFail += 1; prevMasked = nil; continue
        }
        let (masked, bw, bh, mean) = maskedGray(ds, box)
        if let p = prevMasked {
            pairCount += 1
            let req = VNTranslationalImageRegistrationRequest(targetedCGImage: masked)
            let handler = VNImageRequestHandler(cgImage: p, options: [:])
            var cdx = 0.0, cdy = 0.0, mag = 0.0, ok = 0
            do {
                try handler.perform([req])
                if let obs = req.results?.first {
                    let tr = obs.alignmentTransform
                    cdx = tr.tx / Double(prevW); cdy = tr.ty / Double(prevH)
                    mag = hypot(cdx, cdy)
                    if mag <= MAX_JUMP { ok = 1; okCount += 1 }
                }
            } catch { }
            out.append("\(c.alias)\t\(prevFi)\t\(String(format: "%.3f", t))\t" +
                       "\(String(format: "%.5f", cdx))\t\(String(format: "%.5f", cdy))\t" +
                       "\(String(format: "%.5f", mag))\t\(ok)\t\(prevW)\t\(prevH)\t" +
                       "\(String(format: "%.3f", prevBox.bw))\t\(String(format: "%.3f", prevBox.bh))\t" +
                       "\(String(format: "%.3f", prevBox.mean))")
        }
        prevMasked = masked; prevFi = fi; prevW = ds.width; prevH = ds.height
        prevBox = (bw, bh, mean)
    }
    print("[\(c.alias)] valid=\(times.count) pairs=\(pairCount) regOK=\(okCount) " +
          "(\(pairCount > 0 ? String(format: "%.0f%%", 100 * Double(okCount) / Double(pairCount)) : "-")) poseFail=\(poseFail)")
}

try? out.joined(separator: "\n").write(toFile: OUT_TSV, atomically: true, encoding: .utf8)
print("wrote \(OUT_TSV) lines=\(out.count - 1)")
