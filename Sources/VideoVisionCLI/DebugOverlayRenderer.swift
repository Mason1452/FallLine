import AppKit
import AVFoundation
import Foundation
import VideoVisionCore

// MARK: - 调试覆盖图渲染器

/// 将分析结果画回采样帧，方便人工核对板身方向、运动方向和立刃代理分。
public struct DebugOverlayRenderer {
    public struct RenderResult {
        public let outputDirectory: URL
        public let frameCount: Int
        public let manifestURL: URL
    }

    public init() {}

    public static func renderFrameOverlays(
        videoURL: URL,
        analysis: AnalysisOutput,
        outputDirectory: URL? = nil,
        maxDimension: CGFloat = 1280
    ) async throws -> RenderResult {
        let destination = outputDirectory ?? videoURL
            .deletingPathExtension()
            .appendingPathExtension("debug_frames")

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try clearExistingDebugFiles(in: destination)

        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

        let frames = analysis.frames.sorted { $0.time < $1.time }
        let boardFrames = analysis.boardAnalysis.frames.sorted { $0.time < $1.time }
        let interval = medianSampleInterval(frames.map(\.time))

        var manifestLines = [
            "index\ttime\timage\tposeScore\tcalfLeanScore\tvisualBoardAngle\tvisualBoardConfidence\tvisualBoardLength\tboardSource\tboardAngle\ttravelAngle\tsideslipAngle\tcarvingConfidence\tconfidence"
        ]
        var renderedCount = 0

        for (index, frame) in frames.enumerated() {
            let time = CMTime(seconds: frame.time, preferredTimescale: 600)
            let cgImage: CGImage
            do {
                cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            } catch {
                continue
            }

            let boardFrame = nearestBoardFrame(
                to: frame.time,
                in: boardFrames,
                tolerance: max(interval * 0.75, 0.55)
            )
            let image = renderOverlay(
                image: cgImage,
                frame: frame,
                boardFrame: boardFrame,
                summary: analysis.summary
            )

            let filename = String(format: "frame_%04d_%@.png", index + 1, fileSafeTime(frame.time))
            let fileURL = destination.appendingPathComponent(filename)
            guard let pngData = image.pngData else { continue }
            try pngData.write(to: fileURL)
            renderedCount += 1

            manifestLines.append(manifestLine(
                index: index + 1,
                time: frame.time,
                filename: filename,
                frame: frame,
                boardFrame: boardFrame
            ))
        }

        let manifestURL = destination.appendingPathComponent("manifest.tsv")
        try manifestLines.joined(separator: "\n")
            .write(to: manifestURL, atomically: true, encoding: .utf8)

        return RenderResult(
            outputDirectory: destination,
            frameCount: renderedCount,
            manifestURL: manifestURL
        )
    }
}

private extension DebugOverlayRenderer {
    static func renderOverlay(
        image: CGImage,
        frame: DetectionResult,
        boardFrame: BoardFrameAnalysis?,
        summary: VideoSummary
    ) -> NSBitmapImageRep {
        let width = image.width
        let height = image.height
        let size = NSSize(width: width, height: height)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSImage(cgImage: image, size: size).draw(in: NSRect(origin: .zero, size: size))

        drawPoseSkeleton(frame.bodyPose, canvas: size)
        drawAnkleProxyLine(frame.bodyPose, canvas: size)
        if let visualObservation = frame.visualBoardObservation {
            drawVisualBoardObservation(visualObservation, canvas: size)
        }

        if let boardFrame {
            drawBoardObservation(boardFrame.observation, canvas: size)
            if let kinematics = boardFrame.kinematics {
                drawTravelDirection(
                    kinematics.travelAngle,
                    centerX: boardFrame.observation.centerX,
                    centerY: boardFrame.observation.centerY,
                    canvas: size
                )
            }
        }

        drawPoseCenter(frame.bodyPose, canvas: size)
        drawTextPanel(frame: frame, boardFrame: boardFrame, summary: summary, canvas: size)
        NSGraphicsContext.restoreGraphicsState()

        return bitmap
    }

    static func drawPoseSkeleton(_ pose: BodyPoseData, canvas: NSSize) {
        let leftColor = NSColor.systemOrange
        let rightColor = NSColor.systemPink
        let coreColor = NSColor.systemGreen
        let width = max(3, min(canvas.width, canvas.height) * 0.004)

        drawJointLine(pose.leftShoulderPoint, pose.rightShoulderPoint, canvas: canvas, color: coreColor, width: width)
        drawJointLine(pose.leftHipPoint, pose.rightHipPoint, canvas: canvas, color: coreColor, width: width)
        drawJointLine(pose.leftShoulderPoint, pose.leftHipPoint, canvas: canvas, color: leftColor, width: width)
        drawJointLine(pose.leftHipPoint, pose.leftKneePoint, canvas: canvas, color: leftColor, width: width)
        drawJointLine(pose.leftKneePoint, pose.leftAnklePoint, canvas: canvas, color: leftColor, width: width)
        drawJointLine(pose.rightShoulderPoint, pose.rightHipPoint, canvas: canvas, color: rightColor, width: width)
        drawJointLine(pose.rightHipPoint, pose.rightKneePoint, canvas: canvas, color: rightColor, width: width)
        drawJointLine(pose.rightKneePoint, pose.rightAnklePoint, canvas: canvas, color: rightColor, width: width)

        for point in [
            pose.leftShoulderPoint,
            pose.rightShoulderPoint,
            pose.leftHipPoint,
            pose.rightHipPoint,
            pose.leftKneePoint,
            pose.rightKneePoint,
            pose.leftAnklePoint,
            pose.rightAnklePoint
        ] {
            guard let point else { continue }
            drawJointPoint(point, canvas: canvas)
        }
    }

    static func drawAnkleProxyLine(_ pose: BodyPoseData, canvas: NSSize) {
        guard let left = pose.leftAnklePoint,
              let right = pose.rightAnklePoint else {
            return
        }
        drawJointLine(
            left,
            right,
            canvas: canvas,
            color: NSColor.white.withAlphaComponent(0.92),
            width: max(3, min(canvas.width, canvas.height) * 0.0045)
        )
    }

    static func drawBoardObservation(_ observation: BoardObservation, canvas: NSSize) {
        drawObservationLine(
            observation,
            canvas: canvas,
            color: NSColor.systemYellow,
            alpha: CGFloat(max(0.45, observation.confidence)),
            widthMultiplier: 0.006
        )
    }

    static func drawVisualBoardObservation(_ observation: BoardObservation, canvas: NSSize) {
        drawObservationLine(
            observation,
            canvas: canvas,
            color: NSColor.systemPurple,
            alpha: CGFloat(max(0.35, observation.confidence)),
            widthMultiplier: 0.004
        )
    }

    static func drawObservationLine(
        _ observation: BoardObservation,
        canvas: NSSize,
        color: NSColor,
        alpha: CGFloat,
        widthMultiplier: CGFloat
    ) {
        let center = normalizedPoint(x: observation.centerX, y: observation.centerY, canvas: canvas)
        let lengthRatio = observation.lengthRatio.map {
            CGFloat(clamp($0, lower: 0.04, upper: 0.42))
        } ?? 0.42
        let length = min(canvas.width, canvas.height) * lengthRatio
        let direction = vector(angle: observation.axisAngle, length: length / 2)
        let start = NSPoint(x: center.x - direction.x, y: center.y - direction.y)
        let end = NSPoint(x: center.x + direction.x, y: center.y + direction.y)

        drawLine(
            from: start,
            to: end,
            color: color.withAlphaComponent(alpha),
            width: max(3, min(canvas.width, canvas.height) * widthMultiplier)
        )
        drawCircle(center: center, radius: 5, color: color.withAlphaComponent(alpha))
    }

    static func drawTravelDirection(
        _ angle: Double,
        centerX: Double,
        centerY: Double,
        canvas: NSSize
    ) {
        let start = normalizedPoint(x: centerX, y: centerY, canvas: canvas)
        let direction = vector(angle: angle, length: min(canvas.width, canvas.height) * 0.32)
        let end = NSPoint(x: start.x + direction.x, y: start.y + direction.y)

        drawLine(
            from: start,
            to: end,
            color: NSColor.systemCyan,
            width: max(4, min(canvas.width, canvas.height) * 0.005)
        )
        drawArrowHead(start: start, end: end, color: NSColor.systemCyan)
    }

    static func drawPoseCenter(_ pose: BodyPoseData, canvas: NSSize) {
        guard let x = pose.bodyCenterX?.value,
              let y = pose.bodyCenterY?.value else {
            return
        }
        drawCircle(
            center: normalizedPoint(x: x, y: y, canvas: canvas),
            radius: 6,
            color: NSColor.systemGreen
        )
    }

    static func drawJointLine(
        _ first: PoseJointPoint?,
        _ second: PoseJointPoint?,
        canvas: NSSize,
        color: NSColor,
        width: CGFloat
    ) {
        guard let first, let second else { return }
        let confidence = min(first.confidence, second.confidence)
        let effectiveColor = color.withAlphaComponent(CGFloat(max(0.30, confidence)))
        drawLine(
            from: normalizedPoint(x: first.x, y: first.y, canvas: canvas),
            to: normalizedPoint(x: second.x, y: second.y, canvas: canvas),
            color: effectiveColor,
            width: width
        )
    }

    static func drawJointPoint(_ point: PoseJointPoint, canvas: NSSize) {
        let radius = max(4, min(canvas.width, canvas.height) * 0.005)
        let color = NSColor.white.withAlphaComponent(CGFloat(max(0.35, point.confidence)))
        drawCircle(
            center: normalizedPoint(x: point.x, y: point.y, canvas: canvas),
            radius: radius,
            color: color
        )
    }

    static func drawTextPanel(
        frame: DetectionResult,
        boardFrame: BoardFrameAnalysis?,
        summary: VideoSummary,
        canvas: NSSize
    ) {
        let padding: CGFloat = 14
        let panelWidth = min(canvas.width - padding * 2, 520)
        let fontSize = max(13, min(canvas.width, canvas.height) * 0.018)
        let lines = overlayLines(frame: frame, boardFrame: boardFrame, summary: summary)
        let lineHeight = fontSize + 6
        let panelHeight = CGFloat(lines.count) * lineHeight + padding * 1.4
        let panel = NSRect(
            x: padding,
            y: canvas.height - panelHeight - padding,
            width: panelWidth,
            height: panelHeight
        )

        NSColor.black.withAlphaComponent(0.68).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 8, yRadius: 8).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        for (index, line) in lines.enumerated() {
            let y = panel.maxY - padding - CGFloat(index + 1) * lineHeight + 4
            NSString(string: line).draw(
                at: NSPoint(x: panel.minX + padding, y: y),
                withAttributes: attributes
            )
        }
    }

    static func overlayLines(
        frame: DetectionResult,
        boardFrame: BoardFrameAnalysis?,
        summary: VideoSummary
    ) -> [String] {
        var lines = [
            "time \(formatTime(frame.time))   summary \(formatScore(summary.averageScore))"
        ]

        if let poseScore = frame.poseScore {
            lines.append(
                "pose \(formatScore(poseScore.totalScore)) conf \(formatConfidence(poseScore.totalConfidence))"
            )
            lines.append(
                "edgeProxy \(formatScore(poseScore.calfLeanScore)) conf \(formatConfidence(poseScore.calfLeanConfidence))"
            )
        } else {
            lines.append("pose none")
        }

        if let boardFrame {
            if let visualObservation = frame.visualBoardObservation {
                lines.append(
                    "visualBoard \(formatAngle(visualObservation.axisAngle)) len \(formatLength(visualObservation.lengthRatio)) conf \(formatConfidence(visualObservation.confidence))"
                )
            }
            lines.append(
                "board \(formatSource(boardFrame.observation.source)) \(formatAngle(boardFrame.observation.axisAngle)) conf \(formatConfidence(boardFrame.observation.confidence))"
            )
            if let kinematics = boardFrame.kinematics {
                lines.append(
                    "travel \(formatAngle(kinematics.travelAngle)) slip \(formatAngle(kinematics.sideslipAngle))"
                )
                lines.append(
                    "carve \(formatScore(kinematics.carvingConfidence)) conf \(formatConfidence(kinematics.confidence))"
                )
            } else {
                lines.append("travel none")
            }
        } else {
            if let visualObservation = frame.visualBoardObservation {
                lines.append(
                    "visualBoard \(formatAngle(visualObservation.axisAngle)) len \(formatLength(visualObservation.lengthRatio)) conf \(formatConfidence(visualObservation.confidence))"
                )
            }
            lines.append("board none")
        }

        return lines
    }

    static func drawLine(from start: NSPoint, to end: NSPoint, color: NSColor, width: CGFloat) {
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = width
        path.move(to: start)
        path.line(to: end)
        path.stroke()
    }

    static func drawCircle(center: NSPoint, radius: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )).fill()
    }

    static func drawArrowHead(start: NSPoint, end: NSPoint, color: NSColor) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let size: CGFloat = 18
        let left = NSPoint(
            x: end.x - size * cos(angle - .pi / 6),
            y: end.y - size * sin(angle - .pi / 6)
        )
        let right = NSPoint(
            x: end.x - size * cos(angle + .pi / 6),
            y: end.y - size * sin(angle + .pi / 6)
        )
        color.setFill()
        let path = NSBezierPath()
        path.move(to: end)
        path.line(to: left)
        path.line(to: right)
        path.close()
        path.fill()
    }

    static func normalizedPoint(x: Double, y: Double, canvas: NSSize) -> NSPoint {
        NSPoint(
            x: clamp(x, lower: 0, upper: 1) * canvas.width,
            y: clamp(y, lower: 0, upper: 1) * canvas.height
        )
    }

    static func vector(angle: Double, length: CGFloat) -> NSPoint {
        let radians = angle * .pi / 180
        return NSPoint(
            x: CGFloat(cos(radians)) * length,
            y: CGFloat(sin(radians)) * length
        )
    }

    static func nearestBoardFrame(
        to time: Double,
        in frames: [BoardFrameAnalysis],
        tolerance: Double
    ) -> BoardFrameAnalysis? {
        frames
            .map { (frame: $0, distance: abs($0.time - time)) }
            .filter { $0.distance <= tolerance }
            .min { $0.distance < $1.distance }?
            .frame
    }

    static func clearExistingDebugFiles(in directory: URL) throws {
        let fileManager = FileManager.default
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for url in urls where url.pathExtension == "png" || url.lastPathComponent == "manifest.tsv" {
            try fileManager.removeItem(at: url)
        }
    }

    static func manifestLine(
        index: Int,
        time: Double,
        filename: String,
        frame: DetectionResult,
        boardFrame: BoardFrameAnalysis?
    ) -> String {
        let poseScore = frame.poseScore?.totalScore
        let calfLean = frame.poseScore?.calfLeanScore
        let visualBoardAngle = frame.visualBoardObservation?.axisAngle
        let visualBoardConfidence = frame.visualBoardObservation?.confidence
        let visualBoardLength = frame.visualBoardObservation?.lengthRatio
        let boardSource = boardFrame.map { $0.observation.source.rawValue } ?? ""
        let boardAngle = boardFrame?.observation.axisAngle
        let travelAngle = boardFrame?.kinematics?.travelAngle
        let sideslip = boardFrame?.kinematics?.sideslipAngle
        let carving = boardFrame?.kinematics?.carvingConfidence
        let confidence = boardFrame?.kinematics?.confidence ?? boardFrame?.observation.confidence

        return [
            String(index),
            String(format: "%.2f", time),
            filename,
            formatOptional(poseScore),
            formatOptional(calfLean),
            formatOptional(visualBoardAngle),
            formatOptional(visualBoardConfidence),
            formatOptional(visualBoardLength),
            boardSource,
            formatOptional(boardAngle),
            formatOptional(travelAngle),
            formatOptional(sideslip),
            formatOptional(carving),
            formatOptional(confidence)
        ].joined(separator: "\t")
    }

    static func formatOptional(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }

    static func formatScore(_ score: Double) -> String {
        String(format: "%.0f", score)
    }

    static func formatAngle(_ angle: Double) -> String {
        String(format: "%.0f°", angle)
    }

    static func formatConfidence(_ confidence: Double) -> String {
        String(format: "%.0f%%", confidence * 100)
    }

    static func formatLength(_ lengthRatio: Double?) -> String {
        guard let lengthRatio else { return "--" }
        return String(format: "%.0f%%", lengthRatio * 100)
    }

    static func formatSource(_ source: BoardObservationSource) -> String {
        switch source {
        case .ankleProxy:
            return "ankle"
        case .visualCandidate:
            return "visual"
        case .mixed:
            return "mixed"
        }
    }

    static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func fileSafeTime(_ seconds: Double) -> String {
        formatTime(seconds).replacingOccurrences(of: ":", with: "-")
    }

    static func medianSampleInterval(_ times: [Double]) -> Double {
        let deltas = zip(times.dropFirst(), times)
            .map { max($0 - $1, 0) }
            .filter { $0 > 0 }
        guard !deltas.isEmpty else { return 1 }
        let sorted = deltas.sorted()
        return sorted[sorted.count / 2]
    }
}

private extension NSBitmapImageRep {
    var pngData: Data? {
        representation(using: .png, properties: [:])
    }
}
