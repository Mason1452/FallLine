import Foundation
import CoreImage
import CoreGraphics
import Vision

// MARK: - 板身刃线检测器（Phase 1 诊断能力，候选 A）

/// 降级候选选择策略（ADR-002，2026-09-20）。
public enum BoardFallbackPickStrategy: String, Codable {
    /// 踝对与膝对同时算，按 confidence 取高（v2 历史行为）。
    case confMax
    /// 只用踝对；膝对是精度拖累主力（§12.11 三策略扫描 + §12.12 时序累积扫描证）。
    case ankleOnly
}

/// 板身刃线检测配置（Phase 0 GT 校准后的阈值）。
///
/// 阈值为公开常量，便于单测锁定边界；默认值对应 spec §10 Gate-G0 的量化结果。
public struct BoardEdgeConfig {
    /// 前景主体占整帧比例下限：低于此判远景/分割不可用。
    public var minSubjectFraction: Double
    /// 踝点定位置信度下限。
    public var minAnkleConfidence: Double
    /// 板轴相对水平的无符号夹角上限：超过判为竖直物体（雪杖/裤腿/他人）。
    public var maxAxisAngle: Double
    /// 板轴归一长度下限（等效全长 / 图宽）。Phase 0 由 0.10 按 GT 校准到 0.07。
    public var minAxisLength: Double
    /// 板轴归一长度上限。
    public var maxAxisLength: Double
    /// 主轴延伸率下限（长轴/短轴）。
    public var maxAxisBlob: Double
    /// 踝下 ROI 半宽（归一）。
    public var roiHalfWidth: Double
    /// 踝下 ROI 上沿（踝点上方偏移，归一，正为向上）。
    public var roiTopOffset: Double
    /// 踝下 ROI 下沿（踝点下方偏移，负为向下）。
    public var roiBottomOffset: Double
    /// ROI 内最少主体像素，少于则无法形成主轴。
    public var minAxisPixels: Int
    /// 站姿判定：躯干相对竖直方向夹角超过此值判摔倒。
    public var maxTrunkTilt: Double
    /// 实例主体框与姿态框最小重叠（IoU），低于判实例不归属本滑者。
    public var minInstanceOverlap: Double
    /// 主检测失败时是否启用姿态几何降级（ADR-001）。
    public var enableFallback: Bool
    /// 降级合成置信度下限（低于则保留原始拒绝状态）。
    /// ADR-002 (2026-09-20)：从 0.30 提到 0.40，配合 ankleOnly 策略保证准入精度 ≥90%。
    public var fallbackConfidenceFloor: Double
    /// 降级关节对关键点置信度下限。
    public var fallbackPairConfidenceFloor: Double
    /// 双膝连线源相对踝对的权重（膝可相对板扭转）。
    public var fallbackKneeWeight: Double
    /// 几何置信度的间距缩放系数（归一间距 × 该系数）。
    public var fallbackGeometryScale: Double
    /// 降级候选选择策略（ADR-002，2026-09-20）：ankleOnly 是 §12.11/§12.12 联合唯一解。
    public var fallbackPickStrategy: BoardFallbackPickStrategy
    /// 时序聚合因果前向窗大小（帧；ADR-004，§12.15；0.2s 采样下 5 = 1s 物理窗）。
    public var temporalWindowSize: Int
    /// 时序窗通过所需的最少有效候选数（ADR-004；⌈W/2⌉）。
    public var temporalMinCount: Int
    /// 时序窗角度 IQR 上限（度，ADR-004）。
    public var temporalIQRGate: Double
    /// fold-crossing 检测：窗口角度最小值不高于此值且最大值不低于 temporalFoldHighAngle 判为跨折叠。
    public var temporalFoldLowAngle: Double
    /// fold-crossing 检测上界（度）。
    public var temporalFoldHighAngle: Double

    public init(
        minSubjectFraction: Double = 0.02,
        minAnkleConfidence: Double = 0.30,
        maxAxisAngle: Double = 45.0,
        minAxisLength: Double = 0.07,
        maxAxisLength: Double = 0.55,
        maxAxisBlob: Double = 2.0,
        roiHalfWidth: Double = 0.24,
        roiTopOffset: Double = 0.01,
        roiBottomOffset: Double = 0.16,
        minAxisPixels: Int = 30,
        maxTrunkTilt: Double = 50.0,
        minInstanceOverlap: Double = 0.15,
        enableFallback: Bool = true,
        fallbackConfidenceFloor: Double = 0.40,
        fallbackPairConfidenceFloor: Double = 0.30,
        fallbackKneeWeight: Double = 0.6,
        fallbackGeometryScale: Double = 12.0,
        fallbackPickStrategy: BoardFallbackPickStrategy = .ankleOnly,
        temporalWindowSize: Int = 5,
        temporalMinCount: Int = 3,
        temporalIQRGate: Double = 5.0,
        temporalFoldLowAngle: Double = 20.0,
        temporalFoldHighAngle: Double = 70.0
    ) {
        self.minSubjectFraction = minSubjectFraction
        self.minAnkleConfidence = minAnkleConfidence
        self.maxAxisAngle = maxAxisAngle
        self.minAxisLength = minAxisLength
        self.maxAxisLength = maxAxisLength
        self.maxAxisBlob = maxAxisBlob
        self.roiHalfWidth = roiHalfWidth
        self.roiTopOffset = roiTopOffset
        self.roiBottomOffset = roiBottomOffset
        self.minAxisPixels = minAxisPixels
        self.maxTrunkTilt = maxTrunkTilt
        self.minInstanceOverlap = minInstanceOverlap
        self.enableFallback = enableFallback
        self.fallbackConfidenceFloor = fallbackConfidenceFloor
        self.fallbackPairConfidenceFloor = fallbackPairConfidenceFloor
        self.fallbackKneeWeight = fallbackKneeWeight
        self.fallbackGeometryScale = fallbackGeometryScale
        self.fallbackPickStrategy = fallbackPickStrategy
        self.temporalWindowSize = max(1, temporalWindowSize)
        self.temporalMinCount = max(1, temporalMinCount)
        self.temporalIQRGate = max(0, temporalIQRGate)
        self.temporalFoldLowAngle = temporalFoldLowAngle
        self.temporalFoldHighAngle = temporalFoldHighAngle
    }

    /// Phase 1 默认配置（Gate-G0 校准值）。
    public static let standard = BoardEdgeConfig()
}

/// PCA 主轴几何结果（纯数值，不含 Vision 依赖）。
public struct AxisGeometry: Equatable {
    public var pixelCount: Int
    /// 无符号夹角 0...90（度）；无主轴时为 nil。
    public var angle: Double?
    public var elongation: Double
    /// 等效全长 / 参考宽。
    public var lengthRatio: Double
    public var centerX: Double
    public var centerY: Double

    public init(
        pixelCount: Int,
        angle: Double?,
        elongation: Double,
        lengthRatio: Double,
        centerX: Double,
        centerY: Double
    ) {
        self.pixelCount = pixelCount
        self.angle = angle
        self.elongation = elongation
        self.lengthRatio = lengthRatio
        self.centerX = centerX
        self.centerY = centerY
    }
}

/// 基于前景实例分割 + 踝下 ROI PCA 的板身刃线检测器。
///
/// 仅产出诊断观测（`BoardEdgeObservation`），不读取也不修改任何评分字段；
/// 远景 / 非站立 / 跨实例等情况诚实输出对应状态，绝不猜测。
public enum BoardEdgeDetector {

    /// 对单帧执行板身刃线检测。
    /// - Parameters:
    ///   - cgImage: 全分辨率帧（mask/PCA 需要足部细节）。
    ///   - pose: 同帧姿态数据（踝点用于 ROI，躯干点用于站姿与实例归属）。
    ///   - config: 门控配置，默认 `.standard`。
    /// - Returns: 板身刃线观测。
    public static func detect(
        cgImage: CGImage,
        pose: BodyPoseData,
        config: BoardEdgeConfig = .standard
    ) throws -> BoardEdgeObservation {
        let primary = try primaryDetection(cgImage: cgImage, pose: pose, config: config)

        switch primary.status {
        case .board, .rejectPosture, .disabled:
            return primary
        default:
            guard config.enableFallback,
                  let fallback = synthesizeFallback(
                    pose: pose,
                    originalStatus: primary.status,
                    config: config
                  ) else {
                return primary
            }
            return BoardEdgeObservation(
                status: .fallback,
                subjectFraction: primary.subjectFraction,
                ankleConfidence: primary.ankleConfidence,
                fallbackAxis: fallback
            )
        }
    }

    private static func primaryDetection(
        cgImage: CGImage,
        pose: BodyPoseData,
        config: BoardEdgeConfig
    ) throws -> BoardEdgeObservation {
        guard let ankle = ankleCenter(from: pose, config: config) else {
            return BoardEdgeObservation(status: .ankleLowCnf)
        }

        let instances = try foregroundInstances(cgImage: cgImage)
        guard !instances.isEmpty else {
            return BoardEdgeObservation(status: .noMask)
        }

        let poseBox = poseBodyBox(pose)
        guard let selected = selectSubjectInstance(instances, poseBox: poseBox, config: config) else {
            return BoardEdgeObservation(status: .rejectOwnership)
        }

        let subjectFraction = Double(selected.alphaCount) / Double(cgImage.width * cgImage.height)
        guard subjectFraction >= config.minSubjectFraction else {
            return BoardEdgeObservation(
                status: .farShot,
                subjectFraction: subjectFraction,
                ankleConfidence: ankle.confidence
            )
        }

        if postureStatus(pose: pose, config: config) == false {
            return BoardEdgeObservation(
                status: .rejectPosture,
                subjectFraction: subjectFraction,
                ankleConfidence: ankle.confidence
            )
        }

        let geometry = axisGeometry(
            alpha: selected.data,
            width: cgImage.width,
            height: cgImage.height,
            ankleX: ankle.x,
            ankleY: ankle.y,
            config: config
        )

        let status: BoardEdgeStatus
        if let angle = geometry.angle {
            if angle > config.maxAxisAngle {
                status = .rejectVertical
            } else if geometry.lengthRatio < config.minAxisLength
                        || geometry.lengthRatio > config.maxAxisLength {
                status = .rejectLength
            } else if geometry.elongation < config.maxAxisBlob {
                status = .rejectBlob
            } else {
                status = .board
            }
        } else {
            status = .noAxis
        }

        return BoardEdgeObservation(
            status: status,
            axisAngle: geometry.angle,
            centerX: geometry.centerX,
            centerY: geometry.centerY,
            lengthRatio: geometry.lengthRatio,
            elongation: geometry.elongation,
            subjectFraction: subjectFraction,
            ankleConfidence: ankle.confidence
        )
    }

    // MARK: - 姿态几何降级（ADR-001）

    static func synthesizeFallback(
        pose: BodyPoseData,
        originalStatus: BoardEdgeStatus,
        config: BoardEdgeConfig
    ) -> FallbackAxis? {
        let ankleCandidate = fallbackAxis(
            source: .anklePair,
            first: pose.leftAnklePoint,
            second: pose.rightAnklePoint,
            sourceWeight: 1.0,
            originalStatus: originalStatus,
            config: config
        )
        // ADR-002 (2026-09-20)：ankleOnly 策略下跳过膝对，避免 §12.11 精度拖累。
        let kneeCandidate: FallbackAxis?
        switch config.fallbackPickStrategy {
        case .ankleOnly:
            kneeCandidate = nil
        case .confMax:
            kneeCandidate = fallbackAxis(
                source: .kneePair,
                first: pose.leftKneePoint,
                second: pose.rightKneePoint,
                sourceWeight: config.fallbackKneeWeight,
                originalStatus: originalStatus,
                config: config
            )
        }

        switch (ankleCandidate, kneeCandidate) {
        case let (ankle?, knee?):
            return ankle.confidence >= knee.confidence ? ankle : knee
        case let (ankle?, nil):
            return ankle
        case let (nil, knee?):
            return knee
        case (nil, nil):
            return nil
        }
    }

    private static func fallbackAxis(
        source: BoardFallbackSource,
        first: PoseJointPoint?,
        second: PoseJointPoint?,
        sourceWeight: Double,
        originalStatus: BoardEdgeStatus,
        config: BoardEdgeConfig
    ) -> FallbackAxis? {
        guard let first, let second else { return nil }

        let pointConfidence = (first.confidence + second.confidence) / 2
        guard pointConfidence >= config.fallbackPairConfidenceFloor else { return nil }

        let dx = second.x - first.x
        let dy = second.y - first.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > 0.001 else { return nil }

        let geometryConfidence = min(1, max(0, distance * config.fallbackGeometryScale))
        let confidence = pointConfidence * geometryConfidence * sourceWeight
        guard confidence >= config.fallbackConfidenceFloor else { return nil }

        var degrees = abs(atan2(dy, dx) * 180 / Double.pi)
        if degrees > 90 { degrees = 180 - degrees }

        return FallbackAxis(
            source: source,
            axisAngle: degrees,
            centerX: (first.x + second.x) / 2,
            centerY: (first.y + second.y) / 2,
            lengthRatio: distance,
            confidence: confidence,
            originalStatus: originalStatus
        )
    }

    // MARK: - 踝点

    struct AnkleCenter {
        let x: Double
        let y: Double
        let confidence: Double
    }

    static func ankleCenter(from pose: BodyPoseData, config: BoardEdgeConfig) -> AnkleCenter? {
        var points: [PoseJointPoint] = []
        if let left = pose.leftAnklePoint { points.append(left) }
        if let right = pose.rightAnklePoint { points.append(right) }
        guard !points.isEmpty else { return nil }
        let confidence = points.map(\.confidence).reduce(0, +) / Double(points.count)
        guard confidence >= config.minAnkleConfidence else { return nil }
        return AnkleCenter(
            x: points.map(\.x).reduce(0, +) / Double(points.count),
            y: points.map(\.y).reduce(0, +) / Double(points.count),
            confidence: confidence
        )
    }

    // MARK: - 前景实例

    struct InstanceMask {
        let index: Int
        let data: [UInt8]
        let alphaCount: Int
        let box: CGRect
    }

    static func foregroundInstances(cgImage: CGImage) throws -> [InstanceMask] {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else { return [] }

        var masks: [InstanceMask] = []
        for index in observation.allInstances.sorted() {
            guard let data = instanceAlpha(
                observation: observation,
                handler: handler,
                instance: index,
                width: cgImage.width,
                height: cgImage.height
            ) else { continue }
            var count = 0
            var minX = cgImage.width, maxX = 0, minY = cgImage.height, maxY = 0
            for y in 0..<cgImage.height {
                for x in 0..<cgImage.width where data[(y * cgImage.width + x) * 4 + 3] > 127 {
                    count += 1
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
            guard count > 0 else { continue }
            let box = CGRect(
                x: Double(minX) / Double(cgImage.width),
                y: Double(minY) / Double(cgImage.height),
                width: Double(maxX - minX + 1) / Double(cgImage.width),
                height: Double(maxY - minY + 1) / Double(cgImage.height)
            )
            masks.append(InstanceMask(index: index, data: data, alphaCount: count, box: box))
        }
        return masks
    }

    private static func instanceAlpha(
        observation: VNInstanceMaskObservation,
        handler: VNImageRequestHandler,
        instance: Int,
        width: Int,
        height: Int
    ) -> [UInt8]? {
        guard let pixelBuffer = try? observation.generateMaskedImage(
            ofInstances: IndexSet(integer: instance),
            from: handler,
            croppedToInstancesExtent: false
        ) else { return nil }
        let ci = CIImage(cvPixelBuffer: pixelBuffer).oriented(.downMirrored)
        guard let masked = CIContext().createCGImage(
            ci,
            from: CGRect(x: 0, y: 0, width: width, height: height)
        ) else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(masked, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    // MARK: - 实例归属

    static func poseBodyBox(_ pose: BodyPoseData) -> CGRect? {
        let points = [
            pose.leftShoulderPoint, pose.rightShoulderPoint,
            pose.leftHipPoint, pose.rightHipPoint,
            pose.leftKneePoint, pose.rightKneePoint,
            pose.leftAnklePoint, pose.rightAnklePoint
        ].compactMap { $0 }
        guard !points.isEmpty else { return nil }
        let minX = points.map(\.x).min()!
        let maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!
        let maxY = points.map(\.y).max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func selectSubjectInstance(
        _ instances: [InstanceMask],
        poseBox: CGRect?,
        config: BoardEdgeConfig
    ) -> InstanceMask? {
        guard let poseBox, poseBox.width > 0, poseBox.height > 0 else {
            // 无姿态框可比对时，取最大主体作为保守选择。
            return instances.max { $0.alphaCount < $1.alphaCount }
        }
        var best: (mask: InstanceMask, overlap: Double)?
        for instance in instances {
            let overlap = iou(poseBox, instance.box)
            if overlap >= config.minInstanceOverlap,
               best == nil || overlap > best!.overlap {
                best = (instance, overlap)
            }
        }
        return best?.mask
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        guard inter.width > 0, inter.height > 0 else { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        guard unionArea > 0 else { return 0 }
        return Double(interArea / unionArea)
    }

    // MARK: - 站姿判定

    /// 返回 nil 表示证据不足（关键点缺失）无法判定；true 站立；false 摔倒/坐姿。
    static func postureStatus(pose: BodyPoseData, config: BoardEdgeConfig) -> Bool? {
        guard let shoulder = midpoint(pose.leftShoulderPoint, pose.rightShoulderPoint),
              let hip = midpoint(pose.leftHipPoint, pose.rightHipPoint) else {
            return nil
        }
        let trunkTilt = atan2(abs(shoulder.x - hip.x), abs(shoulder.y - hip.y)) * 180 / .pi
        if trunkTilt > config.maxTrunkTilt { return false }

        if let ankle = midpoint(pose.leftAnklePoint, pose.rightAnklePoint) {
            // Vision 坐标 y 向上：坐姿时髋部不高于踝。
            if hip.y < ankle.y { return false }
        }
        return true
    }

    private static func midpoint(_ a: PoseJointPoint?, _ b: PoseJointPoint?) -> (x: Double, y: Double)? {
        switch (a, b) {
        case let (a?, b?): return ((a.x + b.x) / 2, (a.y + b.y) / 2)
        case let (a?, nil): return (a.x, a.y)
        case let (nil, b?): return (b.x, b.y)
        default: return nil
        }
    }

    // MARK: - 踝下 ROI PCA

    static func axisGeometry(
        alpha: [UInt8],
        width: Int,
        height: Int,
        ankleX: Double,
        ankleY: Double,
        config: BoardEdgeConfig
    ) -> AxisGeometry {
        let x0 = max(0, Int((ankleX - config.roiHalfWidth) * Double(width)))
        let x1 = min(width, Int((ankleX + config.roiHalfWidth) * Double(width)))
        let y0 = max(0, Int((ankleY - config.roiBottomOffset) * Double(height)))
        let y1 = min(height, Int((ankleY + config.roiTopOffset) * Double(height)))

        guard x1 > x0, y1 > y0 else {
            return AxisGeometry(pixelCount: 0, angle: nil, elongation: 0,
                                lengthRatio: 0, centerX: ankleX, centerY: ankleY)
        }

        var sumX = 0.0, sumY = 0.0, count = 0.0
        for y in y0..<y1 {
            let row = y * width
            for x in x0..<x1 where alpha[(row + x) * 4 + 3] > 127 {
                sumX += Double(x)
                sumY += Double(y)
                count += 1
            }
        }

        guard count >= Double(config.minAxisPixels) else {
            return AxisGeometry(pixelCount: Int(count), angle: nil, elongation: 0,
                                lengthRatio: 0, centerX: ankleX, centerY: ankleY)
        }

        let meanX = sumX / count
        let meanY = sumY / count
        var cxx = 0.0, cyy = 0.0, cxy = 0.0
        for y in y0..<y1 {
            let row = y * width
            for x in x0..<x1 where alpha[(row + x) * 4 + 3] > 127 {
                let dx = Double(x) - meanX
                let dy = Double(y) - meanY
                cxx += dx * dx
                cyy += dy * dy
                cxy += dx * dy
            }
        }
        cxx /= count
        cyy /= count
        cxy /= count

        let trace = cxx + cyy
        let discriminant = sqrt(max(0, trace * trace / 4 - (cxx * cyy - cxy * cxy)))
        let lambda1 = trace / 2 + discriminant
        let lambda2 = max(trace / 2 - discriminant, 1e-9)
        let radians = atan2(2 * cxy, cxx - cyy) / 2
        var degrees = abs(radians * 180 / Double.pi)
        if degrees > 90 { degrees = 180 - degrees }

        return AxisGeometry(
            pixelCount: Int(count),
            angle: degrees,
            elongation: sqrt(lambda1 / lambda2),
            lengthRatio: 2 * sqrt(lambda1) / Double(width),
            centerX: meanX / Double(width),
            centerY: meanY / Double(height)
        )
    }
}
