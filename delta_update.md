# Delta Update

最后更新：2026-05-13

本文档只记录每轮工作的增量变化，不记录项目全量背景。需要项目当前状态、目标和长期上下文时，先看 `WORK_LOG.md`；需要文件职责时，看 `file_manifest.md`。

## 记录规则

- 只写本轮新增、修改、删除、验证结果和遗留问题。
- 不重复整段项目背景、架构说明、历史决策或完整文件清单。
- 如果某个信息已经在 `WORK_LOG.md`、`AGENTS.md`、`CLAUDE.md` 或 `file_manifest.md` 中存在，只链接或点名引用。
- 每轮结束时新增一条简短记录；优先记录事实，不写推测。
- 同一轮没有代码变更时，明确写“仅文档变更”或“未运行测试”的原因。

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
