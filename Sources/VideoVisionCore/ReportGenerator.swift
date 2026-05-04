import Foundation

// MARK: - 报告上下文

/// 整理后的分析上下文，供报告生成使用
public struct ReportContext {
    public let avgScore: Double
    public let stage: StageLabel
    public let fLean: Double
    public let fLeanConfidence: Double
    public let knee: Double
    public let kneeConfidence: Double
    public let calf: Double
    public let calfConfidence: Double
    public let grav: Double
    public let gravConfidence: Double
    public let cogFit: Double
    public let cogFitConfidence: Double
    public let cogFitLabel: String
    public let cogFitMainIssue: String?
    public let sym: Double
    public let symConfidence: Double
    public let stability: Double
    public let stdDev: Double
    public let visibility: VisibilityLevel
    public let hasPoseData: Bool
    public let stableCarvingBaseline: StableCarvingBaseline?

    public init(avgScore: Double, stage: StageLabel, fLean: Double, fLeanConfidence: Double, knee: Double, kneeConfidence: Double, calf: Double, calfConfidence: Double, grav: Double, gravConfidence: Double, cogFit: Double, cogFitConfidence: Double, cogFitLabel: String, cogFitMainIssue: String?, sym: Double, symConfidence: Double, stability: Double, stdDev: Double, visibility: VisibilityLevel, hasPoseData: Bool, stableCarvingBaseline: StableCarvingBaseline?) {
        self.avgScore = avgScore
        self.stage = stage
        self.fLean = fLean
        self.fLeanConfidence = fLeanConfidence
        self.knee = knee
        self.kneeConfidence = kneeConfidence
        self.calf = calf
        self.calfConfidence = calfConfidence
        self.grav = grav
        self.gravConfidence = gravConfidence
        self.cogFit = cogFit
        self.cogFitConfidence = cogFitConfidence
        self.cogFitLabel = cogFitLabel
        self.cogFitMainIssue = cogFitMainIssue
        self.sym = sym
        self.symConfidence = symConfidence
        self.stability = stability
        self.stdDev = stdDev
        self.visibility = visibility
        self.hasPoseData = hasPoseData
        self.stableCarvingBaseline = stableCarvingBaseline
    }
}

// MARK: - 阶段标签

/// 基于综合表现的阶段划分（方案四）
public enum StageLabel: String, CaseIterable {
    case basicDetection   = "基础识别阶段"
    case basicControl     = "基础控速阶段"
    case stableSkiing     = "稳定滑行阶段"
    case carvingEmerging  = "刻滑雏形阶段"
    case qualitySkiing    = "高质量滑行阶段"
    case advanced         = "高阶表现阶段"

    public var description: String {
        switch self {
        case .basicDetection:
            return "姿态或检测信息不足，先检查基础站姿和雪道适应性"
        case .basicControl:
            return "能控制速度，但动作质量还比较基础，滑行方式以推雪和搓雪为主"
        case .stableSkiing:
            return "能稳定滑下来，但转弯质量主要依赖搓雪而不是走刃"
        case .carvingEmerging:
            return "有走刃倾向，部分弯能看到刻滑影子，但刃线还不够持续"
        case .qualitySkiing:
            return "姿态、稳定性和立刃质量都较好，动作看起来干净"
        case .advanced:
            return "从姿态指标看已经非常优秀，动作控制力强"
        }
    }
}

// MARK: - 自然语言语料库（方案二）

/// 为每个维度/分数区间提供多条自然语言变体
public struct NarrativeLibrary {
    public init() {}

    /// 根据分数和种子值选择一条语料
    /// - Parameters:
    ///   - corpus: 候选语料数组
    ///   - seed: 种子值（用于确定性的伪随机选择）
    /// - Returns: 选中语料
    public static func pick(from corpus: [String], seed: Int = 0) -> String {
        guard !corpus.isEmpty else { return "" }
        let index = abs(seed) % corpus.count
        return corpus[index]
    }

    // MARK: - 教练观察（主评价段）

    /// 各阶段的教练观察语料，每阶段多条
    public static let coachObservation: [StageLabel: [String]] = [
        .basicDetection: [
            "这段视频中关键点检测不够完整，可能因为人物在画面中偏小或动作过快。可以先检查人物的拍摄距离和角度。",
            "检测到的人体关键点不足，难以进行完整的姿态评估。建议确保全身在画面中可见。"
        ],
        .basicControl: [
            "目前处于基础练习阶段，动作还在建立感觉，转弯以推雪为主。",
            "处在基础控速期内：能滑下去但动作质量还没有系统建立，建议先关注稳定性和对称性。"
        ],
        .stableSkiing: [
            "这段已经能稳定滑下来，基础姿态和速度控制都有了，但转弯质量还主要依赖搓雪，离持续走刃还有距离。",
            "整体滑行比较稳，没有明显失控，但转弯主要是靠横向刮雪完成的。你已经进入了能把速度控制住、但还没有真正把板刃立起来切雪的阶段。",
            "控速已经不是问题，问题在于转弯的完成方式：目前以搓雪为主，所以来得比较稳，但立刃质量上不去。",
            "基础姿态基础不错，前倾和膝盖都有一定支撑，但弯中缺少真正的刃角支撑，所以视觉上动作偏稳但不够干脆。"
        ],
        .carvingEmerging: [
            "有刻滑的雏形了，部分弯能看到你试图用刃转弯，但刃角还不够持续，弯尾容易散掉。整体还停留在能做出形状、但刃线不够干净的阶段。",
            "部分弯已经有走刃倾向，不是全程都在扫雪，但刃角的保持时间和弯形还有提升空间。",
            "已经有明显的走刃意识，弯中能看到立刃动作，但还不够持续稳定，有些弯到中途又回到了扫雪状态。"
        ],
        .qualitySkiing: [
            "整体姿态控制不错，立刃质量已经稳定较好的水平，动作看起来干净。",
            "刻滑质量较高，姿态保持和立刃端都表现不错，动作一致性好。"
        ],
        .advanced: [
            "姿态指标表现非常优秀，各维度都在高分区间，动作控制力强。",
            "从数据看已经达到高阶水准，动作质量高。"
        ]
    ]

    // MARK: - 立刃评价语料（多条变体）

    static let calfLowCorpus = [
        "转弯主要还是靠横向刮雪完成，刃没有持续咬住雪面。",
        "板尾扫雪感比较明显，目前更像搓雪弯而不是干净的刻滑弯。",
        "你能把弯转出来，但大部分转向不是靠整条刃画弧完成的。",
        "雪板横向滑移偏多，说明用刃质量还不够稳定。",
        "这段控速没问题，但走刃质量还跟不上。"
    ]

    static let calfMidCorpus = [
        "立刃有基础，但刃角保持时间不足，弯中容易提前释放。",
        "部分弯能看到立刃动作，但全程一致性不够，好的弯和松的弯交替出现。",
        "刃角幅度尚可，但距离持续稳定的走刃还有一段路。"
    ]

    static let calfHighCorpus = [
        "立刃角度不错，有刻滑的感觉了。",
        "走刃质量好，弯形比较干净。"
    ]

    // MARK: - 重心评价语料

    static let gravLowCorpus = [
        "重心偏高，身体没有真正压进弯里，影响板压建立。",
        "髋部位置偏高，弯中板刃支撑不够扎实。",
        "下半身虽然能弯，但重心位置仍然偏高，动作看起来不够贴雪。",
        "身体重心偏高是这段最明显的短板，弯中容易产生滑移。"
    ]

    static let gravMidCorpus = [
        "重心控制还行，但还有进一步降低的空间来获得更好稳定性。",
        "重心位置尚可，不算高但也不算低，弯中稳定性和爆发力还有提升空间。"
    ]

    static let gravHighCorpus = [
        "重心较低，弯中稳定性好。",
        "重心控制到位，滑行姿态扎实。"
    ]

    static let cogFitLowCorpus = [
        "以当前阶段看，重心高度和转弯阶段不太匹配，弯中承压不够稳定。",
        "重心适配度偏低，不是单纯要更低，而是需要在入弯、弯中和出弯之间更贴合动作节奏。",
        "当前重心位置对这个阶段的动作支持不够，容易让板压建立变慢或弯中支撑散掉。"
    ]

    static let cogFitMidCorpus = [
        "重心阶段适配度一般，基础可控，但弯中承压阶段还可以更稳定。",
        "重心高度大体能用，但和转弯阶段的配合还不够精细。"
    ]

    static let cogFitHighCorpus = [
        "重心高度和当前滑行阶段比较匹配，动作支撑感较好。",
        "重心适配度不错，没有为了压低而压低，整体更符合当前阶段。"
    ]

    // MARK: - 膝盖评价语料

    static let kneeLowCorpus = [
        "膝盖过于直立，腿部缺乏弹性，很难有效吸收地形变化。",
        "膝盖弯曲不足是主要瓶颈，站起来滑的方式会限制控板能力。"
    ]

    static let kneeMidCorpus = [
        "膝盖弯曲角度一般，有下压空间但还没有完全利用。",
        "腿部姿态还可以，但弯中下压幅度可以更大。"
    ]

    static let kneeHighCorpus = [
        "膝盖弯曲充分，腿部弹性好，这是这段的优点。",
        "腿部姿态并不差，膝盖弯曲到位，问题更多出在刃角而不是姿态上。",
        "膝盖弯曲是这段的亮点，说明你已经能主动降低姿态。"
    ]

    // MARK: - 前倾评价语料

    static let fLeanLowCorpus = [
        "身体前倾不足，有后坐倾向，影响发力效率。",
        "上半身不够积极向前，重心偏后影响板头控制。"
    ]

    static let fLeanMidCorpus = [
        "前倾角度还有优化空间，保持背部平直、肩部在脚踝前方会更有效。",
        "身体前倾一般，不算后坐但也不够积极。"
    ]

    static let fLeanHighCorpus = [
        "身体前倾角度合理，能有效利用重力。",
        "前倾姿态不错，上半身姿态积极。"
    ]

    // MARK: - 对称性语料

    static let symLowCorpus = [
        "左右两边动作质量不太一致，可能一侧更会压，另一侧更依赖扫雪。",
        "左右不对称较明显，弱势侧的弯会拖低整体流畅度。",
        "左右腿发力均衡性需要改善，建议单独练左右弯对比。"
    ]

    static let symMidCorpus = [
        "左右有一定不对称，但不算严重，注意强化弱势侧即可。",
        "对称性还有改进空间，转弯质量左右有差异。"
    ]

    static let symHighCorpus = [
        "左右动作对称性好，发力均衡。",
        "两侧动作一致性不错，基本功均衡。"
    ]

    // MARK: - 稳定性语料

    static let unstableCorpus = [
        "动作稳定性偏低，各帧之间姿态变化较大。",
        "动作连贯性可以更好，当前各帧的姿态一致性不够。"
    ]

    // MARK: - 选择器

    /// 根据分数选择对应的语料库和种子
    static func narrative(for dimension: String, score: Double, seed: Int) -> String {
        switch dimension {
        case "calf":
            if score < 45 { return pick(from: calfLowCorpus, seed: seed) }
            if score < 65 { return pick(from: calfMidCorpus, seed: seed) }
            return pick(from: calfHighCorpus, seed: seed)
        case "grav":
            if score < 50 { return pick(from: gravLowCorpus, seed: seed) }
            if score < 70 { return pick(from: gravMidCorpus, seed: seed) }
            return pick(from: gravHighCorpus, seed: seed)
        case "cogFit":
            if score < 50 { return pick(from: cogFitLowCorpus, seed: seed) }
            if score < 70 { return pick(from: cogFitMidCorpus, seed: seed) }
            return pick(from: cogFitHighCorpus, seed: seed)
        case "knee":
            if score < 65 { return pick(from: kneeLowCorpus, seed: seed) }
            if score < 80 { return pick(from: kneeMidCorpus, seed: seed) }
            return pick(from: kneeHighCorpus, seed: seed)
        case "fLean":
            if score < 55 { return pick(from: fLeanLowCorpus, seed: seed) }
            if score < 70 { return pick(from: fLeanMidCorpus, seed: seed) }
            return pick(from: fLeanHighCorpus, seed: seed)
        case "sym":
            if score < 55 { return pick(from: symLowCorpus, seed: seed) }
            if score < 70 { return pick(from: symMidCorpus, seed: seed) }
            return pick(from: symHighCorpus, seed: seed)
        default:
            return ""
        }
    }
}

// MARK: - 报告生成器

public struct ReportGenerator {
    private static let lowConfidenceThreshold = 0.35
    private static let cautiousConfidenceThreshold = 0.65

    public init() {}

    public static func generate(output: AnalysisOutput) -> String {
        let ctx = buildContext(output: output)
        let supportsBoardQuality = output.boardAnalysis.summary?.averageSideslipAngle != nil
        let ski = output.skiMetrics
        let edgeQualityName = supportsBoardQuality ? "走刃质量" : "走刃倾向"
        let edgeConfidence = supportsBoardQuality
            ? min(ski.edgeQualityConfidence, output.boardAnalysis.summary?.confidence ?? ski.edgeQualityConfidence)
            : ski.edgeQualityConfidence
        let edgeJudgmentIsReliable = edgeConfidence >= lowConfidenceThreshold
        let weakEdgeEvidence = hasWeakEdgeEvidence(ctx)
        let reliableFrameCount = reliablePoseFrames(from: output.frames).count
        let separator = String(repeating: "=", count: 54)
        var lines: [String] = []

        // 标题
        lines.append(separator)
        lines.append("  🎿 滑雪姿态分析报告")
        lines.append(separator)
        lines.append("")
        lines.append("  视频：\(URL(fileURLWithPath: output.videoPath).lastPathComponent)")
        lines.append("  时长：\(formatDuration(output.duration)) · "
                      + "分析帧数：\(output.frames.filter(\.bodyPose.detected).count)/\(output.totalFrames)")
        lines.append("")

        // 综合评分（保留分数）
        let emoji: String
        switch ctx.stage {
        case .advanced:           emoji = "🏆"
        case .qualitySkiing:      emoji = "⭐"
        case .carvingEmerging:    emoji = "📈"
        case .stableSkiing:       emoji = "📈"
        case .basicControl, .basicDetection: emoji = "💪"
        }
        lines.append("  \(emoji) 综合评分：\(String(format: "%.0f", ctx.avgScore))/100")
        lines.append("  🏷 阶段判断：\(ctx.stage.rawValue)")
        lines.append("  📐 评分口径：取可靠片段中表现最好的前 1/3 加权平均")
        if weakEdgeEvidence {
            lines.append("  ⚠️ 持续立刃证据不足：前倾和屈膝不能单独推高综合分，已按初中级表现封顶")
        }
        if reliableFrameCount < AnalysisReliability.minimumHighlightFrameCount {
            lines.append("  ⚠️ 可靠评分片段不足：仅 \(reliableFrameCount) 帧，综合分已保守封顶")
        } else if reliableFrameCount < 12 {
            lines.append("  ⚠️ 可靠评分片段偏少：\(reliableFrameCount) 帧，综合分仅作谨慎参考")
        }
        lines.append("")

        // 阶段描述
        if let baseline = ctx.stableCarvingBaseline {
            lines.append("  📋 检测到连续稳定的高质量刻滑平台，低分帧可能受大倒伏、低姿态或遮挡影响；综合评分采用该稳定平台作为基线。")
            lines.append("     基线片段：\(formatTime(seconds: baseline.plateauStartTime))-\(formatTime(seconds: baseline.plateauEndTime))")
        } else if weakEdgeEvidence {
            lines.append("  📋 持续立刃证据不足，转弯更接近扫雪/搓雪控制；姿态项看起来有支撑，但还不能评价为高质量滑行。")
        } else if edgeJudgmentIsReliable {
            lines.append("  📋 \(ctx.stage.description)")
        } else {
            lines.append("  📋 走刃/横滑判断置信度不足，本报告只参考可靠可见帧；低姿态或遮挡片段不做负面判断。")
        }
        lines.append("")

        // 教练观察（主评价）
        let seed = videoSeed(output.videoPath)
        let mainObservation: String
        if ctx.stableCarvingBaseline != nil {
            mainObservation = "这段动作稳定性很高，系统不应把部分低分帧直接理解成滑得差；更合理的解释是姿态识别在大倒伏或低姿态刻滑时产生了冲突。"
        } else if weakEdgeEvidence {
            mainObservation = "这段不能因为身体前倾或膝盖弯曲看起来还可以就给高分；核心问题是缺少持续刃角和干净刃线，整体仍属于基础滑行质量。"
        } else if edgeJudgmentIsReliable {
            mainObservation = NarrativeLibrary.pick(
                from: NarrativeLibrary.coachObservation[ctx.stage] ?? [],
                seed: seed
            )
        } else {
            mainObservation = "这段视频里可能存在低姿态、大立刃或遮挡导致的关键点缺失，系统不应据此判断为搓雪或走刃不足。建议结合视频原片复核。"
        }
        if !mainObservation.isEmpty {
            lines.append("  🗣 教练观察")
            lines.append("  \(mainObservation)")
            lines.append("")
        }

        // 滑雪维度评分
        lines.append("  🎿 滑雪维度评分")
        lines.append(makeSkiScoreLine(edgeQualityName, ski.edgeQualityScore, ski.edgeQualityLabel, confidence: edgeConfidence))
        lines.append(makeSkiScoreLine("板压支撑", ski.pressureSupportScore, ski.pressureSupportLabel, confidence: ski.pressureSupportConfidence))
        lines.append(makeSkiScoreLine("前后支撑", ski.foreAftSupportScore, ski.foreAftSupportLabel, confidence: ski.foreAftSupportConfidence))
        if ctx.stableCarvingBaseline != nil, output.centerOfMassAnalysis.confidence < cautiousConfidenceThreshold {
            lines.append("    ⬜⬜⬜⬜⬜ 重心阶段适配 暂不评分 · 稳定刻滑基线与重心关键点识别冲突 · 置信度 \(formatConfidence(output.centerOfMassAnalysis.confidence))")
        } else {
            lines.append(makeCenterOfMassScoreLine(output.centerOfMassAnalysis))
        }
        if ctx.stableCarvingBaseline != nil, ctx.kneeConfidence < cautiousConfidenceThreshold {
            lines.append("    ⬜⬜⬜⬜⬜ 腿部弹性 暂不评分 · 稳定刻滑基线与膝部关键点识别冲突 · 置信度 \(formatConfidence(ctx.kneeConfidence))")
        } else {
            lines.append(makeSkiScoreLine("腿部弹性", ctx.knee, kneeLabel(ctx.knee), confidence: ctx.kneeConfidence))
        }
        lines.append(makeSkiScoreLine("左右一致性", ctx.sym, symLabel(ctx.sym), confidence: ctx.symConfidence))
        lines.append("")

        // 板身方向与横滑分析
        if let boardSummary = output.boardAnalysis.summary {
            lines.append("  🏂 板身方向与横滑")
            lines.append(boardSummaryLine(boardSummary))
            lines.append("    说明：当前用左右脚踝连线代理板身，侧面画面更可靠；正面、背面或遮挡时置信度会下降。")
            lines.append("")
        }

        // 转弯阶段分析
        if ctx.stableCarvingBaseline != nil {
            lines.append("  🧭 转弯阶段分析")
            lines.append("  • 检测到连续稳定高质量片段；低分阶段暂不输出“刃角不足/搓雪”类负面结论。")
            lines.append("")
        } else if !output.turnAnalysis.segments.isEmpty {
            lines.append("  🧭 转弯阶段分析")
            for segment in output.turnAnalysis.segments.prefix(3) {
                lines.append(turnSegmentLine(segment))
                if segment.mainIssue != "阶段衔接基本正常" {
                    lines.append("    建议：\(stageAdvice(for: segment.mainIssue))")
                }
            }
            lines.append("")
        }

        // 高光片段
        if !output.highlightMoments.isEmpty {
            lines.append("  ✨ 高光时刻")
            for moment in output.highlightMoments.prefix(3) {
                lines.append(highlightMomentLine(moment))
                lines.append("    \(moment.description)")
            }
            lines.append("")
        }

        // 分项评分（保留，用于调试）
        lines.append("  🔎 原始姿态指标（调试参考）")
        lines.append(makeScoreLine("身体前倾", ctx.fLean, "fLean", seed: seed + 1, confidence: ctx.fLeanConfidence))
        lines.append(makeScoreLine("膝盖弯曲", ctx.knee, "knee", seed: seed + 2, confidence: ctx.kneeConfidence))
        lines.append(makeScoreLine("小腿倾斜", ctx.calf, "calf", seed: seed + 3, confidence: ctx.calfConfidence))
        lines.append(makeScoreLine("重心高度旧分", ctx.grav, "grav", seed: seed + 4, confidence: ctx.gravConfidence))
        lines.append(makeScoreLine("动作对称", ctx.sym, "sym", seed: seed + 5, confidence: ctx.symConfidence))
        lines.append("")

        // 关键时刻
        if !output.keyMoments.isEmpty {
            lines.append("  🔍 关键时刻")
            for km in output.keyMoments {
                let title = edgeQualityLanguage(km.title, supportsBoardQuality: supportsBoardQuality)
                let description = edgeQualityLanguage(km.description, supportsBoardQuality: supportsBoardQuality)
                if km.type == "best_edge" {
                    lines.append("  ⭐ \(km.time) · \(title)")
                } else {
                    lines.append("  ⚠️ \(km.time) · \(title)")
                }
                lines.append("    \(description)")
            }
            lines.append("")
        }

        // 优势
        let strengths = buildStrengths(ctx: ctx, seed: seed)
        if !strengths.isEmpty {
            lines.append("  ✅ 优势")
            for s in strengths {
                lines.append("    • \(edgeQualityLanguage(s, supportsBoardQuality: supportsBoardQuality))")
            }
            lines.append("")
        }

        // 主要问题
        let problems = buildProblems(ctx: ctx, seed: seed)
        if !problems.isEmpty {
            lines.append("  ⚠️ 主要问题")
            for p in problems {
                lines.append("    • \(edgeQualityLanguage(p, supportsBoardQuality: supportsBoardQuality))")
            }
            lines.append("")
        }

        // 训练建议
        lines.append("  🎯 训练建议")
        lines.append(edgeQualityLanguage(trainingAdvice(ctx: ctx, seed: seed), supportsBoardQuality: supportsBoardQuality))
        lines.append("")

        // 波动提示
        if ctx.stdDev > 18 {
            lines.append("  ⚡ 波动提示")
            lines.append("  各帧评分波动较大（标准差 \(String(format: "%.1f", ctx.stdDev))），"
                         + "动作一致性需要加强。")
            lines.append("")
        }

        lines.append(separator)
        return lines.joined(separator: "\n")
    }

    // MARK: - 上下文构建

    private static func buildContext(output: AnalysisOutput) -> ReportContext {
        let s = output.summary
        let frames = reliablePoseFrames(from: output.frames)
        let scores = frames.compactMap { $0.poseScore }

        let hasPoseData = !scores.isEmpty
        let (fLean, knee, calf, grav, sym) = hasPoseData
            ? StageClassifier.averageSubScores(from: output.frames)
            : (50, 50, 50, 50, 50)
        let (fLeanConfidence, kneeConfidence, calfConfidence, gravConfidence, symConfidence) = hasPoseData
            ? averageSubScoreConfidences(from: scores)
            : (0, 0, 0, 0, 0)

        let visibility = frames.last?.bodyPose.visibility ?? .none

        let stableBaseline = stableCarvingBaseline(from: output.frames, motionStability: s.stabilityScore)
        let stage = StageClassifier.determineStage(
            averageScore: s.averageScore,
            calfScore: calf,
            kneeScore: knee,
            stabilityScore: s.stabilityScore
        )
        let cog = output.centerOfMassAnalysis
        let cogFit = cog.frameCount > 0 ? cog.cogStageFitScore : grav
        let cogFitConfidence = cog.frameCount > 0 ? cog.confidence : 0
        let cogFitLabel = cog.frameCount > 0 ? cog.label : "无检测数据"

        return ReportContext(
            avgScore: s.averageScore,
            stage: stage,
            fLean: fLean,
            fLeanConfidence: fLeanConfidence,
            knee: knee,
            kneeConfidence: kneeConfidence,
            calf: calf,
            calfConfidence: calfConfidence,
            grav: grav,
            gravConfidence: gravConfidence,
            cogFit: cogFit,
            cogFitConfidence: cogFitConfidence,
            cogFitLabel: cogFitLabel,
            cogFitMainIssue: cog.mainIssue,
            sym: sym,
            symConfidence: symConfidence,
            stability: s.stabilityScore,
            stdDev: s.scoreStdDev,
            visibility: visibility,
            hasPoseData: hasPoseData,
            stableCarvingBaseline: stableBaseline
        )
    }

    /// 阶段判断逻辑
    private static func determineStage(avg: Double, calf: Double, knee: Double, stability: Double) -> StageLabel {
        if avg < 50 || avg == 0 { return .basicDetection }
        if avg < 60 { return .basicControl }
        if avg >= 80 { return calf >= 65 ? .advanced : .qualitySkiing }
        if avg >= 70 && calf >= 55 && knee >= 70 { return .carvingEmerging }
        if avg >= 75 { return .qualitySkiing }
        if avg >= 70 && calf < 55 { return .stableSkiing }
        return .stableSkiing
    }

    // MARK: - 优势识别

    private static func buildStrengths(ctx: ReportContext, seed: Int) -> [String] {
        guard ctx.hasPoseData else { return [] }
        var result: [String] = []

        // 只选评分 >= 75 且确实突出的维度
        var candidates: [(score: Double, corpus: [String], seedOffset: Int)] = []
        if ctx.knee >= 80, isHighConfidence(ctx.kneeConfidence) { candidates.append((ctx.knee, NarrativeLibrary.kneeHighCorpus, 10)) }
        if ctx.fLean >= 80, isHighConfidence(ctx.fLeanConfidence) { candidates.append((ctx.fLean, NarrativeLibrary.fLeanHighCorpus, 11)) }
        if ctx.calf >= 70, isHighConfidence(ctx.calfConfidence) { candidates.append((ctx.calf, NarrativeLibrary.calfHighCorpus, 12)) }
        if ctx.cogFit >= 80, isHighConfidence(ctx.cogFitConfidence) {
            candidates.append((ctx.cogFit, NarrativeLibrary.cogFitHighCorpus, 13))
        }
        if ctx.sym >= 80, isHighConfidence(ctx.symConfidence) { candidates.append((ctx.sym, NarrativeLibrary.symHighCorpus, 14)) }
        if ctx.stability >= 70 { candidates.append((ctx.stability, ["动作连贯性好，姿态保持稳定"], 15)) }

        // 按分数从高到低排序，最多取 3 条
        candidates.sort { $0.score > $1.score }
        for c in candidates.prefix(3) {
            result.append(NarrativeLibrary.pick(from: c.corpus, seed: seed + c.seedOffset))
        }
        return result
    }

    // MARK: - 问题识别

    private static func buildProblems(ctx: ReportContext, seed: Int) -> [String] {
        guard ctx.hasPoseData else { return [] }
        var result: [String] = []

        // 按问题严重程度排序（分越低越优先）
        var issues: [(score: Double, label: String, seedOffset: Int)] = []

        if isUsableConfidence(ctx.calfConfidence), !shouldSuppressCarvingConflictIssue(ctx) {
            if ctx.calf < 50 { issues.append((ctx.calf, "calf", 20)) }
            else if ctx.calf < 65 { issues.append((ctx.calf, "calf", 20)) }
        }

        if isUsableConfidence(ctx.cogFitConfidence), !shouldSuppressCarvingConflictIssue(ctx) {
            if ctx.cogFit < 50 { issues.append((ctx.cogFit, "cogFit", 21)) }
            else if ctx.cogFit < 65 { issues.append((ctx.cogFit, "cogFit", 21)) }
        }

        if isUsableConfidence(ctx.kneeConfidence), !shouldSuppressCarvingConflictIssue(ctx) {
            if ctx.knee < 55 { issues.append((ctx.knee, "knee", 22)) }
            else if ctx.knee < 80 { issues.append((ctx.knee, "knee", 22)) }
        }

        if isUsableConfidence(ctx.fLeanConfidence) {
            if ctx.fLean < 55 { issues.append((ctx.fLean, "fLean", 23)) }
            else if ctx.fLean < 65 { issues.append((ctx.fLean, "fLean", 23)) }
        }

        if isUsableConfidence(ctx.symConfidence) {
            if ctx.sym < 55 { issues.append((ctx.sym, "sym", 24)) }
            else if ctx.sym < 65 { issues.append((ctx.sym, "sym", 24)) }
        }

        if ctx.stability < 45 { issues.append((ctx.stability, "stability", 25)) }

        // 按分数升序排序（最严重在前）
        issues.sort { $0.score < $1.score }

        for issue in issues.prefix(3) {
            let text = NarrativeLibrary.narrative(for: issue.label, score: issue.score, seed: seed + issue.seedOffset)
            if !text.isEmpty {
                result.append(text)
            }
        }

        return result
    }

    // MARK: - 训练建议

    private static func trainingAdvice(ctx: ReportContext, seed: Int) -> String {
        guard ctx.hasPoseData else { return "未检测到人体姿态，无法给出训练建议。" }

        if ctx.stableCarvingBaseline != nil {
            return "这段更适合作为稳定刻滑来评价。训练重点不是从搓雪转走刃，而是继续保持弯中承压、弯形节奏和身体倒伏的稳定；如果要细化建议，建议用侧后方全身入镜角度复拍，减少膝踝关键点误识别。"
        }

        // 找到最弱维度
        var allScores: [(label: String, score: Double)] = []
        if isUsableConfidence(ctx.calfConfidence) {
            allScores.append(("calf", ctx.calf))
        }
        if isUsableConfidence(ctx.kneeConfidence) {
            allScores.append(("knee", ctx.knee))
        }
        if isUsableConfidence(ctx.fLeanConfidence) {
            allScores.append(("fLean", ctx.fLean))
        }
        if isUsableConfidence(ctx.symConfidence) {
            allScores.append(("sym", ctx.sym))
        }
        if isUsableConfidence(ctx.cogFitConfidence) {
            allScores.append(("cogFit", ctx.cogFit))
        }
        guard allScores.count >= 3 else {
            return "当前可用姿态数据置信度偏低，建议先用侧后方、全身入镜的视频重新拍摄，再做具体训练判断。"
        }
        let sorted = allScores.sorted { $0.score < $1.score }

        guard let primary = sorted.first, primary.score < 70 else {
            let advices: [String] = [
                "继续练习保持当前水平，逐步优化各维度细节。",
                "各维度表现都不错，可以在速度或坡度上适当增加挑战。",
                "整体姿态保持得不错，多滑多积累即可。"
            ]
            return NarrativeLibrary.pick(from: advices, seed: seed + 30)
        }

        let advice: String
        let seed2 = seed + 31
        switch primary.label {
        case "calf":
            if ctx.calf < 40 {
                let texts: [String] = [
                    "先从搓雪过渡到走刃开始。在缓坡上反复练习横穿走刃（traversing），专注用板刃切雪而不是推雪。目标是留下细线而不是大片雪雾。",
                    "不要太在意低姿态或摸雪，先把转弯方式从扫雪改成用刃。在缓坡上练简单的刻弧弯，先求刃线干净再增加速度。",
                    "当前最需要转换的是转弯方式。建议在缓坡上一个弯一个弯地练：入弯时主动立刃，而不是先横板再扫雪转弯。"
                ]
                advice = NarrativeLibrary.pick(from: texts, seed: seed2)
            } else {
                let texts: [String] = [
                    "刃角幅度有基础了，重点转为保持时间。试着在整个弯中持续加压，不要中途释放。",
                    "立刃感觉已经有了，现在需要加强的是全程一致性——让每个弯的立刃质量都差不多。"
                ]
                advice = NarrativeLibrary.pick(from: texts, seed: seed2)
            }

        case "cogFit":
            let texts: [String] = [
                "先不要把目标理解成一味压低重心。更有效的是让重心跟转弯阶段匹配：入弯逐步进入新弯，弯中稳定承压，出弯平顺释放。",
                "练习时关注髋部高度是否随阶段变化合理：弯中不要突然起身，换刃时也不要为了低而僵住。",
                "可以用慢速大弯练重心节奏：入弯建立方向，弯中稳定压住，出弯逐步释放，而不是全程同一个高度硬撑。"
            ]
            advice = NarrativeLibrary.pick(from: texts, seed: seed2)

        case "knee":
            if ctx.knee < 55 {
                let texts: [String] = [
                    "膝盖弯曲角度需要大幅改善。在滑行中主动屈膝屈髋，保持小腿前侧贴住雪鞋鞋舌。",
                    "目前站得太直了，这会让你失去对板压的控制。试试蹲低一些滑，让膝盖始终处于弹性区间。"
                ]
                advice = NarrativeLibrary.pick(from: texts, seed: seed2)
            } else {
                let texts: [String] = [
                    "膝盖弯曲还有提升空间，弯中持续加大下压幅度，用腿部伸缩来控制板压。",
                    "下压幅度可以再大一些，利用腿部弹簧来吸收地形变化。"
                ]
                advice = NarrativeLibrary.pick(from: texts, seed: seed2)
            }

        case "fLean":
            let texts: [String] = [
                "身体前倾角度需要调整。保持背部平直，肩部在脚踝前方，不要过度弯腰或后坐。",
                "上半身可以更积极一些，想象胸口朝向下山方向，这样重心自然就前移了。"
            ]
            advice = NarrativeLibrary.pick(from: texts, seed: seed2)

        case "sym":
            let texts: [String] = [
                "左右不对称说明一侧转弯更顺手、另一侧在代偿。在缓坡上刻意练弱势侧的转弯，可以请人拍视频对比左右弯差异。",
                "左右动作不一致很常见。试试只练弱势侧转弯，暂时不用管优势侧，先把弱侧的感觉建立起来。"
            ]
            advice = NarrativeLibrary.pick(from: texts, seed: seed2)

        default:
            advice = "继续练习，逐步优化各维度表现。"
        }

        // 稳定性附加
        let stabilityNote: String
        if ctx.stability < 35 {
            let texts: [String] = [
                "另外动作稳定性较低，建议在相同速度下反复练习同一个弯型，稳定了再提速。",
                "还有一个明显问题是动作起伏太大，同一段视频里姿态变化明显。建议先固定好姿态再换弯形。"
            ]
            stabilityNote = "\n\n" + NarrativeLibrary.pick(from: texts, seed: seed2 + 10)
        } else if ctx.stability < 50 {
            stabilityNote = "\n\n同时注意保持动作的连贯性，减少各帧之间的姿态波动。"
        } else {
            stabilityNote = ""
        }

        return advice + stabilityNote
    }

    // MARK: - 辅助

    /// 计算文件名的稳定哈希（DJB2 算法），确保同一视频跨运行输出一致
    /// Swift 的 hashValue 使用随机种子，跨进程不稳定。
    private static func videoSeed(_ path: String) -> Int {
        let name = URL(fileURLWithPath: path).lastPathComponent
        var hash = 5381
        for byte in name.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return abs(hash)
    }

    private static func averageSubScores(from frames: [DetectionResult]) -> (forwardLean: Double, kneeBend: Double, calfLean: Double, gravity: Double, symmetry: Double) {
        let scores = reliablePoseScores(from: frames)
        guard !scores.isEmpty else { return (50, 50, 50, 50, 50) }
        let count = Double(scores.count)
        return (
            forwardLean: scores.map(\.forwardLeanScore).reduce(0, +) / count,
            kneeBend: scores.map(\.kneeBendScore).reduce(0, +) / count,
            calfLean: scores.map(\.calfLeanScore).reduce(0, +) / count,
            gravity: scores.map(\.gravityScore).reduce(0, +) / count,
            symmetry: scores.map(\.symmetryScore).reduce(0, +) / count
        )
    }

    private static func averageSubScoreConfidences(from scores: [PoseScore]) -> (forwardLean: Double, kneeBend: Double, calfLean: Double, gravity: Double, symmetry: Double) {
        guard !scores.isEmpty else { return (0, 0, 0, 0, 0) }
        return (
            forwardLean: average(scores.map(\.forwardLeanConfidence)),
            kneeBend: average(scores.map(\.kneeBendConfidence)),
            calfLean: average(scores.map(\.calfLeanConfidence)),
            gravity: average(scores.map(\.gravityConfidence)),
            symmetry: average(scores.map(\.symmetryConfidence))
        )
    }

    private static func makeScoreLine(_ label: String, _ score: Double, _ dim: String, seed: Int, confidence: Double? = nil) -> String {
        let bar: String
        if score >= 80 {
            bar = "🟢🟢🟢🟢🟢"
        } else if score >= 65 {
            bar = "🟢🟢🟢🟡⬜"
        } else if score >= 50 {
            bar = "🟢🟢🟡⬜⬜"
        } else {
            bar = "🟡⬜⬜⬜⬜"
        }
        guard let confidence else {
            return "    \(bar) \(label) \(String(format: "%.0f", score))/100"
        }
        return "    \(bar) \(label) \(String(format: "%.0f", score))/100 · 置信度 \(formatConfidence(confidence))"
    }

    private static func makeSkiScoreLine(_ label: String, _ score: Double, _ tag: String, confidence: Double? = nil) -> String {
        if let confidence, confidence < lowConfidenceThreshold {
            return "    ⬜⬜⬜⬜⬜ \(label) 暂不评分 · 数据置信度不足 · 置信度 \(formatConfidence(confidence))"
        }

        let bar: String
        if score >= 80 {
            bar = "🟢🟢🟢🟢🟢"
        } else if score >= 65 {
            bar = "🟢🟢🟢🟡⬜"
        } else if score >= 50 {
            bar = "🟢🟢🟡⬜⬜"
        } else {
            bar = "🟡⬜⬜⬜⬜"
        }
        guard let confidence else {
            return "    \(bar) \(label) \(String(format: "%.0f", score))/100 · \(tag)"
        }
        let suffix = confidence < cautiousConfidenceThreshold ? " · 谨慎参考" : ""
        return "    \(bar) \(label) \(String(format: "%.0f", score))/100 · \(tag) · 置信度 \(formatConfidence(confidence))\(suffix)"
    }

    private static func centerOfMassTag(_ analysis: CenterOfMassAnalysis) -> String {
        guard analysis.frameCount > 0 else { return "无检测数据" }
        if let issue = analysis.mainIssue, analysis.cogStageFitScore < 70 {
            return "\(analysis.label) · \(issue)"
        }
        return analysis.label
    }

    private static func makeCenterOfMassScoreLine(_ analysis: CenterOfMassAnalysis) -> String {
        guard analysis.frameCount > 0 else {
            return "    ⬜⬜⬜⬜⬜ 重心阶段适配 暂不评分 · 无检测数据"
        }

        if analysis.confidence < lowConfidenceThreshold {
            let confidence = String(format: "%.0f", analysis.confidence * 100)
            return "    ⬜⬜⬜⬜⬜ 重心阶段适配 暂不评分 · \(analysis.label) · 置信度 \(confidence)/100"
        }

        return makeSkiScoreLine(
            "重心阶段适配",
            analysis.cogStageFitScore,
            centerOfMassTag(analysis),
            confidence: analysis.confidence
        )
    }

    private static func kneeLabel(_ score: Double) -> String {
        if score >= 80 { return "腿部弹性好" }
        if score >= 65 { return "弹性尚可" }
        if score >= 50 { return "弹性偏弱" }
        return "过于直立"
    }

    private static func symLabel(_ score: Double) -> String {
        if score >= 80 { return "左右一致" }
        if score >= 65 { return "轻微不对称" }
        if score >= 50 { return "明显不对称" }
        return "严重不对称"
    }

    private static func turnSegmentLine(_ segment: TurnSegment) -> String {
        let direction: String
        switch segment.edgeDirection {
        case .imageLeft: direction = "画面左侧压刃"
        case .imageRight: direction = "画面右侧压刃"
        case .neutral: direction = "平板过渡"
        case .unknown: direction = "方向不明"
        }

        let dominantPhase = segment.phaseDistribution
            .max { $0.value < $1.value }
            .map { phaseLabel($0.key) } ?? "阶段不明"

        return "  • \(segment.startTimeString)-\(segment.endTimeString) · \(direction) · 主要阶段：\(dominantPhase) · \(segment.mainIssue)"
    }

    private static func highlightMomentLine(_ moment: HighlightMoment) -> String {
        let confidenceSuffix = moment.confidence < cautiousConfidenceThreshold
            ? " · 置信度 \(formatConfidence(moment.confidence)) · 谨慎参考"
            : ""
        return "  ⭐ \(moment.startTime)-\(moment.endTime) · \(moment.title) · \(String(format: "%.0f", moment.score))/100\(confidenceSuffix)"
    }

    private static func boardSummaryLine(_ summary: BoardAnalysisSummary) -> String {
        let source = boardSourceLabel(summary.source)
        let confidence = String(format: "%.0f", summary.confidence * 100)
        guard let sideslip = summary.averageSideslipAngle,
              let carving = summary.carvingConfidence else {
            return "    识别到 \(summary.frameCount) 帧板身线条代理 · 数据来源：\(source) · 置信度 \(confidence)/100；画面位移不足，暂不估计横滑角。"
        }

        if summary.confidence < lowConfidenceThreshold {
            return "    横滑角暂不评分 · 数据来源：\(source) · 置信度 \(confidence)/100；当前画面角度不足以稳定判断走刃/横滑。"
        }

        return "    平均横滑角 \(String(format: "%.0f", sideslip))° · 走刃置信 \(String(format: "%.0f", carving))/100 · \(boardKinematicsLabel(sideslip)) · 数据来源：\(source) · 置信度 \(confidence)/100"
    }

    private static func boardSourceLabel(_ source: BoardObservationSource) -> String {
        switch source {
        case .ankleProxy:
            return "脚踝代理"
        }
    }

    private static func boardKinematicsLabel(_ sideslip: Double) -> String {
        if sideslip <= 15 { return "沿板身移动明显" }
        if sideslip <= 30 { return "有走刃倾向" }
        if sideslip <= 45 { return "横滑偏多" }
        return "以横滑为主"
    }

    private static func edgeQualityLanguage(_ text: String, supportsBoardQuality: Bool) -> String {
        guard !supportsBoardQuality else { return text }
        return text.replacingOccurrences(of: "走刃质量", with: "走刃倾向")
    }

    private static func isUsableConfidence(_ confidence: Double) -> Bool {
        confidence >= lowConfidenceThreshold
    }

    private static func isHighConfidence(_ confidence: Double) -> Bool {
        confidence >= cautiousConfidenceThreshold
    }

    private static func shouldSuppressCarvingConflictIssue(_ ctx: ReportContext) -> Bool {
        guard ctx.stableCarvingBaseline != nil else { return false }
        return ctx.kneeConfidence < cautiousConfidenceThreshold || ctx.calfConfidence < cautiousConfidenceThreshold
    }

    private static func hasWeakEdgeEvidence(_ ctx: ReportContext) -> Bool {
        ctx.stableCarvingBaseline == nil
            && ctx.calfConfidence >= lowConfidenceThreshold
            && ctx.calf < 42
    }

    private static func formatConfidence(_ confidence: Double) -> String {
        "\(String(format: "%.0f", confidence * 100))/100"
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func phaseLabel(_ rawValue: String) -> String {
        switch rawValue {
        case TurnPhase.transition.rawValue: return "换刃/过渡"
        case TurnPhase.initiation.rawValue: return "入弯"
        case TurnPhase.shaping.rawValue: return "弯中承压"
        case TurnPhase.release.rawValue: return "出弯释放"
        default: return rawValue
        }
    }

    private static func stageAdvice(for issue: String) -> String {
        switch issue {
        case "弯中刃角保持不足":
            return "把注意力放在弯中持续压刃，不要刚立起来就提前释放。"
        case "入弯建立刃角偏晚":
            return "换刃后更早让身体进入新弯，先建立方向再加压。"
        case "出弯释放不够平顺":
            return "出弯时逐步释放板压，避免突然起身或横向甩尾。"
        default:
            return "保持阶段衔接稳定，再逐步增加速度和弯形幅度。"
        }
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return "\(mins)分\(secs)秒"
    }

    private static func formatTime(seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
