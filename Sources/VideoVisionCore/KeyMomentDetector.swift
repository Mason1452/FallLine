import Foundation

// MARK: - 关键时刻检测器

/// 从帧序列中找出问题最严重的几个时间点和最佳参考帧
public struct KeyMomentDetector {
    public init() {}

    /// 检测关键时刻
    /// - Parameters:
    ///   - frames: 所有帧结果
    ///   - duration: 视频总时长（秒）
    /// - Returns: 最多 5 个关键时刻，按时间排序
    public static func detect(from frames: [DetectionResult], duration: Double) -> [KeyMoment] {
        let valid = frames.filter { $0.poseScore != nil && $0.bodyPose.detected }
        guard valid.count >= 2 else { return [] }

        var candidates: [KeyMoment] = []

        // 1) 走刃质量最低帧（只有真的偏弱才输出）
        if let worst = valid.min(by: { edgeQuality($0) < edgeQuality($1) }) {
            let score = edgeQuality(worst)
            if score < 55 {
                candidates.append(KeyMoment(
                    time: formatTime(worst.time),
                    seconds: worst.time,
                    type: "weak_edge",
                    title: "走刃质量偏弱",
                    description: edgeMomentDescription(score),
                    score: score
                ))
            }
        }

        // 2) 板压支撑最低帧
        if let worst = valid.min(by: { pressureSupport($0) < pressureSupport($1) }) {
            let score = pressureSupport(worst)
            if score < 55, !isNearExisting(candidates, time: worst.time, threshold: 1.5) {
                candidates.append(KeyMoment(
                    time: formatTime(worst.time),
                    seconds: worst.time,
                    type: "high_cog",
                    title: "板压支撑不足",
                    description: gravMomentDescription(score),
                    score: score
                ))
            }
        }

        // 3) 膝盖最直帧（腿部弹性最差）
        if let worst = valid.min(by: { $0.poseScore!.kneeBendScore < $1.poseScore!.kneeBendScore }) {
            let score = worst.poseScore!.kneeBendScore
            if score < 55, !isNearExisting(candidates, time: worst.time, threshold: 1.5) {
                candidates.append(KeyMoment(
                    time: formatTime(worst.time),
                    seconds: worst.time,
                    type: "straight_legs",
                    title: "腿部弹性不足",
                    description: "这一帧膝盖弯曲角度较小，腿部缺乏弹性吸收地形。",
                    score: score
                ))
            }
        }

        // 4) 对称性最差帧
        if let worst = valid.min(by: { $0.poseScore!.symmetryScore < $1.poseScore!.symmetryScore }) {
            let score = worst.poseScore!.symmetryScore
            if score < 55, !isNearExisting(candidates, time: worst.time, threshold: 1.5) {
                candidates.append(KeyMoment(
                    time: formatTime(worst.time),
                    seconds: worst.time,
                    type: "asymmetry",
                    title: "左右动作不对称",
                    description: "这一帧左右两侧关键点差异较大，转弯质量可能不一致。",
                    score: score
                ))
            }
        }

        // 5) 最佳走刃帧（作为参考）—— 也参与时间去重，且必须明显够好
        if let best = valid.max(by: { edgeQuality($0) < edgeQuality($1) }) {
            let score = edgeQuality(best)
            if score >= 55, !isNearExisting(candidates, time: best.time, threshold: 1.5) {
                candidates.append(KeyMoment(
                    time: formatTime(best.time),
                    seconds: best.time,
                    type: "best_edge",
                    title: "相对较好的走刃时刻",
                    description: "这一帧立刃条件相对较好，可以作为练习时的姿态参考。",
                    score: score
                ))
            }
        }

        // 排序：按时间
        candidates.sort { $0.seconds < $1.seconds }

        // 限制最多 5 个
        return Array(candidates.prefix(5))
    }

    // MARK: - 辅助

    /// 走刃质量（原始分）
    private static func edgeQuality(_ r: DetectionResult) -> Double {
        guard let m = r.skiMetrics else { return 0 }
        return m.edgeQualityScore
    }

    /// 板压支撑（原始分）
    private static func pressureSupport(_ r: DetectionResult) -> Double {
        guard let m = r.skiMetrics else { return 0 }
        return m.pressureSupportScore
    }

    /// 前后支撑（原始分）
    private static func foreAftSupport(_ r: DetectionResult) -> Double {
        guard let m = r.skiMetrics else { return 0 }
        return m.foreAftSupportScore
    }

    private static func isNearExisting(_ moments: [KeyMoment], time: Double, threshold: Double) -> Bool {
        moments.contains { abs($0.seconds - time) <= threshold }
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private static func edgeMomentDescription(_ score: Double) -> String {
        if score < 40 {
            return "这一帧走刃质量偏低，姿态条件更接近搓雪转弯。"
        } else if score < 55 {
            return "这一帧走刃条件一般，立刃和重心配合还不够充分。"
        } else {
            return "这一帧走刃质量尚可，但离稳定的刻滑还有提升空间。"
        }
    }

    private static func gravMomentDescription(_ score: Double) -> String {
        if score < 45 {
            return "这一帧板压支撑不足，重心偏高或腿部下压不够。"
        } else {
            return "这一帧板压偏弱，弯中稳定性可能受影响。"
        }
    }
}
