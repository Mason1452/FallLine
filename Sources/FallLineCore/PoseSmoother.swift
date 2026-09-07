import Foundation

/// PoseSmoother
///
/// 用 1€ Filter 对整段 `[DetectionResult]` 中的姿态角度信号做时序平滑，
/// 消除 Vision 逐帧检测的抖动，再重新调用 PoseScorer 计算每帧评分。
///
/// 平滑作用于所有 `MetricWithConfidence<Double>` 的角度/坐标字段，置信度保持不变。
/// 缺失帧（value=nil）不喂入滤波器，避免 gap 破坏时序连续性。
public enum PoseSmoother {

    /// 平滑参数（滑雪场景推荐值）。
    ///
    /// 关节角度平滑度 vs 响应速度权衡：
    /// - minCutoff 越小 → 越平滑但延迟越大
    /// - beta 越大 → 快速动作时越保留细节但抖动过滤越弱
    public struct Config {
        public let angleMinCutoff: Double
        public let angleBeta: Double
        public let coordinateMinCutoff: Double
        public let coordinateBeta: Double

        public init(
            angleMinCutoff: Double = 1.2,
            angleBeta: Double = 0.02,
            coordinateMinCutoff: Double = 1.5,
            coordinateBeta: Double = 0.03
        ) {
            self.angleMinCutoff = angleMinCutoff
            self.angleBeta = angleBeta
            self.coordinateMinCutoff = coordinateMinCutoff
            self.coordinateBeta = coordinateBeta
        }

        public static let `default` = Config()
    }

    /// 对整段检测结果做时序平滑，并用平滑后的姿态重算 PoseScore。
    /// - Parameters:
    ///   - results: 原始检测结果（按 time 升序）
    ///   - scorer: 用于重新评分的 PoseScorer
    ///   - config: 滤波器参数
    /// - Returns: 与输入等长的、平滑后的检测结果
    public static func smooth(
        _ results: [DetectionResult],
        scorer: PoseScorer,
        config: Config = .default
    ) -> [DetectionResult] {
        guard results.count >= 3 else { return results }

        // P0 预滤：对 knee/calf/lean 关节角度做 3 帧中位数预处理，抹掉孤立尖峰
        // （corpus zigzag 44~62%，表明帧间存在大量高频翻转，会击穿 1€ Filter 的自适应）。
        // P0-A: knee/calf (25% + 20% 权重)
        // P0b:  bodyLean + left/right bodyLean (20% 权重, 2026-09-03 落地)
        //       只覆盖无符号 3 组，signedBodyLean 保守留给下游 (TurnPhaseDetector 需要方向信息)
        let deSpiked = despikeJointAngles(results)

        // P4-A 短空洞插值：对 knee/calf 4 组关节做邻域中位数补值。
        // Vision 在 detected↔undetected 边界会连续几帧丢失单侧或双侧关节，
        // PoseScorer 对 nil 的处理是"缺失→0/50 阶跃"，导致评分崩塌（video 4 t=17.6~18.2s）。
        // 用邻域已有值中位数补上（confidence 衰减），既恢复分数连续性又不虚构可靠证据。
        let imputed = imputeMissingJointMetrics(deSpiked)

        // 每类信号一个滤波器组。使用不同参数以匹配信号性质。
        let angleFilters = MultiOneEuroFilter { OneEuroFilter(minCutoff: config.angleMinCutoff, beta: config.angleBeta) }
        let coordFilters = MultiOneEuroFilter { OneEuroFilter(minCutoff: config.coordinateMinCutoff, beta: config.coordinateBeta) }

        return imputed.map { detection in
            let pose = detection.bodyPose
            guard pose.detected else { return detection }

            let t = detection.time

            let smoothed = BodyPoseData(
                detected: pose.detected,
                visibility: pose.visibility,
                bodyLeanAngle: filterMetric(pose.bodyLeanAngle, key: "bodyLean", t: t, using: angleFilters),
                leftBodyLeanAngle: filterMetric(pose.leftBodyLeanAngle, key: "leftBodyLean", t: t, using: angleFilters),
                rightBodyLeanAngle: filterMetric(pose.rightBodyLeanAngle, key: "rightBodyLean", t: t, using: angleFilters),
                leftKneeBendAngle: filterMetric(pose.leftKneeBendAngle, key: "leftKnee", t: t, using: angleFilters),
                rightKneeBendAngle: filterMetric(pose.rightKneeBendAngle, key: "rightKnee", t: t, using: angleFilters),
                leftCalfLeanAngle: filterMetric(pose.leftCalfLeanAngle, key: "leftCalf", t: t, using: angleFilters),
                rightCalfLeanAngle: filterMetric(pose.rightCalfLeanAngle, key: "rightCalf", t: t, using: angleFilters),
                centerOfGravity: filterMetric(pose.centerOfGravity, key: "cog", t: t, using: coordFilters),
                signedBodyLeanAngle: filterMetric(pose.signedBodyLeanAngle, key: "signedBodyLean", t: t, using: angleFilters),
                signedCalfLeanAngle: filterMetric(pose.signedCalfLeanAngle, key: "signedCalf", t: t, using: angleFilters),
                hipCenterX: filterMetric(pose.hipCenterX, key: "hipX", t: t, using: coordFilters),
                ankleCenterX: filterMetric(pose.ankleCenterX, key: "ankleX", t: t, using: coordFilters),
                bodyCenterX: filterMetric(pose.bodyCenterX, key: "bodyX", t: t, using: coordFilters),
                hipCenterY: filterMetric(pose.hipCenterY, key: "hipY", t: t, using: coordFilters),
                ankleCenterY: filterMetric(pose.ankleCenterY, key: "ankleY", t: t, using: coordFilters),
                bodyCenterY: filterMetric(pose.bodyCenterY, key: "bodyY", t: t, using: coordFilters),
                ankleProxyBoardAngle: filterMetric(pose.ankleProxyBoardAngle, key: "boardAngle", t: t, using: angleFilters),
                leftShoulderPoint: pose.leftShoulderPoint,
                rightShoulderPoint: pose.rightShoulderPoint,
                leftHipPoint: pose.leftHipPoint,
                rightHipPoint: pose.rightHipPoint,
                leftKneePoint: pose.leftKneePoint,
                rightKneePoint: pose.rightKneePoint,
                leftAnklePoint: pose.leftAnklePoint,
                rightAnklePoint: pose.rightAnklePoint
            )

            let newScore = scorer.score(pose: smoothed)

            return DetectionResult(
                time: detection.time,
                objects: detection.objects,
                faces: detection.faces,
                textObservations: detection.textObservations,
                sceneClassifications: detection.sceneClassifications,
                bodyPose: smoothed,
                poseScore: newScore,
                visualBoardObservation: detection.visualBoardObservation,
                skiMetrics: detection.skiMetrics,
                error: detection.error
            )
        }
    }

    // MARK: - 内部

    /// P0 预滤：对关键关节/姿态角度做 3 帧中位数，抹掉孤立尖峰
    /// （Vision 逐帧检测偶发抖动 → 40°/95° 孤立跳变）。
    ///
    /// - **P0-A 覆盖** (2026-09-01): leftKnee / rightKnee / leftCalf / rightCalf（4 组）
    /// - **P0b 覆盖** (2026-09-03): bodyLean / leftBodyLean / rightBodyLean（3 组，无符号）
    /// - 保留原 confidence（滤值不改变检测可信度）
    /// - 缺失帧（value=nil）不参与中位数窗口
    /// - 边界处（前后无 3 帧）保留原值
    /// - 对连续两帧的真实峰值不敏感（median 保留主流值，滤除孤立值）
    ///
    /// **为什么不覆盖 signedBodyLeanAngle**：
    ///   下游 [TurnPhaseDetector.swift#L80](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/TurnPhaseDetector.swift#L80)
    ///   用它做左右倾判定；中位数虽保留多数派符号，但 despike 只用于评分维度，
    ///   与 phase 检测解耦更稳妥。
    private static func despikeJointAngles(_ results: [DetectionResult]) -> [DetectionResult] {
        guard results.count >= 3 else { return results }

        func extract(_ keyPath: KeyPath<BodyPoseData, MetricWithConfidence<Double>?>) -> [Double?] {
            results.map { $0.bodyPose[keyPath: keyPath]?.value }
        }
        let leftKneeMedians = medianWindow(extract(\.leftKneeBendAngle), halfWidth: kneeCalfHalfWidth)
        let rightKneeMedians = medianWindow(extract(\.rightKneeBendAngle), halfWidth: kneeCalfHalfWidth)
        let leftCalfMedians = medianWindow(extract(\.leftCalfLeanAngle), halfWidth: kneeCalfHalfWidth)
        let rightCalfMedians = medianWindow(extract(\.rightCalfLeanAngle), halfWidth: kneeCalfHalfWidth)
        // P0b (2026-09-03): 覆盖 3 组无符号 lean 角度（初版 3 帧窗）
        // P0-D (2026-09-07): lean 扩宽到 5 帧窗（半宽 2），因 stability_decomp
        //   诊断显示 bodyLean 是 v3/v4/v5/v6 的 #1 或 #2 抖动主导项，3 帧窗对
        //   连续多帧漂移（v6 27.20s 单帧 34° 跳变）无效，需要更长感受野。
        //   knee/calf 保持 3 帧窗以免削弱真实动作变化响应。
        let bodyLeanMedians = medianWindow(extract(\.bodyLeanAngle), halfWidth: leanHalfWidth)
        let leftBodyLeanMedians = medianWindow(extract(\.leftBodyLeanAngle), halfWidth: leanHalfWidth)
        let rightBodyLeanMedians = medianWindow(extract(\.rightBodyLeanAngle), halfWidth: leanHalfWidth)

        return results.enumerated().map { (index, detection) in
            let pose = detection.bodyPose
            guard pose.detected else { return detection }

            func replace(
                _ metric: MetricWithConfidence<Double>?,
                with median: Double?
            ) -> MetricWithConfidence<Double>? {
                guard let m = metric, let mv = median else { return metric }
                return MetricWithConfidence(value: mv, confidence: m.confidence)
            }

            let updatedPose = BodyPoseData(
                detected: pose.detected,
                visibility: pose.visibility,
                bodyLeanAngle: replace(pose.bodyLeanAngle, with: bodyLeanMedians[index]),
                leftBodyLeanAngle: replace(pose.leftBodyLeanAngle, with: leftBodyLeanMedians[index]),
                rightBodyLeanAngle: replace(pose.rightBodyLeanAngle, with: rightBodyLeanMedians[index]),
                leftKneeBendAngle: replace(pose.leftKneeBendAngle, with: leftKneeMedians[index]),
                rightKneeBendAngle: replace(pose.rightKneeBendAngle, with: rightKneeMedians[index]),
                leftCalfLeanAngle: replace(pose.leftCalfLeanAngle, with: leftCalfMedians[index]),
                rightCalfLeanAngle: replace(pose.rightCalfLeanAngle, with: rightCalfMedians[index]),
                centerOfGravity: pose.centerOfGravity,
                signedBodyLeanAngle: pose.signedBodyLeanAngle,
                signedCalfLeanAngle: pose.signedCalfLeanAngle,
                hipCenterX: pose.hipCenterX,
                ankleCenterX: pose.ankleCenterX,
                bodyCenterX: pose.bodyCenterX,
                hipCenterY: pose.hipCenterY,
                ankleCenterY: pose.ankleCenterY,
                bodyCenterY: pose.bodyCenterY,
                ankleProxyBoardAngle: pose.ankleProxyBoardAngle,
                leftShoulderPoint: pose.leftShoulderPoint,
                rightShoulderPoint: pose.rightShoulderPoint,
                leftHipPoint: pose.leftHipPoint,
                rightHipPoint: pose.rightHipPoint,
                leftKneePoint: pose.leftKneePoint,
                rightKneePoint: pose.rightKneePoint,
                leftAnklePoint: pose.leftAnklePoint,
                rightAnklePoint: pose.rightAnklePoint
            )

            return DetectionResult(
                time: detection.time,
                objects: detection.objects,
                faces: detection.faces,
                textObservations: detection.textObservations,
                sceneClassifications: detection.sceneClassifications,
                bodyPose: updatedPose,
                poseScore: detection.poseScore,
                visualBoardObservation: detection.visualBoardObservation,
                skiMetrics: detection.skiMetrics,
                error: detection.error
            )
        }
    }

    /// 3 帧中位数窗口。对每个 index i，取 [i-halfWidth, i+halfWidth] 中的非 nil 值中位数。
    ///
    /// 若窗口有效值 < minWindowSize（=2*halfWidth+1），保留原值（避免边界样本被单帧主导）。
    /// 这是刻意折中：
    /// - **首末帧**（index 0 和 count-1）永远只有 halfWidth 个邻居，因此**首末帧的孤立毛刺不会被 despike**
    /// - **中间帧含 nil 邻居**时也退化到"保留原值"（例如短空洞邻居），交给后续 P4-A `imputeMissingJointMetrics` 处理
    /// - 影响面：每段视频固定丢首末各 halfWidth 帧的 despike 效果；100+ 帧长视频 <2%，
    ///   短视频（<5 帧）在 [smooth()](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseSmoother.swift#L44-L49) 入口已被 `count >= 3` 拒绝
    /// - 若未来要覆盖边界，可以对首末帧用偏置窗口（[i, i+1, i+2] 或 [i-2, i-1, i]），
    ///   代价是首末帧引入 ~200ms 相位偏移
    ///
    /// P0-D (2026-09-07): 半宽参数化。knee/calf 用 halfWidth=1（3 帧窗），lean 用 halfWidth=2
    /// （5 帧窗，感受野扩大到 800ms 以覆盖连续多帧漂移）。
    private static let kneeCalfHalfWidth = 1
    private static let leanHalfWidth = 2

    private static func medianWindow(_ values: [Double?], halfWidth: Int = 1) -> [Double?] {
        guard values.count >= 3 else { return values }
        let minWindowSize = 2 * halfWidth + 1

        return values.indices.map { index -> Double? in
            let start = max(0, index - halfWidth)
            let end = min(values.count - 1, index + halfWidth)
            let window = values[start...end].compactMap { $0 }
            guard window.count >= minWindowSize else { return values[index] }
            let sorted = window.sorted()
            return sorted[sorted.count / 2]
        }
    }

    // MARK: - P4-A 短空洞插值

    /// 短空洞插值：邻域窗口半宽（帧数）。5 帧窗口 = 半宽 2，最多覆盖 4 帧连续空洞。
    private static let imputeWindowHalfWidth = 2

    /// 邻域最少健康帧（value 非 nil 且 confidence>0）：低于此值不插值。
    ///
    /// 取 2 是刻意的保守选择：
    /// - 窗口 [i-2, i+2] 共 5 帧（去掉自身 4 邻居），要求至少 2 个健康邻居才补
    /// - 视频里"孤立 1~2 帧空洞"两端仍有 2+ 健康帧，会被正确插值
    /// - 但"3~4 帧连续 nil 的中间几帧"会自然被拒（邻居只有 1 个），避免虚构可靠证据
    ///
    /// video 4 t=17.60~18.20s 的 5 帧连续 calf=nil 场景下，两端各 1 帧会被补上，
    /// 中间 3 帧维持 nil（阶跃损失被压缩，但不造假），是我们期望的行为。
    private static let imputeMinNeighborHealthy = 2

    /// 插值 confidence 衰减因子：填充值的 confidence = 邻居均值 × 衰减，上限截断到
    /// [minimumPoseScoreConfidence](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L97)（0.30）。
    ///
    /// **实际护栏说明（澄清）**：
    /// - 插值只写入**单个维度**（例如 leftCalf）；其余维度仍是真实高置信度
    /// - [reliablePoseFrames](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L294-L299) 判定用 `totalConfidence`（5 维加权均值），
    ///   单维度 conf=0.30 时 totalConfidence 仍远高于 0.30 → **含插值帧照样进入可靠聚合**
    /// - **真正的护栏是** [smoothConfidenceWeight](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L114-L118)：
    ///   conf=0.30 时权重 = ((0.30-0.15)/0.60)² ≈ 0.0625，
    ///   即插值维度的实际贡献被压缩到 ~6.25%，避免污染 bilateralConfidence 的均值
    /// - 若未来单段视频出现 >5 帧插值，考虑在 PoseScorer 层加"帧级插值标记"并给 totalConfidence 打折
    private static let imputeConfidenceDecay = 0.5

    /// 对 4 组 knee/calf 关节做短空洞插值。
    ///
    /// - 只对 `detected==true` 的帧插值；`detected==false` 的帧保持不动
    ///   （否则会把镜头切换/远景整段捏出高分）
    /// - 每组关节独立处理：left/right knee/calf 有一个空就补一个
    /// - 窗口 [i-2, i+2] 内至少 [imputeMinNeighborHealthy] 个健康邻居才插值
    /// - 插值 value = 邻居中位数；插值 confidence = 邻居均值 × [imputeConfidenceDecay]
    ///
    /// 现有帧（value != nil）不受影响。
    private static func imputeMissingJointMetrics(_ results: [DetectionResult]) -> [DetectionResult] {
        guard results.count >= 3 else { return results }

        let leftKneeFilled = imputeSeries(results.map { $0.bodyPose.leftKneeBendAngle })
        let rightKneeFilled = imputeSeries(results.map { $0.bodyPose.rightKneeBendAngle })
        let leftCalfFilled = imputeSeries(results.map { $0.bodyPose.leftCalfLeanAngle })
        let rightCalfFilled = imputeSeries(results.map { $0.bodyPose.rightCalfLeanAngle })

        return results.enumerated().map { (index, detection) in
            let pose = detection.bodyPose
            guard pose.detected else { return detection }

            let updatedPose = BodyPoseData(
                detected: pose.detected,
                visibility: pose.visibility,
                bodyLeanAngle: pose.bodyLeanAngle,
                leftBodyLeanAngle: pose.leftBodyLeanAngle,
                rightBodyLeanAngle: pose.rightBodyLeanAngle,
                leftKneeBendAngle: leftKneeFilled[index] ?? pose.leftKneeBendAngle,
                rightKneeBendAngle: rightKneeFilled[index] ?? pose.rightKneeBendAngle,
                leftCalfLeanAngle: leftCalfFilled[index] ?? pose.leftCalfLeanAngle,
                rightCalfLeanAngle: rightCalfFilled[index] ?? pose.rightCalfLeanAngle,
                centerOfGravity: pose.centerOfGravity,
                signedBodyLeanAngle: pose.signedBodyLeanAngle,
                signedCalfLeanAngle: pose.signedCalfLeanAngle,
                hipCenterX: pose.hipCenterX,
                ankleCenterX: pose.ankleCenterX,
                bodyCenterX: pose.bodyCenterX,
                hipCenterY: pose.hipCenterY,
                ankleCenterY: pose.ankleCenterY,
                bodyCenterY: pose.bodyCenterY,
                ankleProxyBoardAngle: pose.ankleProxyBoardAngle,
                leftShoulderPoint: pose.leftShoulderPoint,
                rightShoulderPoint: pose.rightShoulderPoint,
                leftHipPoint: pose.leftHipPoint,
                rightHipPoint: pose.rightHipPoint,
                leftKneePoint: pose.leftKneePoint,
                rightKneePoint: pose.rightKneePoint,
                leftAnklePoint: pose.leftAnklePoint,
                rightAnklePoint: pose.rightAnklePoint
            )

            return DetectionResult(
                time: detection.time,
                objects: detection.objects,
                faces: detection.faces,
                textObservations: detection.textObservations,
                sceneClassifications: detection.sceneClassifications,
                bodyPose: updatedPose,
                poseScore: detection.poseScore,
                visualBoardObservation: detection.visualBoardObservation,
                skiMetrics: detection.skiMetrics,
                error: detection.error
            )
        }
    }

    /// 对单一 metric 序列做短空洞插值。
    ///
    /// 返回一个与输入等长的可选序列：
    /// - `nil`：本帧无需替换（原值已存在，或邻居健康数不足）
    /// - `.some(metric)`：本帧应替换成这个插值样本
    private static func imputeSeries(_ series: [MetricWithConfidence<Double>?]) -> [MetricWithConfidence<Double>?] {
        guard series.count >= 3 else { return Array(repeating: nil, count: series.count) }

        return series.indices.map { index -> MetricWithConfidence<Double>? in
            // 现有健康值不替换
            if let m = series[index], m.confidence > 0 { return nil }

            let start = max(0, index - imputeWindowHalfWidth)
            let end = min(series.count - 1, index + imputeWindowHalfWidth)

            var values: [Double] = []
            var confs: [Double] = []
            for j in start...end where j != index {
                guard let m = series[j], m.confidence > 0 else { continue }
                values.append(m.value)
                confs.append(m.confidence)
            }

            guard values.count >= imputeMinNeighborHealthy else { return nil }

            let sortedValues = values.sorted()
            let median = sortedValues[sortedValues.count / 2]
            let avgConf = confs.reduce(0, +) / Double(confs.count)
            let insertedConf = min(avgConf * imputeConfidenceDecay,
                                   AnalysisReliability.minimumPoseScoreConfidence)

            return MetricWithConfidence(value: median, confidence: insertedConf)
        }
    }


    /// 对单个 MetricWithConfidence 做滤波，nil 值直传，置信度保持不变。
    private static func filterMetric(
        _ metric: MetricWithConfidence<Double>?,
        key: String,
        t: Double,
        using filters: MultiOneEuroFilter
    ) -> MetricWithConfidence<Double>? {
        guard let m = metric else { return nil }
        let filtered = filters.filter(m.value, key: key, timestamp: t)
        return MetricWithConfidence(value: filtered, confidence: m.confidence)
    }
}
