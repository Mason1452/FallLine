import AVFoundation
import CoreMedia
import CoreImage
import Vision

// MARK: - 分析错误

/// 视频分析过程中可能产生的高层错误。
///
/// CLI 路径通常不会遇到（NE 环境稳定），主要供 iOS/沙箱环境使用。
public enum AnalysisError: LocalizedError {
    /// Vision 神经网络推理上下文创建失败（如 "Failed to create espresso context"），
    /// 熔断阈值内连续失败达到 `consecutiveFailures` 帧
    case visionUnavailable(consecutiveFailures: Int, underlying: String)
    /// 视频完整分析结束但零可用帧
    case noReliableFrames

    public var errorDescription: String? {
        switch self {
        case .visionUnavailable(let count, _):
            return "视觉识别服务暂不可用（连续 \(count) 帧初始化失败）。请尝试重启 App 或设备后重试；如仍失败，请确认在 iOS 17+ 真机上运行。"
        case .noReliableFrames:
            return "未能从视频中提取到有效的姿态帧，请确认视频中人物清晰可见。"
        }
    }
}

// MARK: - 视频分析器（纯库版本，无控制台输出）

/// 负责视频抽帧、组装分析流程、生成全视频总结
///
/// 使用 `VisionFrameAnalyzer` → `PoseMetricsCalculator` → `PoseScorer` 的管线。
/// 此库版本不包含任何 `print()` 调用或文件系统假定。
public class VideoAnalyzer {
    public let videoURL: URL
    public let asset: AVAsset

    // 分析管线
    private let frameAnalyzer: VisionFrameAnalyzer
    private let metricsCalculator: PoseMetricsCalculator
    private let poseScorer: PoseScorer

    /// 采样间隔（秒）。默认 0.2 = 每秒分析五帧
    public let sampleInterval: Double
    /// 最大帧尺寸。nil 表示使用视频原始分辨率
    private let maxFrameSize: CGSize?

    /// 并行帧分析的批次大小
    private let batchSize: Int
    /// 光流缓存帧的最大尺寸，超过则下采样（nil = 不限制）
    private let flowFrameMaxSize: CGSize?

    /// 是否启用板身刃线检测（Phase 1 诊断能力，默认关）。
    /// 启用后逐帧在抽帧原图上跑前景分割 + 踝下 ROI PCA，结果写入
    /// `DetectionResult.boardEdgeObservation`（诊断字段，不参与评分）。
    public let enableBoardEdge: Bool
    /// 板身刃线检测门控配置（仅 `enableBoardEdge` 时使用）。
    private let boardEdgeConfig: BoardEdgeConfig

    /// 光流分析用帧缓存（仅缓存姿态检测成功的帧）
    private var frameCache: [(image: CGImage, pose: BodyPoseData)] = []
    /// 帧缓存对应的时间（与 frameCache 一一对应）
    private var frameCacheTimes: [Double] = []
    /// 光流行进方向缓存（由 computeFlowMetrics() 在一次光流遍历中填充）
    private var cachedTravelDirections: [(time: Double, angle: Double, confidence: Double)] = []

    /// 初始化分析器
    /// - Parameters:
    ///   - videoURL: 视频文件的 URL
    ///   - pointConfidenceThreshold: 关键点检测置信度阈值（默认 0.3）
    ///   - sampleInterval: 采样间隔秒数（默认 1/30 秒 = 30fps；旧默认 0.2 秒 = 5fps 时序精度过低，
    ///     20ms 事件偏差 → 20° 膝角误差，故升至 30fps）
    ///   - maxFrameSize: 最大帧分辨率，nil 使用视频原始尺寸（默认 1920x1080）
    ///   - visionOptions: Vision 请求选项（默认仅姿态检测）
    ///   - batchSize: 并行分析批次大小（默认 8）
    ///   - flowFrameMaxSize: 光流缓存帧最大尺寸（默认 640x480）
    public init(
        videoURL: URL,
        pointConfidenceThreshold: VNConfidence = 0.3,
        sampleInterval: Double = 1.0 / 30.0,
        maxFrameSize: CGSize? = CGSize(width: 1920, height: 1080),
        visionOptions: VisionAnalysisOptions = .skiAnalysis,
        batchSize: Int = 8,
        flowFrameMaxSize: CGSize? = CGSize(width: 640, height: 480),
        enableBoardEdge: Bool = false,
        boardEdgeConfig: BoardEdgeConfig = .standard
    ) {
        self.videoURL = videoURL
        self.asset = AVAsset(url: videoURL)
        self.sampleInterval = max(1.0 / 60.0, sampleInterval)
        self.maxFrameSize = maxFrameSize
        self.batchSize = max(1, batchSize)
        self.flowFrameMaxSize = flowFrameMaxSize
        self.enableBoardEdge = enableBoardEdge
        self.boardEdgeConfig = boardEdgeConfig
        self.frameAnalyzer = VisionFrameAnalyzer(options: visionOptions)
        self.metricsCalculator = PoseMetricsCalculator(pointConfidenceThreshold: pointConfidenceThreshold)
        self.poseScorer = PoseScorer()
    }

    // MARK: - 主分析流程

    /// iOS/沙箱友好的分析入口：包裹 `analyze()`，附带 Vision 预热 + CPU 回退 + 熔断。
    ///
    /// 与 `analyze()` 的区别：
    /// - 分析前先跑一次 `warmUp()`。若失败且错误属于 espresso/CSU/MPSGraph 类，则自动切换到 CPU 后备并再预热一次；仍失败则抛 `AnalysisError.visionUnavailable`。
    /// - 分析结束后若产出 0 帧，抛 `AnalysisError.noReliableFrames`。
    /// - 熔断/CPU 回退全部在 `warmUp` 阶段完成；主循环内部（`analyze()` 已使用并行 taskGroup）保持原容错逻辑。
    ///
    /// CLI 路径可继续调用 `analyze()`；iOS 建议调用此方法。
    public func analyzeWithResilience(progressHandler: ((Double) -> Void)? = nil) async throws -> [DetectionResult] {
        // 三段式预热：
        //   1) Neural Engine 直接成功 → 继续
        //   2) NE 失败但属 espresso 类 → 切 CPU 再预热
        //   3) CPU 也失败 → 立即熔断
        do {
            try await frameAnalyzer.warmUp()
        } catch {
            let message = error.localizedDescription
            if Self.isVisionInitFailure(message) {
                frameAnalyzer.usesCPUOnly = true
                do {
                    try await frameAnalyzer.warmUp()
                } catch {
                    throw AnalysisError.visionUnavailable(
                        consecutiveFailures: 1,
                        underlying: error.localizedDescription
                    )
                }
            }
            // 非 espresso 类错误：交给主循环按帧处理（可能是一次性偶发错误）
        }

        let results = try await analyze(progressHandler: progressHandler)
        if results.isEmpty {
            throw AnalysisError.noReliableFrames
        }
        return results
    }

    /// 判断错误信息是否对应 Vision/Espresso 初始化失败。
    ///
    /// 已知模式：
    /// - "Failed to create espresso context"（Neural Engine / CoreML 上下文初始化失败）
    /// - "CSU exception"（Vision 内部子系统抛出，通常伴随 espresso 错误）
    /// - "MPSGraph"（Metal Performance Shaders Graph 后备失败）
    public static func isVisionInitFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("espresso")
            || lower.contains("csu exception")
            || lower.contains("mpsgraph")
    }

    /// 分析视频，按 `sampleInterval` 抽帧
    /// - Parameter progressHandler: 进度回调（0.0~1.0），可选
    /// - Returns: 每帧的检测结果数组
    public func analyze(progressHandler: ((Double) -> Void)? = nil) async throws -> [DetectionResult] {
        frameCache.removeAll(keepingCapacity: true)
        frameCacheTimes.removeAll(keepingCapacity: true)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw NSError(domain: "VideoAnalyzer", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "视频中没有视频轨道"])
        }

        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        var results: [DetectionResult] = []

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        if let maxSize = maxFrameSize {
            imageGenerator.maximumSize = maxSize
        }

        var currentTime: Double = 0.0
        var globalIndex = 0

        while currentTime < totalSeconds {
            // 1. 批次内顺序提取帧（AVAssetImageGenerator 非线程安全）
            var batch: [(index: Int, cgImage: CGImage, time: CMTime)] = []
            for _ in 0..<batchSize where currentTime < totalSeconds {
                let time = CMTime(seconds: currentTime, preferredTimescale: 600)
                do {
                    let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                    batch.append((globalIndex, cgImage, time))
                } catch {
                    results.append(DetectionResult(
                        time: currentTime,
                        objects: [], faces: [], textObservations: [], sceneClassifications: [],
                        bodyPose: BodyPoseData(
                            detected: false, visibility: .none,
                            bodyLeanAngle: nil, leftBodyLeanAngle: nil, rightBodyLeanAngle: nil,
                            leftKneeBendAngle: nil, rightKneeBendAngle: nil,
                            leftCalfLeanAngle: nil, rightCalfLeanAngle: nil,
                            centerOfGravity: nil
                        ),
                        poseScore: nil,
                        error: "帧提取失败: \(error.localizedDescription)"
                    ))
                }
                currentTime += sampleInterval
                globalIndex += 1
            }

            guard !batch.isEmpty else { continue }

            // 2. 批次内并行分析
            let batchResults: [(Int, DetectionResult)] = try await withThrowingTaskGroup(
                of: (Int, DetectionResult).self
            ) { group in
                for item in batch {
                    group.addTask {
                        do {
                            let result = try await self.analyzeFrame(cgImage: item.cgImage, at: item.time)
                            return (item.index, result)
                        } catch {
                            return (item.index, DetectionResult(
                                time: CMTimeGetSeconds(item.time),
                                objects: [], faces: [], textObservations: [], sceneClassifications: [],
                                bodyPose: BodyPoseData(
                                    detected: false, visibility: .none,
                                    bodyLeanAngle: nil, leftBodyLeanAngle: nil, rightBodyLeanAngle: nil,
                                    leftKneeBendAngle: nil, rightKneeBendAngle: nil,
                                    leftCalfLeanAngle: nil, rightCalfLeanAngle: nil,
                                    centerOfGravity: nil
                                ),
                                poseScore: nil,
                                error: "帧分析失败: \(error.localizedDescription)"
                            ))
                        }
                    }
                }
                var collected: [(Int, DetectionResult)] = []
                for try await pair in group {
                    collected.append(pair)
                }
                return collected.sorted(by: { $0.0 < $1.0 })
            }

            // 3. 按时间顺序追加结果并更新帧缓存
            for (index, result) in batchResults {
                results.append(result)
                if result.bodyPose.detected && result.bodyPose.visibility != .none,
                   let item = batch.first(where: { $0.index == index }) {
                    let cachedImage = downscaleImageForFlow(item.cgImage)
                    frameCache.append((cachedImage, result.bodyPose))
                    frameCacheTimes.append(result.time)
                }
            }

            progressHandler?(min(currentTime / totalSeconds, 1.0))
        }

        // 时序平滑：对全部帧的姿态角度应用 1€ Filter，再重新计算评分
        // 消除 Vision 逐帧检测抖动，避免 motionStability 惩罚被抖动放大
        //
        // 方案 α（2026-09-11 默认开）：confidence-aware 滤波已翻为默认路径
        // （把 smoothConfidenceWeight(m.confidence) 传给 OneEuroFilter 的 weight
        // 参数）。历史行为可通过 `FALLLINE_CONFIDENCE_AWARE=0/false/off/no` 强制回退。
        // 主 corpus A/B 表明本开关对 evidenceCap 阈值命中样本影响集中在 video 4/ON
        // 附近，配合上一轮 [edge evidence cap ramp](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-11-evidence-cap-ramp-softening-design.md)
        // 后 -13 分掉档被软化到 -4.7 分（“中级 → 高级”）。
        let smoothingConfig: PoseSmoother.Config = {
            let raw = ProcessInfo.processInfo.environment["FALLLINE_CONFIDENCE_AWARE"] ?? ""
            let disabled = ["0", "false", "off", "no"].contains(raw.lowercased())
            return PoseSmoother.Config(useConfidenceAwareFiltering: !disabled)
        }()
        let smoothed = PoseSmoother.smooth(results, scorer: poseScorer, config: smoothingConfig)
        return smoothed
    }

    // MARK: - 单帧分析

    /// 分析单帧图像
    private func analyzeFrame(cgImage: CGImage, at time: CMTime) async throws -> DetectionResult {
        // Step 1: Vision 请求
        let raw = try await frameAnalyzer.analyze(cgImage: cgImage)

        // Step 2: 提取检测结果
        var objects: [ObjectItem] = []
        for human in raw.humanDetections {
            objects.append(ObjectItem(label: "人", confidence: human.confidence))
        }

        // 人脸检测
        var faces: [FaceItem] = []
        for face in raw.faceDetections {
            faces.append(FaceItem(
                x: Double(face.boundingBox.origin.x),
                y: Double(face.boundingBox.origin.y),
                width: Double(face.boundingBox.width),
                height: Double(face.boundingBox.height)
            ))
        }

        // 文字识别
        var textObservations: [String] = []
        for observation in raw.textObservations {
            if let text = observation.topCandidates(1).first?.string, text.count > 2 {
                textObservations.append(text)
            }
        }

        // 场景分类
        let sceneClassifications: [SceneItem] = raw.sceneClassifications
            .filter { $0.confidence > 0.3 }
            .map { SceneItem(label: $0.identifier, confidence: $0.confidence) }

        // Step 3: 姿态指标计算
        let bodyPose: BodyPoseData
        if let observation = raw.bodyPoseObservation {
            let pose2D = metricsCalculator.compute(from: observation)
            // 若同帧有 3D 观测，融合膝弯角（其他角度暂保留 2D 以保持评分曲线稳定）
            if #available(macOS 14.0, iOS 17.0, *) {
                bodyPose = PoseMetrics3DAdapter.fuse(base2D: pose2D, with: raw.bodyPose3DObservation)
            } else {
                bodyPose = pose2D
            }
        } else {
            bodyPose = BodyPoseData(
                detected: false,
                visibility: .none,
                bodyLeanAngle: nil,
                leftBodyLeanAngle: nil,
                rightBodyLeanAngle: nil,
                leftKneeBendAngle: nil,
                rightKneeBendAngle: nil,
                leftCalfLeanAngle: nil,
                rightCalfLeanAngle: nil,
                centerOfGravity: nil
            )
        }

        // Step 4: 评分
        let poseScore = poseScorer.score(pose: bodyPose)
        let visualBoardObservation = BoardVisualLineDetector.detect(cgImage: cgImage, pose: bodyPose)

        // Phase 1 诊断：板身刃线检测（默认关）。仅写诊断字段，不接触评分。
        // 诊断失败须局部隔离，不能拖垮同帧已成功的姿态/评分结果。
        let boardEdgeObservation: BoardEdgeObservation?
        if enableBoardEdge {
            boardEdgeObservation = (try? BoardEdgeDetector.detect(
                cgImage: cgImage,
                pose: bodyPose,
                config: boardEdgeConfig
            )) ?? BoardEdgeObservation(status: .noMask)
        } else {
            boardEdgeObservation = nil
        }

        return DetectionResult(
            time: CMTimeGetSeconds(time),
            objects: objects,
            faces: faces,
            textObservations: textObservations,
            sceneClassifications: sceneClassifications,
            bodyPose: bodyPose,
            poseScore: poseScore,
            visualBoardObservation: visualBoardObservation,
            boardEdgeObservation: boardEdgeObservation
        )
    }

    // MARK: - 全视频总结

    /// 根据所有帧的分析结果生成全视频总结
    public func generateSummary(from results: [DetectionResult]) async -> VideoSummary? {
        let reliableFrames = reliablePoseFrames(from: results)
        let scoreEntries = reliableFrames.compactMap { result -> (time: Double, score: Double, confidence: Double)? in
            guard let poseScore = result.poseScore else { return nil }
            return (result.time, poseScore.totalScore, max(0.01, poseScore.totalConfidence))
        }
        guard !scoreEntries.isEmpty else { return nil }

        let rawAvg = weightedAverage(scoreEntries.map { ($0.score, $0.confidence) })
        let bestThirdAvg = bestThirdAverage(scoreEntries.map { ($0.score, $0.confidence) })
        let std = weightedStandardDeviation(scoreEntries.map { ($0.score, $0.confidence) }, mean: rawAvg)
        // 总分一致性只解释评分波动，不代表真实动作稳定性。
        let scoreConsistencyScore = clamp(100 - std * 10, lower: 0, upper: 100)
        let stabilityScore = calculateMotionStability(from: reliableFrames)
        let stableBaseline = stableCarvingBaseline(from: results, motionStability: stabilityScore)
        let uncappedAverage = max(bestThirdAvg, stableBaseline?.adjustedAverageScore ?? 0)
        let techniqueCappedAverage = applyEdgeEvidenceCaps(
            score: uncappedAverage,
            reliableFrames: reliableFrames,
            stableBaseline: stableBaseline,
            stability: stabilityScore
        )
        let boardCappedAverage = applyBoardEvidenceCaps(
            score: techniqueCappedAverage,
            reliableFrames: reliableFrames,
            stableBaseline: stableBaseline
        )
        let avg = applyEvidenceCaps(
            score: boardCappedAverage,
            reliableFrames: reliableFrames
        )

        // 光流调制
        let flowMetrics = await computeFlowMetrics()
        let flowCalculator = FlowMetricsCalculator(sampleInterval: sampleInterval)

        // P0 (2026-09-15) Flow Modulation Edge-Confidence Gating：走刃证据置信度门控
        // - boardKinematicConfidence < 0.30 时，令 modulation = min(mod, 1.0)——只允许向下修正
        // - evidenceCappedScore < 60 时，方案 (c) 低分保护关闭门控，保留 flow ×1.05 加成
        //   避免"中级 60 / 初级 58"跨档伤害（v1 corpus 场景）
        let boardKinematicConfidence = flowMetrics.framePairsUsed >= 2
            ? computeBoardKinematicConfidence(
                from: reliableFrames,
                flowTravelDirections: cachedTravelDirections
            )
            : 1.0

        let flowModulationFactor = flowMetrics.framePairsUsed >= 2
            ? flowCalculator.computeModulation(
                coherence: flowMetrics.motionCoherence,
                stability: flowMetrics.directionalStability,
                smoothness: flowMetrics.velocitySmoothness,
                poseScore: avg,
                boardKinematicConfidence: boardKinematicConfidence,
                evidenceCappedScore: avg
            )
            : 1.0
        let modulatedScore = clamp(avg * flowModulationFactor, lower: 0, upper: 100)

        // P0 (2026-09-15) 报告透明度：仅在门控**实际 kill 了上行加成**时标记 gated=true。
        // 判定 = boardC<0.30 && coherence>70 且未走方案 (c) 低分保护路径。
        // 语义与 [FlowMetricsCalculator.computeModulation](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift#L325-L354) 内的 gateActive 决策严格一致。
        // - v4/v6 场景（capped ≥60 且 coherence 高）：gated=true，报告端追加"（走刃证据不足，未加成）"
        // - v1 场景（capped<60 触发低分保护）：flow ×1.05 实际保留 → gated=false，报告不误标
        // - v2/v3/v5 场景：coherence 未越阈值或 boardC≥0.30 → gated=false
        // - 无光流数据（framePairsUsed<2）：gated=nil，报告端不显示门控标记
        let flowModulationGated: Bool? = {
            guard flowMetrics.framePairsUsed >= 2 else { return nil }
            let gateActive = boardKinematicConfidence < flowCalculator.boardKinematicConfidenceGateThreshold
            let protectionActive = avg < flowCalculator.flowGateLowScoreProtectionThreshold
            let hasUpwardBoost = flowMetrics.motionCoherence > flowCalculator.coherenceBoostThreshold
            return gateActive && !protectionActive && hasUpwardBoost
        }()

        // 找最佳/最差帧（仍基于原始姿态分，光流不改变帧级判断）
        var best = (time: 0.0, score: -1.0)
        var worst = (time: 0.0, score: 101.0)

        for entry in scoreEntries {
            if entry.score > best.score { best = (entry.time, entry.score) }
            if entry.score < worst.score { worst = (entry.time, entry.score) }
        }

        let overallLevel: String = {
            switch modulatedScore {
            case 85...100: return "专业"
            case 75..<85:  return "高级"
            case 60..<75:  return "中级"
            default:       return "初级"
            }
        }()

        // 板轴刃线连续性时序聚合（ADR-004，§12.15；纯诊断，仅板边启用时运行，不参与评分）。
        // 行进方向按精确时间戳对齐到全量 results（无匹配帧为 nil，折叠窗缺方向信号时保守拒绝）。
        let boardTrajectory: BoardTrajectoryMetrics? = {
            guard enableBoardEdge else { return nil }
            let directionByTime = Dictionary(
                cachedTravelDirections.map { ($0.time, $0.angle) },
                uniquingKeysWith: { first, _ in first }
            )
            let alignedDirections = results.map { directionByTime[$0.time] }
            return BoardTemporalAxisAggregator.aggregate(
                frames: results,
                travelDirections: alignedDirections,
                sampleInterval: sampleInterval,
                config: boardEdgeConfig
            )
        }()

        return VideoSummary(
            averageScore: modulatedScore,
            bestFrame: FrameScore(
                time: best.time,
                timeString: formatTime(seconds: best.time),
                score: best.score
            ),
            worstFrame: FrameScore(
                time: worst.time,
                timeString: formatTime(seconds: worst.time),
                score: worst.score
            ),
            stabilityScore: stabilityScore,
            scoreConsistencyScore: scoreConsistencyScore,
            scoreStdDev: std,
            overallLevel: overallLevel,
            rawPoseAverageScore: rawAvg,
            bestThirdAverageScore: bestThirdAvg,
            evidenceCappedScore: avg,
            flowModulationFactor: flowModulationFactor,
            flowFramePairsUsed: flowMetrics.framePairsUsed,
            flowMotionCoherence: flowMetrics.framePairsUsed >= 2 ? flowMetrics.motionCoherence : nil,
            flowDirectionalStability: flowMetrics.framePairsUsed >= 2 ? flowMetrics.directionalStability : nil,
            flowVelocitySmoothness: flowMetrics.framePairsUsed >= 2 ? flowMetrics.velocitySmoothness : nil,
            flowModulationGated: flowModulationGated,
            boardTrajectory: boardTrajectory
        )
    }

    private func bestThirdAverage(_ values: [(value: Double, weight: Double)]) -> Double {
        guard !values.isEmpty else { return 0 }
        let selectedCount = max(1, Int(ceil(Double(values.count) / 3.0)))
        let selected = values.sorted { $0.value > $1.value }.prefix(selectedCount)
        return weightedAverage(Array(selected))
    }

    private func applyEvidenceCaps(score: Double, reliableFrames: [DetectionResult]) -> Double {
        let reliableDuration = sampledDuration(fromTimes: reliableFrames.map(\.time))
        return min(score, VideoAnalyzer.durationCapValue(for: reliableDuration))
    }

    private func applyEdgeEvidenceCaps(
        score: Double,
        reliableFrames: [DetectionResult],
        stableBaseline: StableCarvingBaseline?,
        stability: Double
    ) -> Double {
        // 稳定刻滑基线是低姿态/大倒伏误识别的保护通道，不再用小腿代理二次封顶。
        guard stableBaseline == nil else { return score }

        guard let averageEdgeEvidence = averageEdgeEvidenceScore(from: reliableFrames) else {
            return min(score, 65)
        }

        let evidenceCap = VideoAnalyzer.edgeEvidenceCapValue(for: averageEdgeEvidence)

        // §4.1 双维兜底：即便 calfLean 越过 [30,42] ramp（>=42 放行），若复合
        // “走刃质量”仍低于阈值，说明重心/膝盖/对称拖累，不能直通高分档。
        let averageEdgeQuality = averageEdgeQualityScore(
            from: reliableFrames,
            stability: stability
        )
        let edgeQualityCap = VideoAnalyzer.edgeQualityCapValue(for: averageEdgeQuality)

        return min(score, evidenceCap, edgeQualityCap)
    }

    /// Piecewise linear ramp 替代旧的 4 档阶梯 cap（P2 悬崖软化，2026-09-11 落地）。
    ///
    /// Tick 4 (2026-09-15) edge-first 重构：Tick 2 权重重分配 + Tick 3 sigmoid
    /// 让 `calfLeanScore` 已经在 raw 分层就主导"扫雪 vs 刻滑"，edge cap 不再充当
    /// 分档矫正器，退居为**极端不足兜底**（仅在 avgEdge 极低时才启动）。
    ///
    /// 新曲线（旧 3 段悬崖 → 单段兜底 ramp）：
    ///   - `edge < 30` → 62（保守封顶，等价旧 sparseReliableScoreCap）
    ///   - `edge ∈ [30, 42]` → linearRamp(62 → 100)（12 分过渡带）
    ///   - `edge ≥ 42` → 100（无 cap）
    ///
    /// 阈值 30 = sigmoid 下"平均 calf ≈ 27°"，代表全程扫雪；阈值 42 = "平均
    /// calf ≈ 33°"，代表已经具备基础立刃能力。旧曲线（37/38/40/42/50）已被
    /// Tick 3 sigmoid 的 raw 分变化淘汰。
    ///
    /// 详见 [docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md) §4.3。
    static func edgeEvidenceCapValue(for edge: Double) -> Double {
        if edge < 30 { return 62 }
        if edge < 42 { return linearRamp(edge, x0: 30, x1: 42, y0: 62, y1: 100) }
        return 100
    }

    /// §4.1 edgeQuality 双维兜底 ramp（2026-09-15 落地）。
    ///
    /// 背景：edge-first + sigmoid c=40 后，`calfLeanScore`（即上方 edge 输入）
    /// 单独越过 [30,42] ramp 就能把综合分拉到 80+，但教练视角的“搓雪弯”样本
    /// （BAD_ACC）其复合“走刃质量”仅 57 却被放到 83。引入复合 edgeQuality
    /// 作为第二道独立护栏：
    ///   - `edgeQuality < 57` → 72（典型搓雪弯，封顶回中级偏上）
    ///   - `edgeQuality ∈ [57, 61]` → linearRamp(72 → 100)（4 分窄过渡带）
    ///   - `edgeQuality ≥ 61` → 100（已具备稳定走刃，不额外限制）
    ///
    /// 阈值由 18 份样本（12 锚点 + 主 corpus 6）实测分离得到：BAD_ACC=57、
    /// v4=55 触发兜底，GOOD_A=61 恰好放行保持 86；v2/v3/v6（69-72）无影响。
    /// `nil`（无可靠数据）不施加额外 cap，由上游 65 cap 兜底。
    static func edgeQualityCapValue(for edgeQuality: Double?) -> Double {
        guard let edgeQuality else { return 100 }
        if edgeQuality < edgeQualityCapLowThreshold { return edgeQualityCapValueLow }
        if edgeQuality < edgeQualityCapHighThreshold {
            return linearRamp(
                edgeQuality,
                x0: edgeQualityCapLowThreshold,
                x1: edgeQualityCapHighThreshold,
                y0: edgeQualityCapValueLow,
                y1: 100
            )
        }
        return 100
    }

    static let edgeQualityCapLowThreshold = 57.0
    static let edgeQualityCapHighThreshold = 61.0
    static let edgeQualityCapValueLow = 72.0

    /// Duration evidence cap 的 piecewise linear ramp（P2 悬崖软化，2026-09-11 落地）。
    ///
    /// 与 [edgeEvidenceCapValue(for:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L475-L482)
    /// 同型，但用户输入是“视频总时长”，短片段本身属于结构性证据不足，**不宜整段跨越**
    /// （4s → 8s 匀速涨分会鼓励拍空镜）。折中方案：只在阈值**右侧** 0.5s 做小过渡带，
    /// 消除 “5.00s ↔ 4.99s 差 10 分” 的极端悬崖：
    ///   - 阈值 5.0s（悬崖 10 分, 55→65）→ 过渡带 [5.0, 5.5]
    ///   - 阈值 8.0s（悬崖 13 分, 65→78）→ 过渡带 [8.0, 8.5]
    ///   - 阈值 12.0s（悬崖 22 分, 78→100）→ 过渡带 [12.0, 12.5]
    ///
    /// 主 corpus 6 份视频最短时长 11.60s（video 5），与最近的过渡带 [12.0, 12.5]
    /// 之间隔 0.40s，**没有样本落入 ramp 区**。本改动是**结构性防御**，不为当前
    /// corpus 服务；预期 replay 全 delta = 0。
    ///
    /// 详见 [docs/superpowers/specs/2026-09-11-evidence-cap-ramp-softening-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-11-evidence-cap-ramp-softening-design.md) §4.2.A。
    static func durationCapValue(for duration: Double) -> Double {
        if duration < AnalysisReliability.sparseReliableScoreDuration { return 55 }
        if duration < AnalysisReliability.sparseReliableScoreDuration + 0.5 {
            return linearRamp(
                duration,
                x0: AnalysisReliability.sparseReliableScoreDuration,
                x1: AnalysisReliability.sparseReliableScoreDuration + 0.5,
                y0: 55, y1: 65
            )
        }
        if duration < AnalysisReliability.limitedReliableScoreDuration { return 65 }
        if duration < AnalysisReliability.limitedReliableScoreDuration + 0.5 {
            return linearRamp(
                duration,
                x0: AnalysisReliability.limitedReliableScoreDuration,
                x1: AnalysisReliability.limitedReliableScoreDuration + 0.5,
                y0: 65, y1: 78
            )
        }
        if duration < AnalysisReliability.fullReliableScoreDuration { return 78 }
        if duration < AnalysisReliability.fullReliableScoreDuration + 0.5 {
            return linearRamp(
                duration,
                x0: AnalysisReliability.fullReliableScoreDuration,
                x1: AnalysisReliability.fullReliableScoreDuration + 0.5,
                y0: 78, y1: 100
            )
        }
        return 100
    }

    private static func linearRamp(_ x: Double, x0: Double, x1: Double, y0: Double, y1: Double) -> Double {
        let t = (x - x0) / (x1 - x0)
        return y0 + t * (y1 - y0)
    }

    private func applyBoardEvidenceCaps(
        score: Double,
        reliableFrames: [DetectionResult],
        stableBaseline: StableCarvingBaseline?
    ) -> Double {
        guard stableBaseline == nil else { return score }
        guard let cap = boardKinematicHighScoreCap(from: reliableFrames) else { return score }
        return min(score, cap)
    }


    // MARK: - 动作稳定性

    /// 基于姿态指标的时间平滑度计算动作稳定性。
    /// 入参为已过滤的可靠帧（由 generateSummary 预计算）。
    private func calculateMotionStability(from reliableFrames: [DetectionResult]) -> Double {
        struct MotionSample {
            let time: Double
            let bodyLean: MetricWithConfidence<Double>?
            let leftKnee: MetricWithConfidence<Double>?
            let rightKnee: MetricWithConfidence<Double>?
            let leftCalf: MetricWithConfidence<Double>?
            let rightCalf: MetricWithConfidence<Double>?
            let gravityLevel: MetricWithConfidence<Double>?
        }

        let samples: [MotionSample] = reliableFrames.compactMap { result in
            guard result.bodyPose.detected, result.bodyPose.visibility != .minimal else {
                return nil
            }

            return MotionSample(
                time: result.time,
                bodyLean: result.bodyPose.bodyLeanAngle,
                leftKnee: result.bodyPose.leftKneeBendAngle,
                rightKnee: result.bodyPose.rightKneeBendAngle,
                leftCalf: result.bodyPose.leftCalfLeanAngle,
                rightCalf: result.bodyPose.rightCalfLeanAngle,
                gravityLevel: gravityLevelMetric(result.bodyPose.centerOfGravity)
            )
        }

        guard samples.count >= 2 else { return 0 }

        var weightedPenalty = 0.0
        var totalWeight = 0.0

        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            // 真实帧间时长 dt。此前使用 max(current.time - previous.time, 1.0) 将 dt 强制拉到 ≥1s，
            // 会在 <1s 采样间隔（5fps=0.2s / 30fps=0.033s）下人为削弱速度惩罚，导致运动稳定性
            // 系统性偏高。改用真实 dt，并加一个极小下限避免除零。
            let dt = max(current.time - previous.time, 1.0 / 240.0)

            // tolerancePerSecond 语义为「每秒可容忍的角度变化」。
            // 之前因为 dt 被强制拉到 ≥1s，18/28/32 实际表征的是 5fps 下每帧（0.2s）容忍值，
            // 隐含真实容忍度 ≈ 90/140/160°/s。这里回归物理量纲，保守取真实经验值：
            // 滑雪常见关节角速度峰值 30–90°/s，重心（hipRatio）单位/秒变化多在 0.3–0.5。
            addMotionPenalty(previous.bodyLean, current.bodyLean, dt: dt, tolerancePerSecond: 90, weight: 1.2,
                             weightedPenalty: &weightedPenalty, totalWeight: &totalWeight)
            addMotionPenalty(previous.leftKnee, current.leftKnee, dt: dt, tolerancePerSecond: 140, weight: 1.0,
                             weightedPenalty: &weightedPenalty, totalWeight: &totalWeight)
            addMotionPenalty(previous.rightKnee, current.rightKnee, dt: dt, tolerancePerSecond: 140, weight: 1.0,
                             weightedPenalty: &weightedPenalty, totalWeight: &totalWeight)
            addMotionPenalty(previous.leftCalf, current.leftCalf, dt: dt, tolerancePerSecond: 160, weight: 0.8,
                             weightedPenalty: &weightedPenalty, totalWeight: &totalWeight)
            addMotionPenalty(previous.rightCalf, current.rightCalf, dt: dt, tolerancePerSecond: 160, weight: 0.8,
                             weightedPenalty: &weightedPenalty, totalWeight: &totalWeight)
            addMotionPenalty(previous.gravityLevel, current.gravityLevel, dt: dt, tolerancePerSecond: 0.75, weight: 1.1,
                             weightedPenalty: &weightedPenalty, totalWeight: &totalWeight)
        }

        guard totalWeight > 0 else { return 0 }
        let averagePenalty = weightedPenalty / totalWeight
        return clamp(100 - averagePenalty, lower: 0, upper: 100)
    }

    private func addMotionPenalty(
        _ previous: MetricWithConfidence<Double>?,
        _ current: MetricWithConfidence<Double>?,
        dt: Double,
        tolerancePerSecond: Double,
        weight: Double,
        weightedPenalty: inout Double,
        totalWeight: inout Double
    ) {
        guard let previous, let current else { return }
        // 取相邻两帧置信度的较小值作为该段速度估计的置信度：一端不确定就整段不可靠。
        // 之前使用平均值 + 0.45 硬门控，会把 0.4~0.5 徘徊的关节点整段丢弃。
        // 现改用 smoothConfidenceWeight（softFloor 0.15 / softCeiling 0.75 二次曲线），
        // 与 SkiMetricsCalculator / PoseScorer 的置信度语义保持一致，
        // 让站姿视频的中低置信度段落也能按曲线加权贡献，避免因样本被丢弃而造成时间跨度变大导致的虚高速度。
        let confidence = min(previous.confidence, current.confidence)
        let confWeight = AnalysisReliability.smoothConfidenceWeight(confidence)
        guard confWeight >= 0.01 else { return }

        let velocity = abs(current.value - previous.value) / dt
        // P0-D (2026-09-07): 速度上限门控。
        //   当帧间速度超过 [Self.motionNoiseVelocityMultiplier] × tolerance 时，视为 Vision
        //   检测噪声（如 video 4 t=18.40s knee 单帧 539°/s，远超人体运动极限），
        //   直接跳过不参与惩罚计入。避免极端异常值 saturating penalty=100 拉低整段 stabilityScore。
        //   阈值 3× 的依据：滑雪场景中真实关节角速度极值约 90-140°/s（膝关节屈伸），
        //   3× tolerance = 420°/s 已远超生理极限，可安全归类为噪声。
        //   不同于置信度门控——高置信度帧也可能出现单帧位置跳变，需要速度层护栏。
        if velocity > tolerancePerSecond * Self.motionNoiseVelocityMultiplier {
            return
        }
        let penalty = clamp(velocity / tolerancePerSecond, lower: 0, upper: 1) * 100
        let effectiveWeight = weight * confWeight
        weightedPenalty += penalty * effectiveWeight
        totalWeight += effectiveWeight
    }

    /// P0-D (2026-09-07): 速度上限门控倍数。帧间速度 > tolerance × 此值时判定为噪声，跳过惩罚。
    /// 3.0 覆盖 v4 knee 539°/s、v3 bodyLean 308°/s、v6 rightCalf 308°/s 等诊断样本的极端峰值。
    private static let motionNoiseVelocityMultiplier: Double = 3.0

    /// hipRatio 已是 0~1 连续值，直接用于动作稳定性计算
    /// 注：容忍度在 addMotionPenalty 中针对连续值做了调整
    private func gravityLevelMetric(_ metric: MetricWithConfidence<Double>?) -> MetricWithConfidence<Double>? {
        return metric
    }

    // MARK: - 光流指标计算

    /// 基于缓存的帧对计算光流指标，同时缓存行进方向供后续查询。
    private func computeFlowMetrics() async -> FlowMetrics {
        guard frameCache.count >= 2 else { return .empty }

        let calculator = FlowMetricsCalculator(sampleInterval: sampleInterval)

        var pairs: [(prevImage: CGImage, prevPose: BodyPoseData, nextImage: CGImage, nextPose: BodyPoseData)] = []
        for i in 0..<(frameCache.count - 1) {
            pairs.append((
                prevImage: frameCache[i].image,
                prevPose: frameCache[i].pose,
                nextImage: frameCache[i + 1].image,
                nextPose: frameCache[i + 1].pose
            ))
        }

        let result = await calculator.computeWithDirections(from: pairs)

        // 填充行进方向缓存
        var travelDirs: [(time: Double, angle: Double, confidence: Double)] = []
        for (i, dir) in result.directions.enumerated() where dir.confidence > 0 {
            travelDirs.append((time: frameCacheTimes[i + 1], angle: dir.angle, confidence: dir.confidence))
        }
        cachedTravelDirections = travelDirs

        return result.metrics
    }

    /// 返回由 computeFlowMetrics() 缓存的光流行进方向。
    public func flowTravelDirections() -> [(time: Double, angle: Double, confidence: Double)] {
        return cachedTravelDirections
    }

    // MARK: - 走刃证据置信度（P0 2026-09-15）

    /// P0 (2026-09-15) Flow Modulation Edge-Confidence Gating：计算走刃证据置信度。
    ///
    /// 复用 [BoardDirectionAnalyzer.analyze](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardDirectionAnalyzer.swift#L17-L47) → [summary(from:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardDirectionAnalyzer.swift#L231-L258) 得到的 confidence 字段
    /// （kinematics.confidence 的均值 = center × travel confidence 均值）作为门控信号。
    ///
    /// **调用顺序取舍（spec §4.2 方案 A）**：
    /// - CLI 层 [main.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI/main.swift#L140-L143) 仍在 `generateSummary` 之后再次调用 `BoardDirectionAnalyzer.analyze`
    ///   以取得包括每帧 sideslip / smoothed frames 的完整 `BoardAnalysis`。
    /// - 这里我们只需要 summary.confidence 一个标量，且 Tick 2 目标是最小侵入切换到 6-param modulator。
    /// - 因此接受"两次 analyze"作为 P0 成本；下游可将 board 分析下沉到 VideoAnalyzer 时机重构（P1）。
    ///
    /// **回退策略**：
    /// - `flowTravelDirections` 为空或 `summary` 为 nil → 返回 `1.0`（等价无门控，与 Tick 1 旧调用路径行为一致）。
    /// - 明确不返回 0.0：0.0 会**误触发**门控 kill 上行加成，破坏"缺信号 = 不做判断"的保守语义。
    ///
    /// - Parameters:
    ///   - reliableFrames: 已过滤的可靠姿态帧（由 generateSummary 预计算）。
    ///   - flowTravelDirections: [computeFlowMetrics](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L663-L688) 缓存的行进方向；生产路径下始终非空（`framePairsUsed >= 2` 已保证）。
    /// - Returns: `[0.0, 1.0]` 的置信度；无信号时返回 1.0。
    private func computeBoardKinematicConfidence(
        from reliableFrames: [DetectionResult],
        flowTravelDirections: [(time: Double, angle: Double, confidence: Double)]
    ) -> Double {
        let analysis = BoardDirectionAnalyzer.analyze(
            frames: reliableFrames,
            flowTravelDirections: flowTravelDirections
        )
        guard let summary = analysis.summary else { return 1.0 }
        return summary.confidence
    }

    // MARK: - 图像缩放

    /// 按 flowFrameMaxSize 降采样图像，用于光流缓存。
    /// nil 参数时直接返回原图。
    private func downscaleImageForFlow(_ image: CGImage) -> CGImage {
        guard let maxSize = flowFrameMaxSize else { return image }
        let width = image.width
        let height = image.height
        guard width > Int(maxSize.width) || height > Int(maxSize.height) else { return image }

        let ciImage = CIImage(cgImage: image)
        let scale = min(maxSize.width / CGFloat(width), maxSize.height / CGFloat(height))
        let filtered = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        return context.createCGImage(filtered, from: filtered.extent) ?? image
    }

    // MARK: - 工具

    public func formatTime(seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
