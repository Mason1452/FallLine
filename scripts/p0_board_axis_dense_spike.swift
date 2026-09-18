// p0_board_axis_dense_spike.swift
// Phase 0 候选 A 加密抽样版（Gate-G0 严格量化用）：
// 与 p0_board_axis_spike.swift 同算法（foreground mask + 踝下 ROI PCA + 门控），
// 区别：每片 10 个均匀时间点（0.08–0.92），帧直接由 AVAssetImageGenerator 精确抽取，
// 不依赖 /tmp 抽帧；接触表每片一行 10 列，供逐帧人工 GT（板物理可见性 + 板轴角度）。
//
// 输出：outputs/edge_spike/p0_board_axis_dense.tsv
//       outputs/edge_spike/p0_axis_dense_<group>.jpg
// 运行：swift scripts/p0_board_axis_dense_spike.swift

import AppKit
import Foundation
import Vision
import CoreImage
import AVFoundation

let OUT_TSV = "outputs/edge_spike/p0_board_axis_dense.tsv"
let OUT_DIR = "outputs/edge_spike"
let NTAPS = 10

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
    var angleDeg: Double
    var elong: Double
    var axisLen: Double
    var cxNorm: Double; var cyNorm: Double
    var verdict: String
}

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

let G_MIN_SUBJ = 0.02
let G_MIN_CNF = 0.30
let G_MAX_ANG = 45.0
let G_MIN_LEN = 0.10
let G_MAX_LEN = 0.55
let G_MIN_ELONG = 2.0

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
    var data = [UInt8](repeating:0, count: w * h * 4)
    guard let ctx = CGContext(data: &data, width: w, height: h,
                              bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(masked, in: CGRect(x: 0, y: 0, width: w, height: h))
    return data
}

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

// 缓存抽取的帧供接触表复用
var frameCache: [String: [(tap: Int, cg: CGImage)]] = [:]

func makeSheet(clips: [(group: String, alias: String, rel: String)],
               rowsByAlias: [String: [Row]], outName: String) {
    let tw = 200, th = 356, pad = 6, labelH = 52
    let cols = NTAPS
    let W = cols * (tw + pad) + pad
    let H = clips.count * (th + labelH + pad) + pad
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
    ctx.setFillColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let font = NSFont(name: "Menlo", size: 8) ?? NSFont.systemFont(ofSize: 8)
    let para = NSMutableParagraphStyle(); para.alignment = .left
    for (i, c) in clips.enumerated() {
        for (tap, cg) in (frameCache[c.alias] ?? []) {
            let colX = pad + tap * (tw + pad)
            let cellTop = H - pad - i * (th + labelH + pad)
            let imgY = cellTop - th
            ctx.draw(cg, in: CGRect(x: colX, y: imgY, width: tw, height: th))
            if let r = rowsByAlias[c.alias]?[tap] {
                let rx = CGFloat((r.ankX - 0.24)) * CGFloat(tw)
                let rw = CGFloat(0.48) * CGFloat(tw)
                let ryBottom = CGFloat(r.ankY - 0.16) * CGFloat(th)
                let rh = CGFloat(0.15) * CGFloat(th)
                ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.95))
                ctx.setLineWidth(1.2)
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
                                       : CGColor(red: 1, green: 0.15, blue: 0.2, alpha:0.6))
                    ctx.setLineWidth(2.5)
                    ctx.move(to: CGPoint(x: CGFloat(colX) + cxA - dx, y: CGFloat(imgY) + cyA - dy))
                    ctx.addLine(to: CGPoint(x: CGFloat(colX) + cxA + dx, y: CGFloat(imgY) + cyA + dy))
                    ctx.strokePath()
                }
                let txt = "\(c.alias)#\(tap) [\(r.verdict)]\n" +
                    "cnf=\(String(format: "%.2f", r.ankCnf)) subj=\(String(format: "%.3f", r.subjFrac))\n" +
                    "ang=\(r.angleDeg >= 0 ? String(format: "%.0f", r.angleDeg) : "NA") " +
                    "e=\(String(format: "%.1f", r.elong)) L=\(String(format: "%.2f", r.axisLen))"
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
            .representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return }
    try? rep.write(to: URL(fileURLWithPath: "\(OUT_DIR)/\(outName)"))
    print("wrote \(OUT_DIR)/\(outName)")
}

var rows: [Row] = []
var byAlias: [String: [Row]] = [:]
for c in CLIPS {
    let vidURL = URL(fileURLWithPath: "video/\(c.rel)")
    let asset = AVURLAsset(url: vidURL)
    let dur = CMTimeGetSeconds(asset.duration)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero
    byAlias[c.alias] = []
    frameCache[c.alias] = []
    for tap in 0..<NTAPS {
        let frac = 0.08 + 0.84 * Double(tap) / Double(NTAPS - 1)
        let tSec = dur * frac
        var row = Row(alias: c.alias, tap: tap, group: c.group, tSec: tSec,
                      ankX: 0.5, ankY: 0.5, ankCnf: 0, subjFrac: 0, npix: 0,
                      angleDeg: -1, elong: 0, axisLen: 0, cxNorm: 0, cyNorm: 0,
                      verdict: "farShot")
        var cg: CGImage?
        do { cg = try gen.copyCGImage(at: CMTime(seconds: tSec, preferredTimescale: 600), actualTime: nil) } catch { cg = nil }
        guard let frame = cg else {
            row.verdict = "noFrame"
            rows.append(row); byAlias[c.alias]?.append(row); continue
        }
        frameCache[c.alias]?.append((tap, frame))
        let W = frame.width, H = frame.height
        if let a = ankleOnFrame(frame) {
            row.ankX = a.x; row.ankY = a.y; row.ankCnf = a.cnf
        }
        guard let bitmap = subjectBitmap(frame) else {
            row.verdict = "noMask"; rows.append(row); byAlias[c.alias]?.append(row); continue
        }
        var subj = 0
        for i in 0..<(W * H) where bitmap[i * 4 + 3] > 127 { subj += 1 }
        row.subjFrac = Double(subj) / Double(W * H)
        let p = analyze(data: bitmap, w: W, h: H, ankX: row.ankX, ankY: row.ankY)
        row.npix = p.npix; row.angleDeg = p.angle; row.elong = p.elong
        row.axisLen = p.halfLenNorm; row.cxNorm = p.cx; row.cyNorm = p.cy
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
    let nBoard = byAlias[c.alias]?.filter { $0.verdict == "board" }.count ?? 0
    print("[\(c.alias)] board=\(nBoard)/\(NTAPS)")
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
          outName: "p0_axis_dense_beginner.jpg")
makeSheet(clips: CLIPS.filter { $0.group == "emerging" }, rowsByAlias: byAlias,
          outName: "p0_axis_dense_emerging.jpg")
