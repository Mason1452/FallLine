import Foundation
import Vision

// MARK: - 可见性等级

/// 关键点可见性等级，用于标识姿态指标的数据完整性
public enum VisibilityLevel: String, Codable {
    /// 双侧关键点均可见（8个点全部检测到）
    case full
    /// 单侧可见（4~7个点）
    case partial
    /// 只有躯干关键点（1~3个点）
    case minimal
    /// 未检测到人体
    case none
}

// MARK: - 带置信度的指标包装

public struct MetricWithConfidence<T: Codable>: Codable {
    public let value: T
    public let confidence: Double

    public init(value: T, confidence: Double) {
        self.value = value
        self.confidence = max(0, min(1, confidence))
    }
}

// MARK: - 常规检测数据模型

public struct ObjectItem: Codable {
    public let label: String
    public let confidence: VNConfidence

    public init(label: String, confidence: VNConfidence) {
        self.label = label
        self.confidence = confidence
    }
}

public struct FaceItem: Codable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct SceneItem: Codable {
    public let label: String
    public let confidence: VNConfidence

    public init(label: String, confidence: VNConfidence) {
        self.label = label
        self.confidence = confidence
    }
}

// MARK: - 肢体姿态数据模型

public struct BodyPoseData: Codable {
    public let detected: Bool
    public let visibility: VisibilityLevel

    /// 整体身体前倾角度（双侧均可见时取肩膀-髋部中点连线）
    public let bodyLeanAngle: MetricWithConfidence<Double>?
    /// 左侧前倾角度（左侧肩→髋连线与垂直方向夹角）
    public let leftBodyLeanAngle: MetricWithConfidence<Double>?
    /// 右侧前倾角度（右侧肩→髋连线与垂直方向夹角）
    public let rightBodyLeanAngle: MetricWithConfidence<Double>?

    public let leftKneeBendAngle: MetricWithConfidence<Double>?
    public let rightKneeBendAngle: MetricWithConfidence<Double>?
    public let leftCalfLeanAngle: MetricWithConfidence<Double>?
    public let rightCalfLeanAngle: MetricWithConfidence<Double>?

    /// 相对重心高度（0~1，基于人体比例，与站位远近无关）
    public let centerOfGravity: MetricWithConfidence<String>?

    public init(
        detected: Bool,
        visibility: VisibilityLevel,
        bodyLeanAngle: MetricWithConfidence<Double>?,
        leftBodyLeanAngle: MetricWithConfidence<Double>?,
        rightBodyLeanAngle: MetricWithConfidence<Double>?,
        leftKneeBendAngle: MetricWithConfidence<Double>?,
        rightKneeBendAngle: MetricWithConfidence<Double>?,
        leftCalfLeanAngle: MetricWithConfidence<Double>?,
        rightCalfLeanAngle: MetricWithConfidence<Double>?,
        centerOfGravity: MetricWithConfidence<String>?
    ) {
        self.detected = detected
        self.visibility = visibility
        self.bodyLeanAngle = bodyLeanAngle
        self.leftBodyLeanAngle = leftBodyLeanAngle
        self.rightBodyLeanAngle = rightBodyLeanAngle
        self.leftKneeBendAngle = leftKneeBendAngle
        self.rightKneeBendAngle = rightKneeBendAngle
        self.leftCalfLeanAngle = leftCalfLeanAngle
        self.rightCalfLeanAngle = rightCalfLeanAngle
        self.centerOfGravity = centerOfGravity
    }
}

// MARK: - 基础姿态评分

public struct PoseScore: Codable {
    public let totalScore: Double           // 总分 0-100
    public let forwardLeanScore: Double     // 身体前倾得分（权重20%）
    public let kneeBendScore: Double        // 膝盖弯曲得分（权重25%）
    public let calfLeanScore: Double        // 小腿倾斜得分（权重20%）
    public let gravityScore: Double         // 重心得分（权重20%）
    public let symmetryScore: Double        // 对称性得分（权重15%）
    public let level: String                // "初级" / "中级" / "高级" / "专业"
    public let suggestions: [String]        // 改进建议

    public init(
        totalScore: Double,
        forwardLeanScore: Double,
        kneeBendScore: Double,
        calfLeanScore: Double,
        gravityScore: Double,
        symmetryScore: Double,
        level: String,
        suggestions: [String]
    ) {
        self.totalScore = totalScore
        self.forwardLeanScore = forwardLeanScore
        self.kneeBendScore = kneeBendScore
        self.calfLeanScore = calfLeanScore
        self.gravityScore = gravityScore
        self.symmetryScore = symmetryScore
        self.level = level
        self.suggestions = suggestions
    }
}

// MARK: - 滑雪派生指标（从基础姿态推算）

/// 由基础姿态指标复合计算，反映更接近滑雪体验的维度
public struct SkiDerivedMetrics: Codable {
    /// 走刃质量（0-100）：综合立刃、重心、膝盖、对称性和稳定性
    public let edgeQualityScore: Double
    public let edgeQualityLabel: String     // 搓雪为主 / 有立刃尝试 / 刻滑雏形 / 走刃较稳定 / 走刃优秀

    /// 板压支撑（0-100）：重心 + 膝盖 + 前倾 + 稳定性
    public let pressureSupportScore: Double
    public let pressureSupportLabel: String

    /// 前后支撑（0-100）：前倾 + 重心 + 稳定性
    public let foreAftSupportScore: Double
    public let foreAftSupportLabel: String

    public init(
        edgeQualityScore: Double,
        edgeQualityLabel: String,
        pressureSupportScore: Double,
        pressureSupportLabel: String,
        foreAftSupportScore: Double,
        foreAftSupportLabel: String
    ) {
        self.edgeQualityScore = edgeQualityScore
        self.edgeQualityLabel = edgeQualityLabel
        self.pressureSupportScore = pressureSupportScore
        self.pressureSupportLabel = pressureSupportLabel
        self.foreAftSupportScore = foreAftSupportScore
        self.foreAftSupportLabel = foreAftSupportLabel
    }
}

// MARK: - 关键时刻

/// 标记视频中某一秒值得注意的问题或亮点
public struct KeyMoment: Codable {
    public let time: String                 // "00:06"
    public let seconds: Double              // 原始秒数
    public let type: String                 // "weak_edge" / "high_cog" / "straight_legs" / "poor_lean" / "asymmetry" / "best_edge"
    public let title: String                // "走刃质量偏弱"
    public let description: String          // "这一帧立刃幅度和重心条件都偏弱，转弯更像扫雪。"
    public let score: Double                // 对应的维度分数

    public init(time: String, seconds: Double, type: String, title: String, description: String, score: Double) {
        self.time = time
        self.seconds = seconds
        self.type = type
        self.title = title
        self.description = description
        self.score = score
    }
}

// MARK: - 单帧检测结果

public struct DetectionResult: Codable {
    public let time: Double
    public let objects: [ObjectItem]
    public let faces: [FaceItem]
    public let textObservations: [String]
    public let sceneClassifications: [SceneItem]
    public let bodyPose: BodyPoseData
    public let poseScore: PoseScore?
    public var skiMetrics: SkiDerivedMetrics?

    public init(
        time: Double,
        objects: [ObjectItem],
        faces: [FaceItem],
        textObservations: [String],
        sceneClassifications: [SceneItem],
        bodyPose: BodyPoseData,
        poseScore: PoseScore?,
        skiMetrics: SkiDerivedMetrics? = nil
    ) {
        self.time = time
        self.objects = objects
        self.faces = faces
        self.textObservations = textObservations
        self.sceneClassifications = sceneClassifications
        self.bodyPose = bodyPose
        self.poseScore = poseScore
        self.skiMetrics = skiMetrics
    }
}

// MARK: - 全视频总结

public struct VideoSummary: Codable {
    public let averageScore: Double
    public let bestFrame: FrameScore
    public let worstFrame: FrameScore
    public let stabilityScore: Double       // 动作稳定性评分 0-100，越高越稳定
    public let scoreConsistencyScore: Double // 姿态总分一致性 0-100，越高表示总分波动越小
    public let scoreStdDev: Double          // 姿态总分标准差，仅用于解释评分波动
    public let overallLevel: String

    public init(
        averageScore: Double,
        bestFrame: FrameScore,
        worstFrame: FrameScore,
        stabilityScore: Double,
        scoreConsistencyScore: Double,
        scoreStdDev: Double,
        overallLevel: String
    ) {
        self.averageScore = averageScore
        self.bestFrame = bestFrame
        self.worstFrame = worstFrame
        self.stabilityScore = stabilityScore
        self.scoreConsistencyScore = scoreConsistencyScore
        self.scoreStdDev = scoreStdDev
        self.overallLevel = overallLevel
    }
}

public struct FrameScore: Codable {
    public let time: Double
    public let timeString: String
    public let score: Double

    public init(time: Double, timeString: String, score: Double) {
        self.time = time
        self.timeString = timeString
        self.score = score
    }
}

// MARK: - 最终输出结构

public struct AnalysisOutput: Codable {
    public let videoPath: String
    public let duration: Double
    public let totalFrames: Int
    public let frames: [DetectionResult]
    public let summary: VideoSummary
    public let skiMetrics: SkiDerivedMetrics  // 全视频平均滑雪派生指标
    public let keyMoments: [KeyMoment]        // 关键时刻列表

    public init(
        videoPath: String,
        duration: Double,
        totalFrames: Int,
        frames: [DetectionResult],
        summary: VideoSummary,
        skiMetrics: SkiDerivedMetrics,
        keyMoments: [KeyMoment]
    ) {
        self.videoPath = videoPath
        self.duration = duration
        self.totalFrames = totalFrames
        self.frames = frames
        self.summary = summary
        self.skiMetrics = skiMetrics
        self.keyMoments = keyMoments
    }
}
