# Flow Modulation Edge-Confidence Gating 设计（草案 v3）

> 作者：agent
> 日期：2026-09-15
> 状态：**Draft v3 / Pending Review**（v2 基于 corpus 实测；v3 补齐阈值向量图 + spike 复核 + video 1 保护方案实测校验，[scripts/flow_gating_replay.py](file:///Users/mingsen/Project/FallLine/scripts/flow_gating_replay.py) 提供可重复计算的证据链）
> 关联：
> - [Sources/FallLineCore/FlowMetricsCalculator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift)
> - [Sources/FallLineCore/VideoAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L378-L389)
> - [Sources/FallLineCore/SkiMetricsCalculator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/SkiMetricsCalculator.swift#L80-L116)
> - [Sources/FallLineCore/BoardDirectionAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardDirectionAnalyzer.swift#L231-L258)
> - [docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md)
> - [annotations/calibration_anchors.md](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md)

---

## 0. 一句话动机

**Edge-first 重构完成后，flow modulation 成为高分样本的关键抬升器；但当 `edgeQualityConfidence` 过低（Vision 关键点不可靠）时，`motionCoherence` 高分主要来自相机运动 / 全画面平移，不是真实立刃质量证据——此时 ×1.05 加成放大的是噪声。** 本 spec 目标：让 [applyModulation](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift#L218-L230) 感知 edge 置信度，在低置信度场景下限制上行 modulation。

---

## 1. 现状回顾

### 1.1 Flow modulation 调用链

```
VideoAnalyzer.generateSummary()  (VideoAnalyzer.swift:378-389)
  │
  ├─ let flowMetrics = await computeFlowMetrics()
  ├─ let factor = flowCalculator.computeModulation(
  │     coherence: flowMetrics.motionCoherence,
  │     stability: flowMetrics.directionalStability,   // P7-A 已退役
  │     smoothness: flowMetrics.velocitySmoothness,
  │     poseScore: avg
  │  )
  └─ modulatedScore = clamp(avg * factor, 0, 100)
```

现行 [computeModulation](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift#L255-L269) 逻辑（P7-A 后）：

```swift
var modulation = 1.0
if coherence > 70 { modulation += 0.05 }            // 上行加成
if smoothness > 0 && smoothness < 40 {
    modulation -= 0.05                              // 塌陷降级信号
}
return clamp(modulation, 0.87, 1.13)                // 净有效范围 ±5%
```

**问题**：coherence / smoothness 是"帧对像素运动"派生指标，本质是"运动学"信号；它们**不携带"下半身关键点是否可靠"的信息**。当 Vision 检测崩塌（如 video 4/6：edge 置信 16/28）时，pose 分数本身就不可信，但 flow 模块看到平滑的像素运动（相机稳、全画面一致移动）依然给出 coherence=99 / 71 → 触发 +0.05。

### 1.2 主 corpus 数据（c=40 微调后，直接读 JSON）

从 [testvideo/_edgefirst_c40/{1..6}.json](file:///Users/mingsen/Project/FallLine/testvideo/_edgefirst_c40/) 精确抽取：

| Video | 综合 | rawPose | best⅓ | evidenceCapped | flow factor | motionCoherence | velocitySmoothness | **edgeQualityConfidence** | **boardAnalysis.confidence** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 60.666 | 48.807 | 57.777 | 57.777 | **×1.050** | 86.593 | 78.821 | **0.751** | **0.239** |
| 2 | 86.528 | 78.706 | 86.528 | 86.528 | ×1.000 | 52.951 | 83.958 | **0.573** | **0.292** |
| 3 | 88.132 | 76.963 | 88.132 | 88.132 | ×1.000 | 42.371 | 47.002 | **0.691** | **0.552** |
| 4 | 82.743 | 64.010 | 78.803 | 78.803 | **×1.050** | 98.539 | 58.075 | **0.581** | **0.157** |
| 5 | 73.863 | 62.841 | 73.863 | 73.863 | ×1.000 | 51.884 | 66.740 | **0.654** | **0.510** |
| 6 | 94.664 | 79.315 | 90.157 | 90.157 | **×1.050** | 70.727 | 63.240 | **0.655** | **0.280** |

**v1 修正数据来源**：Draft v1 的 §1.2 表格中 24/29/16/55/51/28 那一列实际不是原始 `edgeQualityConfidence`，
而是 [ReportGenerator.swift#L302-L305](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift#L302-L305)
展示时做的 `min(edgeQualityConfidence, boardAnalysis.summary.confidence)` 合并值。原始 `edgeQualityConfidence`
在 corpus 中 ∈ [0.573, 0.751]，作为门控信号**完全没有区分度**（v1=0.751 反而是最高的一份）。

**关键相关性重排**：
- 3 份触发 ×1.05 加成的视频（v1/v4/v6）：**boardAnalysis.confidence** 分别为 **0.239 / 0.157 / 0.280**，均 <0.30。
- 3 份未触发加成的视频（v2/v3/v5）：`boardAnalysis.confidence` 分别为 0.292 / 0.552 / 0.510。**v2 = 0.292 < 0.30 属于假阳性触发**（原本 flow ×1.000，无加成可 gate，实际零影响）。
- **`edgeQualityConfidence` 在所有 6 份中 ≥ 0.573，任何 <0.35 的阈值都会零触发**——原 Draft v1 用它做门控信号是**错误的信号源**。
- **`edgeQualityScore/100`（走刃质量分归一化）** 分布 [0.366, 0.721]，v1/v4/v5 <0.60 触发，但 v5 属于假阳性（flow ×1.000，无影响）。

### 1.3 阈值敏感度实测（静态 replay，pure-function 复现）

flow modulation 是纯函数 `min(evidenceCapped × factor, 100)`，且 factor 只依赖 `(coherence, smoothness, boardKinematicConfidence, gate)` — 从 JSON 精确抽取上述四值即可无损复现门控结果，与 Swift 真机 replay 等价。

**信号源对比**：
| 门控信号 | 阈值 <0.30 触发数 | v1 Δ | v4 Δ | v6 Δ | 结论 |
|---|---:|---:|---:|---:|---|
| **edgeQualityConfidence** | 0/6 | 0 | 0 | 0 | **信号无区分度，全部不触发** ❌ |
| **boardAnalysis.confidence** ✅ | 4/6（含 v2 假阳性零影响）| −2.89 | **−3.94** | **−4.51** | 本 spec 推荐 |
| **edgeQualityScore/100** | 0/6（阈值 <0.60 时触发 3/6，含 v5 假阳性零影响）| — | — | — | 需要抬高阈值到 0.60，语义变成"分数低时禁止加成" |

**boardKinematicConfidence 阈值敏感度**（主 corpus 6 份）：
| gate 阈值 | 触发数 | 触发样本 | 有效 kill 数（flow ×1.05→×1.0）| 累计 Δ |
|---:|---:|:---:|---:|---:|
| 0.20 | 1 | v4 | 1 | −3.94 |
| 0.25 | 2 | v1/v4 | 2 | −6.83 |
| 0.28 | 2 | v1/v4 | 2 | −6.83 |
| **0.30** ✅ | **4** | v1/v2/v4/v6 | **3** | **−11.34** |
| 0.32 | 4 | v1/v2/v4/v6 | 3 | −11.34 |
| 0.35 | 4 | v1/v2/v4/v6 | 3 | −11.34 |
| 0.40 | 4 | v1/v2/v4/v6 | 3 | −11.34 |
| 0.50 | 4 | v1/v2/v4/v6 | 3 | −11.34 |

**关键洞察**：
1. **0.30 ~ 0.40 是同一门控组（触发集完全相同）**：阈值任选 0.30 / 0.35 / 0.40 结果一致，选 0.30 因为它与 [ReportGenerator.lowConfidenceThreshold](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) "走刃暂不评分" 的行为边界对齐。
2. **0.25 不够激进**：只触发 v1/v4，会漏 v6（boardC=0.280），无法解决"专业档极端高分"问题。
3. **v6 的 boardC=0.280 是临界值**：与 0.30 相差 0.020，处于阈值下方 7% 的位置——需要 replay 确认 boardC 稳定性（多次运行的方差应 <0.02）。
4. **v2 (boardC=0.292) 是"零影响假阳性"**：门控触发但因 flow ×1.000 无加成可 kill，实际输出零变化。这**验证了门控的保守性**——即使阈值稍宽都不会伤害无 boost 的样本。

### 1.4 跨 baseline 稳定性验证（历史 corpus 一致性）

跨 `_edgefirst_c40 / _review_tick4 / baseline_alpha_on / baseline_alpha_off / _p1_baseline / _b_3d_baseline / _c_2d` 7 组 baseline × 6 samples = 42 个 JSON 数据点扫描（由 [scripts/flow_gating_replay.py](file:///Users/mingsen/Project/FallLine/scripts/flow_gating_replay.py) 的 `baseline_scan` 抽样，gate=0.30）：

| baseline | trigger（boardC<0.30 数）| kill（trigger AND flow>1.0 数）| 备注 |
|---|:---:|:---:|---|
| `_edgefirst_c40` ✅ 主 | 4 | 3 | v1/v2/v4/v6 trigger；v1/v4/v6 kill；v2 是假阳性零影响 |
| `_review_tick4` | 4 | 3 | 同上，评分基线略高（c=35 tick） |
| `baseline_alpha_on` | 4 | 3 | 同上，α 平滑开启，boardC 略降触发数不变 |
| `baseline_alpha_off` | 1 | 1 | 只有 v4 触发；v1/v6 的 boardC 在 α off 下分别为 0.304/0.332 略高于阈值 |
| `_p1_baseline` | 1 | 0 | 只有 v4 触发，历史 baseline flow 全部 ≤1.0 无 boost 可 kill |
| `_b_3d_baseline` | 1 | 0 | 同上 |
| `_c_2d` | 1 | 0 | 同上 |

**关键观察**：
- **α on 加剧 boardC 下降**：v1 α off = 0.304，α on = 0.239；v6 α off = 0.332，α on = 0.280。α on 下 board 分析读取的关节可靠度降权，导致 boardC 更精确反映"证据不足"——这是 α 期望行为的直接体现。
- **α on/off 门控输出差异**：α on 下 v6 触发（0.280<0.30），α off 下 v6 不触发（0.332>0.30），产生跨 α 状态一致性分裂。**接受**：α on 是 [PoseSmoother 默认路径](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseSmoother.swift)，opt-out 主要用于 A/B 对照，跨 α 状态一致性不是 spec 目标。
- **历史 baseline (`_p1/_b_3d/_c_2d`) 全部 flow ≤1.0**：门控在这些历史数据上"trigger 但零 kill"，说明门控**不会破坏历史评分**（无 boost 可抑制）。这也验证了门控的"单侧生效"设计：只在有 boost 可 kill 的场景下才产生分数变化。

### 1.5 一致性 review 触发的问题样本

video 4（[testvideo/_edgefirst_c40/4.md](file:///Users/mingsen/Project/FallLine/testvideo/_edgefirst_c40/4.md)）：
- 综合 82.74（**高级档**，[75, 85)；虽在高级档但接近专业下沿，与教练视觉观感"专业极限"接近）
- 报告文本的"主要问题"栏写：**"你能把弯转出来，但大部分转向不是靠整条刃画弧完成的"**
- 报告文本与打分数值内部矛盾：教练自述"中级刻滑"，打分给"高级 83"（不是"专业 83"，v2 修正）
- 关键放大器：boardAnalysis.confidence=0.157（走刃暂不评分）但 flow ×1.05 依然生效

---

## 2. 目标

- **P0**：走刃证据不足时（`boardKinematicConfidence < 0.30`），限制 flow modulation 只允许向下修正，不允许向上加成——避免"走刃暂不评分"的样本被 flow 加分。
- **P1**：保留原 ±5% 有效范围在正常置信度下的所有行为，不改变高置信度样本（v3/v5）的评分。
- **P2**：不引入新配置参数（阈值锁定 0.30，与 [ReportGenerator](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) 显示"暂不评分"的行为一致）。
- **P0/P1/P2 完成即视为 spec 收敛**。

---

## 3. 非目标

- **不改动 [computeFlowMetrics](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift) 的原始输出**（coherence / smoothness 数值本身没错，只是不该无门控生效）。
- **不引入新的 board confidence 定义**（用现有 [BoardDirectionAnalyzer.summary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardDirectionAnalyzer.swift#L231-L258) 的 confidence，来源为 `centerConfidence × travelConfidence` 的均值）。
- **不做全局 flow modulation 禁用开关**——只在低置信场景下做单侧限制，中/高置信度样本继续走原逻辑。
- **不动 velocitySmoothness 下行 penalty 分支**——本 spec 只处理"低置信度下不该加分"的悬挂问题；smoothness 塌陷降级信号（<40）依然生效，且下行修正不受门控（保守原则）。

---

## 4. 方案设计

### 4.1 门控信号选择

**选定**：`boardKinematicConfidence`（来源为 [BoardDirectionAnalyzer.summary(from:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardDirectionAnalyzer.swift#L231-L258) 的 `confidence` 字段，
计算式 = `average(kinematics.confidence)`，其中 `kinematics.confidence = centerConfidence × travelConfidence`）。

**为什么不用 `edgeQualityConfidence`**：
- 主 corpus 6 份中 `edgeQualityConfidence ∈ [0.573, 0.751]`，v1（扫雪场景）反而是 0.751 最高，v4/v6（问题样本）分别是 0.581/0.655。**该信号完全无法区分"走刃证据充分 vs 不足"**。
- 语义偏差：`edgeQualityConfidence` 是"走刃分数计算依据的置信度"（关节可靠度加权），而门控真正想要的是"走刃证据是否成立"——后者由板身几何 + 行进方向证据支持，即 `boardKinematicConfidence`。

**为什么不用 `edgeQualityScore/100`**：
- 语义变成"分数低时禁止加成"，等价于二次封顶，与 [edgeEvidenceCapValue](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L479-L483) 逻辑冲突。
- 阈值需要抬到 0.60 才能覆盖 v1/v4，而 [PoseScorer edge-first 重构](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md) 的核心目标就是让 raw 分主导评分而不是靠外部封顶。

### 4.2 调用顺序问题（关键约束）

**现状**：[BoardDirectionAnalyzer.analyze](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardDirectionAnalyzer.swift#L17) 在 [main.swift#L140-L143](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI/main.swift#L140-L143) 才被调用，**发生在 `analyzer.generateSummary` 之后**。而 flow modulation 在 [generateSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L378-L389) 内部即触发——门控信号此时不可得。

**解决方案 A（推荐）**：将 board 分析下沉到 `VideoAnalyzer` 内部，让 [generateSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L347-L434) 能直接读到 `boardKinematicConfidence`。改造点：
1. 在 [VideoAnalyzer](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift) 中新增 `computeBoardKinematicConfidence(from:)` 私有方法（复用 [BoardDirectionAnalyzer.analyze](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardDirectionAnalyzer.swift#L17)，但只关心 `summary.confidence`）。
2. 在 `generateSummary` 中的 flow modulation 前调用一次，传入 `computeModulation`。
3. **CLI 层 [main.swift#L140-L143](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI/main.swift#L140-L143) 保持不变**（重复调用一次，但 board 分析成本可忽略，且保证 spec 落地边界收窄在 Core 内部）。

**解决方案 B（备选，简单但不推荐）**：在 `main.swift` 集成层先做 board 分析，再手动调用 `flowCalculator.computeModulation` 覆盖 summary。缺点：把评分核心逻辑分散到 CLI 层，违反 Core 独立性。

**决定**：采用**方案 A**。

### 4.3 核心接口

在 [FlowMetricsCalculator.applyModulation](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift#L218-L230) 中引入 `boardKinematicConfidence` 参数：

```swift
public func applyModulation(
    poseScore: Double,
    metrics: FlowMetrics,
    boardKinematicConfidence: Double
) -> Double {
    guard metrics.framePairsUsed >= 2 else { return poseScore }
    if metrics.directionalStability == 0 && metrics.velocitySmoothness == 0 {
        return poseScore
    }
    let factor = computeModulation(
        coherence: metrics.motionCoherence,
        stability: metrics.directionalStability,
        smoothness: metrics.velocitySmoothness,
        poseScore: poseScore,
        boardKinematicConfidence: boardKinematicConfidence
    )
    return clamp(poseScore * factor, lower: 0, upper: 100)
}
```

新增 5-param 重载：

```swift
public func computeModulation(
    coherence: Double,
    stability: Double,
    smoothness: Double,
    poseScore: Double,
    boardKinematicConfidence: Double
) -> Double {
    var modulation = 1.0
    if coherence > coherenceBoostThreshold {
        modulation += coherenceBoostAmount              // +0.05
    }
    if smoothness > 0 && smoothness < smoothnessPenaltyThreshold {
        modulation -= smoothnessPenaltyAmount           // -0.05
    }

    // Edge-confidence gating：走刃证据不足时禁止上行加成，保留下行修正。
    if boardKinematicConfidence < boardKinematicConfidenceGateThreshold {
        modulation = min(modulation, 1.0)
    }

    return clamp(modulation, lower: 0.87, upper: 1.13)
}
```

**方案 (c) 低分保护变体（v3 §5.3 实测校验，推荐主选）**：

```swift
public func computeModulation(
    coherence: Double,
    stability: Double,
    smoothness: Double,
    poseScore: Double,
    boardKinematicConfidence: Double,
    evidenceCappedScore: Double? = nil          // 新增可选参数
) -> Double {
    var modulation = 1.0
    if coherence > coherenceBoostThreshold {
        modulation += coherenceBoostAmount              // +0.05
    }
    if smoothness > 0 && smoothness < smoothnessPenaltyThreshold {
        modulation -= smoothnessPenaltyAmount           // -0.05
    }

    // Edge-confidence gating + 方案 (c) 低分保护
    var gateActive = boardKinematicConfidence < boardKinematicConfidenceGateThreshold
    if let capped = evidenceCappedScore,
       capped < flowGateLowScoreProtectionThreshold {  // 60.0
        gateActive = false                              // 低分场景保留 flow 平滑修正
    }
    if gateActive {
        modulation = min(modulation, 1.0)
    }

    return clamp(modulation, lower: 0.87, upper: 1.13)
}
```


新增常量：
```swift
/// Flow modulation 上行加成的走刃证据门控阈值（2026-09-15 P0）：
/// 与 ReportGenerator 显示"走刃暂不评分" 的行为边界对齐 = 0.30。
/// 依据：主 corpus 6 份中触发 flow ×1.05 的 v1/v4/v6，其
/// boardKinematicConfidence ∈ [0.157, 0.280]，全部 <0.30；
/// 未触发加成的 v3/v5（boardKinematicConfidence 0.552/0.510）不受影响。
public let boardKinematicConfidenceGateThreshold: Double = 0.30

/// Flow modulation 低分保护阈值（2026-09-15 P0 R1 方案 c）：
/// 当 evidenceCappedScore < 60 时禁用 edge-confidence gating，
/// 允许 flow ×1.05 加成保留，避免中级 60 → 初级 58 的跨档伤害。
/// 依据：v3 §5.3 实测：v1 capped=57.78 < 60 → 保护生效，60.67 → 60.67；
/// v4/v6 capped=78.80/90.16 ≥ 60 → 保护不触发 → 门控继续 kill flow ×1.05。
public let flowGateLowScoreProtectionThreshold: Double = 60.0
```

### 4.4 对既有 3/4-param `computeModulation` 的处理

保留 API 兼容层：
- 3-param `computeModulation(coherence:stability:smoothness:)`：**仍留作基础单测入口**，行为不变（不做 gating）。
- 4-param `computeModulation(coherence:stability:smoothness:poseScore:)`：**内部转发到 5-param，`boardKinematicConfidence` 传 1.0**（等价于无门控）。这保证既有测试和调用点在 spec 未落地前完全不受影响。
- 5-param 版本是生产入口。

### 4.5 VideoAnalyzer 集成点

修改 [VideoAnalyzer.generateSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L378-L389)：

```swift
// 光流指标
let flowMetrics = await computeFlowMetrics()
let flowCalculator = FlowMetricsCalculator(sampleInterval: sampleInterval)

// P0 (2026-09-15): 走刃证据置信度门控
let boardConfidence: Double = await computeBoardKinematicConfidence(
    from: reliableFrames,
    flowTravelDirections: cachedTravelDirections
)

let flowModulationFactor = flowMetrics.framePairsUsed >= 2
    ? flowCalculator.computeModulation(
        coherence: flowMetrics.motionCoherence,
        stability: flowMetrics.directionalStability,
        smoothness: flowMetrics.velocitySmoothness,
        poseScore: avg,
        boardKinematicConfidence: boardConfidence
    )
    : 1.0
let modulatedScore = clamp(avg * flowModulationFactor, lower: 0, upper: 100)
```

新增私有方法 `computeBoardKinematicConfidence`：
```swift
private func computeBoardKinematicConfidence(
    from reliableFrames: [DetectionResult],
    flowTravelDirections: [(time: Double, angle: Double, confidence: Double)]
) async -> Double {
    // 直接复用 BoardDirectionAnalyzer.analyze 的 summary 结果
    let analysis = await BoardDirectionAnalyzer.analyze(
        frames: reliableFrames,
        flowTravelDirections: flowTravelDirections
    )
    return analysis.summary?.confidence ?? 0.0
}
```

**性能**：BoardDirectionAnalyzer 全帧分析成本约 <10ms（无 Vision 调用，纯几何计算），可接受重复一次；也可以后续把结果缓存传给 CLI 层减少重复。

### 4.6 报告透明度

[ReportGenerator](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) 的"评分拆解"行现有格式：

```
🧪 评分拆解：原始均分 64.0 · 最佳前1/3 78.8 · 证据封顶后 78.8 · 光流系数 ×1.05
```

**门控触发时**，在光流系数后追加标记：

```
🧪 评分拆解：原始均分 64.0 · 最佳前1/3 78.8 · 证据封顶后 78.8 · 光流系数 ×1.00（走刃证据不足，未加成）
```

判定条件：`boardKinematicConfidence < 0.30 && coherence > 70`（同时满足才是被 gate 抑制的情况；单纯 flow ×1.00 无 boost 触发不打此标记）。为此需要在 [VideoSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift) 里新增 `flowModulationGated: Bool?` 字段，避免 ReportGenerator 重复计算门控条件。

---

## 5. 预期评分变化（实测 spike，v3 补齐）

对 c=40 主 corpus 6 份视频的静态 replay（flow modulation 是纯函数，从 JSON 精确抽取 `motionCoherence / velocitySmoothness / evidenceCappedScore / boardAnalysis.summary.confidence`，通过 [scripts/flow_gating_replay.py](file:///Users/mingsen/Project/FallLine/scripts/flow_gating_replay.py) 无损复现）：

| Video | rawPose | best⅓ | evidenceCapped | boardC | 当前 factor | 当前综合 | gated factor | 门控后综合 | Δ | 门控生效？|
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| 1（扫雪） | 48.81 | 57.78 | 57.78 | **0.239** | ×1.050 | **60.67** | ×1.000 | **57.78** | **−2.89** | ✅ 有效 |
| 2（刻滑） | 78.71 | 86.53 | 86.53 | **0.292** | ×1.000 | 86.53 | ×1.000 | 86.53 | 0.00 | ⚠️ 触发但零影响 |
| 3（刻滑） | 76.96 | 88.13 | 88.13 | 0.552 | ×1.000 | 88.13 | ×1.000 | 88.13 | 0.00 | ❌ 未触发 |
| 4（中质量） | 64.01 | 78.80 | 78.80 | **0.157** | ×1.050 | **82.74** | ×1.000 | **78.80** | **−3.94** | ✅ 有效 |
| 5（中质量） | 62.84 | 73.86 | 73.86 | 0.510 | ×1.000 | 73.86 | ×1.000 | 73.86 | 0.00 | ❌ 未触发 |
| 6（刻滑） | 79.32 | 90.16 | 90.16 | **0.280** | ×1.050 | **94.66** | ×1.000 | **90.16** | **−4.51** | ✅ 有效 |

**Spike 汇总（gate=0.30）**：
- 有效 kill 3 份（v1/v4/v6），零成本假阳性 1 份（v2 触发但 flow ×1.000 无加成可抑制）
- 累计 Δ = **−11.34**（3 份被 kill 的样本共下调 11.34 分）
- v3/v5 完全不变（原 flow ×1.000）

**关键性质**：
- **video 1**：60.67 → 57.78（Δ −2.89）——跨 60 分"中级/初级" 边界。**决策待 review**（§8.2 决策 2，方案 (c) 已实测校验保护 v1 且不伤 v4/v6）
- **video 4**：82.74 → 78.80（Δ −3.94）——档内降级，仍属"高级 [75, 85)"，报告文本"转向不是靠整条刃"教练主问题原本与"高级档" 极不匹配，现分数与文本一致 ✅
- **video 6**：94.66 → 90.16（Δ −4.51）——档内降级，仍属"专业 [85, 100]"，减少"极端高分" ✅
- **video 2**：86.53 → 86.53（Δ 0.00）——boardC=0.292 触发门控但 flow 本就 ×1.000，零影响（"零成本假阳性"）
- **video 3/5**：完全不变

### 5.1 阈值向量图（主 corpus 6 份，实测 spike）

由 [scripts/flow_gating_replay.py](file:///Users/mingsen/Project/FallLine/scripts/flow_gating_replay.py) `--thresholds` 扫描：

```
gate      v1      v2      v3      v4      v5      v6    累计Δ  kill数  跨档
0.20   +0.00   +0.00   +0.00   -3.94   +0.00   +0.00   -3.94    1      0
0.25   -2.89†  +0.00   +0.00   -3.94   +0.00   +0.00   -6.83    2      1
0.28   -2.89†  +0.00   +0.00   -3.94   +0.00   +0.00   -6.83    2      1
0.30   -2.89†  +0.00   +0.00   -3.94   +0.00   -4.51  -11.34    3      1  ← 推荐
0.32   -2.89†  +0.00   +0.00   -3.94   +0.00   -4.51  -11.34    3      1
0.35   -2.89†  +0.00   +0.00   -3.94   +0.00   -4.51  -11.34    3      1
0.40   -2.89†  +0.00   +0.00   -3.94   +0.00   -4.51  -11.34    3      1
0.50   -2.89†  +0.00   +0.00   -3.94   +0.00   -4.51  -11.34    3      1
```
（† = 跨档位边界）

**结论**：0.30 是**最小有效阈值**（覆盖 v1/v4/v6 全部三个 flow ×1.05 样本），且与 0.32/0.35/0.40/0.50 触发集完全相同，选 0.30 因它与 [ReportGenerator "走刃暂不评分" 显示阈值](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) 对齐；再高会误伤（v2 已经在假阳性区，v3/v5 需保护）。

### 5.2 分档表验证（[VideoAnalyzer.overallLevel 分档](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L400-L406)：85..100 专业 / 75..<85 高级 / 60..<75 中级 / else 初级）

| Video | 当前分数 / 档位 | 门控后分数 / 档位 | 跨档？|
|---|:---:|:---:|:---:|
| 1 | 60.67 中级 | 57.78 初级 | ⚠️ 跨档 |
| 2 | 86.53 专业 | 86.53 专业 | — |
| 3 | 88.13 专业 | 88.13 专业 | — |
| 4 | 82.74 高级 | 78.80 高级 | — |
| 5 | 73.86 中级 | 73.86 中级 | — |
| 6 | 94.66 专业 | 90.16 专业 | — |

**结论**：只有 video 1 有真实跨档风险（中级 60→ 初级 58），v4/v6 均为档内降级，风险最低。

### 5.3 video 1 保护方案对比（实测 spike）

针对 R1 三个缓解方案，通过 [scripts/flow_gating_replay.py](file:///Users/mingsen/Project/FallLine/scripts/flow_gating_replay.py) 的 `video1_protection_analysis` 抽样：

| 方案 | video 1 输出 | v4 保护？| v6 保护？| 结论 |
|---|:---:|:---:|:---:|---|
| (a) 无保护，直接门控 | 60.67 → 57.78（跨档 中→初）| — | — | 语义清晰但产生跨档 |
| (b) `rawPose ≥ 60` AND 门控 | 60.67 → 60.67（保留 ×1.05）| v4 rawPose=64.01 保护关闭 ✅ | v6 rawPose=79.32 保护关闭 ✅ | **推荐后备**：语义"低 pose raw 场景保留 flow" |
| (c) `evidenceCapped ≥ 60` AND 门控 | 60.67 → 60.67（保留 ×1.05）| v4 capped=78.80 保护关闭 ✅ | v6 capped=90.16 保护关闭 ✅ | **推荐主选**：语义"低 evidence 场景保留 flow 平滑修正"，与 evidence cap 语义链一致 |

**关键实测**：v4/v6 在两个保护方案下 `rawPose/evidenceCapped` 均 ≥ 60，**保护条件对它们均不触发**，即 v4/v6 门控效果完全保留（门控继续 kill 掉 flow ×1.05 加成）。方案 (c) **胜过** (a) 的关键在于它不产生新的跨档风险；胜过 (b) 的关键在于 `evidenceCapped` 已经是 evidence cap 语义链的下游产物，与 gating 决策的语义源同根，避免引入 `rawPose` 作为新的分数约束语义（若 `rawPose < 60` 但 `evidenceCapped > 60`，说明 evidence 已把它抬升到"值得保留 flow 加成"的位置）。



---

## 6. 实施 Tick

### Tick 1 — FlowMetricsCalculator 接口扩展
- 新增 `edgeConfidenceGateThreshold` 常量 = 0.30
- 新增 5-param `computeModulation(coherence:stability:smoothness:poseScore:edgeConfidence:)`
- 4-param 版本内部转发到 5-param 并传 `edgeConfidence: 1.0`（等价无门控，保留旧行为）
- 新增测试文件 `FlowMetricsEdgeGatingTests.swift`：
  - `test_edgeConfidence_1_0_matchesLegacyBehavior`：edgeC=1.0 时 5-param 输出 == 4-param 旧输出
  - `test_edgeConfidence_below_0_30_disablesUpwardModulation`：edgeC=0.20 + coherence=90 → factor ≤ 1.0
  - `test_edgeConfidence_below_0_30_preservesDownwardModulation`：edgeC=0.20 + smoothness=30 → factor 依然 −0.05
  - `test_edgeConfidence_at_0_30_isBoundary`：edgeC=0.30（含边界值）→ 加成正常
  - `test_edgeConfidence_gate_isMonotonic`：edgeC 从 0.0 → 1.0 时上行加成从"禁用 → 生效"，无跳变（除阈值处）

### Tick 2 — VideoAnalyzer 集成
- [VideoAnalyzer.generateSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L378-L389) 传入 `edgeConfidence`
- 若 [SkiMetricsCalculator.average](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/SkiMetricsCalculator.swift#L80-L116) 未在 flow 上游调用，复用/新增单次调用
- Corpus replay 主 6 份，比对表 §5 数据

### Tick 3 — Report Generator 透明度
- 在 [ReportGenerator](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) 的评分拆解行追加"（edge 置信不足，未加成）"标记
- 新增测试 `ReportGeneratorFlowGatingTests`：门控触发 + 未触发两条契约

### Tick 4 — Spec 归档
- 状态改 `Approved / Implemented`
- 写入 [WORK_LOG.md](file:///Users/mingsen/Project/FallLine/WORK_LOG.md) 和 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md)
- 更新 [posescorer-edge-first-refactor-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md) 的"下一 tick 候选"章节标记为"已落地"

---

## 7. 回退方案

- Tick 1：新常量/新方法可无痛回退，`git revert` 单个 commit 即可。
- Tick 2：VideoAnalyzer 集成点可通过删除 `edgeConfidence` 参数回退到旧调用。
- 全量回退：3 个 tick 都是纯加法，回退无副作用。
- **不引入环境变量开关**——与 [PoseScorer 重构 §7](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md) 决策一致，避免 A/B 组合爆炸。

---

## 8. 风险与开放问题

### 8.1 已识别风险

| # | 风险 | 概率 | 影响 | 缓解 |
|---:|---|---|---|---|
| R1 | video 1 从 60.67 → 57.78 跨"中级/初级"档 | 中 | 中 | **v3 已实测校验方案 (c)**（见 §5.3）：加 `evidenceCapped ≥ 60` AND 门控条件 → v1 capped=57.78 < 60 → 门控失效 → 保留 ×1.05 → v1 维持 60.67；同时 v4/v6 的 evidenceCapped 均 ≥60，门控保留生效，无副作用。**推荐主选方案 (c)**。 |
| R2 | v6/alpha_off boardC=0.332（不触发）vs alpha_on boardC=0.280（触发）产生 α 状态跨版本分裂 | 低 | 低 | α on 是默认路径。opt-out 主要用于 A/B 对照，跨 α 状态一致性不是 spec 目标。记录在 §1.4；实测 α off 下门控 kill 数从 3 降到 1（仅 v4），不会产生额外破坏 |
| R3 | boardKinematicConfidence 计算含运行时随机性（VNDetectHumanBodyPose 帧间稳定性）| 低 | 中 | v6 boardC=0.280 距离 0.30 阈值仅 0.020（7%），需 Tick 2 replay 3+ 次抽样验证 boardC 方差 <0.02；见 §10 落地后自检清单 |
| R4 | 主 corpus 6 份太少，未验证其他扫雪 / 高分样本 | 中 | 中 | Tick 2 后建议扩展到历史 49-video corpus；或在 [SkiAnaylze/testvideo/](file:///Users/mingsen/Project/FallLine/SkiAnaylze/testvideo/) 建立扩展集。v3 已通过 7 组 baseline × 6 samples = 42 数据点扫描初步验证跨版本稳定性（§1.4） |
| R5 | boardConfidence 计算耗时（BoardDirectionAnalyzer.analyze 在 VideoAnalyzer 内重复调用一次）| 低 | 低 | BoardDirectionAnalyzer 纯几何计算，无 Vision 调用；主 corpus 6 份实测 <10ms；Tick 2 提供缓存路径优化空间 |
| R6 | edge 置信度受"低姿态遮挡"（false negative）误伤 | 中 | 中 | 本 spec 只**限制加成**，不做扣分，符合 [annotations/calibration_anchors.md](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md) 保护规则 |
| R7 | 阈值 0.30 与 [ReportGenerator 显示阈值](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) 语义耦合 | 低 | 低 | 若未来调整"走刃暂不评分" 阈值需同步 review；将常量注释明确标记语义链一致性 |

### 8.2 待 review 决策

1. **阈值**：`boardKinematicConfidenceGateThreshold = 0.30` — 由 §5.1 阈值向量图证明为最小有效阈值：
   - 0.20 只触发 v4（漏 v1/v6，无法解决"扫雪场景 flow 加成"问题）
   - 0.25 / 0.28 只触发 v1/v4（漏 v6，无法解决"专业档极端高分"）
   - 0.30 / 0.32 / 0.35 / 0.40 / 0.50 触发集完全相同（同一 4 样本，v1/v2/v4/v6）
   - **选 0.30**：与 [ReportGenerator "走刃暂不评分" 显示阈值](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) 对齐，避免多阈值并存
2. **video 1 保护**：R1 三选一。**推荐主选方案 (c) 加 `evidenceCapped ≥ 60` AND 条件**（v3 实测校验，见 §5.3）：
   - 语义精准（与 evidence cap 语义链一致）
   - v1 保护成功（60.67 → 60.67，不跨档）
   - v4/v6 门控完全保留（capped=78.80/90.16 均 ≥ 60，保护对它们不触发 → 门控继续 kill flow ×1.05）
   - 累计 Δ 从 −11.34 变为 −8.45（v1 从 −2.89 变为 0）
   - 备选：若 review 不接受方案 (c) 的"低分保护"语义，也可用 (b) `rawPose ≥ 60`（v1 rawPose=48.81 < 60，同样保护 v1）
3. **是否同时收敛 smoothness penalty**：现有 `smoothness < 40 → −0.05` 是否也应受门控？本 spec 建议**不动**——下行修正即"检测崩塌降级"是保守方向，不产生"抬分"风险。
4. **报告文案措辞**：`（走刃证据不足，未加成）` 与业务语义对齐（不用 `edge 置信不足`，因为门控信号是 `boardKinematicConfidence` 而非 `edgeQualityConfidence`）
5. **是否合并 Tick 3 到 Tick 2**：报告文案是纯 UI 变化，独立 tick 或并入 Tick 2 都可，建议独立便于回滚
6. **Tick 2 是否 replay 后暂缓落地**：R3 boardC 稳定性风险需要 3+ 次 replay 抽样后再决策；建议先落 Tick 1（接口 + 单测，flow 未启用门控），Tick 2 拆分为 2a (集成) + 2b (启用) 两步

### 8.3 v3 变更摘要（vs v2）

- **新增 §5.1** 阈值向量图（8 个 gate 阈值 × 6 samples 完整实测矩阵）
- **新增 §5.3** video 1 保护方案 (a)/(b)/(c) 实测校验表
- **重写 §1.4** 跨 baseline 稳定性验证（用脚本实测输出替换文字描述）
- **修正 §1.5** video 4 档位描述（"专业档 82.74" → "高级档 82.74"）
- **新增 [scripts/flow_gating_replay.py](file:///Users/mingsen/Project/FallLine/scripts/flow_gating_replay.py)** 可重复实测脚本
- **R1 缓解措施** 从"待决策"升级为"方案 (c) 实测校验完成，推荐主选"

---

## 9. 交叉引用与依据

- **一致性 review 结论**：见 2026-09-15 分析对话，[testvideo/_edgefirst_c40/4.md](file:///Users/mingsen/Project/FallLine/testvideo/_edgefirst_c40/4.md) 教练主问题"转向不是靠整条刃"是本 spec 核心动机来源
- **Edge cap ramp 已消除悬崖**：[VideoAnalyzer.edgeEvidenceCapValue](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L475-L482) 不再是"分档矫正器"，flow modulation 成为高分场景的最后放大器，本 spec 补齐其"证据一致性"缺口
- **P7-A 退役 directionalStability 的教训**：[FlowMetricsCalculator §51 常量注释](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift#L51-L72) 已阐明"像素运动方向 ≠ 真实质量"；本 spec 对 coherence 加成做同类护栏
- **Calibration anchors 保护规则**：低置信度下"deep stance should be protected"，本 spec 明确**只限制加分，不引入扣分**，符合保护原则

---

## 10. 落地后自检清单

### 10.1 编译与单测
- [ ] `swift test` 全绿（新增 5-6 条 flow gating 契约）
- [ ] `swift build -c release` 无 warning

### 10.2 Corpus 精确 replay（Tick 2 落地后）
Corpus 6 份 replay 数据与 §5.1 阈值向量图一致（精确 replay：flow modulation 是纯函数）：
- [ ] **video 1** 综合分：
  - 若采用 R1 方案 (a)：∈ [57.7, 57.9]（预期 57.78）——跨档，接受
  - **若采用 R1 方案 (c)** evidenceCapped ≥ 60 保护：∈ [60.6, 60.7]（预期 60.67，保留 ×1.05）✅ 推荐
- [ ] **video 2** 综合分：∈ [86.5, 86.6]（预期 86.53，假阳性零影响）
- [ ] **video 3** 综合分：∈ [88.1, 88.2]（预期 88.13，不变）
- [ ] **video 4** 综合分：∈ [78.7, 78.9]（预期 78.80）
- [ ] **video 5** 综合分：∈ [73.8, 73.9]（预期 73.86，不变）
- [ ] **video 6** 综合分：∈ [90.0, 90.3]（预期 90.16）

### 10.3 稳定性 & 序列化
- [ ] boardKinematicConfidence 抽样方差 <0.02（R3 检查，v6 边界样本；建议连跑 3 次取 max-min）
- [ ] 报告文本正确显示"（走刃证据不足，未加成）"标记（仅 v1/v4/v6 触发，v2 不显示因原本无 boost）
- [ ] `flowModulationGated: Bool?` 字段序列化到 JSON

### 10.4 复核脚本
落地后建议执行：
```bash
# 主 corpus 精确 replay（预计与 §5 表格一致）
/usr/bin/python3 scripts/flow_gating_replay.py

# 阈值向量扫描（预计与 §5.1 一致）
/usr/bin/python3 scripts/flow_gating_replay.py --thresholds 0.20 0.25 0.30 0.35

# 跨 baseline 稳定性（预计与 §1.4 一致）
/usr/bin/python3 scripts/flow_gating_replay.py --baselines _edgefirst_c40 baseline_alpha_on baseline_alpha_off
```

---

## 11. 附：数据抽取脚本片段（供 replay 复核）

主 corpus 6 份 JSON 已包含 `summary.flowMotionCoherence / flowVelocitySmoothness / evidenceCappedScore / flowModulationFactor` 与 `boardAnalysis.summary.confidence`。以下 Python 片段可无 Swift 依赖复现门控预测：

```python
def modulation(coh, sm, boardC, evidenceCapped=None, gate=0.30, protect_below=None):
    """
    重现 spec §4.3 computeModulation(5-param) 门控
    - protect_below: 若设为 60（方案 c），当 evidenceCapped < protect_below 时禁用门控
    """
    mod = 1.0
    if coh > 70: mod += 0.05         # coherenceBoostAmount
    if 0 < sm < 40: mod -= 0.05      # smoothnessPenaltyAmount

    gate_active = boardC < gate
    if protect_below is not None and evidenceCapped is not None and evidenceCapped < protect_below:
        gate_active = False           # 方案 (c) 低分保护

    if gate_active:
        mod = min(mod, 1.0)          # 新增门控：禁上行加成
    return max(0.87, min(1.13, mod)) # ±13% clamp

def final(evidenceCapped, coh, sm, boardC, gate=0.30, protect_below=None):
    factor = modulation(coh, sm, boardC, evidenceCapped, gate, protect_below)
    return min(100, max(0, evidenceCapped * factor))
```

Corpus 6 份实测输入 / 输出：见 §5 表格与 §5.1 阈值向量图。完整脚本见 [scripts/flow_gating_replay.py](file:///Users/mingsen/Project/FallLine/scripts/flow_gating_replay.py)。
