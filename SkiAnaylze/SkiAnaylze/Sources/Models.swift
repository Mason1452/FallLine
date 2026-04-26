import Foundation
import Vision

// MARK: - 可见性等级

/// 关键点可见性等级，用于标识姿态指标的数据完整性
enum VisibilityLevel: String, Codable {
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

struct MetricWithConfidence<T: Codable>: Codable {
    let value: T
    let confidence: Double

    init(value: T, confidence: Double) {
        self.value = value
        self.confidence = max(0, min(1, confidence))
    }
}

// MARK: - 常规检测数据模型

struct ObjectItem: Codable {
    let label: String
    let confidence: VNConfidence
}

struct FaceItem: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct SceneItem: Codable {
    let label: String
    let confidence: VNConfidence
}

// MARK: - 肢体姿态数据模型

struct BodyPoseData: Codable {
    let detected: Bool
    let visibility: VisibilityLevel

    /// 整体身体前倾角度（双侧均可见时取肩膀-髋部中点连线）
    let bodyLeanAngle: MetricWithConfidence<Double>?
    /// 左侧前倾角度（左侧肩→髋连线与垂直方向夹角）
    let leftBodyLeanAngle: MetricWithConfidence<Double>?
    /// 右侧前倾角度（右侧肩→髋连线与垂直方向夹角）
    let rightBodyLeanAngle: MetricWithConfidence<Double>?

    let leftKneeBendAngle: MetricWithConfidence<Double>?
    let rightKneeBendAngle: MetricWithConfidence<Double>?
    let leftCalfLeanAngle: MetricWithConfidence<Double>?
    let rightCalfLeanAngle: MetricWithConfidence<Double>?

    /// 相对重心高度（0~1，基于人体比例，与站位远近无关）
    let centerOfGravity: MetricWithConfidence<String>?
}

// MARK: - 基础姿态评分

struct PoseScore: Codable {
    let totalScore: Double           // 总分 0-100
    let forwardLeanScore: Double     // 身体前倾得分（权重20%）
    let kneeBendScore: Double        // 膝盖弯曲得分（权重25%）
    let calfLeanScore: Double        // 小腿倾斜得分（权重20%）
    let gravityScore: Double         // 重心得分（权重20%）
    let symmetryScore: Double        // 对称性得分（权重15%）
    let level: String                // "初级" / "中级" / "高级" / "专业"
    let suggestions: [String]        // 改进建议
}

// MARK: - 滑雪派生指标（从基础姿态推算）

/// 由基础姿态指标复合计算，反映更接近滑雪体验的维度
struct SkiDerivedMetrics: Codable {
    /// 走刃质量（0-100）：综合立刃、重心、膝盖、对称性和稳定性
    let edgeQualityScore: Double
    let edgeQualityLabel: String     // 搓雪为主 / 有立刃尝试 / 刻滑雏形 / 走刃较稳定 / 走刃优秀

    /// 板压支撑（0-100）：重心 + 膝盖 + 前倾 + 稳定性
    let pressureSupportScore: Double
    let pressureSupportLabel: String

    /// 前后支撑（0-100）：前倾 + 重心 + 稳定性
    let foreAftSupportScore: Double
    let foreAftSupportLabel: String
}

// MARK: - 关键时刻

/// 标记视频中某一秒值得注意的问题或亮点
struct KeyMoment: Codable {
    let time: String                 // "00:06"
    let seconds: Double              // 原始秒数
    let type: String                 // "weak_edge" / "high_cog" / "straight_legs" / "poor_lean" / "asymmetry" / "best_edge"
    let title: String                // "走刃质量偏弱"
    let description: String          // "这一帧立刃幅度和重心条件都偏弱，转弯更像扫雪。"
    let score: Double                // 对应的维度分数
}

// MARK: - 单帧检测结果

struct DetectionResult: Codable {
    let time: Double
    let objects: [ObjectItem]
    let faces: [FaceItem]
    let textObservations: [String]
    let sceneClassifications: [SceneItem]
    let bodyPose: BodyPoseData
    let poseScore: PoseScore?
    var skiMetrics: SkiDerivedMetrics?
}

// MARK: - 全视频总结

struct VideoSummary: Codable {
    let averageScore: Double
    let bestFrame: FrameScore
    let worstFrame: FrameScore
    let stabilityScore: Double       // 动作稳定性评分 0-100，越高越稳定
    let scoreConsistencyScore: Double // 姿态总分一致性 0-100，越高表示总分波动越小
    let scoreStdDev: Double          // 姿态总分标准差，仅用于解释评分波动
    let overallLevel: String
}

struct FrameScore: Codable {
    let time: Double
    let timeString: String
    let score: Double
}

// MARK: - 最终输出结构

struct AnalysisOutput: Codable, Identifiable {
    var id: String { videoPath }
    let videoPath: String
    let duration: Double
    let totalFrames: Int
    let frames: [DetectionResult]
    let summary: VideoSummary
    let skiMetrics: SkiDerivedMetrics  // 全视频平均滑雪派生指标
    let keyMoments: [KeyMoment]        // 关键时刻列表
}
