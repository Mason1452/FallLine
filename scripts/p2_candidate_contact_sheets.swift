// p2_candidate_contact_sheets.swift
// Phase 2 起步 1：为 19 片未标注候选池生成板轴接触表 JPG，供教练一站式判档。
//
// 与 Phase 0 p0_board_axis_dense_spike.swift 的差异：
//   1. 目标不同：P0 生成全 corpus 单张宽拼图供人工 GT；P2 每片一张 5×2 拼图（10 均匀帧），
//      供教练看到板轴/踝下 ROI 后回填「档位 + 稳定刻滑? + 弯形备注」到 §4.4。
//   2. 门控口径与生产 BoardEdgeDetector 一致：G_MIN_LEN=0.07（Gate-G0 校准值），
//      而非 P0 早期先验 0.10。
//   3. 未做实例归属 / 站姿状态校验（保留 Phase 1 生产观测器语义即可，接触表主要目的
//      是让教练看清雪板位置和运动阶段；生产开关 --board-edge 才做严格门控）。
//   4. 产物写 outputs/board_edge_p2/contact_sheets/<alias>.jpg（.gitignore 已排除）。
//
// 运行：swift scripts/p2_candidate_contact_sheets.swift
//     可选：swift scripts/p2_candidate_contact_sheets.swift ONLY=<alias>,<alias>...
//           只处理指定别名，加快先行验证。

import AppKit
import Foundation
import Vision
import CoreImage
import AVFoundation

let NTAPS = 10
let OUT_DIR = "outputs/board_edge_p2/contact_sheets"

// 与 spec §12.1 一致：19 片候选池（good 8 / middle 10 / bad 1）。
// hint 为「弱先验档位提示」，仅用于图内文字提醒教练；判档以人眼为准。
let CLIPS: [(alias: String, rel: String, hint: String, score: Int)] = [
    ("CAND_G01", "good/0946ed384e732c357a3d55fac77426c0.MP4", "中偏上/高质量", 73),
    ("CAND_G02", "good/3134552bed78447b9f7ba8e2003ce678.MP4", "中偏上", 72),
    ("CAND_G03", "good/3e6f37fe76521781506c19c02c1b97ed.MP4", "高质量", 83),
    ("CAND_G04", "good/5382da0c825e30518ab376505cbcfaf2.MOV", "中偏上", 72),
    ("CAND_G05", "good/641efed02be271b6d9f014c97d1f8ae0.MOV", "中偏上", 77),
    ("CAND_G06", "good/9ed0bb6c707fc47fce153cee3dcd365e.MP4", "中偏上", 75),
    ("CAND_G07", "good/v0200fg10000d7r0017og65qoh1vgeg0.MP4", "专业(GOOD_A)", 89),
    ("CAND_G08", "good/v2800fgi0000d6m0mk7og65qamcvgf80.MP4", "中偏上", 78),
    ("CAND_M01", "middle/1c5771fc7dd1ea546eb5bc3e4e01bc48.MP4", "中级", 67),
    ("CAND_M02", "middle/4a7dfe960f07ac14b06bbd8de3d38aa4.MP4", "中偏上", 73),
    ("CAND_M03", "middle/96001e37e76be9ef6cf7a65e73efcac4.MP4", "专业", 85),
    ("CAND_M04", "middle/992f063b79d27b96b471e44a48d8465e.MP4", "初级", 55),
    ("CAND_M05", "middle/a7791a475a244c938dd0815e89b1dec5.MP4", "中偏上", 74),
    ("CAND_M06", "middle/ccfd9967aa6d3ab5abd04fb8991872c7.MOV", "中级", 68),
    ("CAND_M07", "middle/v0200fg10000d2tcts7og65t6h63ua2g.MP4", "初级", 58),
    ("CAND_M08", "middle/v0200fg10000d6a4i57og65mkjkcdpu0.MP4", "中偏上", 76),
    ("CAND_M09", "middle/v0300fg10000d4oq6avog65ihr8qf550.MP4", "中级", 60),
    ("CAND_M10", "middle/v2800fgi0000d5ehg1vog65tinkepgl0.MP4", "中偏上", 77),
    ("CAND_B01", "bad/0b7522e9db823b910ac67727aea726da.MP4", "初级/中级", 70),
]

// 生产 BoardEdgeConfig.standard（Gate-G0 校准值）
let G_MIN_SUBJ = 0.02
let G_MIN_CNF = 0.30
let G_MAX_ANG = 45.0
let G_MIN_LEN = 0.07
let G_MAX_LEN = 0.55
let G_MIN_ELONG = 2.0

struct Row {
    var tap: Int; var tSec: Double
    var ankX: Double; var ankY: Double; var ankCnf: Double
    var subjFrac: Double
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

func classify(row: Row) -> String {
    if row.ankCnf < G_MIN_CNF { return "ankleLowCnf" }
    if row.subjFrac < G_MIN_SUBJ { return "farShot" }
    if row.angleDeg < 0 { return "noAxis" }
    if row.angleDeg > G_MAX_ANG { return "rejectVertical" }
    if row.axisLen < G_MIN_LEN || row.axisLen > G_MAX_LEN { return "rejectLength" }
    if row.elong < G_MIN_ELONG { return "rejectBlob" }
    return "board"
}

func buildSheet(alias: String, hint: String, hintScore: Int,
                frames: [(tap: Int, cg: CGImage)], rows: [Row]) -> URL? {
    let cols = 5, rowsN = 2
    let tw = 300, th = 533, pad = 8, labelH = 66
    let headerH = 60
    let W = cols * (tw + pad) + pad
    let H = rowsN * (th + labelH + pad) + pad + headerH
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    ctx.setFillColor(red: 0.086, green: 0.094, blue: 0.11, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // 顶部标题
    let font = NSFont(name: "Menlo", size: 12) ?? NSFont.systemFont(ofSize: 12)
    let fontBig = NSFont(name: "Menlo-Bold", size: 18) ?? NSFont.boldSystemFont(ofSize: 18)
    let boardCount = rows.filter { $0.verdict == "board" }.count
    let farCount = rows.filter { $0.verdict == "farShot" }.count
    let lowCount = rows.filter { $0.verdict == "ankleLowCnf" }.count
    let title = "\(alias)  hint=\(hint) (score=\(hintScore))   板轴 board=\(boardCount)/10   farShot=\(farCount)   ankleLowCnf=\(lowCount)"
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSAttributedString(string: title, attributes: [
        .font: fontBig,
        .foregroundColor: NSColor(red: 0.95, green: 0.98, blue: 1, alpha: 1)
    ]).draw(in: CGRect(x: pad, y: H - headerH + 22, width: W - 2 * pad, height: headerH - 22))
    NSGraphicsContext.restoreGraphicsState()

    for r in rows {
        let tap = r.tap
        let col = tap % cols, gridRow = tap / cols
        let x0 = pad + col * (tw + pad)
        let y0 = H - headerH - pad - (gridRow + 1) * (th + labelH + pad) + labelH
        if let f = frames.first(where: { $0.tap == tap }) {
            ctx.draw(f.cg, in: CGRect(x: x0, y: y0, width: tw, height: th))
        }
        // ROI 黄框（生产口径：踝下 x ±0.24，y 从 anky-0.16 到 anky-0.01）
        let rx = CGFloat(r.ankX - 0.24) * CGFloat(tw)
        let rw = CGFloat(0.48) * CGFloat(tw)
        let ryBottom = CGFloat(r.ankY - 0.16) * CGFloat(th)
        let rh = CGFloat(0.15) * CGFloat(th)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.9))
        ctx.setLineWidth(1.5)
        ctx.stroke(CGRect(x: CGFloat(x0) + rx, y: CGFloat(y0) + ryBottom,
                          width: rw, height: rh))
        // 板轴（board=绿，rejected=红）
        if r.angleDeg >= 0 {
            let rad = CGFloat(r.angleDeg * .pi / 180)
            let cxA = CGFloat(r.cxNorm) * CGFloat(tw)
            let cyA = CGFloat(r.cyNorm) * CGFloat(th)
            let half = min(CGFloat(r.axisLen) * CGFloat(tw) / 2, CGFloat(tw) * 0.32)
            let dx = cos(rad) * half, dy = sin(rad) * half
            let ok = r.verdict == "board"
            ctx.setStrokeColor(ok
                               ? CGColor(red: 0.2, green: 0.9, blue: 0.35, alpha: 0.95)
                               : CGColor(red: 1, green: 0.15, blue: 0.2, alpha: 0.6))
            ctx.setLineWidth(3.0)
            ctx.move(to: CGPoint(x: CGFloat(x0) + cxA - dx, y: CGFloat(y0) + cyA - dy))
            ctx.addLine(to: CGPoint(x: CGFloat(x0) + cxA + dx, y: CGFloat(y0) + cyA + dy))
            ctx.strokePath()
        }
        // 标签
        let statusColor: NSColor
        switch r.verdict {
        case "board": statusColor = NSColor(red: 0.35, green: 0.95, blue: 0.5, alpha: 1)
        case "farShot", "ankleLowCnf", "noMask", "noFrame":
            statusColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
        default: statusColor = NSColor(red: 1, green: 0.55, blue: 0.35, alpha: 1)
        }
        let txt = "#\(tap) t=\(String(format:"%.1f",r.tSec))s  [\(r.verdict)]\n" +
            "cnf=\(String(format: "%.2f", r.ankCnf))  subj=\(String(format: "%.3f", r.subjFrac))\n" +
            "ang=\(r.angleDeg >= 0 ? String(format: "%.0f°", r.angleDeg) : "  NA") " +
            "  e=\(String(format: "%.1f", r.elong))  L=\(String(format: "%.2f", r.axisLen))"
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSAttributedString(string: txt, attributes: [
            .font: font, .foregroundColor: statusColor
        ]).draw(in: CGRect(x: x0 + 4, y: y0 - labelH + 4, width: tw, height: labelH))
        NSGraphicsContext.restoreGraphicsState()
    }
    guard let out = ctx.makeImage(),
          let rep = NSBitmapImageRep(cgImage: out)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
    let url = URL(fileURLWithPath: "\(OUT_DIR)/\(alias).jpg")
    try? rep.write(to: url)
    return url
}

// -- 主流程 --
let onlyArg = CommandLine.arguments.first(where: { $0.hasPrefix("ONLY=") })
let only: Set<String>? = onlyArg.map { Set($0.dropFirst("ONLY=".count).split(separator: ",").map(String.init)) }
try? FileManager.default.createDirectory(atPath: OUT_DIR, withIntermediateDirectories: true)

for c in CLIPS {
    if let filter = only, !filter.contains(c.alias) { continue }
    let vidURL = URL(fileURLWithPath: "video/\(c.rel)")
    guard FileManager.default.fileExists(atPath: vidURL.path) else {
        print("[\(c.alias)] MISS \(c.rel)"); continue
    }
    let asset = AVURLAsset(url: vidURL)
    let dur = CMTimeGetSeconds(asset.duration)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero
    var frames: [(tap: Int, cg: CGImage)] = []
    var rows: [Row] = []
    for tap in 0..<NTAPS {
        let frac = 0.08 + 0.84 * Double(tap) / Double(NTAPS - 1)
        let tSec = dur * frac
        var row = Row(tap: tap, tSec: tSec, ankX: 0.5, ankY: 0.5, ankCnf: 0,
                      subjFrac: 0, angleDeg: -1, elong: 0, axisLen: 0,
                      cxNorm: 0, cyNorm: 0, verdict: "noFrame")
        let cg: CGImage?
        do { cg = try gen.copyCGImage(at: CMTime(seconds: tSec, preferredTimescale: 600), actualTime: nil) } catch { cg = nil }
        guard let frame = cg else { rows.append(row); continue }
        frames.append((tap, frame))
        let W = frame.width, H = frame.height
        if let a = ankleOnFrame(frame) {
            row.ankX = a.x; row.ankY = a.y; row.ankCnf = a.cnf
        }
        guard let bitmap = subjectBitmap(frame) else {
            row.verdict = "noMask"; rows.append(row); continue
        }
        var subj = 0
        for i in 0..<(W * H) where bitmap[i * 4 + 3] > 127 { subj += 1 }
        row.subjFrac = Double(subj) / Double(W * H)
        let p = analyze(data: bitmap, w: W, h: H, ankX: row.ankX, ankY: row.ankY)
        row.angleDeg = p.angle; row.elong = p.elong
        row.axisLen = p.halfLenNorm; row.cxNorm = p.cx; row.cyNorm = p.cy
        row.verdict = classify(row: row)
        rows.append(row)
    }
    let nBoard = rows.filter { $0.verdict == "board" }.count
    if let url = buildSheet(alias: c.alias, hint: c.hint, hintScore: c.score,
                            frames: frames, rows: rows) {
        print("[\(c.alias)] board=\(nBoard)/10  → \(url.path)")
    } else {
        print("[\(c.alias)] board=\(nBoard)/10  ! sheet build failed")
    }
}
