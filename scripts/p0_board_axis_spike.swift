// p0_board_axis_spike.swift
// Phase 0 候选 A：foreground mask + 踝下 ROI 几何 → 板轴拟合（离线原型）。
//
// 流程：
//   1. VNGenerateForegroundInstanceMaskRequest 取主体（近景 spike 已证板作为身体延伸被包含，
//      且单实例天然只含滑者本人，规避他人/红网/阴影等 near-board false positive）；
//   2. 从该视频帧级 JSON 取 tap 时刻最近邻帧的踝中心（Vision 归一化，左下原点 y 向上）；
//   3. 踝下 ROI（y: ankleY-0.20 … ankleY-0.01；x: ±0.30）内对主体像素 PCA：
//      主轴角=板轴候选（unsigned 0–90，0=横板），elong=√(λ1/λ2)，halfLen=主轴等效半长；
//   4. 近景门控量 subjFrac=主体面积/全帧、ankleCnf 来自 JSON。
// 输出：outputs/edge_spike/p0_board_axis.tsv
//       outputs/edge_spike/p0_axis_sheet_<group>.jpg（正立，黄=踝下 ROI，红=PCA 主轴）
//
// 运行：swift scripts/p0_board_axis_spike.swift
// 依赖：/tmp/edge_spike/frames/<alias>_t<0...3>.jpg 与 video/**/<rel>.json

import AppKit
import Foundation
import Vision
import CoreImage
import AVFoundation

let FRAME_DIR = "/tmp/edge_spike/frames"
let OUT_TSV = "outputs/edge_spike/p0_board_axis.tsv"
let OUT_DIR = "outputs/edge_spike"
let TAPS = [0.2, 0.4, 0.6, 0.8]

let CLIPS: [(group: String, alias: String, rel: String)] = [
    ("beginner", "BND2_LB", "bad/v0300fg10000cusoptnog65pkehng280.MP4"),
    ("beginner", "BND2_L6", "bad/v0200fg10000d6olrffog65vrste5qqg.MOV"),
    ("beginner", "BND2_L5", "bad/v0300fg10000d664l37og65t6pnbois0.MOV"),
    ("beginner", "BND2_L4", "bad/v1e00fgi0000cv786ffog65rtmm48gmg.MOV"),
    ("beginner", "BND2_L3", "bad/v2800fgi0000d4v24r7og65oi0fmka5g.MP4"),
    ("beginner", "BND2_L2", "bad/v0d00fg10000ctm0ufvog65rqb97g2p0.MP4"),
    ("beginner", "BND2_L1", "bad/v0d00fg10000csgr6inog65n8mlpg2m0.MP4"),
    ("emerging", "BND_L1", "middle/v1e00fgi0000d5bksdfog65irrhr4bog.MP4"),
    ("emerging", "BND_L2", "middle/v0300fg10000d5h313fog65nermuqklg.MP4"),
    ("emerging", "BND_L3", "middle/v2800fgi0000d54jhefog65lbfdhma2g.MP4"),
    ("emerging", "BND2_LM", "bad/v0200fg10000d7nnh5vog65i52ermgog.MP4"),
]

struct Row {
    var alias: String; var tap: Int; var group: String
    var tSec: Double
    var ankX: Double; var ankY: Double; var ankCnf: Double
    var subjFrac: Double
    var npix: Int
    var angleDeg: Double      // unsigned 主轴角 [0,90]，-1=NA
    var elong: Double
    var axisLen: Double        // 主轴等效全长 / 图宽
    var cxNorm: Double; var cyNorm: Double
    var verdict: String
}

// MARK: - 同帧 Vision bodyPose 踝点（避免 tap 抽帧与 5fps 分析帧错位）
func ankleOnFrame(_ cg: CGImage) -> (x: Double, y: Double, cnf: Double)? {
    let req = VNDetectHumanBodyPoseRequest()
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    do { try handler.perform([req]) } catch { return nil }
    guard let obs = req.results?.max(by: { ($0.confidence) < ($1.confidence) }) else { return nil }
    var pts: [(CGPoint, Double)] = []
    for name in [VNHumanBodyPoseObservation.JointName.leftAnkle, .rightAnkle] {
        if let p = try? obs.recognizedPoint(name), p.confidence > 0.2 {
            pts.append((p.location, Double(p.confidence)))
        }
    }
    guard !pts.isEmpty else { return nil }
    let x = pts.map { $0.0.x }.reduce(0, +) / Double(pts.count)
    let y = pts.map { $0.0.y }.reduce(0, +) / Double(pts.count)
    let c = pts.map { $0.1 }.reduce(0, +) / Double(pts.count)
    return (Double(x), Double(y), c)
}

// MARK: - 门控阈值（Phase 0 原型先验，待 GT 校准）
let G_MIN_SUBJ = 0.02      // 主体占比：低于此判远景/分割不可用
let G_MIN_CNF = 0.30       // 踝点置信
let G_MAX_ANG = 45.0       // 板轴须近水平（站姿垂直板轴）
let G_MIN_LEN = 0.10       // 主轴等效全长 / 图宽
let G_MAX_LEN = 0.55
let G_MIN_ELONG = 2.0

// MARK: - foreground mask → 自管 RGBA bitmap（原点左下，与 Vision 归一化一致）
func subjectBitmap(_ cg: CGImage) -> [UInt8]? {
    let req = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    do { try handler.perform([req]) } catch { return nil }
    guard let obs = req.results?.first,
          let pb = try? obs.generateMaskedImage(ofInstances: obs.allInstances,
                                                 from: handler,
                                                 croppedToInstancesExtent: false) else { return nil }
    let w = cg.width, h = cg.height
    let ci = CIImage(cvPixelBuffer: pb).oriented(.downMirrored)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let masked = CIContext().createCGImage(ci, from: CGRect(x: 0, y: 0, width: w, height: h)) else { return nil }
    var data = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &data, width: w, height: h,
                              bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(masked, in: CGRect(x: 0, y: 0, width: w, height: h))
    return data
}

// MARK: - 踝下 ROI PCA
func analyze(data: [UInt8], w: Int, h: Int, ankX: Double, ankY: Double)
-> (npix: Int, angle: Double, elong: Double, halfLenNorm: Double, cx: Double, cy: Double) {
    let x0 = max(0, Int((ankX - 0.24) * Double(w)))
    let x1 = min(w, Int((ankX + 0.24) * Double(w)))
    let y0 = max(0, Int((ankY - 0.16) * Double(h)))
    let y1 = min(h, Int((ankY - 0.01) * Double(h)))
    var sx = 0.0, sy = 0.0, n = 0.0
    guard y1 > y0, x1 > x0 else { return (0, -1, 0, 0, 0, 0) }
    for y in y0..<y1 {
        let row = y * w
        for x in x0..<x1 where data[(row + x) * 4 + 3] > 127 {
            sx += Double(x); sy += Double(y); n += 1
        }
    }
    if n < 30 { return (Int(n), -1, 0, 0, 0, 0) }
    let mx = sx / n, my = sy / n
    var cxx = 0.0, cyy = 0.0, cxy = 0.0
    for y in y0..<y1 {
        let row = y * w
        for x in x0..<x1 where data[(row + x) * 4 + 3] > 127 {
            let dx = Double(x) - mx, dy = Double(y) - my
            cxx += dx * dx; cyy += dy * dy; cxy += dx * dy
        }
    }
    cxx /= n; cyy /= n; cxy /= n
    let tr = cxx + cyy
    let disc = sqrt(max(0, tr * tr / 4 - (cxx * cyy - cxy * cxy)))
    let l1 = tr / 2 + disc, l2 = max(tr / 2 - disc, 1e-9)
    let ang = atan2(2 * cxy, cxx - cyy) / 2
    var deg = abs(ang * 180 / .pi)
    if deg > 90 { deg = 180 - deg }
    return (Int(n), deg, sqrt(l1 / l2), 2 * sqrt(l1) / Double(w), mx / Double(w), my / Double(h))
}

// MARK: - 诊断接触表（正立绘制）
func makeSheet(clips: [(group: String, alias: String, rel: String)],
               rowsByAlias: [String: [Row]], outName: String) {
    let tw = 280, th = 498, pad = 8, labelH = 58
    let cols = 4
    let W = cols * (tw + pad) + pad
    let H = clips.count * (th + labelH + pad) + pad
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
    ctx.setFillColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let font = NSFont(name: "Menlo", size: 10) ?? NSFont.systemFont(ofSize: 10)
    let para = NSMutableParagraphStyle(); para.alignment = .left
    for (i, c) in clips.enumerated() {
        for tap in 0..<4 {
            guard let img = NSImage(contentsOfFile: "\(FRAME_DIR)/\(c.alias)_t\(tap).jpg"),
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff), let cg = rep.cgImage else { continue }
            let colX = pad + tap * (tw + pad)
            let cellTop = H - pad - i * (th + labelH + pad)
            let imgY = cellTop - th
            ctx.draw(cg, in: CGRect(x: colX, y: imgY, width: tw, height: th))

            if let r = rowsByAlias[c.alias]?[tap] {
                // ROI（踝下）：归一化 y 向上，转 cell 坐标
                let rx = CGFloat((r.ankX - 0.24)) * CGFloat(tw)
                let rw = CGFloat(0.48) * CGFloat(tw)
                let ryBottom = CGFloat(r.ankY - 0.16) * CGFloat(th)
                let rh = CGFloat(0.15) * CGFloat(th)
                ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.95))
                ctx.setLineWidth(1.5)
                ctx.stroke(CGRect(x: colX + Int(rx), y: imgY + Int(ryBottom),
                                  width: Int(rw), height: Int(rh)))
                if r.angleDeg >= 0 {
                    let rad = CGFloat(r.angleDeg * .pi / 180)
                    let cxA = CGFloat(r.cxNorm) * CGFloat(tw)
                    let cyA = CGFloat(r.cyNorm) * CGFloat(th)
                    let half = min(CGFloat(r.axisLen) * CGFloat(tw) / 2, CGFloat(tw) * 0.3)
                    let dx = cos(rad) * half, dy = sin(rad) * half
                    let ok = r.verdict == "board"
                    ctx.setStrokeColor(ok
                                       ? CGColor(red: 0.2, green: 0.9, blue: 0.35, alpha: 0.95)
                                       : CGColor(red: 1, green: 0.15, blue: 0.2, alpha: 0.6))
                    ctx.setLineWidth(3)
                    let p0 = CGPoint(x: CGFloat(colX) + cxA - dx, y: CGFloat(imgY) + cyA - dy)
                    let p1 = CGPoint(x: CGFloat(colX) + cxA + dx, y: CGFloat(imgY) + cyA + dy)
                    ctx.move(to: p0)
                    ctx.addLine(to: p1)
                    ctx.strokePath()
                }
                let txt = "\(c.alias) t\(tap) [\(r.verdict)] cnf=\(String(format: "%.2f", r.ankCnf))\n" +
                    "subj=\(String(format: "%.3f", r.subjFrac)) n=\(r.npix)\n" +
                    "ang=\(r.angleDeg >= 0 ? String(format: "%.0f", r.angleDeg) : "NA") " +
                    "e=\(String(format: "%.2f", r.elong)) L=\(String(format: "%.2f", r.axisLen))"
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSAttributedString(string: txt, attributes: [
                    .font: font, .foregroundColor: NSColor(red: 0.92, green: 0.97, blue: 1, alpha: 1),
                    .paragraphStyle: para
                ]).draw(in: CGRect(x: colX + 2, y: cellTop - labelH + 2, width: tw + pad, height: labelH))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
    guard let out = ctx.makeImage(),
          let rep = NSBitmapImageRep(cgImage: out)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return }
    let url = URL(fileURLWithPath: "\(OUT_DIR)/\(outName)")
    try? rep.write(to: url)
    print("wrote \(url.path)")
}

// MARK: - main
var rows: [Row] = []
var byAlias: [String: [Row]] = [:]
for c in CLIPS {
    let vidURL = URL(fileURLWithPath: "video/\(c.rel)")
    let dur = CMTimeGetSeconds(AVURLAsset(url: vidURL).duration)
    byAlias[c.alias] = []
    guard let img0 = NSImage(contentsOfFile: "\(FRAME_DIR)/\(c.alias)_t0.jpg"),
          let tiff0 = img0.tiffRepresentation, let rep0 = NSBitmapImageRep(data: tiff0),
          let cg0 = rep0.cgImage else { continue }
    let W = cg0.width, H = cg0.height
    for (tap, frac) in TAPS.enumerated() {
        let tSec = dur * frac
        let path = "\(FRAME_DIR)/\(c.alias)_t\(tap).jpg"
        var row = Row(alias: c.alias, tap: tap, group: c.group, tSec: tSec,
                      ankX: 0.5, ankY: 0.5, ankCnf: 0, subjFrac: 0, npix: 0,
                      angleDeg: -1, elong: 0, axisLen: 0, cxNorm: 0, cyNorm: 0,
                      verdict: "farShot")
        guard let img = NSImage(contentsOfFile: path),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let cg = rep.cgImage else {
            row.verdict = "noFrame"
            rows.append(row); byAlias[c.alias]?.append(row); continue
        }
        if let a = ankleOnFrame(cg) {
            row.ankX = a.x; row.ankY = a.y; row.ankCnf = a.cnf
        }
        guard let bitmap = subjectBitmap(cg) else {
            row.verdict = "noMask"; rows.append(row); byAlias[c.alias]?.append(row); continue
        }
        var subj = 0
        for i in 0..<(W * H) where bitmap[i * 4 + 3] > 127 { subj += 1 }
        row.subjFrac = Double(subj) / Double(W * H)
        let p = analyze(data: bitmap, w: W, h: H, ankX: row.ankX, ankY: row.ankY)
        row.npix = p.npix; row.angleDeg = p.angle; row.elong = p.elong
        row.axisLen = p.halfLenNorm; row.cxNorm = p.cx; row.cyNorm = p.cy

        // 门控：近景主体 + 踝点置信 + 近水平长轴
        if row.ankCnf < G_MIN_CNF {
            row.verdict = "ankleLowCnf"
        } else if row.subjFrac < G_MIN_SUBJ {
            row.verdict = "farShot"
        } else if p.angle < 0 {
            row.verdict = "noAxis"
        } else if p.angle > G_MAX_ANG {
            row.verdict = "rejectVertical"
        } else if p.halfLenNorm < G_MIN_LEN || p.halfLenNorm > G_MAX_LEN {
            row.verdict = "rejectLength"
        } else if p.elong < G_MIN_ELONG {
            row.verdict = "rejectBlob"
        } else {
            row.verdict = "board"
        }
        rows.append(row); byAlias[c.alias]?.append(row)
    }
}

let header = "alias\ttap\tgroup\ttSec\tankCnf\tsubjFrac\tankX\tankY\tnpix\tangleDeg\telong\taxisLen\tverdict"
let lines = rows.map { r in
    [r.alias, "\(r.tap)", r.group, String(format: "%.2f", r.tSec),
     String(format: "%.2f", r.ankCnf), String(format: "%.4f", r.subjFrac),
     String(format: "%.3f", r.ankX), String(format: "%.3f", r.ankY),
     "\(r.npix)", String(format: "%.1f", r.angleDeg),
     String(format: "%.2f", r.elong), String(format: "%.3f", r.axisLen),
     r.verdict].joined(separator: "\t")
}
try? ([header] + lines).joined(separator: "\n").write(toFile: OUT_TSV, atomically: true, encoding: .utf8)
print("wrote \(OUT_TSV) rows=\(rows.count)")
makeSheet(clips: CLIPS.filter { $0.group == "beginner" }, rowsByAlias: byAlias,
          outName: "p0_axis_sheet_beginner.jpg")
makeSheet(clips: CLIPS.filter { $0.group == "emerging" }, rowsByAlias: byAlias,
          outName: "p0_axis_sheet_emerging.jpg")
