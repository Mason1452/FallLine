// edge_spike_foreground_mask.swift
// 刃线检测立项 spike：VNGenerateForegroundInstanceMaskRequest（macOS 14+）
// 验证前景主体 mask 是否把雪板作为人体延伸一并分割出来。
// 输出 原图 | 去背景主体（灰底） 并排 JPG 到 outputs/edge_spike/mask_<alias>.jpg。
//
// 运行：swift scripts/edge_spike_foreground_mask.swift <frame.jpg> <alias>
// 或无参数跑内置代表帧。

import AppKit
import Foundation
import Vision
import CoreImage

func render(_ path: String, _ alias: String) throws {
    let url = URL(fileURLWithPath: path)
    guard let nsImage = NSImage(contentsOf: url),
          let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let cgImage = bitmap.cgImage else {
        print("[\(alias)] load fail"); return
    }

    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([request])

    guard let obs = request.results?.first else {
        print("[\(alias)] no foreground observation"); return
    }

    let pixelBuffer = try obs.generateMaskedImage(
        ofInstances: obs.allInstances,
        from: handler,
        croppedToInstancesExtent: false
    )
    let ci = CIImage(cvPixelBuffer: pixelBuffer).oriented(.downMirrored)
    let ctx = CIContext()
    guard let maskedCG = ctx.createCGImage(ci, from: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)) else {
        print("[\(alias)] mask render fail"); return
    }

    let w = cgImage.width, h = cgImage.height
    let gap = 8
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w * 2 + gap, height: h,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        print("[\(alias)] context fail"); return
    }
    ctx.setFillColor(gray: 0.55, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w * 2 + gap, height: h))
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(maskedCG, in: CGRect(x: w + gap, y: 0, width: w, height: h))
    guard let outCG = ctx.makeImage(),
          let outRep = NSBitmapImageRep(cgImage: outCG)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
        print("[\(alias)] encode fail"); return
    }
    let outURL = URL(fileURLWithPath: "outputs/edge_spike/mask_\(alias).jpg")
    try outRep.write(to: outURL)
    print("[\(alias)] instances=\(obs.allInstances.count) wrote \(outURL.path)")
}

let args = CommandLine.arguments
let pairs: [(String, String)]
if args.count >= 3 {
    pairs = [(args[1], args[2])]
} else {
    pairs = [
        ("/tmp/edge_spike/frames/BND2_LM_t2.jpg", "LM_t2"),
        ("/tmp/edge_spike/frames/BND2_L3_t2.jpg", "L3_t2"),
        ("/tmp/edge_spike/frames/BND_L1_t1.jpg",  "MIDL1_t1"),
        ("/tmp/edge_spike/frames/BND2_L1_t2.jpg", "L1_t2"),
    ]
}
for (p, a) in pairs {
    do { try render(p, a) } catch { print("[\(a)] error: \(error)") }
}
