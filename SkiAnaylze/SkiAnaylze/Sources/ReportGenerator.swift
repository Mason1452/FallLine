import Foundation

// MARK: - 报告上下文

/// 整理后的分析上下文，供报告生成使用
struct ReportContext {
    let avgScore: Double
    let stage: StageLabel
    let fLean: Double
    let knee: Double
    let calf: Double
    let grav: Double
    let sym: Double
    let stability: Double
    let stdDev: Double
    let visibility: VisibilityLevel
    let hasPoseData: Bool
}

// MARK: - 阶段标签

/// 基于综合表现的阶段划分（方案四）
enum StageLabel: String {
    case basicDetection   = "基础识别阶段"
    case basicControl     = "基础控速阶段"
    case stableSkiing     = "稳定滑行阶段"
    case carvingEmerging  = "刻滑雏形阶段"
    case qualitySkiing    = "高质量滑行阶段"
    case advanced         = "高阶表现阶段"

    var description: String {
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
struct NarrativeLibrary {

    /// 根据分数和种子值选择一条语料
    /// - Parameters:
    ///   - corpus: 候选语料数组
    ///   - seed: 种子值（用于确定性的伪随机选择）
    /// - Returns: 选中语料
    static func pick(from corpus: [String], seed: Int = 0) -> String {
        guard !corpus.isEmpty else { return "" }
        let index = abs(seed) % corpus.count
        return corpus[index]
    }

    // MARK: - 教练观察（主评价段）

    /// 各阶段的教练观察语料，每阶段多条
    static let coachObservation: [StageLabel: [String]] = [
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
        case "knee":
            if score < 55 { return pick(from: kneeLowCorpus, seed: seed) }
            if score < 70 { return pick(from: kneeMidCorpus, seed: seed) }
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

struct ReportGenerator {

    static func generate(output: AnalysisOutput) -> String {
        let ctx = buildContext(output: output)
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
        lines.append("")

        // 阶段描述
        lines.append("  📋 \(ctx.stage.description)")
        lines.append("")

        // 教练观察（主评价）
        let seed = videoSeed(output.videoPath)
        let mainObservation = NarrativeLibrary.pick(
            from: NarrativeLibrary.coachObservation[ctx.stage] ?? [],
            seed: seed
        )
        if !mainObservation.isEmpty {
            lines.append("  🗣 教练观察")
            lines.append("  \(mainObservation)")
            lines.append("")
        }

        // 滑雪维度评分
        let ski = output.skiMetrics
        lines.append("  🎿 滑雪维度评分")
        lines.append(makeSkiScoreLine("走刃质量", ski.edgeQualityScore, ski.edgeQualityLabel))
        lines.append(makeSkiScoreLine("板压支撑", ski.pressureSupportScore, ski.pressureSupportLabel))
        lines.append(makeSkiScoreLine("前后支撑", ski.foreAftSupportScore, ski.foreAftSupportLabel))
        lines.append(makeSkiScoreLine("腿部弹性", ctx.knee, kneeLabel(ctx.knee)))
        lines.append(makeSkiScoreLine("左右一致性", ctx.sym, symLabel(ctx.sym)))
        lines.append("")

        // 分项评分（保留，用于调试）
        lines.append("  🔎 原始姿态指标（调试参考）")
        lines.append(makeScoreLine("身体前倾", ctx.fLean, "fLean", seed: seed + 1))
        lines.append(makeScoreLine("膝盖弯曲", ctx.knee, "knee", seed: seed + 2))
        lines.append(makeScoreLine("小腿倾斜", ctx.calf, "calf", seed: seed + 3))
        lines.append(makeScoreLine("重心控制", ctx.grav, "grav", seed: seed + 4))
        lines.append(makeScoreLine("动作对称", ctx.sym, "sym", seed: seed + 5))
        lines.append("")

        // 关键时刻
        if !output.keyMoments.isEmpty {
            lines.append("  🔍 关键时刻")
            for km in output.keyMoments {
                if km.type == "best_edge" {
                    lines.append("  ⭐ \(km.time) · \(km.title)")
                } else {
                    lines.append("  ⚠️ \(km.time) · \(km.title)")
                }
                lines.append("    \(km.description)")
            }
            lines.append("")
        }

        // 优势
        let strengths = buildStrengths(ctx: ctx, seed: seed)
        if !strengths.isEmpty {
            lines.append("  ✅ 优势")
            for s in strengths {
                lines.append("    • \(s)")
            }
            lines.append("")
        }

        // 主要问题
        let problems = buildProblems(ctx: ctx, seed: seed)
        if !problems.isEmpty {
            lines.append("  ⚠️ 主要问题")
            for p in problems {
                lines.append("    • \(p)")
            }
            lines.append("")
        }

        // 训练建议
        lines.append("  🎯 训练建议")
        lines.append(trainingAdvice(ctx: ctx, seed: seed))
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
        let frames = output.frames.filter { $0.bodyPose.detected }
        let scores = frames.compactMap { $0.poseScore }

        let hasPoseData = !scores.isEmpty
        let (fLean, knee, calf, grav, sym) = hasPoseData
            ? averageSubScores(from: output.frames)
            : (50, 50, 50, 50, 50)

        let visibility = frames.last?.bodyPose.visibility ?? .none

        let stage = determineStage(avg: s.averageScore, calf: calf, knee: knee, stability: s.stabilityScore)

        return ReportContext(
            avgScore: s.averageScore,
            stage: stage,
            fLean: fLean,
            knee: knee,
            calf: calf,
            grav: grav,
            sym: sym,
            stability: s.stabilityScore,
            stdDev: s.scoreStdDev,
            visibility: visibility,
            hasPoseData: hasPoseData
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
        if ctx.knee >= 80 { candidates.append((ctx.knee, NarrativeLibrary.kneeHighCorpus, 10)) }
        if ctx.fLean >= 80 { candidates.append((ctx.fLean, NarrativeLibrary.fLeanHighCorpus, 11)) }
        if ctx.calf >= 70 { candidates.append((ctx.calf, NarrativeLibrary.calfHighCorpus, 12)) }
        if ctx.grav >= 80 { candidates.append((ctx.grav, NarrativeLibrary.gravHighCorpus, 13)) }
        if ctx.sym >= 80 { candidates.append((ctx.sym, NarrativeLibrary.symHighCorpus, 14)) }
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

        if ctx.calf < 50 { issues.append((ctx.calf, "calf", 20)) }
        else if ctx.calf < 65 { issues.append((ctx.calf, "calf", 20)) }

        if ctx.grav < 50 { issues.append((ctx.grav, "grav", 21)) }
        else if ctx.grav < 65 { issues.append((ctx.grav, "grav", 21)) }

        if ctx.knee < 55 { issues.append((ctx.knee, "knee", 22)) }
        else if ctx.knee < 65 { issues.append((ctx.knee, "knee", 22)) }

        if ctx.fLean < 55 { issues.append((ctx.fLean, "fLean", 23)) }
        else if ctx.fLean < 65 { issues.append((ctx.fLean, "fLean", 23)) }

        if ctx.sym < 55 { issues.append((ctx.sym, "sym", 24)) }
        else if ctx.sym < 65 { issues.append((ctx.sym, "sym", 24)) }

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

        // 找到最弱维度
        let allScores: [(label: String, score: Double)] = [
            ("calf", ctx.calf),
            ("grav", ctx.grav),
            ("knee", ctx.knee),
            ("fLean", ctx.fLean),
            ("sym", ctx.sym)
        ]
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

        case "grav":
            let texts: [String] = [
                "降低重心是这个阶段最直接的突破点。滑行时保持屈膝屈髋，上半身稳定面朝山下，不要因为速度加快而起身。",
                "尝试在转弯过程中刻意保持髋部高度不变，不要随着弯形起伏。重心稳住了，刃角和板压才能建立。",
                "想象自己坐在一个看不见的椅子上滑完整个弯——起身的瞬间就是重心失控的开始。"
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

    private static func videoSeed(_ path: String) -> Int {
        // 用文件名的 hash 作为种子，让同一个视频每次输出一致
        let name = URL(fileURLWithPath: path).lastPathComponent
        return abs(name.hashValue)
    }

    private static func averageSubScores(from frames: [DetectionResult]) -> (forwardLean: Double, kneeBend: Double, calfLean: Double, gravity: Double, symmetry: Double) {
        let scores = frames.compactMap { $0.poseScore }
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

    private static func makeScoreLine(_ label: String, _ score: Double, _ dim: String, seed: Int) -> String {
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
        return "    \(bar) \(label) \(String(format: "%.0f", score))/100"
    }

    private static func makeSkiScoreLine(_ label: String, _ score: Double, _ tag: String) -> String {
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
        return "    \(bar) \(label) \(String(format: "%.0f", score))/100 · \(tag)"
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

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return "\(mins)分\(secs)秒"
    }
}
