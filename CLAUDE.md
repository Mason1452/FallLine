# CLAUDE.md

> 开始任何工作前，先阅读 `WORK_LOG.md`（当前状态/目标/下一步）、`file_manifest.md`（文件索引）和 `delta_update.md`（近期变更）。

## 构建与测试

```bash
swift build -c release          # 构建 CLI（macOS）
swift run FallLineCLI <video> # 运行分析 → JSON + Markdown 报告
swift run FallLineCLI --debug-overlay <video>  # + 逐帧调试 PNG
swift run FallLineCLI --output-video <video>  # + 带标注的 MP4（原生帧率，逐帧 Vision 分析）
swift test                       # 88 个测试
swift test --filter <TestName>
swift test 2>&1 | tail -5        # 仅看摘要
```

## 项目架构

FallLine 使用 Apple Vision 分析滑雪视频中的姿态。要求 macOS 14+。

- **FallLineCore** — 15 个源码文件
- **FallLineCLI** — macOS 命令行工具，依赖 FallLineCore
- **FallLineCoreTests** — 11 个测试文件
- `SkiAnaylze/` — iOS 应用，包含重复的核心代码（已知技术债，不在 SwiftPM 工作空间中）

## 分析流水线

```
视频帧（CGImage，采样间隔 0.2s = 5fps）
  → VisionFrameAnalyzer（VNDetectHumanBodyPoseRequest）
  → PoseMetricsCalculator（8 个关键点 → 角度、髋比、倾斜度、重心）
  → PoseScorer（5 维度：倾斜 20%、膝盖 25%、小腿 20%、重心 20%、对称性 15%）
  → DetectionResult（每帧结果）
  ↓
generateSummary() 后处理：
  → SkiMetricsCalculator（立刃质量、压力支撑、前后重心）
  → KeyMomentDetector（最佳/最差帧）
  → FlowMetricsCalculator（光流：一致性、稳定性、平滑度、行进方向）
  → BoardDirectionAnalyzer（脚踝代理 + 光流行进角度 → 侧滑、刻滑置信度）
  → TurnPhaseDetector（过渡/入弯/控制/出弯）
  → CenterOfMassFitCalculator（阶段感知的髋比目标）
  → HighlightMomentDetector（最佳连续片段）
  → 光流调制（±13% 分数调整）
  → ReportGenerator（Markdown 报告）
```

`VideoAnalyzer` 负责编排帧提取和逐帧分析。`FlowMetricsCalculator.computeWithDirections()` 单次光流遍历同时产出 FlowMetrics 和行进方向。后处理在 `main.swift` 中。

## 关键设计决策

- **置信度门控**：minimumPoseScoreConfidence=0.30，minimumSkiMetricConfidence=0.35。低置信度帧不计入评分，报告中显示"暂不评分"。
- **稳定刻滑基线**：稳定性 ≥85 + 连续 ≥5 帧的平台期 ≥ 视频总时长 18% → 取平台期平均值作为真实分数。防止低置信度刻滑帧被误判。
- **证据上限**：立刃/雪板/时长证据各自对分数设上限。阈值基于时长（秒），而非帧数（5fps）。
- **光流（第一阶段）**：`VNGenerateOpticalFlowRequest` 在缓存的帧对上运行。三个指标调制证据上限分 ±13%。稳定性阈值上下文感知：低分 + 高稳定性 → 加分；高分 + 低稳定性 → 扣分。
- **分数透明**：`VideoSummary` 包含 rawPoseAverageScore、bestThirdAverageScore、evidenceCappedScore、flowModulationFactor。报告中展示分解明细。
- **VideoSeed**：使用文件名的 DJB2 哈希，确保输出确定性。
- **雪板检测**：脚踝代理为主要方法；视觉线条检测仅为调试用途（存在 near_board_false_positive 问题）。
- **行进方向**：光流（`computeWithDirections`）采样髋+踝位置的像素运动向量作为行进方向，替代了 hipCenter 2D 位移。已知问题：低置信度帧角度跳动大，画面 2D 像素运动 ≠ 雪板实际行进方向。travelAngle → sideslip → carvingConfidence → boardKinematicHighScoreCap（62分封顶）链路可能误判，待决策。

## 代码重复

`SkiAnaylze/SkiAnaylze/Sources/` 中有 8 个文件与 FallLineCore/ 重复。`SkiAnaylze/Package.swift` 已声明依赖但 Xcode 项目尚未更新。参见 REFACTOR_PLAN.md 第二阶段。工具类已统一（2026-05-06）。

## 评分阈值

基于经验校准，非实验性。校准锚点参见 `annotations/calibration_anchors.md`。
- 倾斜：理想 10°–60°（2D 无法区分前倾和侧倾）
- 膝盖：理想 80°–135°（过深扣 4分/10°，过直扣 28分/10°）
- 小腿：0°=0分，80°=100分
- 重心：`107.5 - hipRatio × 100`，范围 [10, 100]
- 对称性：加权（膝盖 0.5，小腿 0.3，倾斜 0.2）
- 质量上限：当膝盖<60 或对称性<45 时，totalScore ≤72

## 阅读指南

- **增量记录**：`delta_update.md` — 每轮结束只记录本轮变化、验证和遗留问题，不重讲全量项目
- **文件索引**：`file_manifest.md` — 源码、测试、iOS App、文档、脚本和生成产物清单
- **流水线**：`VideoAnalyzer.swift`、`main.swift`
- **光流**：`FlowMetricsCalculator.swift`（compute、computeModulation、applyModulation）
- **模型**：`Models.swift` — 按关键词查找，不要通读全文件
- **报告**：`ReportGenerator.swift` — `buildContext()` 是入口点
- 可跳过通读的文件：`PoseMetrics.swift`、`PoseScorer.swift`、`DebugOverlayRenderer.swift`
- 使用 `rg "keyword" Sources/` 进行查找；展开 diff 前先用 `git diff --stat`
