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

/// 归一化 2D 关键点坐标（Vision 坐标，0...1）及其置信度。
public struct PoseJointPoint: Codable {
    public let x: Double
    public let y: Double
    public let confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = max(0, min(1, x))
        self.y = max(0, min(1, y))
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

    /// 相对重心高度（hipRatio，0~1 连续值，基于人体比例，与站位远近无关）
    /// 值越小 = 髋部越靠近脚踝 = 重心越低（理想滑雪姿态）
    public let centerOfGravity: MetricWithConfidence<Double>?

    /// 有符号身体倾斜角。正值表示向画面右侧倾斜，负值表示向画面左侧倾斜。
    public let signedBodyLeanAngle: MetricWithConfidence<Double>?
    /// 有符号小腿倾斜角。正值表示小腿向画面右侧倾斜，负值表示向画面左侧倾斜。
    public let signedCalfLeanAngle: MetricWithConfidence<Double>?
    /// 髋部中心点 X 坐标（Vision 归一化坐标，0...1）。
    public let hipCenterX: MetricWithConfidence<Double>?
    /// 脚踝中心点 X 坐标（Vision 归一化坐标，0...1）。
    public let ankleCenterX: MetricWithConfidence<Double>?
    /// 身体中心点 X 坐标（肩、髋、踝可见中心的平均）。
    public let bodyCenterX: MetricWithConfidence<Double>?
    /// 髋部中心点 Y 坐标（Vision 归一化坐标，0...1）。
    public let hipCenterY: MetricWithConfidence<Double>?
    /// 脚踝中心点 Y 坐标（Vision 归一化坐标，0...1）。
    public let ankleCenterY: MetricWithConfidence<Double>?
    /// 身体中心点 Y 坐标（肩、髋、踝可见中心的平均）。
    public let bodyCenterY: MetricWithConfidence<Double>?
    /// 用左右脚踝连线代理的板身角度。0 度指向画面右侧，逆时针为正，范围 [-180, 180)。
    public let ankleProxyBoardAngle: MetricWithConfidence<Double>?
    /// 调试可视化用原始关键点。业务评分仍使用上方派生指标。
    public let leftShoulderPoint: PoseJointPoint?
    public let rightShoulderPoint: PoseJointPoint?
    public let leftHipPoint: PoseJointPoint?
    public let rightHipPoint: PoseJointPoint?
    public let leftKneePoint: PoseJointPoint?
    public let rightKneePoint: PoseJointPoint?
    public let leftAnklePoint: PoseJointPoint?
    public let rightAnklePoint: PoseJointPoint?

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
        centerOfGravity: MetricWithConfidence<Double>?,
        signedBodyLeanAngle: MetricWithConfidence<Double>? = nil,
        signedCalfLeanAngle: MetricWithConfidence<Double>? = nil,
        hipCenterX: MetricWithConfidence<Double>? = nil,
        ankleCenterX: MetricWithConfidence<Double>? = nil,
        bodyCenterX: MetricWithConfidence<Double>? = nil,
        hipCenterY: MetricWithConfidence<Double>? = nil,
        ankleCenterY: MetricWithConfidence<Double>? = nil,
        bodyCenterY: MetricWithConfidence<Double>? = nil,
        ankleProxyBoardAngle: MetricWithConfidence<Double>? = nil,
        leftShoulderPoint: PoseJointPoint? = nil,
        rightShoulderPoint: PoseJointPoint? = nil,
        leftHipPoint: PoseJointPoint? = nil,
        rightHipPoint: PoseJointPoint? = nil,
        leftKneePoint: PoseJointPoint? = nil,
        rightKneePoint: PoseJointPoint? = nil,
        leftAnklePoint: PoseJointPoint? = nil,
        rightAnklePoint: PoseJointPoint? = nil
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
        self.signedBodyLeanAngle = signedBodyLeanAngle
        self.signedCalfLeanAngle = signedCalfLeanAngle
        self.hipCenterX = hipCenterX
        self.ankleCenterX = ankleCenterX
        self.bodyCenterX = bodyCenterX
        self.hipCenterY = hipCenterY
        self.ankleCenterY = ankleCenterY
        self.bodyCenterY = bodyCenterY
        self.ankleProxyBoardAngle = ankleProxyBoardAngle
        self.leftShoulderPoint = leftShoulderPoint
        self.rightShoulderPoint = rightShoulderPoint
        self.leftHipPoint = leftHipPoint
        self.rightHipPoint = rightHipPoint
        self.leftKneePoint = leftKneePoint
        self.rightKneePoint = rightKneePoint
        self.leftAnklePoint = leftAnklePoint
        self.rightAnklePoint = rightAnklePoint
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
    public let totalConfidence: Double
    public let forwardLeanConfidence: Double
    public let kneeBendConfidence: Double
    public let calfLeanConfidence: Double
    public let gravityConfidence: Double
    public let symmetryConfidence: Double
    public let level: String                // "初级" / "中级" / "高级" / "专业"
    public let suggestions: [String]        // 改进建议

    public init(
        totalScore: Double,
        forwardLeanScore: Double,
        kneeBendScore: Double,
        calfLeanScore: Double,
        gravityScore: Double,
        symmetryScore: Double,
        totalConfidence: Double = 0,
        forwardLeanConfidence: Double = 0,
        kneeBendConfidence: Double = 0,
        calfLeanConfidence: Double = 0,
        gravityConfidence: Double = 0,
        symmetryConfidence: Double = 0,
        level: String,
        suggestions: [String]
    ) {
        self.totalScore = totalScore
        self.forwardLeanScore = forwardLeanScore
        self.kneeBendScore = kneeBendScore
        self.calfLeanScore = calfLeanScore
        self.gravityScore = gravityScore
        self.symmetryScore = symmetryScore
        self.totalConfidence = max(0, min(1, totalConfidence))
        self.forwardLeanConfidence = max(0, min(1, forwardLeanConfidence))
        self.kneeBendConfidence = max(0, min(1, kneeBendConfidence))
        self.calfLeanConfidence = max(0, min(1, calfLeanConfidence))
        self.gravityConfidence = max(0, min(1, gravityConfidence))
        self.symmetryConfidence = max(0, min(1, symmetryConfidence))
        self.level = level
        self.suggestions = suggestions
    }

    enum CodingKeys: String, CodingKey {
        case totalScore
        case forwardLeanScore
        case kneeBendScore
        case calfLeanScore
        case gravityScore
        case symmetryScore
        case totalConfidence
        case forwardLeanConfidence
        case kneeBendConfidence
        case calfLeanConfidence
        case gravityConfidence
        case symmetryConfidence
        case level
        case suggestions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalScore = try container.decode(Double.self, forKey: .totalScore)
        forwardLeanScore = try container.decode(Double.self, forKey: .forwardLeanScore)
        kneeBendScore = try container.decode(Double.self, forKey: .kneeBendScore)
        calfLeanScore = try container.decode(Double.self, forKey: .calfLeanScore)
        gravityScore = try container.decode(Double.self, forKey: .gravityScore)
        symmetryScore = try container.decode(Double.self, forKey: .symmetryScore)
        totalConfidence = try container.decodeIfPresent(Double.self, forKey: .totalConfidence) ?? 0
        forwardLeanConfidence = try container.decodeIfPresent(Double.self, forKey: .forwardLeanConfidence) ?? 0
        kneeBendConfidence = try container.decodeIfPresent(Double.self, forKey: .kneeBendConfidence) ?? 0
        calfLeanConfidence = try container.decodeIfPresent(Double.self, forKey: .calfLeanConfidence) ?? 0
        gravityConfidence = try container.decodeIfPresent(Double.self, forKey: .gravityConfidence) ?? 0
        symmetryConfidence = try container.decodeIfPresent(Double.self, forKey: .symmetryConfidence) ?? 0
        level = try container.decode(String.self, forKey: .level)
        suggestions = try container.decode([String].self, forKey: .suggestions)
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
    public let edgeQualityConfidence: Double
    public let pressureSupportConfidence: Double
    public let foreAftSupportConfidence: Double

    public init(
        edgeQualityScore: Double,
        edgeQualityLabel: String,
        pressureSupportScore: Double,
        pressureSupportLabel: String,
        foreAftSupportScore: Double,
        foreAftSupportLabel: String,
        edgeQualityConfidence: Double = 0,
        pressureSupportConfidence: Double = 0,
        foreAftSupportConfidence: Double = 0
    ) {
        self.edgeQualityScore = edgeQualityScore
        self.edgeQualityLabel = edgeQualityLabel
        self.pressureSupportScore = pressureSupportScore
        self.pressureSupportLabel = pressureSupportLabel
        self.foreAftSupportScore = foreAftSupportScore
        self.foreAftSupportLabel = foreAftSupportLabel
        self.edgeQualityConfidence = max(0, min(1, edgeQualityConfidence))
        self.pressureSupportConfidence = max(0, min(1, pressureSupportConfidence))
        self.foreAftSupportConfidence = max(0, min(1, foreAftSupportConfidence))
    }

    enum CodingKeys: String, CodingKey {
        case edgeQualityScore
        case edgeQualityLabel
        case pressureSupportScore
        case pressureSupportLabel
        case foreAftSupportScore
        case foreAftSupportLabel
        case edgeQualityConfidence
        case pressureSupportConfidence
        case foreAftSupportConfidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        edgeQualityScore = try container.decode(Double.self, forKey: .edgeQualityScore)
        edgeQualityLabel = try container.decode(String.self, forKey: .edgeQualityLabel)
        pressureSupportScore = try container.decode(Double.self, forKey: .pressureSupportScore)
        pressureSupportLabel = try container.decode(String.self, forKey: .pressureSupportLabel)
        foreAftSupportScore = try container.decode(Double.self, forKey: .foreAftSupportScore)
        foreAftSupportLabel = try container.decode(String.self, forKey: .foreAftSupportLabel)
        edgeQualityConfidence = try container.decodeIfPresent(Double.self, forKey: .edgeQualityConfidence) ?? 0
        pressureSupportConfidence = try container.decodeIfPresent(Double.self, forKey: .pressureSupportConfidence) ?? 0
        foreAftSupportConfidence = try container.decodeIfPresent(Double.self, forKey: .foreAftSupportConfidence) ?? 0
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

// MARK: - 高光时刻

/// 标记视频中滑得最好的连续片段。
public struct HighlightMoment: Codable {
    public let startTime: String
    public let endTime: String
    public let startSeconds: Double
    public let endSeconds: Double
    public let duration: Double
    public let score: Double
    public let confidence: Double
    public let title: String
    public let description: String

    public init(
        startTime: String,
        endTime: String,
        startSeconds: Double,
        endSeconds: Double,
        duration: Double,
        score: Double,
        confidence: Double,
        title: String,
        description: String
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.duration = duration
        self.score = max(0, min(100, score))
        self.confidence = max(0, min(1, confidence))
        self.title = title
        self.description = description
    }
}

// MARK: - 转弯阶段分析

/// 画面方向上的压刃方向。v1 不推断 toe side / heel side。
public enum EdgeDirection: String, Codable, CaseIterable {
    case imageLeft
    case imageRight
    case neutral
    case unknown
}

/// 单板转弯中的粗阶段。
public enum TurnPhase: String, Codable, CaseIterable {
    case transition
    case initiation
    case shaping
    case release
}

/// 单帧转弯阶段分析。
public struct TurnFrameAnalysis: Codable {
    public let time: Double
    public let edgeSignal: Double
    public let edgeDirection: EdgeDirection
    public let phase: TurnPhase
    public let confidence: Double

    public init(time: Double, edgeSignal: Double, edgeDirection: EdgeDirection, phase: TurnPhase, confidence: Double) {
        self.time = time
        self.edgeSignal = edgeSignal
        self.edgeDirection = edgeDirection
        self.phase = phase
        self.confidence = confidence
    }
}

/// 一次连续同向压刃片段。
public struct TurnSegment: Codable {
    public let startTime: Double
    public let endTime: Double
    public let startTimeString: String
    public let endTimeString: String
    public let edgeDirection: EdgeDirection
    public let frameCount: Int
    public let phaseDistribution: [String: Double]
    public let mainIssue: String

    public init(
        startTime: Double,
        endTime: Double,
        startTimeString: String,
        endTimeString: String,
        edgeDirection: EdgeDirection,
        frameCount: Int,
        phaseDistribution: [String: Double],
        mainIssue: String
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.startTimeString = startTimeString
        self.endTimeString = endTimeString
        self.edgeDirection = edgeDirection
        self.frameCount = frameCount
        self.phaseDistribution = phaseDistribution
        self.mainIssue = mainIssue
    }
}

/// 顶层转弯分析结果。
public struct TurnAnalysis: Codable {
    public let frames: [TurnFrameAnalysis]
    public let segments: [TurnSegment]

    public static let empty = TurnAnalysis(frames: [], segments: [])

    public init(frames: [TurnFrameAnalysis], segments: [TurnSegment]) {
        self.frames = frames
        self.segments = segments
    }
}

// MARK: - 重心阶段适配分析

/// 单帧重心是否适合当前滑行阶段/转弯阶段。
public struct CenterOfMassFrameAnalysis: Codable {
    public let time: Double
    public let hipRatio: Double
    public let targetRangeLower: Double
    public let targetRangeUpper: Double
    public let phase: TurnPhase?
    public let score: Double
    public let confidence: Double
    public let issue: String

    public init(
        time: Double,
        hipRatio: Double,
        targetRangeLower: Double,
        targetRangeUpper: Double,
        phase: TurnPhase?,
        score: Double,
        confidence: Double,
        issue: String
    ) {
        self.time = time
        self.hipRatio = hipRatio
        self.targetRangeLower = targetRangeLower
        self.targetRangeUpper = targetRangeUpper
        self.phase = phase
        self.score = max(0, min(100, score))
        self.confidence = max(0, min(1, confidence))
        self.issue = issue
    }
}

/// 顶层重心阶段适配分析结果。旧 `PoseScore.gravityScore` 保留作为兼容字段。
public struct CenterOfMassAnalysis: Codable {
    public let cogStageFitScore: Double
    public let confidence: Double
    public let label: String
    public let stage: String
    public let frameCount: Int
    public let mainIssue: String?
    public let frames: [CenterOfMassFrameAnalysis]

    public static let empty = CenterOfMassAnalysis(
        cogStageFitScore: 0,
        confidence: 0,
        label: "无检测数据",
        stage: "unknown",
        frameCount: 0,
        mainIssue: nil,
        frames: []
    )

    public init(
        cogStageFitScore: Double,
        confidence: Double,
        label: String,
        stage: String,
        frameCount: Int,
        mainIssue: String?,
        frames: [CenterOfMassFrameAnalysis]
    ) {
        self.cogStageFitScore = max(0, min(100, cogStageFitScore))
        self.confidence = max(0, min(1, confidence))
        self.label = label
        self.stage = stage
        self.frameCount = frameCount
        self.mainIssue = mainIssue
        self.frames = frames
    }
}

// MARK: - 板身方向与横滑分析

/// 板身线条识别来源。v1 使用脚踝连线作为低成本代理，并逐步引入图像候选线。
public enum BoardObservationSource: String, Codable, CaseIterable {
    case ankleProxy
    case visualCandidate
    case mixed
}

/// 单帧板身线条观测。
public struct BoardObservation: Codable {
    public let source: BoardObservationSource
    public let axisAngle: Double
    public let centerX: Double
    public let centerY: Double
    public let confidence: Double
    /// 可视化线段长度，相对于短边归一化。nil 表示使用默认调试长度。
    public let lengthRatio: Double?

    public init(
        source: BoardObservationSource,
        axisAngle: Double,
        centerX: Double,
        centerY: Double,
        confidence: Double,
        lengthRatio: Double? = nil
    ) {
        self.source = source
        self.axisAngle = axisAngle
        self.centerX = centerX
        self.centerY = centerY
        self.confidence = max(0, min(1, confidence))
        self.lengthRatio = lengthRatio.map { max(0.02, min(1, $0)) }
    }
}

// MARK: - 板身刃线观测（Phase 1 诊断能力，候选 A）

/// 板身刃线逐帧观测的门控状态。
///
/// `board` 代表检测到归属本滑者、站姿可靠的板轴；`fallback` 代表主检测失败但姿态几何
/// 合成的降级板轴有效；其余状态均为“不可用”的具体原因，供诊断与覆盖率统计。
public enum BoardEdgeStatus: String, Codable, CaseIterable {
    /// 检测到归属本滑者、站姿可靠的板轴。
    case board
    /// 主检测失败，由姿态几何合成的降级板轴（详见 `BoardEdgeObservation.fallbackAxis`）。
    case fallback
    /// 未启用板身刃线检测（默认关闭路径）。
    case disabled
    /// Vision / 分割未能产出可用掩码。
    case noMask
    /// 踝点置信度不足，无法可靠定位 ROI。
    case ankleLowCnf
    /// 主体占比过小（远景/雪雾），分割不具备足部细节。
    case farShot
    /// ROI 内未形成可识别主轴。
    case noAxis
    /// 主轴近竖直，判为雪杖/裤腿/竖直他人而非板。
    case rejectVertical
    /// 主轴归一长度越界（过短噪声或过长物体）。
    case rejectLength
    /// 主轴延伸率不足，判为团块而非细长板身。
    case rejectBlob
    /// 主轴几何虽成立，但空间上不归属本滑者（如背景中他人的板）。
    case rejectOwnership
    /// 主体处于摔倒/坐姿等非站立状态，板轴不代表滑行刃线质量。
    case rejectPosture
}

/// 降级板轴的姿态几何来源。
public enum BoardFallbackSource: String, Codable {
    /// 双踝连线（一阶代理，双脚沿板长前后固定）。
    case anklePair
    /// 双膝连线（二阶弱代理，膝可相对板扭转）。
    case kneePair
}

/// 主检测失败时由姿态几何合成的降级板轴（ADR-001，仅诊断）。
public struct FallbackAxis: Codable, Equatable {
    public let source: BoardFallbackSource
    /// 板轴相对水平的无符号夹角（0...90，度）。
    public let axisAngle: Double
    /// 关节对中点 X（归一化 0...1）。
    public let centerX: Double
    /// 关节对中点 Y（归一化 0...1）。
    public let centerY: Double
    /// 关节对归一间距（仅展示用，0.02...1）。
    public let lengthRatio: Double
    /// 合成置信度（点置信度 × 几何置信度 × 源权重，0...1）。
    public let confidence: Double
    /// 触发降级合成的原始主检测拒绝状态。
    public let originalStatus: BoardEdgeStatus

    public init(
        source: BoardFallbackSource,
        axisAngle: Double,
        centerX: Double,
        centerY: Double,
        lengthRatio: Double,
        confidence: Double,
        originalStatus: BoardEdgeStatus
    ) {
        self.source = source
        self.axisAngle = max(0, min(90, axisAngle))
        self.centerX = max(0, min(1, centerX))
        self.centerY = max(0, min(1, centerY))
        self.lengthRatio = max(0.02, min(1, lengthRatio))
        self.confidence = max(0, min(1, confidence))
        self.originalStatus = originalStatus
    }
}

/// 单帧板身刃线观测（Phase 1，仅诊断，不参与评分）。
///
/// 由前景实例分割 + 踝下 ROI PCA 得到；字段为归一化几何量，跨次确定性由纯函数计算保证。
public struct BoardEdgeObservation: Codable {
    public let status: BoardEdgeStatus
    /// 板轴相对水平的无符号夹角（0...90，度）。仅 `status == .board` 时有效，否则为 nil。
    public let axisAngle: Double?
    /// 主轴中心 X（归一化 0...1）。
    public let centerX: Double?
    /// 主轴中心 Y（归一化 0...1）。
    public let centerY: Double?
    /// 主轴等效全长 / 图宽。
    public let lengthRatio: Double?
    /// 主轴延伸率（长轴/短轴，越大越细长）。
    public let elongation: Double?
    /// 前景主体占整帧比例（近景门控输入）。
    public let subjectFraction: Double?
    /// 踝点定位置信度（0...1）。
    public let ankleConfidence: Double?
    /// `status == .fallback` 时的降级板轴；其余状态为 nil。
    public let fallbackAxis: FallbackAxis?

    public init(
        status: BoardEdgeStatus,
        axisAngle: Double? = nil,
        centerX: Double? = nil,
        centerY: Double? = nil,
        lengthRatio: Double? = nil,
        elongation: Double? = nil,
        subjectFraction: Double? = nil,
        ankleConfidence: Double? = nil,
        fallbackAxis: FallbackAxis? = nil
    ) {
        self.status = status
        self.axisAngle = axisAngle
        self.centerX = centerX.map { max(0, min(1, $0)) }
        self.centerY = centerY.map { max(0, min(1, $0)) }
        self.lengthRatio = lengthRatio.map { max(0, min(1, $0)) }
        self.elongation = elongation.map { max(0, $0) }
        self.subjectFraction = subjectFraction.map { max(0, min(1, $0)) }
        self.ankleConfidence = ankleConfidence.map { max(0, min(1, $0)) }
        self.fallbackAxis = fallbackAxis
    }

    /// 默认关闭路径的占位观测。
    public static let disabled = BoardEdgeObservation(status: .disabled)
}

// MARK: - 板轴刃线时序连续性（ADR-004，仅诊断，不参与评分）

/// 时序窗口未通过的原因（ADR-004，§12.15）。
public enum BoardTemporalRejectReason: String, Codable {
    /// 窗口内有效候选数不足（< minCount）。
    case insufficientCandidates
    /// 窗口角度离散度过大（IQR > iqrGate）。
    case unstableIQR
    /// 角度跨 PCA 0/90° 折叠边界且无行进方向信号可重建有向角。
    case foldCrossing
}

/// 帧对齐的时序窗口聚合产物（ADR-004，§12.15）。
public struct BoardTemporalAxisPoint: Codable, Equatable {
    /// 对应 DetectionResult 的帧序号。
    public let frameIndex: Int
    /// 该帧的因果前向窗是否通过稳定性门控。
    public let windowPass: Bool
    /// 窗口内有效候选数。
    public let candidateCount: Int
    /// 窗口角度中位数（通过时有效，0...90；未通过为 nil）。
    public let medianAngle: Double?
    /// 窗口候选置信度中位数（通过时有效，0...1；未通过为 nil）。
    public let medianConfidence: Double?
    /// 窗口角度 IQR（度）。
    public let iqr: Double?
    /// 窗口内源多数派（通过时有效；tie 取 ankle）。
    public let source: BoardFallbackSource?
    /// 未通过原因（通过时为 nil）。
    public let rejectReason: BoardTemporalRejectReason?

    public init(
        frameIndex: Int,
        windowPass: Bool,
        candidateCount: Int,
        medianAngle: Double? = nil,
        medianConfidence: Double? = nil,
        iqr: Double? = nil,
        source: BoardFallbackSource? = nil,
        rejectReason: BoardTemporalRejectReason? = nil
    ) {
        self.frameIndex = frameIndex
        self.windowPass = windowPass
        self.candidateCount = candidateCount
        self.medianAngle = medianAngle.map { max(0, min(90, $0)) }
        self.medianConfidence = medianConfidence.map { max(0, min(1, $0)) }
        self.iqr = iqr.map { max(0, $0) }
        self.source = source
        self.rejectReason = rejectReason
    }
}

/// 聚合器参数回声（写入 JSON 保证结果自解释，ADR-004）。
public struct BoardTrajectoryConfigEcho: Codable, Equatable {
    public let windowSize: Int
    public let minCount: Int
    public let iqrGate: Double
    public let sampleInterval: Double
    public let foldLowAngle: Double
    public let foldHighAngle: Double

    public init(
        windowSize: Int,
        minCount: Int,
        iqrGate: Double,
        sampleInterval: Double,
        foldLowAngle: Double,
        foldHighAngle: Double
    ) {
        self.windowSize = windowSize
        self.minCount = minCount
        self.iqrGate = iqrGate
        self.sampleInterval = sampleInterval
        self.foldLowAngle = foldLowAngle
        self.foldHighAngle = foldHighAngle
    }
}

/// 片级板轴刃线连续性度量（ADR-004，§12.15；进 summary `boardTrajectory`）。
public struct BoardTrajectoryMetrics: Codable, Equatable {
    /// 可评估窗口数（窗口至少含 1 个候选）。
    public let evaluatedWindows: Int
    /// 通过稳定性门控的窗口数。
    public let stableWindows: Int
    /// 通过窗数 / 可评估窗数（0...1）。
    public let stableWindowRate: Double
    /// 连续通过窗最长段（帧数）。
    public let longestStableRunFrames: Int
    /// 连续通过窗最长段（秒）。
    public let longestStableRunSeconds: Double
    /// 连续通过段数量。
    public let stableRunCount: Int
    /// 连续通过段平均长度（秒）。
    public let stableRunMeanSeconds: Double
    /// 落在连续稳定段内的帧占全部帧比例（0...1）。
    public let stableFrameCoverage: Double
    /// 折叠窗（无方向信号被保守拒绝）占可评估窗比例（0...1）。
    public let foldCrossingRate: Double
    /// 拒绝原因分布（按原因计数，键顺序在编码时由聚合器显式排序）。
    public let rejectHist: [String: Int]
    /// 参数回声。
    public let configEcho: BoardTrajectoryConfigEcho
    /// 帧对齐窗口产物（默认仅含通过帧；debug 下含全量）。
    public let points: [BoardTemporalAxisPoint]

    public init(
        evaluatedWindows: Int,
        stableWindows: Int,
        stableWindowRate: Double,
        longestStableRunFrames: Int,
        longestStableRunSeconds: Double,
        stableRunCount: Int,
        stableRunMeanSeconds: Double,
        stableFrameCoverage: Double,
        foldCrossingRate: Double,
        rejectHist: [String: Int],
        configEcho: BoardTrajectoryConfigEcho,
        points: [BoardTemporalAxisPoint]
    ) {
        self.evaluatedWindows = evaluatedWindows
        self.stableWindows = stableWindows
        self.stableWindowRate = max(0, min(1, stableWindowRate))
        self.longestStableRunFrames = longestStableRunFrames
        self.longestStableRunSeconds = max(0, longestStableRunSeconds)
        self.stableRunCount = stableRunCount
        self.stableRunMeanSeconds = max(0, stableRunMeanSeconds)
        self.stableFrameCoverage = max(0, min(1, stableFrameCoverage))
        self.foldCrossingRate = max(0, min(1, foldCrossingRate))
        self.rejectHist = rejectHist
        self.configEcho = configEcho
        self.points = points
    }
}

/// 单帧板身与运动方向关系。
public struct BoardKinematics: Codable {
    public let boardAngle: Double
    public let travelAngle: Double
    /// 板身方向与移动方向的夹角，范围 0...90。越小越接近沿板身走刃，越大越接近横滑。
    public let sideslipAngle: Double
    public let carvingConfidence: Double
    public let confidence: Double

    public init(
        boardAngle: Double,
        travelAngle: Double,
        sideslipAngle: Double,
        carvingConfidence: Double,
        confidence: Double
    ) {
        self.boardAngle = boardAngle
        self.travelAngle = travelAngle
        self.sideslipAngle = max(0, min(90, sideslipAngle))
        self.carvingConfidence = max(0, min(100, carvingConfidence))
        self.confidence = max(0, min(1, confidence))
    }
}

/// 单帧板身方向分析。
public struct BoardFrameAnalysis: Codable {
    public let time: Double
    public let observation: BoardObservation
    public let kinematics: BoardKinematics?

    public init(time: Double, observation: BoardObservation, kinematics: BoardKinematics?) {
        self.time = time
        self.observation = observation
        self.kinematics = kinematics
    }
}

/// 全视频板身与横滑概要。
public struct BoardAnalysisSummary: Codable {
    public let frameCount: Int
    public let averageSideslipAngle: Double?
    public let carvingConfidence: Double?
    public let confidence: Double
    public let source: BoardObservationSource

    public init(
        frameCount: Int,
        averageSideslipAngle: Double?,
        carvingConfidence: Double?,
        confidence: Double,
        source: BoardObservationSource
    ) {
        self.frameCount = frameCount
        self.averageSideslipAngle = averageSideslipAngle
        self.carvingConfidence = carvingConfidence
        self.confidence = max(0, min(1, confidence))
        self.source = source
    }
}

/// 顶层板身方向与横滑分析结果。
public struct BoardAnalysis: Codable {
    public let frames: [BoardFrameAnalysis]
    public let summary: BoardAnalysisSummary?

    public static let empty = BoardAnalysis(frames: [], summary: nil)

    public init(frames: [BoardFrameAnalysis], summary: BoardAnalysisSummary?) {
        self.frames = frames
        self.summary = summary
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
    public let visualBoardObservation: BoardObservation?
    /// 板身刃线观测（Phase 1 诊断，默认关；关闭时为 status=.disabled）。不参与评分。
    public var boardEdgeObservation: BoardEdgeObservation?
    public var skiMetrics: SkiDerivedMetrics?
    /// 帧分析错误信息（抽帧或 Vision 请求失败时填充，成功时为 nil）
    public var error: String?

    public init(
        time: Double,
        objects: [ObjectItem],
        faces: [FaceItem],
        textObservations: [String],
        sceneClassifications: [SceneItem],
        bodyPose: BodyPoseData,
        poseScore: PoseScore?,
        visualBoardObservation: BoardObservation? = nil,
        boardEdgeObservation: BoardEdgeObservation? = nil,
        skiMetrics: SkiDerivedMetrics? = nil,
        error: String? = nil
    ) {
        self.time = time
        self.objects = objects
        self.faces = faces
        self.textObservations = textObservations
        self.sceneClassifications = sceneClassifications
        self.bodyPose = bodyPose
        self.poseScore = poseScore
        self.visualBoardObservation = visualBoardObservation
        self.boardEdgeObservation = boardEdgeObservation
        self.skiMetrics = skiMetrics
        self.error = error
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
    /// 可靠帧的加权原始均分（未取最佳片段、未证据封顶、未光流调制）
    public let rawPoseAverageScore: Double?
    /// 可靠帧中表现最好的前 1/3 加权均分（未证据封顶、未光流调制）
    public let bestThirdAverageScore: Double?
    /// 姿态、走刃、板身和可靠时长证据封顶后的分数（光流调制前）
    public let evidenceCappedScore: Double?
    /// 光流调制系数，最终分 = evidenceCappedScore × flowModulationFactor
    public let flowModulationFactor: Double?
    /// 参与光流计算的帧对数量
    public let flowFramePairsUsed: Int?
    /// 光流运动一致性 0-100（Phase 1 实验指标）
    public let flowMotionCoherence: Double?
    /// 光流方向稳定性 0-100（Phase 1 实验指标）
    public let flowDirectionalStability: Double?
    /// 光流速度平滑度 0-100（Phase 1 实验指标）
    public let flowVelocitySmoothness: Double?
    /// P0 (2026-09-15) Flow Modulation Edge-Confidence Gating：走刃证据门控是否实际 kill 了上行加成。
    /// - `true`：`boardKinematicConfidence < 0.30 && coherence > 70` 且未走方案 (c) 低分保护路径，
    ///   flow ×1.05 加成已被门控钳制到 ×1.00（v4/v6 场景）。
    /// - `false`：门控条件未满足或无上行加成可 kill（v2/v3/v5 场景，以及 v1 因低分保护实际未被 kill）。
    /// - `nil`：无光流数据（`framePairsUsed < 2`）或历史归档，报告端不显示门控标记。
    /// 报告端 [ReportGenerator](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) 根据此字段追加"（走刃证据不足，未加成）"标记，避免二次计算门控条件。
    public let flowModulationGated: Bool?
    /// 板轴刃线连续性时序度量（ADR-004，§12.15；仅 `--board-edge` 启用时非 nil，纯诊断不参与评分）。
    public let boardTrajectory: BoardTrajectoryMetrics?

    public init(
        averageScore: Double,
        bestFrame: FrameScore,
        worstFrame: FrameScore,
        stabilityScore: Double,
        scoreConsistencyScore: Double,
        scoreStdDev: Double,
        overallLevel: String,
        rawPoseAverageScore: Double? = nil,
        bestThirdAverageScore: Double? = nil,
        evidenceCappedScore: Double? = nil,
        flowModulationFactor: Double? = nil,
        flowFramePairsUsed: Int? = nil,
        flowMotionCoherence: Double? = nil,
        flowDirectionalStability: Double? = nil,
        flowVelocitySmoothness: Double? = nil,
        flowModulationGated: Bool? = nil,
        boardTrajectory: BoardTrajectoryMetrics? = nil
    ) {
        self.averageScore = averageScore
        self.bestFrame = bestFrame
        self.worstFrame = worstFrame
        self.stabilityScore = stabilityScore
        self.scoreConsistencyScore = scoreConsistencyScore
        self.scoreStdDev = scoreStdDev
        self.overallLevel = overallLevel
        self.rawPoseAverageScore = rawPoseAverageScore
        self.bestThirdAverageScore = bestThirdAverageScore
        self.evidenceCappedScore = evidenceCappedScore
        self.flowModulationFactor = flowModulationFactor
        self.flowFramePairsUsed = flowFramePairsUsed
        self.flowMotionCoherence = flowMotionCoherence
        self.flowDirectionalStability = flowDirectionalStability
        self.flowVelocitySmoothness = flowVelocitySmoothness
        self.flowModulationGated = flowModulationGated
        self.boardTrajectory = boardTrajectory
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

public struct AnalysisOutput: Codable, Identifiable {
    public var id: String { videoPath }
    public let videoPath: String
    public let duration: Double
    public let totalFrames: Int
    public let frames: [DetectionResult]
    public let summary: VideoSummary
    public let skiMetrics: SkiDerivedMetrics  // 全视频平均滑雪派生指标
    public let keyMoments: [KeyMoment]        // 关键时刻列表
    public let highlightMoments: [HighlightMoment] // 滑得最好的连续片段
    public let centerOfMassAnalysis: CenterOfMassAnalysis // 重心阶段适配分析
    public let boardAnalysis: BoardAnalysis    // 板身方向与横滑分析
    public let turnAnalysis: TurnAnalysis      // 单板转弯阶段分析

    public init(
        videoPath: String,
        duration: Double,
        totalFrames: Int,
        frames: [DetectionResult],
        summary: VideoSummary,
        skiMetrics: SkiDerivedMetrics,
        keyMoments: [KeyMoment],
        highlightMoments: [HighlightMoment] = [],
        centerOfMassAnalysis: CenterOfMassAnalysis = .empty,
        boardAnalysis: BoardAnalysis = .empty,
        turnAnalysis: TurnAnalysis = .empty
    ) {
        self.videoPath = videoPath
        self.duration = duration
        self.totalFrames = totalFrames
        self.frames = frames
        self.summary = summary
        self.skiMetrics = skiMetrics
        self.keyMoments = keyMoments
        self.highlightMoments = highlightMoments
        self.centerOfMassAnalysis = centerOfMassAnalysis
        self.boardAnalysis = boardAnalysis
        self.turnAnalysis = turnAnalysis
    }

    enum CodingKeys: String, CodingKey {
        case videoPath
        case duration
        case totalFrames
        case frames
        case summary
        case skiMetrics
        case keyMoments
        case highlightMoments
        case centerOfMassAnalysis
        case boardAnalysis
        case turnAnalysis
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        videoPath = try container.decode(String.self, forKey: .videoPath)
        duration = try container.decode(Double.self, forKey: .duration)
        totalFrames = try container.decode(Int.self, forKey: .totalFrames)
        frames = try container.decode([DetectionResult].self, forKey: .frames)
        summary = try container.decode(VideoSummary.self, forKey: .summary)
        skiMetrics = try container.decode(SkiDerivedMetrics.self, forKey: .skiMetrics)
        keyMoments = try container.decode([KeyMoment].self, forKey: .keyMoments)
        highlightMoments = try container.decodeIfPresent([HighlightMoment].self, forKey: .highlightMoments) ?? []
        centerOfMassAnalysis = try container.decodeIfPresent(CenterOfMassAnalysis.self, forKey: .centerOfMassAnalysis) ?? .empty
        boardAnalysis = try container.decodeIfPresent(BoardAnalysis.self, forKey: .boardAnalysis) ?? .empty
        turnAnalysis = try container.decodeIfPresent(TurnAnalysis.self, forKey: .turnAnalysis) ?? .empty
    }
}
