# FallLine 文件清单

最后更新：2026-05-21

本文档是项目文件索引，用来帮助快速判断“应该读哪个文件、改哪个文件、哪些目录只是样本或生成产物”。源码文件逐个列出；视频、日志、调试图这类大目录按用途归类，不逐个枚举每个媒体或输出文件。

## 更新规则

新增、删除、重命名重要文件，或改变文件/目录职责时，需要同步更新本文档。生成产物目录默认按目录级别说明；只有当某个产物成为稳定参考资产时，才单独列出。

## 顶层文件

| 路径 | 用途 |
| --- | --- |
| `Package.swift` | SwiftPM 包定义，声明 `FallLineCore`、`FallLineCLI` 和 `FallLineCoreTests`。 |
| `README.md` | 面向使用者的项目介绍、运行方式、输出结构和评分说明。 |
| `AGENTS.md` | Agent 使用的项目工作说明。 |
| `CLAUDE.md` | Claude 使用的项目工作说明副本。 |
| `WORK_LOG.md` | 当前项目状态、目标、已完成工作和下一步。开始工作前必须先读。 |
| `delta_update.md` | 每轮工作的增量变化记录；只写变化，不重复全量项目背景。 |
| `file_manifest.md` | 项目文件索引和职责说明。 |
| `.gitignore` | Git 忽略规则。 |

## Swift 包源码

### `Sources/FallLineCore/`

核心 macOS 分析库，是 CLI 和测试使用的主实现。分析逻辑优先在这里修改。

| 文件 | 用途 |
| --- | --- |
| `Models.swift` | Codable 输出模型和分析领域类型。文件较大，按关键字读取。 |
| `VideoAnalyzer.swift` | 视频抽帧、帧缓存和逐帧分析编排。 |
| `VisionFrameAnalyzer.swift` | Apple Vision 请求封装，负责人体姿态等帧级观测。 |
| `PoseMetrics.swift` | 将 Vision 关节点转换为身体倾斜、膝盖弯曲、小腿倾斜、重心代理等姿态指标。 |
| `PoseScorer.swift` | 姿态评分权重、等级和改进建议。 |
| `SkiMetricsCalculator.swift` | 滑雪派生指标：走刃质量、板压支撑、前后支撑。 |
| `KeyMomentDetector.swift` | 从评分帧中检测薄弱时刻和最佳时刻。 |
| `BoardDirectionAnalyzer.swift` | 使用脚踝代理板身方向和运动方向估计走刃/横滑证据。 |
| `BoardVisualLineDetector.swift` | 仅用于调试的图像级板身候选线检测，不作为主评分证据。 |
| `TurnPhaseDetector.swift` | 推断转换、入弯、塑形、释放等转弯阶段。 |
| `CenterOfMassFitCalculator.swift` | 按阶段目标评估 hipRatio 对应的重心匹配度。 |
| `HighlightMomentDetector.swift` | 检测连续高光片段。 |
| `FlowMetricsCalculator.swift` | Phase 1 光流三指标和分数调制逻辑。 |
| `StageClassifier.swift` | 报告上下文使用的阶段/水平分类辅助逻辑。 |
| `ReportGenerator.swift` | 根据分析上下文生成 Markdown 自然语言报告。 |
| `Utilities.swift` | 通用数学、置信度、时长、可靠性和证据封顶辅助函数。 |

### `Sources/FallLineCLI/`

macOS 命令行入口和可选调试图渲染。

| 文件 | 用途 |
| --- | --- |
| `main.swift` | CLI 参数解析、视频分析执行、JSON/Markdown 输出和汇总生成。 |
| `DebugOverlayRenderer.swift` | 渲染逐帧调试覆盖图：板身方向、图像候选线、运动方向和骨架标记。也包含 `renderVideoOverlay()` 用于将分析覆盖图渲染为 MP4 视频。 |

## 测试

### `Tests/FallLineCoreTests/`

针对主实现 `FallLineCore` 的单元测试。

| 文件 | 用途 |
| --- | --- |
| `AngleCalculationTests.swift` | 姿态角度计算测试。 |
| `PoseScorerTests.swift` | 评分阈值、权重、可见性处理和等级测试。 |
| `EdgeCaseTests.swift` | 缺失姿态、低置信度等边界情况测试。 |
| `SkiMetricsCalculatorTests.swift` | 滑雪派生指标计算测试。 |
| `StableCarvingBaselineTests.swift` | 稳定刻滑平台期基线和分数选择行为测试。 |
| `BoardDirectionAnalyzerTests.swift` | 板身方向、运动方向、横滑/走刃证据测试。 |
| `BoardVisualLineDetectorTests.swift` | 调试用图像候选线检测测试。 |
| `TurnPhaseDetectorTests.swift` | 转弯阶段切分和刃向行为测试。 |
| `CenterOfMassFitCalculatorTests.swift` | 重心匹配评分和阶段目标测试。 |
| `HighlightMomentDetectorTests.swift` | 连续高光片段检测测试。 |
| `FlowMetricsCalculatorTests.swift` | 光流指标、调制逻辑和边界保护测试。 |

## iOS App

### `SkiAnaylze/`

SwiftUI iOS App。`SkiAnaylze/SkiAnaylze/Sources/` 下存在一份核心分析代码副本，这是已知技术债；在 Xcode 工程仍直接持有这些文件之前，不应把它们当成主实现。

| 路径 | 用途 |
| --- | --- |
| `SkiAnaylze/Package.swift` | iOS App 的本地包依赖声明。 |
| `SkiAnaylze/SkiAnaylze.xcodeproj/` | Xcode 工程、scheme 和 workspace 元数据。 |
| `SkiAnaylze/SkiAnaylze/SkiAnaylzeApp.swift` | iOS App 入口。 |
| `SkiAnaylze/SkiAnaylze/ContentView.swift` | App 根视图。 |
| `SkiAnaylze/SkiAnaylze/VideoAnalysisManager.swift` | iOS 分析状态和进度编排。 |
| `SkiAnaylze/SkiAnaylze/AppTheme.swift` | App 颜色、卡片样式、进度条和分数条组件。 |
| `SkiAnaylze/SkiAnaylze/Views/HomeView.swift` | 视频选择和开始分析流程。 |
| `SkiAnaylze/SkiAnaylze/Views/AnalysisProgressView.swift` | 分析进度界面。 |
| `SkiAnaylze/SkiAnaylze/Views/HistoryView.swift` | 已保存报告/历史记录界面。 |
| `SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift` | 报告展示和分享界面。 |
| `SkiAnaylze/SkiAnaylze/Sources/DemoData.swift` | 模拟器测试用默认演示 AnalysisOutput（基于 testvideo/3.MP4 数据）。 |
| `SkiAnaylze/SkiAnaylze/Sources/` | 重复的分析核心子集：`Models`、`VideoAnalyzer`、`VisionFrameAnalyzer`、`PoseMetrics`、`PoseScorer`、`SkiMetricsCalculator`、`KeyMomentDetector`、`ReportGenerator`。 |

## 文档和标定

| 路径 | 用途 |
| --- | --- |
| `annotations/calibration_anchors.md` | 标定锚点和经验评分参考。 |
| `annotations/good_coach_annotations.json` | 教练/参考标注数据。 |
| `docs/superpowers/specs/2026-05-08-temporal-smoothing-design.md` | 时间平滑设计说明。 |
| `docs/superpowers/specs/2026-05-11-optical-flow-scoring-enhancement-design.md` | 光流评分增强设计说明。 |
| `docs/superpowers/specs/2026-05-17-output-video-overlay-design.md` | --output-video 输出标注视频功能设计说明。 |
| `docs/superpowers/plans/2026-05-11-optical-flow-scoring-enhancement.md` | 光流增强实现计划。 |
| `docs/superpowers/plans/2026-05-17-output-video-overlay-plan.md` | --output-video 输出标注视频实现计划。 |

## 脚本

| 路径 | 用途 |
| --- | --- |
| `scripts/setup_ios_deps.sh` | iOS 依赖设置辅助脚本。 |

## 视频、输出和复核产物

这些目录包含样本输入、生成报告、调试覆盖图和批量跑分产物。它们适合做回归复核，但不是实现逻辑的源头。

| 路径 | 用途 |
| --- | --- |
| `video/good/` | 标注为 good 的滑雪样本视频和生成的 Markdown 报告。 |
| `video/middle/` | 标注为 middle 的滑雪样本视频和生成的 Markdown 报告。 |
| `video/bad/` | 标注为 bad 的滑雪样本视频和生成的 Markdown 报告。 |
| `testvideo/` | 编号测试视频和生成的 Markdown 报告。 |
| `output/` | 较早的分析输出示例。 |
| `outputs/all_video_scores_*/` | 批量跑分结果、日志、分数汇总和 ablation 输出。 |
| `outputs/testvideo_scores_*/` | 针对 `testvideo/` 的批量跑分产物。 |
| `outputs/edge_debug_review/` | 板身/走刃证据调试覆盖图复核资产。 |
| `outputs/misjudgment_review_*/` | 误判复核帧图、拼图、manifest 和日志。 |
| `outputs/visual_candidate_review_round1/` | 图像级板身候选线的人工复核资产。 |
| `outputs/high_score_segments/` | 高分片段抽取复核产物。 |

## 已知职责边界

- 分析逻辑优先修改 `Sources/FallLineCore/`。
- 除非明确处理 iOS App 或代码重复债，否则不要同步修改 `SkiAnaylze/SkiAnaylze/Sources/` 下的重复文件。
- `outputs/`、`output/`、`video/`、`testvideo/` 属于证据/产物目录，不要主动做大范围清理或重写。
- 熟悉项目时，先读 `WORK_LOG.md`，再读 `AGENTS.md`/`CLAUDE.md`，然后用本文档定位文件。
