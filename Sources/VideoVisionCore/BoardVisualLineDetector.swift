import CoreGraphics
import Foundation

// MARK: - 图像级板身候选线检测

/// 从脚踝附近的图像纹理里找一条“可能的板身线”。
///
/// 这是一个保守的可视化/调试层检测器：它寻找脚踝附近细长、暗色或高饱和、
/// 且与周围雪面有对比的线段。当前结果只作为候选证据，评分端仍会按置信度回退。
public enum BoardVisualLineDetector {
    public static func detect(cgImage: CGImage, pose: BodyPoseData) -> BoardObservation? {
        guard pose.detected,
              let anchor = anchorPoint(from: pose),
              let image = PixelImage(cgImage: cgImage) else {
            return nil
        }

        let angleSeeds = candidateAngles(around: pose.ankleProxyBoardAngle?.value)
        let imageSize = CGSize(width: image.width, height: image.height)
        let anchorConfidence = anchor.confidence
        let proxyAngleConfidence = pose.ankleProxyBoardAngle?.confidence ?? anchorConfidence
        let proxyAngle = pose.ankleProxyBoardAngle?.value

        var best: Candidate?
        for mapping in AnchorMapping.allCases {
            let center = mapping.pixelPoint(fromNormalized: anchor.point, imageSize: imageSize)
            let ankleDistance = ankleDistancePixels(pose: pose, imageSize: imageSize, mapping: mapping)
            let lineLength = max(44, min(min(image.width, image.height) * 0.26, ankleDistance * 2.2))
            let searchRadius = max(10, min(min(image.width, image.height) * 0.045, ankleDistance * 0.45))

            for angle in angleSeeds {
                let direction = mapping.pixelVector(angle: angle)
                let normal = CGPoint(x: -direction.y, y: direction.x)
                for alongFactor in [-0.06, 0.0, 0.06] {
                    for normalFactor in [-0.55, -0.25, 0.0, 0.25, 0.55] {
                        let shifted = CGPoint(
                            x: center.x + direction.x * lineLength * alongFactor + normal.x * searchRadius * normalFactor,
                            y: center.y + direction.y * lineLength * alongFactor + normal.y * searchRadius * normalFactor
                        )
                        guard let scored = scoreLine(
                            center: shifted,
                            angle: angle,
                            direction: direction,
                            normal: normal,
                            length: lineLength,
                            image: image
                        ) else {
                            continue
                        }

                        let poseSupport = max(0.25, min(anchorConfidence, proxyAngleConfidence))
                        let anglePrior = proxyAngle.map {
                            clamp(1 - axisAngleDifference(angle, $0) / 50, lower: 0.25, upper: 1)
                        } ?? 1
                        let lengthRatio = scored.length / min(image.width, image.height)
                        let lengthPrior = clamp((lengthRatio - 0.06) / 0.14, lower: 0.25, upper: 1)
                        let confidence = clamp((scored.score - 0.18) / 0.36, lower: 0, upper: 1)
                            * clamp(poseSupport / 0.55, lower: 0.35, upper: 1)
                            * anglePrior
                            * lengthPrior
                        let candidate = Candidate(
                            angle: normalizeAngle(angle),
                            center: CGPoint(
                                x: shifted.x + direction.x * scored.centerOffset,
                                y: shifted.y + direction.y * scored.centerOffset
                            ),
                            lengthRatio: lengthRatio,
                            score: scored.score,
                            confidence: confidence,
                            mapping: mapping
                        )
                        if best == nil || candidate.confidence > (best?.confidence ?? 0) {
                            best = candidate
                        }
                    }
                }
            }
        }

        guard let best, best.confidence >= 0.08 else { return nil }
        let normalized = best.mapping.normalizedPoint(fromPixel: best.center, imageSize: imageSize)
        return BoardObservation(
            source: .visualCandidate,
            axisAngle: best.angle,
            centerX: normalized.x,
            centerY: normalized.y,
            confidence: best.confidence,
            lengthRatio: best.lengthRatio
        )
    }
}

private extension BoardVisualLineDetector {
    struct Anchor {
        let point: CGPoint
        let confidence: Double
    }

    struct Candidate {
        let angle: Double
        let center: CGPoint
        let lengthRatio: Double
        let score: Double
        let confidence: Double
        let mapping: AnchorMapping
    }

    struct LineScore {
        let score: Double
        let centerOffset: Double
        let length: Double
    }

    enum AnchorMapping: CaseIterable {
        case yUpRows
        case yDownRows

        func pixelPoint(fromNormalized point: CGPoint, imageSize: CGSize) -> CGPoint {
            switch self {
            case .yUpRows:
                return CGPoint(x: point.x * imageSize.width, y: point.y * imageSize.height)
            case .yDownRows:
                return CGPoint(x: point.x * imageSize.width, y: (1 - point.y) * imageSize.height)
            }
        }

        func normalizedPoint(fromPixel point: CGPoint, imageSize: CGSize) -> CGPoint {
            let x = clamp(point.x / imageSize.width, lower: 0, upper: 1)
            let rawY = clamp(point.y / imageSize.height, lower: 0, upper: 1)
            switch self {
            case .yUpRows:
                return CGPoint(x: x, y: rawY)
            case .yDownRows:
                return CGPoint(x: x, y: 1 - rawY)
            }
        }

        func pixelVector(angle: Double) -> CGPoint {
            let radians = angle * .pi / 180
            let ySign: Double = self == .yUpRows ? 1 : -1
            return CGPoint(x: cos(radians), y: sin(radians) * ySign)
        }
    }

    struct PixelImage {
        let width: Double
        let height: Double
        let pixels: [UInt8]
        let bytesPerRow: Int

        init?(cgImage: CGImage) {
            let pixelWidth = cgImage.width
            let pixelHeight = cgImage.height
            guard pixelWidth > 8, pixelHeight > 8 else { return nil }

            var data = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
            let rowBytes = pixelWidth * 4

            let drewImage = data.withUnsafeMutableBytes { rawBuffer -> Bool in
                guard let baseAddress = rawBuffer.baseAddress,
                      let context = CGContext(
                        data: baseAddress,
                        width: pixelWidth,
                        height: pixelHeight,
                        bitsPerComponent: 8,
                        bytesPerRow: rowBytes,
                        space: colorSpace,
                        bitmapInfo: bitmapInfo
                      ) else {
                    return false
                }
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
                return true
            }
            guard drewImage else { return nil }

            self.width = Double(pixelWidth)
            self.height = Double(pixelHeight)
            self.pixels = data
            self.bytesPerRow = rowBytes
        }

        func color(at point: CGPoint) -> (luma: Double, saturation: Double)? {
            let x = Int(point.x.rounded())
            let y = Int(point.y.rounded())
            guard x >= 0, x < Int(width), y >= 0, y < Int(height) else { return nil }

            let offset = y * bytesPerRow + x * 4
            guard offset + 2 < pixels.count else { return nil }
            let r = Double(pixels[offset]) / 255
            let g = Double(pixels[offset + 1]) / 255
            let b = Double(pixels[offset + 2]) / 255
            let maxValue = max(r, max(g, b))
            let minValue = min(r, min(g, b))
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let saturation = maxValue == 0 ? 0 : (maxValue - minValue) / maxValue
            return (luma, saturation)
        }
    }

    static func anchorPoint(from pose: BodyPoseData) -> Anchor? {
        let anklePoints = [pose.leftAnklePoint, pose.rightAnklePoint].compactMap { $0 }
        if !anklePoints.isEmpty {
            let weightSum = anklePoints.map { max(0.05, $0.confidence) }.reduce(0, +)
            let x = anklePoints.map { $0.x * max(0.05, $0.confidence) }.reduce(0, +) / weightSum
            let y = anklePoints.map { $0.y * max(0.05, $0.confidence) }.reduce(0, +) / weightSum
            let confidence = anklePoints.map(\.confidence).reduce(0, +) / Double(anklePoints.count)
            return Anchor(point: CGPoint(x: x, y: y), confidence: confidence)
        }

        guard let x = pose.ankleCenterX, let y = pose.ankleCenterY else { return nil }
        return Anchor(
            point: CGPoint(x: x.value, y: y.value),
            confidence: min(x.confidence, y.confidence)
        )
    }

    static func ankleDistancePixels(
        pose: BodyPoseData,
        imageSize: CGSize,
        mapping: AnchorMapping
    ) -> Double {
        guard let left = pose.leftAnklePoint, let right = pose.rightAnklePoint else {
            return min(imageSize.width, imageSize.height) * 0.08
        }
        let leftPoint = mapping.pixelPoint(fromNormalized: CGPoint(x: left.x, y: left.y), imageSize: imageSize)
        let rightPoint = mapping.pixelPoint(fromNormalized: CGPoint(x: right.x, y: right.y), imageSize: imageSize)
        let dx = leftPoint.x - rightPoint.x
        let dy = leftPoint.y - rightPoint.y
        return max(18, sqrt(dx * dx + dy * dy))
    }

    static func candidateAngles(around proxyAngle: Double?) -> [Double] {
        if let proxyAngle {
            let base = normalizeAxis(proxyAngle)
            return stride(from: -45.0, through: 45.0, by: 5.0).map { normalizeAxis(base + $0) }
        }
        return stride(from: -85.0, through: 85.0, by: 5.0).map { $0 }
    }

    static func scoreLine(
        center: CGPoint,
        angle: Double,
        direction: CGPoint,
        normal: CGPoint,
        length: Double,
        image: PixelImage
    ) -> LineScore? {
        let sampleCount = 29
        let normalOffset = max(3.5, min(9, length * 0.055))
        var samples: [(t: Double, score: Double)] = []
        var strongCount = 0

        for index in 0..<sampleCount {
            let t = (Double(index) / Double(sampleCount - 1) - 0.5) * length
            let point = CGPoint(x: center.x + direction.x * t, y: center.y + direction.y * t)
            guard let centerColor = image.color(at: point) else { continue }

            let neighborA = CGPoint(
                x: point.x + normal.x * normalOffset,
                y: point.y + normal.y * normalOffset
            )
            let neighborB = CGPoint(
                x: point.x - normal.x * normalOffset,
                y: point.y - normal.y * normalOffset
            )
            let neighborLuma = [
                image.color(at: neighborA)?.luma,
                image.color(at: neighborB)?.luma
            ].compactMap { $0 }
            let surroundingLuma = neighborLuma.isEmpty
                ? centerColor.luma
                : neighborLuma.reduce(0, +) / Double(neighborLuma.count)

            let darkObjectScore = clamp((0.82 - centerColor.luma) / 0.58, lower: 0, upper: 1)
            let colorObjectScore = clamp(centerColor.saturation * 1.25, lower: 0, upper: 1)
            let contrastScore = clamp(abs(surroundingLuma - centerColor.luma) * 2.6, lower: 0, upper: 1)
            let pointScore = max(darkObjectScore, colorObjectScore) * 0.62 + contrastScore * 0.38
            samples.append((t, pointScore))
            if pointScore >= 0.28 { strongCount += 1 }
        }

        guard samples.count >= sampleCount / 2 else { return nil }
        let pointScores = samples.map(\.score)
        guard let run = strongestRun(in: pointScores, threshold: 0.28) else { return nil }
        let runCount = run.upperBound - run.lowerBound
        guard runCount >= max(4, Int(ceil(Double(samples.count) * 0.16))) else { return nil }

        let averageScore = pointScores.reduce(0, +) / Double(pointScores.count)
        let coverage = Double(strongCount) / Double(pointScores.count)
        let continuity = Double(runCount) / Double(pointScores.count)
        let score = averageScore * 0.56 + coverage * 0.22 + continuity * 0.22
        let startT = samples[run.lowerBound].t
        let endT = samples[run.upperBound - 1].t
        let sampleStep = length / Double(sampleCount - 1)
        let detectedLength = max(sampleStep * 3, abs(endT - startT) + sampleStep * 2)
        return LineScore(
            score: score,
            centerOffset: (startT + endT) / 2,
            length: min(length, detectedLength)
        )
    }

    static func strongestRun(in values: [Double], threshold: Double) -> Range<Int>? {
        var bestStart = 0
        var bestCount = 0
        var currentStart = 0
        var current = 0
        for (index, value) in values.enumerated() {
            if value >= threshold {
                if current == 0 { currentStart = index }
                current += 1
                if current > bestCount {
                    bestStart = currentStart
                    bestCount = current
                }
            } else {
                current = 0
            }
        }
        guard bestCount > 0 else { return nil }
        return bestStart..<(bestStart + bestCount)
    }

    static func normalizeAxis(_ angle: Double) -> Double {
        var normalized = normalizeAngle(angle)
        if normalized >= 90 {
            normalized -= 180
        } else if normalized < -90 {
            normalized += 180
        }
        return normalized
    }

    static func axisAngleDifference(_ first: Double, _ second: Double) -> Double {
        let raw = abs(normalizeAngle(first - second))
        return raw > 90 ? 180 - raw : raw
    }

    static func normalizeAngle(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized >= 180 {
            normalized -= 360
        } else if normalized < -180 {
            normalized += 360
        }
        return normalized
    }
}
