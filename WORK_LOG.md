# FallLine Work Log

## Current State (2026-05-18)

**--output-video 功能已完成（含每帧独立分析）**，88 tests 全通过，`swift build -c release` 通过。

**已完成功能**：
- `--output-video` CLI 开关：将姿态分析覆盖图渲染为 MP4 (H.264) 视频
- 直接复用 `renderOverlay()` 绘制逻辑，与 `--debug-overlay` 的 PNG 覆盖图内容一致
- 输出原视频**每一帧**（原生帧率），**每帧独立跑 Vision 姿态检测**，标注数据随帧实时更新
- `AVAssetImageGenerator` 精确帧提取：`requestedTimeToleranceBefore/After = .zero`（修复前几秒帧重复 bug）
- `VideoAnalyzer` 采样间隔下限从 0.1s 降至 1/60s，支持原生 60fps 分析
- `--output-video` 启用时自动检测视频原生帧率作为采样间隔
- AVAssetWriter 管线：NSBitmapImageRep → CVPixelBuffer (BGRA, IOSurface backed) → H.264 Baseline 3Mbps
- 默认输出路径：原视频同目录 `<视频名>_analyzed.mp4`

**之前完成的优化（2026-05-13）**：
- 批次并行帧分析（batchSize=8，TaskGroup 并发）
- 帧缓存降采样（640x480，mem ~400MB → ~60MB）
- main.swift 四个检测器 async let 并发
- generateSummary 内 reliableFrames 缓存复用

**未验证**：并行优化在真实视频上的加速效果，以及输出一致性。
**光流调制也未验证**：需要批量跑 49 个视频对比调制前后分数。

**最新批量基线**：`outputs/all_video_scores_20260511_224820/` — bad=57.6, good=74.7, middle=66.4, testvideo=64.7, 全体 67.1。

## Current Goal

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

## Recorded: 待优化点

### 中优先级
1. SkiAnaylze 代码重复 — 8 文件落后于 FallLineCore，`scripts/setup_ios_deps.sh` 写好删除逻辑
2. 光流信号薄弱 — 只用髋+踝 2 关键点，circularVariance 硬编码边界未文档化
3. 置信度阈值分散 — 五处各自定义（0.30/0.35/0.15/0.65），无单一来源
4. ReportGenerator 种子溢出 — `abs(Int.min)` 可能崩溃
5. 报告优势/问题阈值不对称 — 系统性负面偏见
6. "重心旧分"与"重心阶段适配"并存 — 用户易困惑

### 低优先级
1. CI/CD 缺失 — 无 GitHub Actions、无 lint、无覆盖率
2. 输出资产膨胀 — edge_debug_review/（399 MB）、misjudgment_review/（242 MB）
3. 4 个过期批量跑分目录可清理
4. TemporalSmoother 孤文档 — 设计已写但从未实现
5. DebugOverlayRenderer.swift:115 唯一 `!` 强制解包
6. 提交信息风格不一致

## Next Steps

1. 批量跑 49 视频，对比光流调制前后分数，重点看变化 >5 分的
2. 同期验证并行优化的输出一致性（JSON/MD 与优化前对比）
3. 效果好 → merge 到 main；效果差 → 调参重跑
4. 长期：Phase 2 光流纳入 PoseScorer 独立维度

## Important Files

- `Sources/FallLineCore/VideoAnalyzer.swift` — 管线编排（含批次并行 + 帧缓存降采样）
- `Sources/FallLineCore/FlowMetricsCalculator.swift` — Phase 1 光流
- `Sources/FallLineCLI/main.swift` — CLI 入口（含 async let 并发后处理 + --output-video 分支）
- `Sources/FallLineCLI/DebugOverlayRenderer.swift` — 调试图渲染（PNG 帧 + MP4 视频覆盖图）
- `Sources/FallLineCore/Models.swift` — 数据结构
- `Sources/FallLineCore/ReportGenerator.swift` — 报告生成
- `Sources/FallLineCore/BoardDirectionAnalyzer.swift` — 板身判断
- `Tests/FallLineCoreTests/FlowMetricsCalculatorTests.swift` — 19 tests
- `docs/superpowers/specs/2026-05-11-optical-flow-scoring-enhancement-design.md`
- `docs/superpowers/specs/2026-05-17-output-video-overlay-design.md`
- `docs/superpowers/plans/2026-05-11-optical-flow-scoring-enhancement.md`
- `docs/superpowers/plans/2026-05-17-output-video-overlay-plan.md`
- `delta_update.md` — 每轮增量变化记录（含中低优待办清单）
- `file_manifest.md` — 项目文件索引
- `outputs/all_video_scores_20260511_224820/score_summary.tsv`
