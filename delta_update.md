# Delta Update

最后更新：2026-05-18

本文档只记录每轮工作的增量变化，不记录项目全量背景。需要项目当前状态、目标和长期上下文时，先看 `WORK_LOG.md`；需要文件职责时，看 `file_manifest.md`。

## 记录规则

- 只写本轮新增、修改、删除、验证结果和遗留问题。
- 不重复整段项目背景、架构说明、历史决策或完整文件清单。
- 如果某个信息已经在 `WORK_LOG.md`、`AGENTS.md`、`CLAUDE.md` 或 `file_manifest.md` 中存在，只链接或点名引用。
- 每轮结束时新增一条简短记录；优先记录事实，不写推测。
- 同一轮没有代码变更时，明确写“仅文档变更”或“未运行测试”的原因。

## 2026-05-18 (--output-video 每帧独立分析修复)

### 问题
- `AVAssetImageGenerator` 默认时间容差为 `kCMTimePositiveInfinity`，导致前几秒反复返回同一帧（画面冻结）
- `VideoAnalyzer` 采样间隔下限 `max(0.1, ...)` 截断了原生帧率，50fps 视频只做到 10fps 分析

### 代码变更
- **VideoAnalyzer.swift**: `analyze()` 内 imageGenerator 新增 `requestedTimeToleranceBefore/After = .zero`；init 采样间隔下限从 `max(0.1, ...)` 改为 `max(1.0/60.0, ...)` 支持至 60fps
- **DebugOverlayRenderer.swift**: `renderVideoOverlay()` 内 generator 新增 `requestedTimeToleranceBefore/After = .zero`
- **main.swift**: 当 `--output-video` 启用时检测视频原生帧率，`sampleInterval = 1.0 / nativeFPS`；新增单独的 `AVAsset` 实例用于 FPS 探测

### 效果
- 50fps 视频：分析帧数从 200 (10fps) 增至 1000 (50fps)，每帧独立 Vision 姿态检测
- 输出视频每帧标注数据随帧实时更新，不再出现连续帧标注一致

### 验证
- `swift build -c release` 通过
- `swift test` 88 tests, 0 failures
- E2E：testvideo/3.MP4 产出 999 帧 50fps MP4，分析 835/1000 帧

---

## 2026-05-17 (--output-video 输出标注视频功能)

### 代码变更
- **main.swift**: CLIOptions 新增 `outputVideo: Bool` 字段；parseOptions() 新增 `--output-video` 解析；printUsage() 新增用法行；主流程新增 `if options.outputVideo` 分支调用 `renderVideoOverlay()`
- **DebugOverlayRenderer.swift**: 新增 `RenderVideoResult` struct、`RenderError` enum、`renderVideoOverlay()` 方法（遍历原视频每一帧，逐帧查找最近邻分析数据，复用 `renderOverlay()` 绘制，经 CVPixelBuffer 写入 AVAssetWriter H.264 管线）、`findNearestFrame()` / `findNearestBoardFrame()` 最近邻匹配、`pixelBuffer()` RGBA→BGRA 字节交换转换、`outputDimensions()` 尺寸计算辅助方法

### 关键设计决策
- 输出原视频**每一帧**（原生帧率），而非仅分析采样帧（5fps）。中间帧通过最近邻匹配查找分析数据叠加覆盖图
- NSBitmapImageRep 的 deviceRGB RGBA → CVPixelBuffer 的 BGRA 需要 R↔B 字节交换
- IOSurface-backed pixel buffer 以启用 GPU 加速编码
- 输出文件若已存在则先删除，避免 AVAssetWriter "Cannot Save" 错误
- `renderOverlay()` 无修改，PNG 和 MP4 两条路径共享同一渲染逻辑

### 新增文件
- `docs/superpowers/specs/2026-05-17-output-video-overlay-design.md` — 功能设计说明
- `docs/superpowers/plans/2026-05-17-output-video-overlay-plan.md` — 实现计划

### 提交记录
- `43defcd` feat: add --output-video flag to CLIOptions and argument parser
- `5445d8d` feat: add renderVideoOverlay with AVAssetWriter H.264 pipeline
- `dbdfa6a` feat: wire --output-video to renderVideoOverlay in main flow
- `6e0cc9a` merge: --output-video feature branch
- `b7ca850` fix: renderVideoOverlay now processes every original frame at native FPS

### 验证
- `swift build -c release` 通过
- `swift test` 88 tests, 0 failures
- E2E：12s 测试视频产出 360 帧、30fps、1.6MB MP4，覆盖图内容与 --debug-overlay PNG 一致

---

## 2026-05-13 (第二轮 — 流水线性能优化)

### 代码变更
- **VideoAnalyzer.swift**: 批次并行帧分析（batchSize=8），替换顺序 while 循环为 TaskGroup 并发；新增 `downscaleImageForFlow` 按 flowFrameMaxSize（默认 640x480）降采样帧缓存；`calculateMotionStability` 复用 generateSummary 预计算的 reliableFrames
- **main.swift**: 四个独立检测器（KeyMoment/HighlightMoment/BoardDirection/TurnPhase）改为 `async let` 并发执行

### 验证
- `swift build -c release` 通过
- `swift test` 88 tests, 0 failures

### 记录：中低优优化点（本次未实施）

#### 中优先级
1. **SkiAnaylze 代码重复** — 8 文件与 FallLineCore 重复且落后，`scripts/setup_ios_deps.sh` 已写好删除逻辑
2. **光流信号薄弱** — 只用髋+踝 2 关键点采样全图光流，circularVariance 硬编码边界未文档化
3. **置信度阈值分散** — 五处各自定义阈值（0.30/0.35/0.15/0.65），无单一事实来源
4. **ReportGenerator 种子溢出** — `abs(Int.min)` 可能崩溃（line 100-104）
5. **优势/问题阈值不对称** — 导致系统性负面偏见
6. **重心旧分/新分并存** — 用户易困惑

#### 低优先级
1. **CI/CD 缺失** — 无 GitHub Actions、无 lint、无覆盖率
2. **输出资产膨胀** — `edge_debug_review/`（399 MB）、`misjudgment_review_20260506/`（242 MB）
3. **4 个过期批量跑分目录** 可清理
4. **TemporalSmoother 孤文档** — 设计文档已写但从未实现
5. **DebugOverlayRenderer.swift:115** 唯一 `!` 强制解包
6. **提交信息风格不一致** — `update scrore` 有拼写错误

---

## 2026-05-13 (第一轮 — 文档流程)

- 新增本文件，用于约束后续每轮结束时只记录增量，不重讲整个项目。
- 本轮是文档流程变更，无 Swift 代码修改。
- 统一使用 `delta_update.md` 作为增量记录文件名，并更新相关文档引用。
