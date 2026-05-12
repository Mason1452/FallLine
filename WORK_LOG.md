# FallLine Work Log

## Current State (2026-05-12)

**代码已提交到 `feature/optical-flow-phase1` 分支**，88 tests 全通过，`swift build -c release` 通过。

**未验证**：光流调制在真实视频上的效果。需要批量跑 49 个视频对比调制前后分数。

**最新批量基线**：`outputs/all_video_scores_20260511_224820/` — bad=57.6, good=74.7, middle=66.4, testvideo=64.7, 全体 67.1。含光流三项指标和 Ablation Scores。

**沙箱**：`mcp__workspace__bash` 不可用。git/build/test 需用户在终端执行后贴结果。

## Current Goal

Phase 1 光流增强：Apple Vision `VNGenerateOpticalFlowRequest` 产出三个运动指标，以 ±13% 调制系数修正姿态总分，提升泛化性。Phase 1 仅做后处理调制，后续验证有效后可纳入 PoseScorer 作为独立维度（Phase 2）。

## Context Snapshot

- 光流在 `generateSummary()` 内计算，利用 `analyze()` 缓存的帧对。不改 `DetectionResult`/`PoseScorer`。
- `FlowMetricsCalculator` 三指标：motionCoherence（髋-踝方向差）、directionalStability（髋部 circular variance）、velocitySmoothness（光流幅值变化率）。
- 调制公式：stability 阈值依赖 poseScore 上下文——低分高 stability → 提分，高分低 stability → 扣分。范围 ±13%。
- `VideoSummary` 含评分拆解字段：rawPoseAverageScore → bestThirdAverageScore → evidenceCappedScore → flowModulationFactor → 最终分。报告显示拆解行。
- `sampleInterval` 默认 0.2s（5fps），帧数阈值已改为时长阈值。
- 板身判断用脚踝代理线；紫色图像候选线仅 debug，存在 near_board_false_positive 问题。

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
- 88 tests, 0 failures

## Next Steps

1. 批量跑 49 视频，对比光流调制前后分数，重点看变化 >5 分的
2. 效果好 → merge 到 main；效果差 → 调参重跑
3. 长期：Phase 2 光流纳入 PoseScorer 独立维度

## Important Files

- `Sources/FallLineCore/FlowMetricsCalculator.swift` — Phase 1 光流
- `Sources/FallLineCore/VideoAnalyzer.swift` — 管线编排
- `Sources/FallLineCore/Models.swift` — 数据结构
- `Sources/FallLineCore/ReportGenerator.swift` — 报告生成
- `Sources/FallLineCore/BoardDirectionAnalyzer.swift` — 板身判断
- `Tests/FallLineCoreTests/FlowMetricsCalculatorTests.swift` — 19 tests
- `docs/superpowers/specs/2026-05-11-optical-flow-scoring-enhancement-design.md`
- `docs/superpowers/plans/2026-05-11-optical-flow-scoring-enhancement.md`
- `outputs/all_video_scores_20260511_224820/score_summary.tsv`
