# edgeQuality 正式取代 sideslip 走刃语义（方向 α）设计

> 作者：agent
> 日期：2026-09-15
> 状态：**Landed（2026-09-15）** — 落地于 commit `ed9dac5`（[ReportGenerator](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) + [ReportGeneratorEdgeQualitySemanticsTests](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/ReportGeneratorEdgeQualitySemanticsTests.swift)），baseline md 归档 `80d80e8`，文档归档 `f524b25`，诊断脚本入库 `1fcff10`，`main` 于 2026-09-15 fast-forward 至 `1fcff10`。
> 前置：
> - [2026-09-15-posescorer-edge-first-refactor-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md)（edgeQuality 已成为评分主导维度）
> - [2026-09-15-flow-modulation-edge-gating-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-flow-modulation-edge-gating-design.md)（flow ×1.05 加成的走刃证据门控）
> - P8-A（2026-09-08）已退役 sideslip 高分 cap（sideslip 展示保留但标注"不参与评分"）
> 关联：
> - [Sources/FallLineCore/ReportGenerator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift)
> - [Sources/FallLineCore/BoardDirectionAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardDirectionAnalyzer.swift)
> - [Sources/FallLineCore/Models.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L626-L646)
> - [scripts/footplant_diagnose.py](file:///Users/mingsen/Project/FallLine/scripts/footplant_diagnose.py)（触发本次决策的诊断脚本）
> - [Tests/FallLineCoreTests/ReportGeneratorEdgeQualitySemanticsTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/ReportGeneratorEdgeQualitySemanticsTests.swift)

---

## 0. 一句话动机

**sideslip / carvingConfidence 是"板身几何方向 vs 2D 光流行进方向"派生的量，foot-plant 诊断证实它带 ~40-50° 系统性偏差且与真正的立刃质量弱相关。** 报告端却仍在把它作为走刃结论使用（走刃行取 min、板身段派生"沿板身移动/走刃倾向/横滑偏多/以横滑为主"定性）。本 spec 目标：**在报告展示/语义层把走刃结论正式移交给姿态派生的 [edgeQuality](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/SkiMetricsCalculator.swift) 信号**，让 sideslip 降级为一个诚实标注的"板身方向 2D 几何原始诊断"，不再充当走刃语义。改动**只发生在展示层**，综合分链路（flow 门控 + 62 分时长 cap 仍独立消费 `boardKinematicConfidence`）零改动。

---

## 1. 现状与问题

### 1.1 语义层的双轨错配

改动前 [ReportGenerator.generate](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift) 里存在两处对 sideslip 的隐式依赖：

```swift
// A. 走刃行命名 & 置信度
let supportsBoardQuality = output.boardAnalysis.summary?.averageSideslipAngle != nil
let edgeName = supportsBoardQuality ? "走刃质量" : "走刃倾向"          // ①双轨命名
let edgeConfidence = min(ski.edgeQualityConfidence,
                        output.boardAnalysis.summary?.confidence ?? 1) // ②min-and

// B. 板身段派生定性
"平均横滑角 X° · 走刃置信 Y/100 · <boardKinematicsLabel(sideslip)> · ..."
```

问题：
- **①**：sideslip 有/无就切换走刃命名，暗示"没有几何量→只是倾向"。但姿态派生的 edgeQuality 本身并不依赖 sideslip，命名切换只在制造混淆。
- **②**：`edgeQualityConfidence` 与 `boardKinematicConfidence` 取 min。主 corpus 里几何置信度多为 0.16-0.29（[boardKinematicHighScoreCap](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift) 的 0.30 门槛就是为了识别这种情况），min 后 v1/v2/v4/v6 的走刃行被压成 `暂不评分`，即使 edgeQualityConfidence 高达 0.75。
- **B**：`boardKinematicsLabel(sideslip)` 把 sideslip 直接翻译为"沿板身移动/有走刃倾向/横滑偏多/以横滑为主"。foot-plant 诊断（§2）证实 sideslip 与真实走刃质量弱相关，这些定性文案在实际使用中会与走刃质量行给出的分数矛盾。

### 1.2 主 corpus 数据（改动前）

| 视频 | edgeConf | boardConf | 走刃行改动前 | 走刃行改动后 |
|---|---|---|---|---|
| v1 | 0.75 | 0.24 | **走刃质量 暂不评分** | 走刃质量 37/100 · 搓雪为主 · 置信度 75/100 |
| v2 | 0.57 | 0.29 | 走刃质量 72/100 · 置信度 **29/100 · 谨慎参考** | 走刃质量 72/100 · 置信度 57/100 · 谨慎参考 |
| v3 | 0.69 | 0.55 | 走刃质量 69/100 · 置信度 55/100 | 走刃质量 69/100 · 置信度 69/100 |
| v4 | 0.58 | 0.16 | **走刃质量 暂不评分** | 走刃质量 55/100 · 置信度 58/100 · 谨慎参考 |
| v5 | 0.65 | 0.51 | 走刃质量 52/100 · 置信度 51/100 | 走刃质量 52/100 · 置信度 65/100 |
| v6 | 0.65 | 0.28 | **走刃质量 暂不评分** | 走刃质量 72/100 · 置信度 65/100 |

6 份里有 3 份（v1/v4/v6）走刃行被 min-and 逻辑错误压成"暂不评分"，属于严重的展示层错配。

---

## 2. 触发依据（foot-plant 诊断证伪路径）

- **P8-A（2026-09-08）**：sideslip 派生的 62/70 分 cap 已退役，理由是主 corpus 6 份全部 sideslip 42-53°（含已确认刻滑样本 v2/v3），2D 光流方向不携带质量信息。
- **本轮 foot-plant 诊断**（[scripts/footplant_diagnose.py](file:///Users/mingsen/Project/FallLine/scripts/footplant_diagnose.py)）：借鉴 perfanalysis / pose2sim 的低速脚踝锚定思路，检验"低速窗口是否能把 sideslip 收敛到小角度"。结果全面否定：
  1. 低速窗内 sideslip 反而更大（低速段板身速度小，任何几何噪声都被放大成大夹角）；
  2. boardAngle 帧间跳动在低速窗未见明显改善；
  3. sideslip 与 edgeQuality 相关性 |r| < 0.2，几何量与走刃质量属独立信号。
- **结论**：sideslip 本身是 2D 光流方向失真+骨架关键点噪声的复合产物，不适合承担走刃语义。**下一步不是修 sideslip，而是把走刃语义从 sideslip 上拆下来**——这正是本 spec 的方向 α。

---

## 3. 落地方案

### 3.1 报告核心语义（[ReportGenerator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift#L302-L312)）

```swift
// P0-α (2026-09-15)：走刃结论正式由 skiMetrics.edgeQuality 承担。
let edgeQualityName = "走刃质量"                          // ①命名恒定
let edgeConfidence = ski.edgeQualityConfidence            // ②不再与几何 conf 取 min
let edgeJudgmentIsReliable = edgeConfidence >= lowConfidenceThreshold
```

- `edgeQualityLanguage()` 方法整个删除（原本用来在双轨命名之间切换文案）。
- 走刃行 [makeSkiScoreLine](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift#L834-L854) 消费 `edgeQualityName + edgeConfidence`，即"暂不评分"判定只看 edgeQualityConfidence。

### 3.2 板身方向段（[boardSummaryLine](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift#L968-L979)）

```swift
private static func boardSummaryLine(_ summary: BoardAnalysisSummary) -> String {
    let source = boardSourceLabel(summary.source)
    let confidence = String(format: "%.0f", summary.confidence * 100)
    guard let sideslip = summary.averageSideslipAngle else {
        return "    识别到 \(summary.frameCount) 帧板身线条代理 · 数据来源：\(source) · 置信度 \(confidence)/100；画面位移不足，暂不估计板身-行进夹角。"
    }
    return "    板身-行进夹角（2D 几何）\(String(format: "%.0f", sideslip))° · 数据来源：\(source) · 几何置信度 \(confidence)/100 · 原始诊断，不代表走刃/搓雪"
}
```

段标题从 `🏂 板身方向与横滑` 改为 `🏂 板身方向（几何诊断）`，段末追加固定说明行：
```
    说明：左右脚踝连线代理板身的几何方向，仅作诊断参考；走刃/搓雪结论以"走刃质量"为准，本段不参与评分。
```

同时删除 `boardKinematicsLabel` 常量方法（原本用来把 sideslip 翻译成"沿板身移动/有走刃倾向/横滑偏多/以横滑为主"定性）。

### 3.3 JSON 保留承诺

- [BoardAnalysisSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L626-L646) 的 `averageSideslipAngle` / `carvingConfidence` **字段与 Codable 结构完全不动**，仍在 [testvideo/*.json](file:///Users/mingsen/Project/FallLine/testvideo) 中输出，供 debug / 诊断脚本消费。
- 承诺理由：foot-plant 诊断脚本、travel_angle_audit、以及后续 3D 拓扑升级实验都需要 sideslip 的原始几何数据作为对照序列。方向 α 拆走的是"走刃语义"而不是"字段本身"。

### 3.4 综合分链路：显式不动

- `boardKinematicConfidence` 仍独立驱动：
  - [FlowMetricsCalculator.computeModulation](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift) 的 flow 门控（`boardKinematicConfidence < 0.30 → min(modulation, 1.0)`）；
  - [VideoAnalyzer](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift) 里的 62 分时长 cap（低置信度短片段）。
- 这两条独立走 `BoardDirectionAnalyzer.summary(from:).confidence`，与报告层 `edgeConfidence` 完全解耦——`edgeConfidence` 只用于报告渲染，不回流综合分。

---

## 4. 契约测试

[ReportGeneratorEdgeQualitySemanticsTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/ReportGeneratorEdgeQualitySemanticsTests.swift) 5 条用例锁定四个不变量：

| # | 用例 | 断言语义 |
|---|---|---|
| 1 | `test_edgeRow_isReliable_whenGeometryConfidenceIsLow` | edgeConf=0.80、boardConf=0.10 → 走刃行必须正常给分（v1/v4/v6 修复） |
| 2 | `test_edgeRow_isNotScored_whenEdgeQualityConfidenceIsLow_evenIfGeometryIsHigh` | 反向：edgeConf=0.20、boardConf=0.90 → 仍"暂不评分"，几何高置信度不得补救 |
| 3 | `test_edgeName_isAlways走刃质量_whenBoardSummaryAbsent` | 无 boardSummary → 命名仍恒定"走刃质量" |
| 4 | `test_boardSection_isRawGeometryDiagnostic_only` | 板身段只保留中性几何夹角，不出现"横滑角/走刃置信/沿板身移动/以横滑为主/有走刃倾向" |
| 5 | `test_boardSection_withoutSideslip_saysAngleUnavailable` | sideslip 缺失 → "暂不估计板身-行进夹角"，不出现"横滑角" |

---

## 5. 验证

### 5.1 单元测试
- `swift test`：**240 tests, 0 failures**（本轮 +5：α 契约用例）。

### 5.2 主 corpus 6 份 release 端到端回放

对 [testvideo/{1..6}.MP4](file:///Users/mingsen/Project/FallLine/testvideo) 逐份用 release CLI 重跑，与改动前的基线 JSON 对比 9 项关键字段：

| 视频 | avgScore | rawPose | bestThird | evidenceCapped | flowFactor | gated | edgeScore | edgeConf | boardConf | sideslip° |
|---|---|---|---|---|---|---|---|---|---|---|
| v1 | 60.67 | 48.81 | 57.78 | 57.78 | 1.05 | False | 36.60 | 0.75 | 0.24 | 44.2 |
| v2 | 86.53 | 78.71 | 86.53 | 86.53 | 1.00 | False | 72.08 | 0.57 | 0.29 | 50.5 |
| v3 | 88.13 | 76.96 | 88.13 | 88.13 | 1.00 | False | 68.62 | 0.69 | 0.55 | 50.3 |
| v4 | 78.80 | 64.01 | 78.80 | 78.80 | 1.00 | True | 55.02 | 0.58 | 0.16 | 45.3 |
| v5 | 73.86 | 62.84 | 73.86 | 73.86 | 1.00 | False | 52.15 | 0.65 | 0.51 | 39.4 |
| v6 | 90.16 | 79.31 | 90.16 | 90.16 | 1.00 | True | 71.58 | 0.65 | 0.28 | 51.3 |

6×9=54 个数值全部与基线 bit-identical，`gated=true` 集合仍为 {v4, v6}——JSON 侧完全不变，只有 [testvideo/*.md](file:///Users/mingsen/Project/FallLine/testvideo) 按 α 契约刷新。

### 5.3 报告文案人工核对
- 6 份 `.md` 走刃行全部按 α 契约展示（v1 从"暂不评分"恢复为"走刃质量 37/100 · 搓雪为主 · 置信度 75/100"）；
- 6 份板身段标题全部改为 `🏂 板身方向（几何诊断）`；
- 6 份行文全部为"板身-行进夹角（2D 几何）xx° · 数据来源：混合候选 · 几何置信度 xx/100 · 原始诊断，不代表走刃/搓雪"格式；
- 报告全文中已无"横滑角/走刃置信/沿板身移动/以横滑为主/有走刃倾向"等 sideslip 派生的走刃定性。

---

## 6. 遗留与后续

### 6.1 显式不做（本 spec 范围外）
- **修 sideslip 数值本身的 42-53° 系统偏差**：需升级关键点拓扑（3D 骨架 / 板身分割），不在方向 α 范围。方向 α 的定位是"把 sideslip 从走刃语义中拆走"，不是"修好 sideslip"。
- **删除 `averageSideslipAngle` / `carvingConfidence` JSON 字段**：显式保留，见 §3.3。

### 6.2 已知遗留
- **iOS App UI**：核查 [SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift) 后确认——iOS 端直接消费 `AnalysisOutput.skiMetrics.edgeQualityScore` 展示走刃质量分数，**不消费 `boardAnalysis.summary` 任何字段、不使用 sideslip / carvingConfidence**，方向 α 对 iOS UI 零影响。iOS 端里存在的"走刃倾向"字样仅出现在 [stageDescription](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift#L582-L592)（按 `summary.averageScore` 分档的口语化描述），语义与 sideslip 无关，不需要改。
- **calibration_anchors 教练标注校准复核**：edge-first 后等级分布向"专业"迁移，方向 α 恢复了 v1/v4/v6 走刃行展示，可能进一步影响用户对分数的解读（尽管数值本身没变），建议后续与教练主观评级复核。

### 6.3 后续候选
- 关键点拓扑升级（3D 骨架 / 板身分割）修复 sideslip 2D 几何偏差本身；
- 姿态与板身双通道 fusion——若 3D 拓扑成熟，可让 sideslip 重新参与走刃语义（但需要先证伪 §2 的偏差）。

---

## 7. Commit 链

| SHA | 类型 | 内容 |
|---|---|---|
| `ed9dac5` | feat(report) | ReportGenerator α 语义 + 5 条契约用例 |
| `80d80e8` | chore(baseline) | testvideo/{1..6}.md 按 α 刷新（JSON bit-identical） |
| `f524b25` | docs(log) | WORK_LOG + delta_update 归档 |
| `1fcff10` | chore(scripts) | 补入 footplant_diagnose.py + repeatability_probe.py |
