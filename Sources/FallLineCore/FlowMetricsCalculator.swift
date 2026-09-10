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
    /// 速度平滑度 0-100：光流幅值 median(changeRate) → linearMap([0.30, 1.20]→[100, 0])。
    /// P6-A (2026-09-07)：从 avg + [0.15, 0.50] 迁移，因 avg 被单帧跳变污染导致 100% 塌陷。
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
///   （P7-A 2026-09-08：已退役评分调制，仅作报告展示——2D 光流方向不携带质量信息）
/// - velocitySmoothness: 光流幅值变化率 → 动作流畅度
///
/// 调制范围 ±13%（P7-A 后有效范围 ±5%：coherence +0.05 / smoothness -0.05）。
public struct FlowMetricsCalculator {

    // MARK: - 配置常量

    /// 光流采样时的关键点置信度最低要求
    public let minPointConfidence: Double = 0.3

    /// 调制参数
    public let coherenceBoostThreshold: Double = 70.0
    public let coherenceBoostAmount: Double = 0.05
    /// P7-A (2026-09-08)：directionalStability 已退役，不再参与评分调制。
    /// 诊断显示 6 种统计口径（全段/0.5s/1s 窗 × travelAngle/boardAngle ×
    /// variance/median delta）全部无法区分 corpus 质量排序——滑雪换刃天然
    /// 产生 ~180° 方向摆动，2D 光流方向被相机运动主导，信号源不携带质量信息。
    /// 以下 stability 常量保留仅为 API 兼容，computeModulation 已不引用。
    public let stabilityBoostThreshold: Double = 70.0
    public let stabilityBoostAmount: Double = 0.08
    public let stabilityPenaltyThreshold: Double = 30.0
    public let stabilityPenaltyAmount: Double = 0.08
    public let smoothnessPenaltyThreshold: Double = 40.0
    public let smoothnessPenaltyAmount: Double = 0.05
    /// P7-A (2026-09-08)：随 stability 调制一并退役，保留仅为 API 兼容。
    public let stabilityBoostScoreCap: Double = 75.0
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

    /// P6-B (2026-09-10): 光流窗采样半径（像素）。0 = 单点（旧行为），>=1 = (2r+1)×(2r+1) 邻域均值。
    /// 单点采样对光流噪声（局部纹理、遮挡、亚像素抖动）无免疫力，导致：
    ///   1. hipFlowDirections 的 circular variance 被随机方向污染 → directionalStability 塌陷
    ///   2. coherence 的 hip vs ankle 方向差异被单像素噪声随机抬高
    ///   3. velocity 的帧间 changeRate 被单点跳变主导 → 已在 P6-A 用 median 兜底
    /// **radius=3（7×7 = 49 采样点，2026-09-10 P6-B-r3 上调）**：radius=2 阶段 corpus 观测到
    /// 部分弱一致 / 中一致样本仍受空间噪声牵引，遂扩大窗尺寸继续压噪。radius=2 的对照数据
    /// 保留在 git 历史与 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md)。
    /// radius=0 保留是为了单测回归与紧急回退。若关节落点集中在近骨盆区（正面 / 背面
    /// 大幅遮挡），7×7 窗有轻微越界到相邻身体部位的风险，此时可用 init 参数临时降到 2。
    public let flowSampleRadius: Int

    public init(sampleInterval: Double = 1.0 / 30.0, flowSampleRadius: Int = 3) {
        self.sampleInterval = sampleInterval
        self.flowSampleRadius = max(0, flowSampleRadius)
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
        // P6-A (2026-09-07): 见 computeVelocitySmoothness 文档。
        let velocitySmoothness = computeVelocitySmoothness(fromChangeRates: velocityChanges)

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
    /// 内部调用带 poseScore 上下文的 computeModulation（P7-A 后两者行为一致）。
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

    /// 根据三个光流指标计算调制系数（不含稳定性阈值——P7-A 起 stability 不再参与调制）。
    /// 供基础测试使用；生产环境使用带 poseScore 的重载版本（行为一致）。
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
    ///
    /// P7-A (2026-09-08)：stability 分支已退役（见常量区注释），本函数与
    /// 3-param 版本行为一致，stability / poseScore 参数仅为 API 兼容保留。
    /// smoothness = 0 视为塌陷降级信号：penalty 分支加 > 0 守卫，
    /// 避免"工具坏了所以扣分"的错误逻辑。塌陷双 0 由 applyModulation 早退熔断兜底。
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
                let radius = self.flowSampleRadius

                func sample(atX x: Double, y: Double) -> (dx: Double, dy: Double)? {
                    let px = Int(x * Double(width))
                    let py = Int(y * Double(height))
                    guard px >= 0, px < width, py >= 0, py < height else { return nil }
                    // P6-B (2026-09-10): (2r+1)×(2r+1) 窗均值，边界裁剪。radius=0 退化为单点。
                    if radius == 0 {
                        let offset = py * floatsPerRow + px * 2
                        return (Double(floatPtr[offset]), Double(floatPtr[offset + 1]))
                    }
                    let x0 = max(0, px - radius)
                    let x1 = min(width - 1, px + radius)
                    let y0 = max(0, py - radius)
                    let y1 = min(height - 1, py + radius)
                    var sumDx = 0.0
                    var sumDy = 0.0
                    var count = 0
                    for sy in y0...y1 {
                        let rowBase = sy * floatsPerRow
                        for sx in x0...x1 {
                            let offset = rowBase + sx * 2
                            sumDx += Double(floatPtr[offset])
                            sumDy += Double(floatPtr[offset + 1])
                            count += 1
                        }
                    }
                    guard count > 0 else { return nil }
                    return (sumDx / Double(count), sumDy / Double(count))
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

    /// P6-B (2026-09-10): 光流窗采样纯数学函数，供单测在不依赖 CVPixelBuffer 的情况下守护窗均值行为。
    /// `field` 以 (dx, dy) 元组的行主序二维数组给出（每个元素代表一个像素的光流向量）。
    /// - 当 radius=0 时退化为单点采样（对齐旧行为）。
    /// - 边界处按 image 边界 clip，返回窗内实际落点的均值。
    /// - centerX/Y 使用整数像素坐标；越界返回 nil，与 sampleFlowVectors 内嵌 sample 语义一致。
    /// 与生产采样路径共享相同的窗遍历/边界 clip/均值语义，仅剥离了 CVPixelBuffer 与归一化坐标。
    func averageFlowWindow(
        field: [[(dx: Double, dy: Double)]],
        centerX: Int,
        centerY: Int,
        radius: Int
    ) -> (dx: Double, dy: Double)? {
        let height = field.count
        guard height > 0 else { return nil }
        let width = field[0].count
        guard width > 0, centerX >= 0, centerX < width, centerY >= 0, centerY < height else {
            return nil
        }
        if radius == 0 {
            return field[centerY][centerX]
        }
        let x0 = max(0, centerX - radius)
        let x1 = min(width - 1, centerX + radius)
        let y0 = max(0, centerY - radius)
        let y1 = min(height - 1, centerY + radius)
        var sumDx = 0.0
        var sumDy = 0.0
        var count = 0
        for sy in y0...y1 {
            for sx in x0...x1 {
                sumDx += field[sy][sx].dx
                sumDy += field[sy][sx].dy
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return (sumDx / Double(count), sumDy / Double(count))
    }

    /// P6-A (2026-09-07): 速度平滑度 = median(changeRate) → linearMap([0.30, 1.20]→[100, 0])。
    /// 用 median 替代 avg 抗离群，阈值从 [0.15, 0.50] 重标为 [0.30, 1.20]。诊断显示 6 份 corpus 中：
    ///   - avgChange ∈ [0.93, 3.47]，被 max >20 倍跳变主导；100% 塌陷为 0
    ///   - median(changeRate) ∈ [0.49, 0.83]，稳定反映真实动作变化率
    /// 新阈值锚点：0.30 = 主 corpus median 最小值，1.20 = 观测 median 最大 +45%
    /// buffer，保证正常滑行样本落在 (0, 100) 有效区，异常抖动仍能触发扣分。
    /// 空序列回落 50（中性）。internal 供单测直接验证 median 抗离群与阈值锚点。
    func computeVelocitySmoothness(fromChangeRates changes: [Double]) -> Double {
        guard !changes.isEmpty else { return 50 }
        let medianChange = medianOfChangeRates(changes)
        return linearMap(medianChange, inMin: 0.30, inMax: 1.20, outMin: 100, outMax: 0)
    }

    /// 计算 changeRate 序列的中位数。P6-A (2026-09-07) 用于替代 avg，
    /// 抵消单帧极端跳变（诊断中观测 max changeRate 75.2 vs median 0.62）对均值的污染。
    private func medianOfChangeRates(_ changes: [Double]) -> Double {
        guard !changes.isEmpty else { return 0 }
        let sorted = changes.sorted()
        let count = sorted.count
        if count % 2 == 1 {
            return sorted[count / 2]
        }
        return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
    }
}
