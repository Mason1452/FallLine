import Foundation
import FallLineCore

/// Provides a default high-score AnalysisOutput for simulator testing,
/// sourced from testvideo/3.MP4 analysis results.
enum DemoData {

    static func makeDemoOutput() -> AnalysisOutput {
        let summary = VideoSummary(
            averageScore: 72.57,
            bestFrame: FrameScore(time: 13.28, timeString: "00:13", score: 92.46),
            worstFrame: FrameScore(time: 11.98, timeString: "00:11", score: 45.91),
            stabilityScore: 83.91,
            scoreConsistencyScore: 0,
            scoreStdDev: 11.54,
            overallLevel: "中级"
        )

        let skiMetrics = SkiDerivedMetrics(
            edgeQualityScore: 64.39,
            edgeQualityLabel: "刻滑雏形",
            pressureSupportScore: 69.22,
            pressureSupportLabel: "支撑尚可",
            foreAftSupportScore: 81.23,
            foreAftSupportLabel: "前后支撑积极"
        )

        let keyMoments: [KeyMoment] = [
            KeyMoment(
                time: "00:02",
                seconds: 2.2,
                type: "straight_legs",
                title: "腿部弹性不足",
                description: "这一帧膝盖弯曲角度较小，腿部缺乏弹性吸收地形。",
                score: 20
            ),
            KeyMoment(
                time: "00:03",
                seconds: 3.76,
                type: "asymmetry",
                title: "左右动作不对称",
                description: "这一帧左右两侧关键点差异较大，转弯质量可能不一致。",
                score: 8.05
            ),
            KeyMoment(
                time: "00:10",
                seconds: 10.16,
                type: "weak_edge",
                title: "走刃质量偏弱",
                description: "这一帧走刃质量偏低，姿态条件更接近搓雪转弯。",
                score: 31.31
            ),
            KeyMoment(
                time: "00:13",
                seconds: 13.26,
                type: "high_cog",
                title: "板压支撑不足",
                description: "这一帧板压偏弱，弯中稳定性可能受影响。",
                score: 48.07
            ),
            KeyMoment(
                time: "00:15",
                seconds: 15.90,
                type: "best_edge",
                title: "相对较好的走刃时刻",
                description: "这一帧立刃条件相对较好，可以作为练习时的姿态参考。",
                score: 90.70
            )
        ]

        // 10 synthetic frames with poseScore distribution matching testvideo/3.json averages
        // (lean≈88, knee≈74, calf≈57, grav≈51, sym≈59)
        let frames: [DetectionResult] = [
            makeFrame(time: 0, total: 77, lean: 100, knee: 100, calf: 66, grav: 57, sym: 51, level: "高级"),
            makeFrame(time: 2.2, total: 45, lean: 90, knee: 25, calf: 40, grav: 40, sym: 60, level: "初级"),
            makeFrame(time: 3.76, total: 50, lean: 85, knee: 70, calf: 45, grav: 55, sym: 15, level: "初级"),
            makeFrame(time: 5.0, total: 65, lean: 95, knee: 75, calf: 50, grav: 50, sym: 60, level: "中级"),
            makeFrame(time: 7.5, total: 80, lean: 100, knee: 95, calf: 70, grav: 60, sym: 80, level: "高级"),
            makeFrame(time: 10.16, total: 55, lean: 80, knee: 60, calf: 40, grav: 45, sym: 50, level: "初级"),
            makeFrame(time: 12.0, total: 68, lean: 85, knee: 75, calf: 55, grav: 55, sym: 65, level: "中级"),
            makeFrame(time: 13.26, total: 50, lean: 70, knee: 65, calf: 45, grav: 35, sym: 55, level: "初级"),
            makeFrame(time: 15.9, total: 92, lean: 100, knee: 95, calf: 85, grav: 75, sym: 90, level: "高级"),
            makeFrame(time: 18.0, total: 75, lean: 95, knee: 80, calf: 65, grav: 55, sym: 70, level: "中级")
        ]

        return AnalysisOutput(
            videoPath: "/Users/mingsen/Project/FallLine/a3_analyzed.mp4",
            duration: 19.99,
            totalFrames: 1000,
            frames: frames,
            summary: summary,
            skiMetrics: skiMetrics,
            keyMoments: keyMoments
        )
    }

    private static func makeFrame(
        time: Double,
        total: Double,
        lean: Double,
        knee: Double,
        calf: Double,
        grav: Double,
        sym: Double,
        level: String
    ) -> DetectionResult {
        let suggestions: [String]
        switch total {
        case ..<50:
            suggestions = ["关键点识别不足，请确保全身在画面中可见"]
        case ..<65:
            suggestions = ["尝试增加立刃幅度", "降低重心以获得更好的稳定性"]
        case ..<80:
            suggestions = ["降低重心以获得更好的稳定性", "注意左右动作的对称性"]
        default:
            suggestions = ["保持当前姿态，继续练习巩固"]
        }

        return DetectionResult(
            time: time,
            objects: [],
            faces: [],
            textObservations: [],
            sceneClassifications: [],
            bodyPose: BodyPoseData(
                detected: true,
                visibility: .full,
                bodyLeanAngle: nil,
                leftBodyLeanAngle: nil,
                rightBodyLeanAngle: nil,
                leftKneeBendAngle: nil,
                rightKneeBendAngle: nil,
                leftCalfLeanAngle: nil,
                rightCalfLeanAngle: nil,
                centerOfGravity: nil
            ),
            poseScore: PoseScore(
                totalScore: total,
                forwardLeanScore: lean,
                kneeBendScore: knee,
                calfLeanScore: calf,
                gravityScore: grav,
                symmetryScore: sym,
                level: level,
                suggestions: suggestions
            ),
            skiMetrics: nil
        )
    }
}
