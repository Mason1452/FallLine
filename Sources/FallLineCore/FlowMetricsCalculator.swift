import Foundation
import Vision
import CoreImage

// MARK: - 光流指标

/// 从光流分析中提取的三个质量指标，用于调制姿态评分。
/// 调制系数不在本结构体中存储——它依赖 poseScore 上下文，在 applyModulation 中动态计算。
public struct FlowMetrics {
    /// 运动一致性 0-100：髋部与脚踝光流方向越接近，分值越高
    public let motionCoherence: Double
    /// 方向稳定性 0-100：髋部运动方向帧间一致性，高值 = 走刃特征明显
    public let directionalStability: Double
    /// 速度平滑度 0-100：光流幅值变化率，高值 = 动作流畅
    public let velocitySmoothness: Double
    /// 参与计算的有效帧对数
    public let framePairsUsed: Int

    public init(
        motionCoherence: Double,
        directionalStability: Double,
        velocitySmoothness: Double,
        framePairsUsed: Int
    ) {
        self.motionCoherence = motionCoherence
        self.directionalStability = directionalStability
        self.velocitySmoothness = velocitySmoothness
        self.framePairsUsed = framePairsUsed
    }

    /// 空结果 — 无可用的光流数据时使用
    public static let empty = FlowMetrics(
        motionCoherence: 0,
        directionalStability: 0,
        velocitySmoothness: 0,
        framePairsUsed: 0
    )
}

// MARK: - 光流指标计算器

/// 从帧对序列计算光流质量指标，并将指标转化为姿态评分的调制系数。
///
/// 三个指标：
/// - motionCoherence: 髋部 vs 脚踝光流方向夹角 → 上下身运动一致性
/// - directionalStability: 髋部光流方向的 circular variance → 走刃/搓雪区分
/// - velocitySmoothness: 光流幅值变化率 → 动作流畅度
///
/// 调制范围 ±13%。
public struct FlowMetricsCalculator {

    // MARK: - 配置常量

    /// 光流采样时的关键点置信度最低要求
    public let minPointConfidence: Double = 0.3

    /// 调制参数
    public let coherenceBoostThreshold: Double = 70.0
    public let coherenceBoostAmount: Double = 0.05
    public let stabilityBoostThreshold: Double = 70.0
    public let stabilityBoostAmount: Double = 0.08
    public let stabilityPenaltyThreshold: Double = 30.0
    public let stabilityPenaltyAmount: Double = 0.08
    public let smoothnessPenaltyThreshold: Double = 40.0
    public let smoothnessPenaltyAmount: Double = 0.05
    /// 方向稳定性调制仅在姿态分低于此阈值时提升（避免已高分因拍摄角度被低估）
    public let stabilityBoostScoreCap: Double = 75.0
    /// 方向稳定性调制仅在姿态分高于此阈值时扣减（避免已低分再被压低）
    public let stabilityPenaltyScoreFloor: Double = 75.0

    /// 光流置信度分母（帧率归一化后的像素位移基准）。
    ///
    /// 原实现使用 `magnitude / 8.0`，其中 8.0 是在 5fps（sampleInterval=0.2s）下经验值。
    /// 30fps（sampleInterval≈0.033s）下同样运动的相邻帧像素位移只有 5fps 的 1/6，导致
    /// directionalStability / velocitySmoothness 系统性塌陷为 0。
    ///
    /// 归一化公式：magnitudeAtBaseline = magnitude × (baselineInterval / sampleInterval)，
    /// 其中 baselineInterval = 0.2s。等价于把置信度定义在「等价 5fps 下的像素位移」上。
    public let baselineFrameInterval: Double = 0.2
    public let flowConfidenceReference: Double = 8.0

    /// 采样间隔（秒），来自 VideoAnalyzer.sampleInterval。用于光流置信度分母的帧率归一化。
    /// 默认 1/30 与新的 30fps 采样对齐。
    public let sampleInterval: Double

    public init(sampleInterval: Double = 1.0 / 30.0) {
        self.sampleInterval = sampleInterval
    }

    /// 按当前帧率归一化的等价 5fps magnitude
    @inline(__always)
    private func normalizedMagnitude(_ magnitude: Double) -> Double {
        let scale = baselineFrameInterval / max(sampleInterval, 1.0 / 240.0)
        return magnitude * scale
    }

    /// 光流置信度：将像素位移归一化到基线帧率后再除以经验分母
    @inline(__always)
    private func flowConfidence(magnitude: Double) -> Double {
        return clamp(normalizedMagnitude(magnitude) / flowConfidenceReference, lower: 0, upper: 1)
    }

    // MARK: - 主入口

    /// 计算光流指标并返回 FlowMetrics
    /// - Parameter framePairs: 连续帧对数组，每项为 (前帧图像, 前帧姿态, 后帧图像, 后帧姿态)
    /// - Returns: FlowMetrics，如果帧对不足返回 .empty
    public func compute(
        from framePairs: [(prevImage: CGImage, prevPose: BodyPoseData, nextImage: CGImage, nextPose: BodyPoseData)]
    ) async -> FlowMetrics {
        let result = await computeWithDirections(from: framePairs)
        return result.metrics
    }

    /// 合并计算：一次光流遍历同时产出 FlowMetrics 和帧级行进方向。
    /// - Returns: (metrics, directions)。directions 与输入帧对一一对应，失败项 confidence=0。
    public func computeWithDirections(
        from framePairs: [(prevImage: CGImage, prevPose: BodyPoseData, nextImage: CGImage, nextPose: BodyPoseData)]
    ) async -> (metrics: FlowMetrics, directions: [(angle: Double, confidence: Double)]) {
        guard framePairs.count >= 2 else { return (.empty, []) }

        var coherenceSamples: [Double] = []
        var hipFlowDirections: [Double] = []
        var velocityChanges: [Double] = []
        var previousVelocity: Double? = nil
        var directions: [(angle: Double, confidence: Double)] = []
        directions.reserveCapacity(framePairs.count)

        for pair in framePairs {
            guard let flowVectors = await sampleFlowVectors(
                prevImage: pair.prevImage,
                nextImage: pair.nextImage,
                prevPose: pair.prevPose,
                nextPose: pair.nextPose
            ) else {
                directions.append((angle: 0, confidence: 0))
                continue
            }

            // 运动一致性：髋部 vs 脚踝方向差异越小，分值越高。
            let hipDir = atan2(flowVectors.hip.dy, flowVectors.hip.dx)
            let ankleDir = atan2(flowVectors.ankle.dy, flowVectors.ankle.dx)
            let dirDiff = abs(angleDifferenceDegrees(hipDir, ankleDir))
            let coherence = linearMap(dirDiff, inMin: 15, inMax: 60, outMin: 100, outMax: 0)
            coherenceSamples.append(coherence)

            // 髋部方向
            hipFlowDirections.append(hipDir)

            // 速度平滑度
            let velocity = sqrt(flowVectors.hip.dx * flowVectors.hip.dx + flowVectors.hip.dy * flowVectors.hip.dy)
            if let prev = previousVelocity {
                let changeRate = prev > 0 ? abs(velocity - prev) / prev : 0
                velocityChanges.append(changeRate)
            }
            previousVelocity = velocity

            // 行进方向：髋部+脚踝光流向量的平均
            let dx = (flowVectors.hip.dx + flowVectors.ankle.dx) / 2
            let dy = (flowVectors.hip.dy + flowVectors.ankle.dy) / 2
            let magnitude = sqrt(dx * dx + dy * dy)
            if magnitude > 0 {
                let angle = normalizeAngle(atan2(dy, dx) * 180 / Double.pi)
                let conf = flowConfidence(magnitude: magnitude)
                directions.append((angle: angle, confidence: conf))
            } else {
                directions.append((angle: 0, confidence: 0))
            }
        }

        guard !coherenceSamples.isEmpty else { return (.empty, directions) }

        let motionCoherence = clamp(coherenceSamples.reduce(0, +) / Double(coherenceSamples.count), lower: 0, upper: 100)
        let directionalStability = computeCircularStability(hipFlowDirections)
        let velocitySmoothness: Double
        if velocityChanges.isEmpty {
            velocitySmoothness = 50
        } else {
            let avgChange = velocityChanges.reduce(0, +) / Double(velocityChanges.count)
            velocitySmoothness = linearMap(avgChange, inMin: 0.15, inMax: 0.50, outMin: 100, outMax: 0)
        }

        return (
            metrics: FlowMetrics(
                motionCoherence: motionCoherence,
                directionalStability: directionalStability,
                velocitySmoothness: velocitySmoothness,
                framePairsUsed: framePairs.count
            ),
            directions: directions
        )
    }

    // MARK: - 调制公式

    /// 应用光流调制到原始姿态评分。
    /// 内部调用带 poseScore 上下文的 computeModulation，确保稳定性阈值判断正确。
    ///
    /// 塌陷熔断（2026-09-01 稳定性收敛，配合 scripts/stability_audit.py 量化基线）：
    /// 当 directionalStability 与 velocitySmoothness 同时为 0 时视为
    /// FlowMetricsCalculator 内部降级信号（见 computeCircularStability 的
    /// count>=2 门以及 velocitySmoothness 空样本回落），不参与调制。
    /// 单个指标为 0 由 computeModulation 内部的 > 0 守卫处理。
    public func applyModulation(poseScore: Double, metrics: FlowMetrics) -> Double {
        guard metrics.framePairsUsed >= 2 else { return poseScore }
        if metrics.directionalStability == 0 && metrics.velocitySmoothness == 0 {
            return poseScore
        }
        let factor = computeModulation(
            coherence: metrics.motionCoherence,
            stability: metrics.directionalStability,
            smoothness: metrics.velocitySmoothness,
            poseScore: poseScore
        )
        return clamp(poseScore * factor, lower: 0, upper: 100)
    }

    /// 根据三个光流指标计算调制系数（不含稳定性阈值——稳定性依赖 poseScore 上下文）。
    /// 供基础测试使用；生产环境使用带 poseScore 的重载版本。
    public func computeModulation(
        coherence: Double,
        stability: Double,
        smoothness: Double
    ) -> Double {
        var modulation = 1.0
        if coherence > coherenceBoostThreshold {
            modulation += coherenceBoostAmount
        }
        if smoothness > 0 && smoothness < smoothnessPenaltyThreshold {
            modulation -= smoothnessPenaltyAmount
        }
        return clamp(modulation, lower: 0.87, upper: 1.13)
    }

    /// 带姿态分上下文的完整调制系数（生产环境使用此版本）。
    /// stability 阈值仅在 poseScore 满足条件时触发 boost/penalty。
    ///
    /// stability / smoothness = 0 视为塌陷降级信号：penalty 分支加 > 0 守卫，
    /// 避免"工具坏了所以扣分"的错误逻辑。boost 分支保留以便未来 stability 修复
    /// 后自动恢复。塌陷双 0 由 applyModulation 早退熔断兜底。
    public func computeModulation(
        coherence: Double,
        stability: Double,
        smoothness: Double,
        poseScore: Double
    ) -> Double {
        var modulation = 1.0
        if coherence > coherenceBoostThreshold {
            modulation += coherenceBoostAmount
        }
        if stability > stabilityBoostThreshold && poseScore < stabilityBoostScoreCap {
            modulation += stabilityBoostAmount
        }
        if stability > 0 && stability < stabilityPenaltyThreshold && poseScore > stabilityPenaltyScoreFloor {
            modulation -= stabilityPenaltyAmount
        }
        if smoothness > 0 && smoothness < smoothnessPenaltyThreshold {
            modulation -= smoothnessPenaltyAmount
        }
        return clamp(modulation, lower: 0.87, upper: 1.13)
    }

    // MARK: - 光流行进方向

    /// 从帧对序列中提取每帧的行进方向。
    /// 在每个帧对的髋部+脚踝位置采样光流，平均 (dx, dy) 后转换为角度。
    /// 返回数组与输入帧对一一对应（失败项跳过，因此返回长度可能小于输入）。
    public func computeTravelDirections(
        from framePairs: [(prevImage: CGImage, prevPose: BodyPoseData, nextImage: CGImage, nextPose: BodyPoseData)]
    ) async -> [(angle: Double, confidence: Double)] {
        var directions: [(angle: Double, confidence: Double)] = []
        directions.reserveCapacity(framePairs.count)

        for pair in framePairs {
            guard let flowVectors = await sampleFlowVectors(
                prevImage: pair.prevImage,
                nextImage: pair.nextImage,
                prevPose: pair.prevPose,
                nextPose: pair.nextPose
            ) else {
                directions.append((angle: 0, confidence: 0))
                continue
            }

            let dx = (flowVectors.hip.dx + flowVectors.ankle.dx) / 2
            let dy = (flowVectors.hip.dy + flowVectors.ankle.dy) / 2
            let magnitude = sqrt(dx * dx + dy * dy)
            guard magnitude > 0 else {
                directions.append((angle: 0, confidence: 0))
                continue
            }

            let angle = normalizeAngle(atan2(dy, dx) * 180 / Double.pi)
            let confidence = flowConfidence(magnitude: magnitude)
            directions.append((angle: angle, confidence: confidence))
        }

        return directions
    }

    // MARK: - 光流采样

    /// 帧对光流关键点采样结果
    private struct FlowSample {
        let hip: (dx: Double, dy: Double)
        let ankle: (dx: Double, dy: Double)
    }

    /// 在帧对之间运行 VNGenerateOpticalFlowRequest 并在关键点位置采样光流向量
    private func sampleFlowVectors(
        prevImage: CGImage,
        nextImage: CGImage,
        prevPose: BodyPoseData,
        nextPose: BodyPoseData
    ) async -> FlowSample? {
        // 检查关键点置信度
        guard let prevHipX = prevPose.hipCenterX, prevHipX.confidence >= minPointConfidence,
              let prevHipY = prevPose.hipCenterY, prevHipY.confidence >= minPointConfidence,
              let prevAnkleX = prevPose.ankleCenterX, prevAnkleX.confidence >= minPointConfidence,
              let prevAnkleY = prevPose.ankleCenterY, prevAnkleY.confidence >= minPointConfidence else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNGenerateOpticalFlowRequest(targetedCGImage: nextImage, options: [:])
            let handler = VNImageRequestHandler(cgImage: prevImage, options: [:])

            do {
                try handler.perform([request])
                guard let result = request.results?.first as? VNPixelBufferObservation else {
                    continuation.resume(returning: nil)
                    return
                }

                let buffer = result.pixelBuffer
                let width = CVPixelBufferGetWidth(buffer)
                let height = CVPixelBufferGetHeight(buffer)

                CVPixelBufferLockBaseAddress(buffer, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

                guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
                    continuation.resume(returning: nil)
                    return
                }

                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                // 光流像素格式为 two-component float32: (dx, dy)
                let floatPtr = baseAddress.assumingMemoryBound(to: Float.self)
                let floatsPerRow = bytesPerRow / MemoryLayout<Float>.stride

                func sample(atX x: Double, y: Double) -> (dx: Double, dy: Double)? {
                    let px = Int(x * Double(width))
                    let py = Int(y * Double(height))
                    guard px >= 0, px < width, py >= 0, py < height else { return nil }
                    let offset = py * floatsPerRow + px * 2
                    return (Double(floatPtr[offset]), Double(floatPtr[offset + 1]))
                }

                guard let hipFlow = sample(atX: prevHipX.value, y: prevHipY.value),
                      let ankleFlow = sample(atX: prevAnkleX.value, y: prevAnkleY.value) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: FlowSample(hip: hipFlow, ankle: ankleFlow))
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - 数学工具

    /// 计算角度的 circular variance（0=完全一致, 1=完全随机）
    private func computeCircularStability(_ directions: [Double]) -> Double {
        guard directions.count >= 2 else { return 0 }
        var sumSin = 0.0
        var sumCos = 0.0
        for dir in directions {
            sumSin += sin(dir)
            sumCos += cos(dir)
        }
        let meanSin = sumSin / Double(directions.count)
        let meanCos = sumCos / Double(directions.count)
        let r = sqrt(meanSin * meanSin + meanCos * meanCos) // mean resultant length
        // Fix: handle NaN from floating point precision
        let variance = max(0.0, min(1.0, 1.0 - r)) // circular variance, clamped to valid range
        return linearMap(variance, inMin: 0.15, inMax: 0.50, outMin: 100, outMax: 0)
    }

    /// 两角度差（degrees）
    private func angleDifferenceDegrees(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b)
        let pi = Double.pi
        if diff > pi {
            return (2 * pi - diff) * 180.0 / pi
        }
        return diff * 180.0 / pi
    }
}
