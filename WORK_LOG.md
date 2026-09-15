# FallLine Work Log

## Current State (2026-09-15 方向 α edgeQuality 取代 sideslip 语义 已落地)

**方向 α（Foot-Plant 诊断证伪后的替代方向）**：走刃结论正式由姿态派生的 `edgeQualityScore/Confidence` 承担，sideslip 几何量降级为原始诊断（不参与走刃语义、不参与评分、报告显式标注）。改动**只发生在展示/语义层**，综合分链路（flow 门控 + 62 分时长 cap 仍独立消费 `boardKinematicConfidence`）零改动。
- 触发依据：[scripts/footplant_diagnose.py](file:///Users/mingsen/Project/FallLine/scripts/footplant_diagnose.py) 证伪低速锚定假设——低速窗 sideslip 反而更大、boardAngle 帧跳无改善、sideslip 与 edgeQuality 弱相关；确认 2D 光流方向不携带质量信息，与 P8-A 退役 sideslip cap 同根因。
- [ReportGenerator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift#L302-L312)：命名恒定"走刃质量"（旧双轨"走刃质量/走刃倾向"下线），`edgeConfidence` 直接用 `ski.edgeQualityConfidence`（不再与 `boardKinematicConfidence` 取 min，v1/v2/v4/v6 走刃行从"暂不评分"恢复正常给分）；[boardSummaryLine](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift#L968-L979) 重写为"板身-行进夹角（2D 几何）· 原始诊断，不代表走刃/搓雪"，删除 `boardKinematicsLabel`。
- 契约测试：[ReportGeneratorEdgeQualitySemanticsTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/ReportGeneratorEdgeQualitySemanticsTests.swift) 5 条用例锁定"几何低置信度不再压制走刃行"、"edgeQualityConfidence 低时几何高置信度不得补救"、命名恒定、sideslip 段无走刃语义。

**PoseScorer edge-first 重构（把 calfLean 立刃证据从"外部 cap"升级为评分主导维度，commit `ce751a4`→`b584b12` + 微调 `fbeb1da`）**：
- Tick 1 `ce751a4` [PoseScorer.Weights](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift) struct 前置重构（数值不变）；Tick 2 `06f5ed7` 权重重分配 lean/knee/calf/gravity/symmetry = 0.15/0.25/**0.35**/0.15/**0.10**（calf 主导、symmetry 降到 0.10）；Tick 3 `48ea262` calfLean 改 sigmoid；Tick 4 `b584b12` edge cap 放宽为 fallback-only ramp。
- **sigmoid 中点 c=35→c=40（`fbeb1da`，corpus review 后微调）**：`calfSigmoidScore = 100/(1+exp(-0.10·(angle-40)))`，40°=50 分（及格，"入门—中级刻滑分界"），30-50° 段陡度 ~2.31 分/°，端点 0°→1.8/80°→98.2。c=35 曾让专业档普涨、v5 中级→高级、v4 中级→专业，c=40 后 v5 回落中级。
- edge cap [edgeEvidenceCapValue](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L509-L513)：`edge<30→62` 兜底 / `30–42` 线性放行 / `≥42→100`，悬崖软化、纯扫雪防误抬。
- Spec 已 Landed：[2026-09-15-posescorer-edge-first-refactor-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md)。

**Flow modulation 走刃置信度门控（edge-first 的下游护栏，`ab16817` + 归档 `31950a5`）**：
- [computeModulation](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift) 扩 6-param：`boardKinematicConfidence < 0.30 → min(modulation,1.0)`（只禁上行 ×1.05、不扣分）；方案 (c) 低分保护 `evidenceCappedScore < 60` 关门控（防 v1 跨中/初档）。[VideoSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift) 加 `flowModulationGated: Bool?`；报告 gated=true 追加"（走刃证据不足，未加成）"。
- Tick 4 release CLI 复核：`gated=true` 集合精确 **{v4,v6}**，v1 保护不掉档；阈值 0.30 处 [0.30,0.50] 稳定平台且为覆盖 v6(boardC=0.280) 的最小值。Spec Landed：[2026-09-15-flow-modulation-edge-gating-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-flow-modulation-edge-gating-design.md)。

**当前主 corpus 顶层分数**（c=40 叠加 gating，[testvideo/](file:///Users/mingsen/Project/FallLine/testvideo)）：v1 61 · v2 87 · v3 88 · v4 79 · v5 74 · v6 90（edge-first 前基线 61/83/85/74/70/92）。对照归档：[_review_tick4](file:///Users/mingsen/Project/FallLine/testvideo/_review_tick4)(c=35)、[_edgefirst_c40](file:///Users/mingsen/Project/FallLine/testvideo/_edgefirst_c40)(c=40 无门控)、[_tick4_gated](file:///Users/mingsen/Project/FallLine/testvideo/_tick4_gated)(c=40+门控)。

**评分确定性基线（2026-09-15 探针，未提交）**：新增 [scripts/repeatability_probe.py](file:///Users/mingsen/Project/FallLine/scripts/repeatability_probe.py)，对标 SportsReflector ±3.0 pts 方法（同视频 ×10 次全新 release 进程）。主 corpus 6×10=60 次运行**全部 bit-identical**（JSON 剔除 videoPath 后 SHA256 唯一），最大跨次 **SD=0.000**，`--deep` 逐帧 totalScore 也全部一致。结论：task group 并发 + Vision 熔断在固定输入下不引入跨次非确定性；分数变化只能来自代码/输入/工具链变化，跨次实验对比可信。该基线作为后续重构（自适应抽帧、归约并行化等）的守门探针。

**验证状态**：`swift build` 0 warning；`swift test` **240 tests, 0 failures**（本轮新增 [ReportGeneratorEdgeQualitySemanticsTests](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/ReportGeneratorEdgeQualitySemanticsTests.swift) 5 条契约用例）；主 corpus 6 份 release 重跑 → 综合分及 rawPose/bestThird/evidenceCapped/flowFactor/gated/edgeScore/edgeConf/boardConf/sideslip 全部字段与基线**逐字段 bit-identical**，仅 md 报告文案按 α 契约刷新。**edge-first + flow gating + 方向 α 共 13 个 commit 已 fast-forward 推送 origin/main**（`ce751a4..1fcff10`）：Tick 1-4 权重/sigmoid/edge cap 重构 + `fbeb1da` c=40 微调 + gating 集成 `ab16817` + gating spec Landed `31950a5` + edge-first spec Landed `21a24f8` + `e362a76` 日志、`a60d93e`/`80d80e8` baseline 归档、`ed9dac5` 方向 α 报告改写、`f524b25` α 日志归档、`1fcff10` 诊断脚本入库。方向 α spec 归档：[2026-09-15-edgequality-carving-semantics-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-edgequality-carving-semantics-design.md)（Landed）。

**下一步候选**（不阻塞）：
- ~~采样率 5fps → 视频原生 30fps~~：**已实验，用户判定效果不好，暂缓**（2026-09-15），代码维持 5fps；重启需先补对照数据。
- ~~Foot-Plant Stabilisation~~：**已诊断证伪**（2026-09-15，见 [footplant_diagnose.py](file:///Users/mingsen/Project/FallLine/scripts/footplant_diagnose.py)）——低速窗 sideslip 反而更大、与 edgeQuality 弱相关；改走**方向 α**（本轮落地，见 Current State），走刃语义正式移交 edgeQuality。
- ~~**calibration anchors 教练标注校准复核**~~：**已完成**（2026-09-15，见 [outputs/calibration_review_20260915/SUMMARY.md](file:///Users/mingsen/Project/FallLine/outputs/calibration_review_20260915/SUMMARY.md) 与 [annotations/calibration_anchors.md#L43](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md#L43-L73) 快照）。12 锚点 + 主 corpus 6 份 = **18 份联合交叉核对**（由固化脚本 [scripts/calibration_cross_check.py](file:///Users/mingsen/Project/FallLine/scripts/calibration_cross_check.py) 一键复现），档位不一致率 **9/12 = 75%**（7 上迁 + 2 下迁），Pearson r 六维：**edge=+0.959 / calf=+0.949 / knee=+0.894 / lean=+0.639 / gravity=+0.509 / sym=-0.657**。核心归因 **calf 权重 0.35 + sigmoid c=40 主导抬分**：
  1. **middle-accepted 上迁**：8 份 middle 里 5 份（62.5%）综合 ≥78 落入"高质量滑行阶段"，MID_ACC7 达 93。历史"中级=middle"语义与当前分档错位。
  2. **GOOD_A 反向掉档**（94.1→86，Δ=-8.1）：calfLean 48 (≈40°) 落在 sigmoid c=40 中点，主导权重 0.35 拉低整体分。
  3. **BAD_ACC 严重上迁**（65→83，Δ=+18）：edge cap [30,42] 兜底段没兜住（edge=57>42 直接放行到 100 cap），calfLean=45 主导反而拉高。
  4. **MID_FP1（腿太直）未收敛**：仍 77 分，knee=74 但 knee 权重 0.25 无力压制。
  5. **文案-分数自相矛盾** 5 份（MID_ACC5/6/7、MID_FP1、BAD_ACC）：算法自动"主要问题"文本明确说"搓雪弯 / 走刃不稳定 / 立刃不一致"，但综合分给到 77-93，评分口径与语义口径分裂。
  6. **sym r=-0.657 反相关**：18 份里越高分样本对称性反而越低，怀疑运动幅度未归一化，需要单独排查。
- **calibration follow-ups**（unblocked，按优先级）：
  - **【高优 §4.1】edge cap 双维兜底**：`edge≥42 && calfLean<40 → cap=72`，预期 BAD_ACC 83→72、MID_FP2 82→72，不影响 v2/v3/v6（calf ≥ 66）。触点：[edgeEvidenceCapValue](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L509-L513)。
  - **【高优 §4.2】knee<75 时动态加权**：`weights.knee += 0.10, weights.calf -= 0.10`，预期 MID_FP1 77→72、v4 79→76。触点：[PoseScorer.Weights](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift)。
  - **【中优 §4.3】stage classifier 收紧**：`avg≥80→qualitySkiing` 加 `calf≥55 && sym≥70`；advanced 门槛加 `knee≥85 && sym≥75`。预期 MID_ACC3/5/6 落回中级偏上。
  - **【新增 §4.5】排查 sym r=-0.657 反相关**：先跑 sym 分数 × 综合分散点、再判断是否引入"运动幅度归一化"或"低 sym 硬 cap"。
  - **【长期 §4.4】扩样本 20-30 份 middle 边界**：从 [SkiAnaylze/testvideo/](file:///Users/mingsen/Project/FallLine/SkiAnaylze/testvideo/) 抽样二次标注，建立"中级顶=78/中级中=68/中级底=58"三级基准，为重训 sigmoid c 提供统计基础。
- iOS 端已 SPM 化（主线 B `94ce905` 起），[SkiAnaylze/SkiAnaylze/Views](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/Views) 通过 `import FallLineCore` 复用 Core，本轮方向 α 的 sigmoid/权重/edge cap/gating/α 报告文案会随下次 iOS 重编译自动同步。UI 卡片直接读 `output.skiMetrics.edgeQualityScore` 等字段，不消费 `boardAnalysis.summary` 那段板身诊断文案，因此 α 报告改写对 iOS UI 无副作用；仅 [ReportDetailView](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift) 分享/导出用的 `ReportGenerator.generate` 长文会随之更新。仅有的旧代码副本残余是 [SkiAnaylze/SkiAnaylze/Sources/DemoData.swift](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/Sources/DemoData.swift)（demo 用固定 AnalysisOutput），也不含 Core 逻辑。
- 关键点拓扑升级（3D 骨架 / 板身分割）以修复 sideslip 2D 几何偏差，方向 α 只是把 sideslip 从走刃语义中拆走、并未修复几何测量本身。

## Previous State (2026-09-10 P6-B / P6-B-r3 / P9-A / P9-B 已落地)

**P6-B（光流窗采样，commit `3681dc2`）+ P6-B-r3（radius 2→3，commit `b25c082`）**：`FlowMetricsCalculator` hip/ankle 光流从单点采样改为 (2r+1)×(2r+1) 邻域均值，默认 radius=3（7×7 窗）。与 P6-A 时序 median 形成"空间+时序"双层抗噪；`averageFlowWindow` 作为纯函数供单测直接验证；radius=0 保留紧急回退。主 corpus 5 份重跑：视频 2 velocitySmoothness 81→84（+3），视频 3 43→47（+4），其他 3 份 coherence/smoothness/finalScore 全部稳定。

**P9-A（TurnPhase 报告文案 tie-break，commit `70f2149`）**：`ReportGenerator.dominantPhaseRawValue(from:)` 替换 `phaseDistribution.max { ... }`。同频 tie 时按语义优先级 shaping > initiation > release > transition 二次排序。`ReportGeneratorPhaseTieBreakTests` 9 条用例（含 2000 次稳定性 fuzz）守护。**只影响文案标签，不影响任何评分或 JSON 结构**。

**P9-B（重心主问题 tie-break，commit `f092025`）**：`CenterOfMassFitCalculator.dominantIssue(from:)` 同型 bug，抖动面比 P9-A 更大（作用在整个视频顶层 `mainIssue`）。同频 tie 时按语义优先级 **偏高 > 过低** 二次排序，理据：`score(hipRatio:targetRange:)` 里偏高每 0.24 单位掉 100 分（≈416 分/单位）远高于过低（≈305 分/单位），教练视角上"跟不上刃角"是刻滑典型缺陷。`CenterOfMassFitCalculatorTieBreakTests` 9 条用例（含 2000 次稳定性 fuzz）守护。**同样只影响文案标签**。

**dict/set 无序迭代审计（未落库）**：本轮全 `Sources/` 审计命中 12+ 处，其中 11 处为 Array-based（`Array.max/min/sorted(by:)` 语义保证稳定或返回首个最大值），唯一必修高风险点是 P9-B 的 `CenterOfMassFitCalculator.dominantIssue`，已修复。`AGENTS.md` "Report determinism" 条目已升级为通用规约：**任何依赖 `Dictionary`/`Set` 归约影响用户可见输出的位置必须显式声明 tie-break 顺序**。

**验证状态**：`swift test` **173 tests, 0 failures**（149 → 155 → 164 → 173）；`swift build -c release` PASS（未在当轮显式跑，P9-B 已过 diagnostics）。

**下一步候选（09-10 时点，部分已过时）**：
- 采样率 5fps → 视频原生 30fps（WORK_LOG Next Steps #1，深度研究确认 200ms 帧间隔 → 20° 膝角误差）
- travelAngle 输出链路精简（P8-A 已退役 sideslip 高分 cap，横滑角展示还留着）
- ~~confidence-weighted 时序平滑~~：**已落地**——1€ Filter 的 α 方案（`useConfidenceAwareFiltering` 默认 true），见 [PoseSmoother](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseSmoother.swift)。
- 最新候选以顶部 2026-09-15 Current State 为准。

## Previous State (2026-09-08 P6-A + P7-A 落地)

**P6-A（velocitySmoothness avg→median，commit `be59c7c`）**：修复 velocitySmoothness 在 6 份主 corpus 100% 塌陷为 0。corpus 重跑后恢复 40.8~78.7，flowMod/averageScore 不变（恢复值均高于 penalty 阈值 40）。

**P7-A（退役 directionalStability 评分调制，commit `256d3f2`）**：诊断证实 6 种 2D 统计口径全部无法区分 corpus 质量排序（换刃天然 ~180° 摆动 + 相机运动主导光流方向），用户拍板方案 A。`computeModulation` 移除 stability 分支，报告标注 `*不参与评分`。corpus 分数 Δ=0.00（零行为变化正式化）。**光流调制有效范围现为 ±5%**（coherence +0.05 / smoothness -0.05）。

**自 2026-09-01 以来的稳定性提交**（未逐轮记录，见 git log）：P2 flow 熔断、P3 sideslip 5 帧中值、P4-A 短缺口插补、P5-A/B 膝盖评分、P0-A/P0b/P0-D/P0-E despike 系列、P6-A、P7-A。

## Previous State (2026-09-01 CLI 复核方案 A)

**方案 A 生产数据复核**：用 [FallLineCLI](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI) 重跑 6 份主 corpus 视频，坐实 audit 预测。仅报告文本改动，无生产代码变化。

**本轮变更概要**（详见 `delta_update.md` 的"2026-09-01（CLI 复核方案 A）"条目）：
- 逐份跑 `swift run -c release FallLineCLI testvideo/N.MP4` × 6
- Python 对照 pre/post 的 `averageScore` / `evidenceCappedScore` / `boardKinematicHighScoreCap` / `flowModulationFactor`
- 3.json：**averageScore 55.10 → 73.91，Δ=+18.81**（与 audit 预测 Δ=18.4 高度吻合，微差来自 flowMod 抖动）
- 其他 5 份：0 变化（4 份 obsCnf<0.55 pre 就不 cap，1 份 evidence-cap 与 boardCap 巧合等价）
- 均值：66.34 → 69.47（+3.13）

**用户可见变化**（[testvideo/3.md](file:///Users/mingsen/Project/FallLine/testvideo/3.md)）：
- 综合评分 **55/100 → 74/100**
- 阶段判断"基础控速阶段" → **"刻滑雏形阶段"**
- ⚠️ "板身/滑行方向夹角偏大"警告：**消失**
- 高光时刻：无 → 2 段

**改动文件**：
- [testvideo/1.md](file:///Users/mingsen/Project/FallLine/testvideo/1.md) / [3.md](file:///Users/mingsen/Project/FallLine/testvideo/3.md) / [4.md](file:///Users/mingsen/Project/FallLine/testvideo/4.md) / [5.md](file:///Users/mingsen/Project/FallLine/testvideo/5.md)（21 行 diff）
- JSON 是 [.gitignore](file:///Users/mingsen/Project/FallLine/.gitignore) 排除的，只在本地存在

**验证**：
- 用户本地已确认方案 A 效果
- 未跑 `swift test`（本轮无代码改动，测试跑分保持上一轮的 106 tests 全绿）

## Previous State (2026-09-01 补 TrendAnalytics 边界用例)

**hotfix 后续 nice-to-have**：补齐 `weekly.count == 1` 真空区回归。仅测试文件改动，无生产代码变化。详见 `delta_update.md` 的"2026-09-01（补边界用例）"条目。

- [TrendAnalyticsTests.swift#L180-L219](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift#L180-L219) 新增 `test_detectMilestones_singleWeek_noWeeklyImprovementNoStreakNoCrash`
- `swift test`：Executed 106 tests, with 0 failures

## Previous State (2026-09-01 hotfix：TrendAnalytics 空 weekly 崩溃兜底)

**运行时崩溃 hotfix**：上一轮方案 A 落地后本机首次跑 `swift test` 触发。iOS App 首次打开"进步"Tab（无 session）会走 `TrendAnalytics.detectMilestones(sorted: [], weekly: [])` → `for i in 1..<0` 触发 `Fatal error: Range requires lowerBound <= upperBound` SIGABRT。**上一轮 [test_analyze_emptySessions_returnsAllEmptyOrNil](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift) 就应该拦下，但沙箱 XCTest 阻塞 → 只跑 `swift build --build-tests` 没跑运行时**。教训：仅编译不跑测试无法拦运行时崩溃。

- [TrendAnalytics.swift#L235-L243](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/TrendAnalytics.swift#L235-L243)：加 `if weekly.count >= 2` 兜底
- 顺便清查所有 `1..<...` 模式：VideoAnalyzer / TurnPhaseDetector / TrendAnalytics#L288 均已有兜底，仅 L236 漏网

## Previous State (2026-08-30 方案 A 落地)

**travelAngle 阈值决策方案 A 已落地** —— 从"决策前置"进入"生产落地"。改动最小（1 行常量 + 边界回归 2 用例 + 3 处文档同步），由测试守护"真横滑仍会 cap"这条主线。详见 `delta_update.md` 的"2026-08-30（方案 A 落地）"条目。

- [Utilities.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L144) `minimumBoardKinematicConfidenceForHighScore`: `0.55 → 0.7`
- [BoardDirectionAnalyzerTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardDirectionAnalyzerTests.swift#L137-L201)：新增 2 条边界回归用例
- `python3 scripts/travel_angle_audit.py` 复跑：**cap 触发数 8 → 0**（24 份 corpus）

**量化影响预估**：
- 24 份 corpus 里 8 次 sideslip 分支 cap 触发全部消失
- 3.json 类样本（raw 76 → cap 58，Δ=-18.4 分）现在 raw 76 可以透传
- **不影响**低置信度短片 62 cap 保护
- **不影响**真横滑（obsCnf ≥ 0.7 + sideslip ≥ 30°）—— 用例守护

**当前项目定位**（本轮起有变化）：
- iOS App = Core 唯一消费方（SwiftPM 本地依赖）
- Core 对外契约就绪（Package.swift products + AnalysisOutput: Identifiable）
- 进步曲线闭环：埋点 → UserDefaults → 里程碑 → 本地推送 → 折线图
- Vision 稳定性：iOS 已用 warmUp + espresso 熔断 + CPU 后备
- 算法层测试覆盖：TrendAnalytics 13 用例 + BoardDirectionAnalyzer 边界 2 用例
- **travelAngle 阈值方案 A 已上线**：0.55 → 0.7，audit 脚本作为持续对照基线

**下一步（用户本地）**：
1. `swift test` 本机复验 103 用例全通过
2. `swift run FallLineCLI <video>` 重跑 corpus，生成新一批 JSON 产物
3. `python3 scripts/travel_angle_audit.py` 对新产物再跑一次，确认实际 averageScore 变化符合预期
4. 若变化符合预期 → 主线 B 收官清单完全清空

**后续可优化方向（不阻塞）**：
- 方案 B（`sideslipStd > 25°` 高波动豁免）暂搁置，等 A 上线跑通后视 corpus 表现决定是否叠加
- 方案 C（弃用 travelAngle）：需要先复原旧 hipCenter 2D 位移代码跑 audit 对比才好决策
- 方案 D（IMU 融合）：长线独立技术栈
- 拓展 corpus：添加更多真实用户视频做 A/B 对照

## Previous State (2026-08-30 决策前置)

**travelAngle 链路误判决策已量化前置** —— 清单里最后一项优化的量化基线搭好、决策候选 A/B/C/D 已根据 24 份 corpus 拉齐。

**变更概要**（详见 `delta_update.md` 的"2026-08-30 (决策前置)"条目）：
- 新增 [scripts/travel_angle_audit.py](file:///Users/mingsen/Project/FallLine/scripts/travel_angle_audit.py)：只读扫描 24 份 corpus，与 Core `boardKinematicHighScoreCap` 完全一致口径复现 cap 判定
- 量化结论 5 条硬事实：cap 触发率 33.3%、travelStd 大多 >100°、无样本 avgObsCnf ≥ 0.6、最大惩罚 Δ=-18.4 分、cap 抹平 3D 融合优化
- 决策候选 A/B/C/D 拉齐，推荐方案 A（本轮已落地）

## Previous State (2026-08-30 TrendAnalytics 测试覆盖)

**TrendAnalytics 单元测试覆盖落地（+13 用例）** —— 主线 B 收官后清单里的第 2 项可选优化完成。仅新增 [TrendAnalyticsTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift) 1 个测试文件，无生产代码改动。

**当轮变更概要**（详见 `delta_update.md` 的"2026-08-30：TrendAnalytics 单元测试覆盖"条目）：
- 新增 13 个 XCTest 用例，覆盖 7 大能力域
- 测试用固定时间锚 + `session(offsetDays:score:level:)` helper 保证确定性
- 每个用例都与 `TrendAnalytics.swift` 源码具体行号交叉核对

## Previous State (2026-08-29 收官后 +1)

**iOS 已切换到 `analyzeWithResilience()`** —— 主线 B 收官后清单里的第 1 项可选优化已落地。单文件改动 [VideoAnalysisManager.swift](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/VideoAnalysisManager.swift#L134-L165)。

**当轮变更概要**（详见 `delta_update.md` 的"2026-08-29 (收官后 +1)"条目）：
- `analyzer.analyze()` → `analyzer.analyzeWithResilience(progressHandler:)`：接入 Vision espresso 上下文预热 + CPU 后备 + 连续 3 帧失败熔断
- 用 `progressHandler` 把 Core 抽帧真实进度映射到 App 进度条 0.2→0.75 区间，替代原两段 500ms 假 sleep
- `AnalysisError.visionUnavailable` / `.noReliableFrames` 各自转 `NSError` 沿现有错误弹窗链路展示

## Previous State (2026-08-29 收官)

**主线 B（iOS SPM 化）+ 进步曲线全链路接入完成**。3 个 commit 已推送到 `origin/main`：

```
efd7843  feat(trend): 进步曲线接入主流程
264a1b2  feat(core): AnalysisOutput 支持 Identifiable，兼容 SwiftUI sheet(item:)
94ce905  feat(ios): 主线 B 完成 - iOS SPM 化，消除 8 个复制文件
```

本轮变更明细见 `delta_update.md` 的"2026-08-29 (收官)"条目。

## Previous State (2026-08-29 再续)

**主线 B（iOS SPM 化）Core 端就绪 + 进步曲线 c1/c2/c3 骨架已入库**。3 个 commit 推送到 `origin/main`：

```
b825c7f  feat(trend): c3 里程碑本地推送 - TrendNotificationCenter
18436c0  feat(trend): 进步曲线 - Core 算法层 + iOS 骨架
2c5ef8d  feat(core): 主线 B iOS SPM 化 - Core 端就绪
```

**本阶段完成的**：
- Core 层 iOS 兼容改造（`Package.swift` iOS 17 平台，`VisionFrameAnalyzer.usesCPUOnly + warmUp`，`VideoAnalyzer.AnalysisError + analyzeWithResilience`）
- 进步曲线骨架（`TrendAnalytics.swift` 220 行 + `TrendStore.swift` UserDefaults 持久化 + `TrendView.swift` Charts 折线图 + `TrendNotificationCenter.swift` UNUserNotificationCenter 推送）
- `scripts/setup_ios_deps.sh` --dry / --yes / --rollback + 备份机制

**已由 2026-08-29 收官轮接管**：SPM 化真正落地、8 个复制文件删除、iOS App 接入 3 处。

## Previous State (2026-08-29 续)

**算法准确度 P0/P1/P2 + iOS 熔断已入库**（commit `45dad57`，已推送 `origin/main`）。核心引擎按 2026-06-05 深度研究结论完成采样率、软置信度、travelAngle 门控、板身线仲裁、3D 融合五处改动；iOS 端补齐 Vision warmUp/CPU 回退/熔断与错误 UI。详细变更见 `delta_update.md` 的"2026-08-29 (续)"条目。

**验证状态（当轮）**：
- `swift build -c release` PASS；`swift test` 沙箱限制未跑
- 6 个测试样本被证据封顶卡在 58/55/66 三档，收益体现在内部指标（stabilityScore、kneeBendScore、rawPoseAverageScore）
- 三阶段对照快照保留：`testvideo/_p1_baseline/`、`testvideo/_c_2d/`、`testvideo/_b_3d_baseline/`

## Previous State (2026-06-05)

**仓库清理**：`.gitignore` 已加入 `UserInterfaceState.xcuserstate`，用于忽略 Xcode 用户界面状态文件。注意：该文件当前已在 Git 索引中且处于未合并状态，ignore 规则不会自动解除跟踪或解决冲突。

**深度研究完成：算法准确度提升方向**。通过 deep-research 工作流（5 角度搜索 → 22 来源 → 75 声明 → 3 票对抗验证 → 7 综合发现），梳理了单目姿态估计和光流运动分析在滑雪场景下的准确度瓶颈与改进路径。完整报告见 Journal。

**iOS 开屏页面已实现**（2026-05-28）：`SkiAnaylze/` 新增滑雪主题开屏动画，3 秒自动进入主页面，可跳过，预留广告接口。编译通过，模拟器验证通过。

**验证状态**：
- `xcodebuild -project SkiAnaylze/SkiAnaylze.xcodeproj -scheme SkiAnaylze -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`：`** BUILD SUCCEEDED **`
- `swift test`：88 tests, 0 failures（待确认：与上次验证间隔 8 天，其间代码可能有变更）

**变更文件**（开屏）：
- 新增 `SkiAnaylze/SkiAnaylze/Services/AdProvider.swift` — 广告接口协议 + 默认空实现
- 新增 `SkiAnaylze/SkiAnaylze/Views/SplashView.swift` — 4 阶段开屏动画 + 跳过按钮 + 广告位
- 新增 `SkiAnaylze/SkiAnaylze/Views/RootView.swift` — splash → content 状态切换
- 修改 `SkiAnaylze/SkiAnaylze/SkiAnaylzeApp.swift` — ContentView → RootView

**变更边界**：只改 iOS SwiftUI UI 层，不改 FallLineCore/CLI 的分析逻辑、评分模型或持久化行为。

### 深度研究关键发现

**高置信度（3-0 投票通过）**：

1. **姿态规范化（3DPCNet）**：混合 GCN-Transformer 将单目姿态旋转误差从 >20° 降至 3.4°，MPJPE 降低 27%。Estimator-agnostic——可直接操作 3D 关节点坐标，无需修改底层检测器。[arXiv:2509.23455](https://arxiv.org/html/2509.23455) (ICASSP 2026)

2. **2D 透视误差公式**：E = 100 × d / (D − d)%。简单乘性修正只能纠正平动运动学（位移、速度），**无法纠正关节角度**。透视误差是系统误差（非随机），无法通过平滑消除。[Yokoi & Okada 1994](https://cir.nii.ac.jp/crid/1390001204309690752)

3. **Apple Vision 硬限制**：VNDetectHumanBodyPoseRequest 腿部链终止于脚踝，iOS 18+ 的 3D 变体也未增加足部关键点。脚踝代理方法是当前框架下的最优解——立刃角度检测有理论上限。

4. **时序精度**：跑步步态中 20ms 事件检测偏差 → 20° 膝关节角度误差。当前 5fps（200ms 帧间隔）远超此阈值，提高采样率可能比算法改进更有效。[Mundt et al. 2024](https://pubmed.ncbi.nlm.nih.gov/38984681/)

**中置信度（2-1 投票通过）**：
- 滑雪专项 AlphaPose 微调：98% PCK，10.32px MPJPE（仅 2 受试者训练，通用性存疑）
- 2D+3D 融合 + 骨长约束 + Kalman 滤波：MPJPE -10.2%，关节角误差 -16.6%（理疗数据集，非滑雪，arXiv 预印本）

**已剔除声明（≥2 票反对）**：共 14 条，包括 "100Hz 是 2D 分析最低采样率"、"Kalman 可从 2D 恢复 47 DOF 全身关节角" 等。

## Previous State (2026-05-25)

**iOS App Icon 已更新（2026-05-27）**：`SkiAnaylze/` 的 AppIcon 已替换为已确认的 **Alpine scan-reticle / 山地扫描准星** 方向。图标保留 Ice Sport Technology 的深色山地背景、冰蓝刻滑轨迹和扫描准星，不使用 “AI” 文本。生成脚本见 `scripts/generate_fallline_app_icon.swift`，资产位于 `SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/`。

**iOS App UI redesign implemented**：`SkiAnaylze/` 已按 **Ice Sport Technology / 冰雪运动科技** 方向完成第一轮 SwiftUI 改造。视觉语言覆盖首页/壳层、视频确认、分析进度、报告详情、历史记录和分享卡：雪山剪影、坡线轨迹、数据 HUD、冰蓝玻璃面板、环形评分仪表。规格见 `docs/superpowers/specs/2026-05-25-ios-ui-ice-sport-technology-design.md`，计划见 `docs/superpowers/plans/2026-05-25-ios-ui-ice-sport-technology.md`。

**验证状态**：
- App Icon PNG：Default/Dark/Tinted 均为 1024×1024。
- `xcodebuild -project SkiAnaylze/SkiAnaylze.xcodeproj -scheme SkiAnaylze -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`：`** BUILD SUCCEEDED **`
- `swift test`：88 tests, 0 failures
- iPhone 16 Pro Simulator：启动成功，首页/训练记录/报告页可渲染；用户已确认视觉效果“可以”。

**变更边界**：本次只改 iOS SwiftUI UI/主题文件和项目文档，不改 `Sources/FallLineCore/`、`Sources/FallLineCLI/`、`SkiAnaylze/SkiAnaylze/Sources/` 的分析逻辑、评分模型或持久化行为。

## Previous State (2026-05-21)

**--output-video 功能已完成（含每帧独立分析）**，88 tests 全通过，`swift build -c release` 通过。

**运动方向（cyan 箭头）稳定性待解决**：已从 hipCenter 位移切换为光流方案，有改善但仍不可靠。低置信度帧的角度跳动很大（-4.7° ↔ 112.4°）。核心矛盾：画面 2D 像素运动 ≠ 雪板实际行进方向。

**已完成功能**：
- `--output-video` CLI 开关：将姿态分析覆盖图渲染为 MP4 (H.264) 视频
- 直接复用 `renderOverlay()` 绘制逻辑，与 `--debug-overlay` 的 PNG 覆盖图内容一致
- 输出原视频**每一帧**（原生帧率），**每帧独立跑 Vision 姿态检测**，标注数据随帧实时更新
- `AVAssetImageGenerator` 精确帧提取：`requestedTimeToleranceBefore/After = .zero`（修复前几秒帧重复 bug）
- `VideoAnalyzer` 采样间隔下限从 0.1s 降至 1/60s，支持原生 60fps 分析
- `--output-video` 启用时自动检测视频原生帧率作为采样间隔
- AVAssetWriter 管线：NSBitmapImageRep → CVPixelBuffer (BGRA, IOSurface backed) → H.264 Baseline 3Mbps
- 默认输出路径：原视频同目录 `<视频名>_analyzed.mp4`

**iOS App 模拟器测试支持（2026-05-21）**：
- 新增 `DemoData.swift`：基于 testvideo/3.MP4 分析数据构建默认演示 AnalysisOutput（72.57 分，"中级"）
- `VideoAnalysisManager` 新增 AnalysisOutput 持久化（`analyses.json`），首次启动自动注入 demo 条目
- `HistoryView` 删除操作同步清理持久化数据
- `ReportDetailView` 视频播放器改为 9:16 竖屏比例铺满宽度

**之前完成的优化（2026-05-13）**：
- 批次并行帧分析（batchSize=8，TaskGroup 并发）
- 帧缓存降采样（640x480，mem ~400MB → ~60MB）
- main.swift 四个检测器 async let 并发
- generateSummary 内 reliableFrames 缓存复用

**未验证**：并行优化在真实视频上的加速效果，以及输出一致性。
**光流调制也未验证**：需要批量跑 49 个视频对比调制前后分数。

**最新批量基线**：`outputs/all_video_scores_20260511_224820/` — bad=57.6, good=74.7, middle=66.4, testvideo=64.7, 全体 67.1。

## Current Goal

Current iOS UI redesign goal is complete. Next UI work should start from the implemented Ice Sport Technology SwiftUI components and preserve existing analysis behavior.

Previous analysis goal:

Phase 1 光流增强：Apple Vision `VNGenerateOpticalFlowRequest` 产出三个运动指标，以 ±13% 调制系数修正姿态总分，提升泛化性。Phase 1 仅做后处理调制，后续验证有效后可纳入 PoseScorer 作为独立维度（Phase 2）。

## Context Snapshot

- 光流在 `generateSummary()` 内计算，利用 `analyze()` 缓存的帧对。不改 `DetectionResult`/`PoseScorer`。
- `FlowMetricsCalculator` 三指标：motionCoherence（髋-踝方向差）、directionalStability（髋部 circular variance）、velocitySmoothness（光流幅值变化率）。
- 调制公式：stability 阈值依赖 poseScore 上下文——低分高 stability → 提分，高分低 stability → 扣分。范围 ±13%。
- `VideoSummary` 含评分拆解字段：rawPoseAverageScore → bestThirdAverageScore → evidenceCappedScore → flowModulationFactor → 最终分。报告显示拆解行。
- `sampleInterval` 默认 0.2s（5fps），帧数阈值已改为时长阈值。
- 板身判断用脚踝代理线；紫色图像候选线仅 debug，存在 near_board_false_positive 问题。
- 帧分析改为批次并行（batchSize=8），AVAssetImageGenerator 非线程安全故提取串行、分析并行。
- 帧缓存降采样至 640x480 再入光流，大幅降低内存。

## Existing Review Assets

- `outputs/edge_debug_review/` — 9 个样本（3 good, 3 middle, 3 bad），紫色线复核
- `outputs/misjudgment_review_20260506/` — 6 个疑似误判候选
- `outputs/all_video_scores_20260511_224820/` — 最新 50 视频批量跑分（含光流指标和 Ablation）
- 三个锚点：bad=65.0, middle=85.3, good=94.1（已确认合理，不要动）
- 代码重复已消除：7 个工具函数收敛到 `Utilities.swift`

## Completed (chronological)

- 紫色线复核：Round 1 确认 A/B/C 均为 near_board_false_positive，暂不升级为主证据
- 板身/滑行方向夹角接入封顶：≥30° 保守，≥45° 按横滑处理
- 高横滑角接入高光过滤 + 报告文案更新
- 49 视频批量回归：bad=57.3, middle=66.6, good=76.8
- Phase 1 光流增强：FlowMetricsCalculator + 帧缓存 + async generateSummary + 调制集成
- sampleInterval 1.0→0.2s，帧数阈值→时长阈值
- 评分拆解字段 + 报告拆解行
- 新增 `file_manifest.md`，用于快速定位项目文件与产物目录
- 将新增文件索引及引用说明改为中文
- 新增 `delta_update.md`，约束每轮结束只记录增量变化
- 统一使用 `delta_update.md` 作为增量记录文件名
- 88 tests, 0 failures
- 流水线性能优化：并行帧分析 + 帧缓存降采样 + async let 并发后处理 + reliableFrames 缓存复用
- CLAUDE.md 更新为启动时同时读取 WORK_LOG.md + file_manifest.md + delta_update.md
- --output-video 功能：独立 CLI 开关 → renderVideoOverlay → AVAssetWriter H.264 MP4，每帧独立跑 Vision 姿态检测，标注数据随帧实时更新。修复了帧提取容差和采样间隔下限两个 bug
- iOS App 模拟器测试支持：新增 DemoData.swift（72.57分 demo 数据）、AnalysisOutput 持久化到 analyses.json、首次启动注入 demo 条目、HistoryView 删除同步清理、ReportDetailView 视频播放器竖屏比例

## Recorded: 待优化点

### 高优先级
1. **运动方向（travelAngle）不可靠** — 光流方案低置信度帧角度跳动大。travelAngle → sideslipAngle → carvingConfidence → boardKinematicHighScoreCap（62分封顶）这条链路如果 travelAngle 不准，封顶可能误判。选项：A) 删除整条链路，edgeQualityScore 独立已够；B) 光流高置信度时启用，低时退化为不封顶；C) 继续优化光流采样方式。**深度研究确认：2D 透视误差是系统误差（E=100d/(D-d)），无法通过平滑消除——这说明 A 或 B 比 C 更合理。**
2. **5fps 采样率过低** — 深度研究确认：20ms 事件检测偏差 → 20° 膝关节角度误差（Mundt et al. 2024）。当前 200ms 帧间隔远超此阈值。**提高采样率到原生帧率（≥30fps）可显著提升关键事件（换刃/入弯）的时序精度。**
3. **Apple Vision 缺少足部关键点** — 官方文档确认腿部链终止于脚踝，iOS 18+ 也未增加。**脚踝代理方法是当前框架的理论上限，立刃角度检测存在不可消除的信号丢失。** 长期需考虑光流追踪雪板边缘或 IMU 融合。

### 中优先级
1. SkiAnaylze 代码重复 — 8 文件落后于 FallLineCore，`scripts/setup_ios_deps.sh` 写好删除逻辑
2. 光流信号薄弱 — 只用髋+踝 2 关键点，circularVariance 硬编码边界未文档化
3. 置信度阈值分散 — 五处各自定义（0.30/0.35/0.15/0.65），无单一来源。**深度研究推荐：参考 Anipose 的 confidence-weighted IK 方案，低置信度关节点降低权重而非直接丢弃帧。**
4. ReportGenerator 种子溢出 — `abs(Int.min)` 可能崩溃
5. 报告优势/问题阈值不对称 — 系统性负面偏见
6. "重心旧分"与"重心阶段适配"并存 — 用户易困惑

### 低优先级
1. CI/CD 缺失 — 无 GitHub Actions、无 lint、无覆盖率
2. 输出资产膨胀 — edge_debug_review/（399 MB）、misjudgment_review/（242 MB）
3. 4 个过期批量跑分目录可清理
4. TemporalSmoother 孤文档 — 设计已写但从未实现。**深度研究为时序平滑提供了三个参考方案：SmoothNet（SOTA plug-and-play）、Anipose Viterbi filter（confidence + 运动先验）、Sports2D pipeline（Hampel 异常值剔除 + GCV 样条 + Kalman）。**
5. DebugOverlayRenderer.swift:115 唯一 `!` 强制解包
6. 提交信息风格不一致

## Next Steps

### 算法准确度提升（来自 2026-06-05 深度研究）

**立即做**：
1. **提高采样率**：从 5fps 升至视频原生帧率（≥30fps）。200ms 帧间隔远超 20ms/20° 的时序误差阈值。可批量处理、降低 per-frame 分辨率来平衡 Vision API 性能。

**短期（1-2 周）**：
2. **升级到 VNHumanBodyPose3DObservation**（iOS 17+）：获取 3D 关节点，为后续规范化步骤和视角校准提供基础。当前返回的 2D 关键点无法进行有意义的透视修正（公式确认关节角度无法通过简单比例修正）。
3. **实现 confidence-weighted 时序平滑**：替代当前的简单置信度门控（<0.30 丢弃）。参考方案：Anipose 的 Viterbi filter（confidence 先验 + 预期运动 std）或 Sports2D 的 pipeline（Hampel 异常值剔除 → GCV 样条 → Kalman）。

**中期（1-2 月）**：
4. **决定 travelAngle 链路去留**：深度研究确认 2D 透视误差是系统误差、无法通过平滑消除 → 选项 A（删除链路）或 B（光流高置信度时启用）比 C（继续优化光流采样）更合理。

**长期**：
5. **探索滑雪场景透视误差估计**：基于 Yokoi & Okada 公式 E=100d/(D-d)，假设雪面为标定面来估计 2D 光流与真实 3D 行进方向之间的系统偏差。需验证在非正交相机角度下的适用性。
6. **评估 3DPCNet 规范化**：在滑雪视频上验证高度 crouch/旋转姿态下的退化程度。如可用，可大幅减少不同拍摄角度下的一致性差异。
7. **Phase 2 光流纳入 PoseScorer**：前提是完成 travelAngle 去留决策和采样率提升。

### 之前待办（未被取代）
- 批量跑 49 视频，对比光流调制前后分数，重点看变化 >5 分的
- 同期验证并行优化的输出一致性（JSON/MD 与优化前对比）

## Important Files

### 进步曲线（2026-08-29 再续）
- `Sources/FallLineCore/TrendAnalytics.swift` — Core 纯计算模块（SessionEntry / WeeklySummary / Milestone / TrendReport / TrendAnalytics）
- `SkiAnaylze/SkiAnaylze/TrendStore.swift` — iOS UserDefaults 持久化 + record/refreshReport 单一 API
- `SkiAnaylze/SkiAnaylze/Views/TrendView.swift` — Charts 折线图 UI（三段：统计卡 → 折线图 → 里程碑徽章）
- `SkiAnaylze/SkiAnaylze/TrendNotificationCenter.swift` — UNUserNotificationCenter 里程碑推送封装
- `scripts/setup_ios_deps.sh` — iOS SPM 化辅助脚本（--dry / --yes / --rollback + 备份 + Xcode 7 步说明）

### 深度研究（2026-06-05）
- `outputs/research/2026-06-05-pose-estimation-accuracy-deep-research.md` — 完整研究报告（7 发现 + 4 开放问题 + 5 建议）
- 关键来源: [3DPCNet](https://arxiv.org/html/2509.23455) / [透视误差](https://cir.nii.ac.jp/crid/1390001204309690752) / [时序精度](https://pubmed.ncbi.nlm.nih.gov/38984681/) / [Apple Vision 文档](https://developer.apple.com/documentation/Vision/detecting-human-body-poses-in-images) / [滑雪专项微调](https://ciss-journal.org/article/view/11530)
- 工作流 run ID: `wf_64680db7-fce`，104 agents，~300 万 token

### iOS UI
- `docs/superpowers/specs/2026-05-25-ios-ui-ice-sport-technology-design.md` — iOS UI redesign approved design spec
- `docs/superpowers/plans/2026-05-25-ios-ui-ice-sport-technology.md` — iOS UI redesign implementation plan
- `SkiAnaylze/SkiAnaylze/AppTheme.swift` — UI redesign theme/component entry point
- `SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/` — iOS App Icon assets (Alpine scan-reticle)
- `scripts/generate_fallline_app_icon.swift` — reproducible generator for the AppIcon PNGs
- `SkiAnaylze/SkiAnaylze/Views/HomeView.swift` — redesigned home/upload flow target
- `SkiAnaylze/SkiAnaylze/Views/AnalysisProgressView.swift` — redesigned analysis progress target
- `SkiAnaylze/SkiAnaylze/Views/HistoryView.swift` — redesigned training records target
- `SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift` — redesigned report/detail/share target
- `SkiAnaylze/SkiAnaylze/Views/SplashView.swift` — 开屏动画视图（新增）
- `SkiAnaylze/SkiAnaylze/Views/RootView.swift` — 根视图状态管理（新增）
- `SkiAnaylze/SkiAnaylze/Services/AdProvider.swift` — 广告接口协议 + 默认实现（新增）

### FallLineCore / CLI
- `Sources/FallLineCore/VideoAnalyzer.swift` — 管线编排（含批次并行 + 帧缓存降采样）
- `Sources/FallLineCore/FlowMetricsCalculator.swift` — Phase 1 光流
- `Sources/FallLineCLI/main.swift` — CLI 入口（含 async let 并发后处理 + --output-video 分支）
- `Sources/FallLineCLI/DebugOverlayRenderer.swift` — 调试图渲染（PNG 帧 + MP4 视频覆盖图）
- `Sources/FallLineCore/Models.swift` — 数据结构
- `Sources/FallLineCore/ReportGenerator.swift` — 报告生成
- `Sources/FallLineCore/BoardDirectionAnalyzer.swift` — 板身判断
- `Tests/FallLineCoreTests/FlowMetricsCalculatorTests.swift` — 19 tests

### 文档与产物
- `docs/superpowers/specs/2026-05-11-optical-flow-scoring-enhancement-design.md`
- `docs/superpowers/specs/2026-05-17-output-video-overlay-design.md`
- `docs/superpowers/plans/2026-05-11-optical-flow-scoring-enhancement.md`
- `docs/superpowers/plans/2026-05-17-output-video-overlay-plan.md`
- `delta_update.md` — 每轮增量变化记录（含中低优待办清单）
- `file_manifest.md` — 项目文件索引
- `outputs/all_video_scores_20260511_224820/score_summary.tsv`
