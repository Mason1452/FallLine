import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let design: CGFloat = 238
let outputDirectory = URL(fileURLWithPath: "SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

struct Palette {
    let backgroundTop: CGColor
    let backgroundMid: CGColor
    let backgroundBottom: CGColor
    let snowStart: CGColor
    let snowEnd: CGColor
    let cyan: CGColor
    let mint: CGColor
    let ice: CGColor
    let badgeFill: CGColor
    let badgeStroke: CGColor
}

func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var value: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&value)
    let r = CGFloat((value >> 16) & 0xff) / 255
    let g = CGFloat((value >> 8) & 0xff) / 255
    let b = CGFloat(value & 0xff) / 255
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

func makePalette(variant: String) -> Palette {
    switch variant {
    case "tinted":
        return Palette(
            backgroundTop: color("#243447"),
            backgroundMid: color("#111A24"),
            backgroundBottom: color("#05080D"),
            snowStart: color("#FFFFFF"),
            snowEnd: color("#B8C7D6"),
            cyan: color("#EAF7FF"),
            mint: color("#FFFFFF"),
            ice: color("#FFFFFF"),
            badgeFill: color("#05080D", alpha: 0.82),
            badgeStroke: color("#FFFFFF", alpha: 0.42)
        )
    case "dark":
        return Palette(
            backgroundTop: color("#164A70"),
            backgroundMid: color("#04101D"),
            backgroundBottom: color("#010408"),
            snowStart: color("#F3FDFF"),
            snowEnd: color("#6EA9E8"),
            cyan: color("#29D7FF"),
            mint: color("#6DFFBF"),
            ice: color("#F3FDFF"),
            badgeFill: color("#010408", alpha: 0.84),
            badgeStroke: color("#BFEFFF", alpha: 0.42)
        )
    default:
        return Palette(
            backgroundTop: color("#1F5D87"),
            backgroundMid: color("#06111E"),
            backgroundBottom: color("#02070D"),
            snowStart: color("#F3FDFF"),
            snowEnd: color("#7AB7FF"),
            cyan: color("#29D7FF"),
            mint: color("#6DFFBF"),
            ice: color("#F3FDFF"),
            badgeFill: color("#02070D", alpha: 0.82),
            badgeStroke: color("#BFEFFF", alpha: 0.42)
        )
    }
}

func gradient(_ colors: [CGColor], locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations)!
}

func strokePath(_ path: CGPath, in context: CGContext, color: CGColor, width: CGFloat, lineCap: CGLineCap = .round, lineJoin: CGLineJoin = .round) {
    context.addPath(path)
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(lineCap)
    context.setLineJoin(lineJoin)
    context.strokePath()
}

func carvePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 39, y: 177))
    path.addCurve(to: CGPoint(x: 160, y: 159), control1: CGPoint(x: 79, y: 151), control2: CGPoint(x: 119, y: 148))
    path.addCurve(to: CGPoint(x: 222, y: 130), control1: CGPoint(x: 185, y: 166), control2: CGPoint(x: 205, y: 154))
    return path
}

func drawIcon(named filename: String, variant: String) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: Int(canvas),
        height: Int(canvas),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw NSError(domain: "FallLineIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context"])
    }

    let palette = makePalette(variant: variant)
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: canvas / design, y: -canvas / design)

    let background = gradient([palette.backgroundTop, palette.backgroundMid, palette.backgroundBottom], locations: [0, 0.46, 1])
    context.drawRadialGradient(
        background,
        startCenter: CGPoint(x: 83, y: 36),
        startRadius: 0,
        endCenter: CGPoint(x: 83, y: 36),
        endRadius: 230,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    let mountain = CGMutablePath()
    mountain.move(to: CGPoint(x: 34, y: 164))
    mountain.addLine(to: CGPoint(x: 72, y: 109))
    mountain.addLine(to: CGPoint(x: 96, y: 135))
    mountain.addLine(to: CGPoint(x: 124, y: 76))
    mountain.addLine(to: CGPoint(x: 152, y: 122))
    mountain.addLine(to: CGPoint(x: 184, y: 83))
    mountain.addLine(to: CGPoint(x: 216, y: 164))
    mountain.addLine(to: CGPoint(x: 216, y: 238))
    mountain.addLine(to: CGPoint(x: 34, y: 238))
    mountain.closeSubpath()

    context.saveGState()
    context.addPath(mountain)
    context.clip()
    context.setAlpha(0.24)
    context.drawLinearGradient(
        gradient([palette.snowStart, palette.snowEnd], locations: [0, 1]),
        start: CGPoint(x: 34, y: 76),
        end: CGPoint(x: 216, y: 238),
        options: []
    )
    context.restoreGState()

    let trace = carvePath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 0), blur: 6, color: palette.cyan.copy(alpha: 0.65))
    strokePath(trace, in: context, color: palette.cyan, width: 9)
    context.restoreGState()

    let badgeCenter = CGPoint(x: 156, y: 80)
    context.addEllipse(in: CGRect(x: badgeCenter.x - 36, y: badgeCenter.y - 36, width: 72, height: 72))
    context.setFillColor(palette.badgeFill)
    context.fillPath()

    context.addEllipse(in: CGRect(x: badgeCenter.x - 36, y: badgeCenter.y - 36, width: 72, height: 72))
    context.setStrokeColor(palette.badgeStroke)
    context.setLineWidth(6)
    context.strokePath()

    let progress = CGMutablePath()
    progress.addArc(center: badgeCenter, radius: 36, startAngle: -.pi / 2, endAngle: .pi * 0.12, clockwise: false)
    strokePath(progress, in: context, color: palette.mint, width: 8)

    context.addEllipse(in: CGRect(x: badgeCenter.x - 15, y: badgeCenter.y - 15, width: 30, height: 30))
    context.setStrokeColor(palette.ice)
    context.setLineWidth(5)
    context.strokePath()

    let reticle = CGMutablePath()
    reticle.move(to: CGPoint(x: 156, y: 54))
    reticle.addLine(to: CGPoint(x: 156, y: 66))
    reticle.move(to: CGPoint(x: 156, y: 94))
    reticle.addLine(to: CGPoint(x: 156, y: 106))
    reticle.move(to: CGPoint(x: 130, y: 80))
    reticle.addLine(to: CGPoint(x: 142, y: 80))
    reticle.move(to: CGPoint(x: 170, y: 80))
    reticle.addLine(to: CGPoint(x: 182, y: 80))
    strokePath(reticle, in: context, color: palette.ice, width: 5)

    context.addEllipse(in: CGRect(x: badgeCenter.x - 4.5, y: badgeCenter.y - 4.5, width: 9, height: 9))
    context.setFillColor(palette.mint)
    context.fillPath()

    guard let cgImage = context.makeImage() else {
        throw NSError(domain: "FallLineIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create CGImage"])
    }

    let destinationURL = outputDirectory.appendingPathComponent(filename)
    guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "FallLineIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create image destination"])
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    if !CGImageDestinationFinalize(destination) {
        throw NSError(domain: "FallLineIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not write \(filename)"])
    }
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try drawIcon(named: "AppIcon-Default.png", variant: "default")
try drawIcon(named: "AppIcon-Dark.png", variant: "dark")
try drawIcon(named: "AppIcon-Tinted.png", variant: "tinted")
print("Generated FallLine app icons in \(outputDirectory.path)")
