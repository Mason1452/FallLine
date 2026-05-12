# VideoVision Work Log

## Current State (2026-05-12)

**代码状态**：Phase 1 光流增强已实现完毕，88 tests 全通过。**但代码未提交，仍在 main 分支工作区。** 光流逻辑尚未在真实视频上验证效果。

**已改动但未提交的文件**：
- `FlowMetricsCalculator.swift` (新) — 光流指标计算 + 调制公式
- `FlowMetricsCalculatorTests.swift` (新) — 19 tests
- `VideoAnalyzer.swift` — 帧缓存、async generateSummary、光流调制、sampleInterval 0.2s、时长阈值
- `Models.swift` — VideoSummary 新增 rawPoseAverageScore/bestThirdAverageScore/evidenceCappedScore/flowModulationFactor/flowFramePairsUsed/光流三指标
- `ReportGenerator.swift` — 评分拆解行 + 光流指标展示
- `main.swift` — await generateSummary
- `StableCarvingBaselineTests.swift` — async/await 适配
- `Utilities.swift` — 新增 linearMap()

**已验证**：`swift test` 88 tests, 0 failures（含 19 个 FlowMetricsCalculatorTests + 6 个 StableCarvingBaselineTests）。

**已验证**：`swift build -c release` 通过。

**未验证**：49 个视频批量跑分对比（光流调制前 vs 后）。这是 Phase 1 能否合入的关键决策依据。

**最新批量基线**：`outputs/all_video_scores_20260511_224820/` — bad=57.6, good=74.7, middle=66.4, testvideo=64.7, 全体 67.1。含光流三项指标和 Ablation Scores。

**设计文档**：`docs/superpowers/specs/2026-05-11-optical-flow-scoring-enhancement-design.md`
**实现计划**：`docs/superpowers/plans/2026-05-11-optical-flow-scoring-enhancement.md`

**沙箱问题**：`mcp__workspace__bash` 不可用（coworkKappa/operon 在本版本未启用）。所有 git/build/test 命令需用户在终端执行后贴结果。

## Current Goal
Phase 1 光流增强：引入 Apple Vision `VNGenerateOpticalFlowRequest` 作为姿态评分的补充信号。光流产出三个指标（运动一致性、方向稳定性、速度平滑度），以 ±13% 调制系数修正姿态总分，提升跨拍摄角度和滑法的泛化性。Phase 1 仅做后处理调制，不改逐帧评分逻辑。

## Context Snapshot
- 光流调制是 Phase 1 后处理：不修改 `DetectionResult`、`PoseScorer`、`VisionFrameAnalyzer`。光流计算在 `generateSummary()` 内完成，利用 `analyze()` 阶段缓存的帧对。
- `FlowMetricsCalculator` 三个指标：motionCoherence（髋-踝方向差 → 上下身分离）、directionalStability（髋部方向 circular variance → 走刃/搓雪）、velocitySmoothness（光流幅值变化率 → 动作流畅度）。
- 调制系数通过 `computeModulation(coherence, stability, smoothness, poseScore:)` 计算，stability 阈值依赖 poseScore 上下文：低分高 stability → 提分（拍摄角度低估），高分低 stability → 扣分（静态好姿态但运动不稳）。
- 调制范围 ±13%，调制后分数 clamp 到 0-100。
- `VideoSummary` 增加评分拆解字段：`rawPoseAverageScore`、`bestThirdAverageScore`、`evidenceCappedScore`、`flowModulationFactor`、`flowFramePairsUsed`。报告显示「评分拆解」行。
- `sampleInterval` 默认改为 0.2s（5fps），帧数阈值已改为时长阈值以避免高采样率误判。
- 紫色线 = `visualBoardObservation` / `BoardObservationSource.visualCandidate`，来自 `BoardVisualLineDetector`。

## Existing Review Assets
- 复核输出目录：`outputs/edge_debug_review/`
- 样本汇总：`outputs/edge_debug_review/visual_candidate_summary.tsv`
- 每个样本目录包含逐帧 overlay PNG 和 `manifest.tsv`。
- 当前代表样本共 9 个：3 个 `good`，3 个 `middle`，3 个 `bad`。
- 去重回归复核目录：`outputs/all_video_scores_20260506_150537/`
- 疑似误判复核包：`outputs/misjudgment_review_20260506/`

- 已消除代码重复：将 `weightedAverage`、`average`、`formatTime`、`medianSampleInterval`、`normalizeAngle`、`weightedConfidence`、`weightedStandardDeviation` 共 7 个工具函数从 28 份拷贝收敛为 `Utilities.swift` 中的 7 个 `public` 版本。删除 3 处死代码（PoseMetrics 左右侧未使用统计、ReportGenerator 旧 `averageSubScores`）。`clamp` 已先收敛完毕。`swift test` 65 tests 全通过，CLI 构建成功。
- 注意：`SkiMetricsCalculator` 因存在同名 `static func average(from:stability:)` 无法直接调用全局 `average`，内部已内联计算。`StageClassifier` 保留其特有签名的 `weightedAverage([Double], [Double], Double)`。

## Completed
- 已确认 `outputs/edge_debug_review` 下存在 9 个样本目录。
- 已确认 `visual_candidate_summary.tsv` 汇总了每个样本的帧数、紫色候选出现帧数、平均/最佳置信度、候选长度和最佳帧图片路径。
- 已确认 `DebugOverlayRenderer` 会把紫色候选线画到 overlay PNG，并把 `visualBoardAngle`、`visualBoardConfidence`、`visualBoardLength` 写入 `manifest.tsv`。
- 已确认当前评分逻辑仍不使用紫色图像候选线。
- 已生成第一轮人工复核包：`outputs/visual_candidate_review_round1/`。该轮从 `bad` / `good` / `middle` 三类各挑一个最高置信紫色候选，并生成 3 秒原视频片段、对应 overlay PNG 和 `README.md` 复核索引。
- Round 1 人工结论：A/B/C 看到的紫色线都不是板身，而是在板身或脚附近的误检。已在 `outputs/visual_candidate_review_round1/README.md` 标为 `snow_texture`，子类记为 `near_board_false_positive`。
- 已将板身/滑行方向夹角接入保守封顶：`>=30°` 不能保留高刻滑分，`>=45°` 基本按横滑/推坡封顶。
- 已将高横滑角接入高光过滤：如果没有稳定刻滑基线，且脚踝代理给出可信高横滑角，则不输出“最佳刻滑/高质量”高光。
- 已更新报告文案：高横滑角时明确提示“板身/滑行方向夹角偏大，更像横滑或推坡，不能按刻滑高分处理”。
- 已补测试并通过 `swift test`：65 tests, 0 failures。
- 已批量重跑 `video/` 下 49 个视频，失败数 0。汇总输出在 `outputs/all_video_scores_20260505_210424/score_summary.md` 和 `score_summary.tsv`；本次分组均分：`bad=57.3`、`middle=66.6`、`good=76.8`、`root=65.0`。
- 人工复核确认以下三个原本疑似需校准的分数没有问题：`video/bad/0b7522e9db823b910ac67727aea726da.MP4` = 65.0，`video/middle/96001e37e76be9ef6cf7a65e73efcac4.MP4` = 85.3，`video/good/v0200fg10000d7r0017og65qoh1vgeg0.MP4` = 94.1。已写入 `annotations/calibration_anchors.md` 的 accepted current scores。
- 去重后回归已完成：`swift test` 65 tests 通过；三个锚点 CLI 复跑仍为 65/85/94（CLI 取整，对应 65.0/85.3/94.1）；49 个视频复跑失败数 0。
- 新汇总在 `outputs/all_video_scores_20260506_150537/score_summary.tsv` 和 `.md`；与 `outputs/all_video_scores_20260505_210424/score_summary.tsv` 逐字段对比差异数 0，差异文件 `outputs/all_video_scores_20260506_150537/score_diff_vs_20260505_210424.tsv` 只有表头。
- 已筛 6 个疑似误判候选并生成覆盖图 sheet：`good_9ed0bb6c...`、`middle_b343...`、`middle_v2800...d54j...`、`good_86ae...`、`good_5382...`、`bad_v2800...d4v24...`。初步复核未发现必须立刻改规则的新误判：高横滑高分样本已被低置信度或封顶文案约束，`good` 低分样本主要是视角/关键点稳定性不足导致的保守分。
- 已按当前工作区评分标准重跑 `testvideo/` 下 6 个视频，失败数 0。汇总输出在 `outputs/testvideo_scores_20260506_162240/score_summary.tsv` 和 `.md`；均分 65.8，单片分数：`1=58`、`2=58`、`3=85.9`、`4=65`、`5=58`、`6=70`。
- 用户修改大量代码后，已按当前工作区代码重跑 `video/` 与 `testvideo/` 下全部 50 个视频，失败数 0。汇总输出在 `outputs/all_video_scores_20260511_220451/score_summary.tsv` 和 `.md`；分组均分：`bad=55.5`、`good=72.9`、`middle=66.3`、`testvideo=64.4`、全体 `66.1`。
- 已将 `VideoAnalyzer` 默认采样间隔从 1.0 秒提升到 0.2 秒（默认 5fps），用于给光流更密集的相邻帧；同时清空 `analyze()` 开始时的光流帧缓存，避免同一 analyzer 重复调用时缓存叠加。`swift test` 85 tests 全通过。
- 已按 0.2 秒采样间隔（5fps）重跑 `video/` 与 `testvideo/` 下全部 50 个视频，失败数 0。汇总输出在 `outputs/all_video_scores_20260511_222027/score_summary.tsv` 和 `.md`；分组均分：`bad=59.4`、`good=74.7`、`middle=67.4`、`testvideo=64.7`、全体 `67.8`。本轮汇总额外包含光流三项指标列。
- 已将高采样率下的帧数阈值改为时长阈值：可靠评分封顶、高光输出、短片段低板身证据、横滑封顶和稳定刻滑平台都按秒数判断，避免 5fps 让几帧证据被误当作持续证据。`VideoSummary` 增加评分拆解字段：原始可靠均分、最佳前 1/3、证据封顶后分、光流系数和光流帧对数；报告会输出“评分拆解”。新增高采样率短片段测试，`swift test` 88 tests 全通过。
- 按上述时长阈值与评分拆解代码重跑 `video/` 与 `testvideo/` 下全部 50 个视频，失败数 0。汇总输出在 `outputs/all_video_scores_20260511_224820/score_summary.tsv` 和 `.md`；分组均分：`bad=57.6`、`good=74.7`、`middle=66.4`、`testvideo=64.7`、全体 `67.1`。本轮 `score_summary.md` 包含 `Ablation Scores` 表。

## Next Steps
1. **提交当前改动到 feature 分支**（不要在 main 上继续堆改动）：
   ```bash
   git checkout -b feature/optical-flow-phase1
   git add -A
   git commit -m "feat(Phase 1): optical flow post-processing modulation"
   ```
2. **批量跑 49 个视频，对比光流调制效果**：关注调制前后分数变化 >5 分的视频，人工判断是否合理。
3. **如果光流效果正面**：merge 回 main。
4. **如果效果不明显或负面**：在分支上调参数（阈值/调制幅度），重新跑批。
5. **Phase 2（远期）**：若 Phase 1 验证有效，将光流指标纳入 PoseScorer 作为独立评分维度（5→7-8 维）。
6. 紫色线分支暂不推进。iOS app 代码重复问题（REFACTOR_PLAN.md Phase 2）暂不处理。

## Important Files
- `README.md`
- `Sources/VideoVisionCore/FlowMetricsCalculator.swift` — **New** Phase 1 光流指标计算与调制
- `Sources/VideoVisionCore/BoardVisualLineDetector.swift`
- `Sources/VideoVisionCore/BoardDirectionAnalyzer.swift`
- `Sources/VideoVisionCore/Models.swift`
- `Sources/VideoVisionCore/Utilities.swift`
- `Sources/VideoVisionCore/VideoAnalyzer.swift`
- `Sources/VideoVisionCore/HighlightMomentDetector.swift`
- `Sources/VideoVisionCore/ReportGenerator.swift`
- `Sources/VideoVisionCLI/DebugOverlayRenderer.swift`
- `Tests/VideoVisionCoreTests/FlowMetricsCalculatorTests.swift` — **New** 19 tests
- `docs/superpowers/specs/2026-05-11-optical-flow-scoring-enhancement-design.md`
- `docs/superpowers/plans/2026-05-11-optical-flow-scoring-enhancement.md`
- `outputs/all_video_scores_20260511_224820/score_summary.tsv` — 最新批量跑分

## Working Tree Note
当前工作区已有多处未提交改动和未跟踪输出，包括 `BoardVisualLineDetector.swift`、`DebugOverlayRenderer.swift`、相关测试和 `outputs/edge_debug_review/`。后续任务应先读 `git status --short`，不要回退不属于当前任务的改动。

## Update Rule
每次长任务开始或结束时更新本文件。保持短小，只记录可恢复上下文：目标、关键结论、改动文件、跑过的验证、剩余步骤和风险。
