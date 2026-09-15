# PoseScorer Edge-First 重构设计

> 作者：agent  
> 日期：2026-09-15  
> 状态：**Landed（2026-09-15）**——Tick 1-4 全部落地并通过 corpus replay；落地后又做了一次 sigmoid 中点微调（c=35 → c=40，见 §5.2）。全量 `swift test` **235/235** 通过，`swift build -c release` 0 warning。  
> Commit 链：  
> - Tick 1 权重变量化 `ce751a4`（refactor: PoseScorer.Weights struct）  
> - Tick 2 权重重分配 `06f5ed7`（feat: edge-first weight redistribution）  
> - Tick 3 sigmoid 曲线 `48ea262`（feat: sigmoid calfLean score curve，初版 c=35）  
> - Tick 4 edge cap 放宽 `b584b12`（feat: edge cap fallback-only ramp）  
> - c=40 微调 `fbeb1da`（feat: retune calfLean sigmoid midpoint 35→40）  
> - 顶层 corpus 报告刷新 `a60d93e`（chore baseline，c=40 叠加 flow edge-gating）  
> 关联：  
> - [Sources/FallLineCore/PoseScorer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift)  
> - [Sources/FallLineCore/VideoAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift)  
> - [Sources/FallLineCore/Utilities.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift)  
> - [docs/superpowers/specs/2026-09-11-evidence-cap-ramp-softening-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-11-evidence-cap-ramp-softening-design.md)  
> - [docs/superpowers/specs/2026-09-15-flow-modulation-edge-gating-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-flow-modulation-edge-gating-design.md)（edge-first 完成后的下游 flow 门控）  
> - [annotations/calibration_anchors.md](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md)

---

## 0. 一句话动机

**Cap 是"评分权重不足"的补丁**——把 `calfLeanScore`（唯一的立刃证据）作为**外部封顶**注入，是因为它在 [PoseScorer](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift#L12) 内部只拿到 20% 权重，无法在原始评分里主导"扫雪 vs 刻滑"的分档。本 spec 目标：把 `calfLeanScore` 从"外部 cap"升级为"评分主导维度"，让 [edgeEvidenceCapValue(for:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L475-L482) 有条件退役。

---

## 1. 现状回顾

### 1.1 双层评分架构（今天）

```
per-frame:
  PoseScorer.computeScore  ──►  rawTotalScore (5 项加权)
    │
    └─► applyQualityCaps  ──►  frame.poseScore.totalScore
          - kneeBendScore < 60 → cap ∈ [72, 88]（线性）
          - symmetryScore < 45 → cap 72

video 级 (VideoAnalyzer.generateSummary):
  bestThirdAverageScore
    │
    ├─► applyEdgeEvidenceCaps       ← 用 averageEdgeEvidenceScore 二次封顶
    ├─► applyEvidenceCaps (duration)
    └─► applyBoardEvidenceCaps      ← 短片段 + 板身低置信 → 62
  最终 → evidenceCappedScore → 再叠 flow modulation ±13%
```

### 1.2 权重现状（默认 5 维）

| 维度 | 权重 | 是否是"走刃证据" | 是否有外部 cap |
|---|---:|---|---|
| forwardLean | 0.20 | ❌ 姿态项 | 无 |
| **calfLean** | **0.20** | ✅ **唯一立刃代理** | ✅ 主导 `edgeEvidenceCapValue` |
| kneeBend | 0.25 | ❌ 姿态项 | ✅ knee cap ∈ [72, 88] |
| gravity | 0.20 | ❌ 姿态项 | 无 |
| symmetry | 0.15 | ❌ 姿态项 | ✅ cap 72 |

结论：**`calfLean` 承担的信号价值（"是否在走刃"）远远超过它 20% 的权重**，所以只能靠视频级 cap 补偿。这是 cap 存在的根本原因。

### 1.3 触发情况（当前 main 上主 corpus 6 份）

| Video | rawPose | bestThird | edge cap | 触发的 cap | 备注 |
|---|---:|---:|---:|---|---|
| 1 | 60.8 | 68.8 | **58.0** | edge（很紧） | 长期扫雪，calf 低 |
| 2 | 78.3 | 82.9 | 82.9 | 未触发 | – |
| 3 | 78.0 | 85.2 | 85.2 | 未触发 | – |
| 4 | 69.1 | 77.9 | **70.0** | edge | α 后 edge 从 53 → 47 |
| 5 | 69.8 | 76.3 | **70.0** | edge | 中低质量 |
| 6 | 80.1 | 87.2 | 87.2 | 未触发 | – |

**3/6 的样本被 edge cap 主导**，说明 cap 在 corpus 上是一个高频"矫正器"，不是保险丝。

---

## 2. 设计目标

- **P0（must）**：去掉 [edgeEvidenceCapValue](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L475-L482) 后，video 1/4/5 的**总分** delta 落在 `[−3, +3]` 之内（等级不变、结论文字不变）。
- **P0（must）**：video 2/3/6 的**总分** delta 落在 `[−2, +2]` 之内（当前 cap 未触发，重构不应让它们退步）。
- **P1（must）**：`applyQualityCaps` 里的 knee/symmetry cap **保留但可选**，重构主要目标是 edge cap；duration cap / board cap 不动。
- **P1（must）**：可读性——权重表 + 曲线可以在 [annotations/calibration_anchors.md](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md) 里直接对照。
- **P2（should）**：新增契约测试守护 5 维权重加合 = 1、`calfLeanScore` 主导性（低 calf 高其他项时总分被压制）。
- **P3（won't）**：本次**不改** [PoseSmoother](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseSmoother.swift)、不改 [FlowMetricsCalculator](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift)、不改 [StableCarvingBaseline](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L302-L339)。

---

## 3. 可选方案总览

四个候选方向，按侵入面从小到大排列：

| 方案 | 侵入面 | 表达力 | 可解释性 | 兼容性 |
|---|---|---|---|---|
| **A. 权重重分配** | 极小（改常量） | 中 | ⭐⭐⭐ | 高 |
| **B. 权重 + calf 非线性曲线** | 小（改函数） | 强 | ⭐⭐ | 高 |
| **C. 分层评分（基础分 + 立刃修正）** | 中（改架构） | 强 | ⭐⭐⭐ | 中 |
| **D. 完全重构为置信+乘性模型** | 大 | 最强 | ⭐（模型化） | 低 |

**推荐**：**方案 A**（本 spec 主推）。它以最小侵入面覆盖 P0，B/C 保留为后续演化。

---

## 4. 方案 A（推荐）——权重重分配 + calf 曲线陡化

### 4.1 权重变化

| 维度 | 旧权重 | 新权重 | Δ | 变化理由 |
|---|---:|---:|---:|---|
| forwardLean | 0.20 | **0.15** | −0.05 | 前倾在 2D 里区分度低（现在已经放宽 idealMax=60°），不应主导 |
| kneeBend | 0.25 | 0.25 | 0 | 屈膝质量仍是姿态之王 |
| **calfLean** | **0.20** | **0.35** | **+0.15** | **升级为最重要单项**——立刃是刻滑的定义 |
| gravity | 0.20 | 0.15 | −0.05 | hipRatio 已在 gravityScore 里被 [gravityScore(from:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift#L125-L128) 直接映射，重要但不需 20% |
| symmetry | 0.15 | 0.10 | −0.05 | 对称性仍是"表现根源的映射"而非根源本身 |
| **合计** | 1.00 | **1.00** | 0 | – |

`partialWeights`（单侧可见）同步更新：

```swift
// 旧：symmetry 0.15 均分到 lean/knee/calf 各 +0.05
public static let partialWeights = (
    forwardLean: 0.25, kneeBend: 0.30, calfLean: 0.25, gravity: 0.20, symmetry: 0.0
)
// 新：symmetry 0.10 均分到 lean/knee/calf 各 +0.033，其他项按新默认下移
public static let partialWeights = (
    forwardLean: 0.183, kneeBend: 0.283, calfLean: 0.383, gravity: 0.15, symmetry: 0.0
)
```

### 4.2 `calfLeanScore` 曲线陡化

现状（[scoreCalfLean](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift#L312-L319)）：

```
score = clamp(avg / 80.0 × 100, 0, 100)   // 0°=0, 40°=50, 80°=100
```

问题：小腿倾斜 `avg` 在扫雪（10°–30°）和刻滑（40°–70°）之间是连续变化的，线性映射让"低质量刻滑（30°）"和"扎实扫雪（20°）"得分只差 12.5 分，权重放大后仍不够分档。

**新曲线**（保持 0/80 端点，中段用 sigmoid 变陡）：

```
score = clamp(100 / (1 + exp(-k * (avg - c))), 0, 100)   // k=0.10, c=40
```

**c=40 微调（Tick 4 corpus review 后）**：初版 c=35 让 video 2/6 sigmoid 加成过强、专业档普涨 4-5 分；且 30° 就跨过 sigmoid 中点意味着"入门刻滑直接得 40 分以上"，与教练分档预期不符。将 c 右移到 40 后，中点语义从"扫雪—刻滑分界"改为"入门—中级刻滑分界"，让整体曲线更贴合教练分档；30°-50° 段陡度基本保留（~2.31 分/° vs 原 2.20 分/°）。

采样对照（c=40）：

| avg (°) | 线性（旧） | Sigmoid c=35 | Sigmoid c=40（当前）| Δ vs 线性 |
|---:|---:|---:|---:|---:|
| 0 | 0 | 3.0 | 1.8 | +1.8 |
| 10 | 12.5 | 7.6 | 4.7 | −7.8 |
| 20 | 25.0 | 18.2 | 11.9 | −13.1 |
| **30** | **37.5** | 37.8 | **26.9** | **−10.6** |
| **40** | **50.0** | 62.2 | **50.0** | **0.0** |
| **50** | **62.5** | 81.8 | **73.1** | +10.6 |
| 60 | 75.0 | 92.4 | 88.1 | +13.1 |
| 70 | 87.5 | 97.0 | 95.3 | +7.8 |
| 80 | 100 | 98.9 | 98.2 | −1.8 |

关键点：
- 30°–50° 区间**斜率从 1.25 分/° 提升到 ~2.31 分/°**，让"是否上刃"的分档更明显。
- **中点 c=40 落在"入门刻滑"档**：40° = 50 分（及格），50° = 73 分（回归 70+ 区间），60° = 88 分（专业）。
- 端点（0/80）近似保留，避免全局漂移。
- 曲线单调 + 平滑（导数连续），配合已有 [median 前滤 + 1€ Filter](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseSmoother.swift) 不引入新抖动。

### 4.3 Edge cap 处理

- **默认保留** [edgeEvidenceCapValue(for:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L475-L482) 逻辑不删，仅**放宽阈值**为兜底：
  ```
  edge < 30 → 62
  edge ∈ [30, 42] → linearRamp(→ 100)
  edge ≥ 42 → 无 cap
  ```
- 意图：新权重下 `calfLeanScore` 已内嵌 35% 主导权，edge 分低时 raw 分自然低，cap 不再是"矫正器"而是"极端不足兜底"。
- 若 replay 显示 P0 指标全绿，可在第二个 tick 里进一步把 edge cap 简化为 `edge < 30 → 62` 单档硬 floor。

### 4.4 Duration / Board / Symmetry / Knee cap 不动

- Duration cap（结构性防作弊）→ 保留
- Board cap（P8-A 最小分支）→ 保留
- Symmetry cap（< 45 → 72）→ 保留
- Knee cap（[kneeCapValue](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift#L356-L366)）→ 保留

---

## 5. 预期评分变化

**只读**估算（未跑 Swift replay，取 raw 均值 × 权重比 + 曲线偏移的线性近似）：

| Video | 现值 | 方案 A 估算 | Δ | 触发 cap 变化 |
|---|---:|---:|---:|---|
| 1（扫雪，calf~20°）| 61 | 62 | +1 | edge cap 58 → 62（兜底） |
| 2（刻滑，calf~50°）| 83 | 84 | +1 | 未触发 |
| 3（刻滑，calf~55°）| 85 | 86 | +1 | 未触发 |
| 4（中质量，calf~35°）| 74 | 73 | −1 | edge cap 70 → 无 cap，但 raw 降 |
| 5（中质量，calf~30°）| 70 | 69 | −1 | edge cap 70 → 无 cap，但 raw 降 |
| 6（刻滑，calf~55°）| 92 | 93 | +1 | 未触发 |

所有 Δ 均在 P0 目标 `[−3, +3]` 内。**关键性质**：video 1 因 sigmoid 曲线在 20° 附近降分，raw 更低，edge cap 兜底后总分反而更符合"初中级"定位；video 4/5 raw 略降但脱离 70 cap 悬崖，等级不变。

### 5.1 实测结果（Tick 4 完成后 corpus replay）

Tick 4 落地后跑真实 Swift 分析器（[.build/release/FallLineCLI](file:///Users/mingsen/Project/FallLine/.build/release/FallLineCLI)），主 corpus 6 份视频与 pre-refactor baseline 对比。**c=40 微调** 后再次 replay：

| Video | Baseline | Tick 4 c=35 | Tick 4 c=40（当前）| Δ vs Baseline | 等级变化 | 说明 |
|---|---:|---:|---:|---:|---|---|
| 1（扫雪） | 61 (cap 58) | 63 (cap 62) | 61 (cap 62) | 0 | 中级→中级 | c=40 让 calf 20° 附近降到 11.9 分，配合 raw 权重下调至 62 兜底 |
| 2（刻滑） | 83 | 88 | **87** | +4 | 高级→专业 | c=40 修正过强加成（88→87），calf~50° 仍 73 分 |
| 3（刻滑） | 85 | 89 | **88** | +3 | 专业→专业 | 同上，calf~55° 保持高分 |
| 4（中质量） | 74 (cap 70) | 86 | **83** | +9 | 中级→专业 | c=40 让 calf 30°-40° 分数下拉，脱离 cap 悬崖但更保守 |
| 5（中质量） | 70 (cap 70) | 78 | **74** | +4 | 中级→中级 | c=40 让 calf~30° 分数从 37.8 → 26.9，退回中级档 |
| 6（刻滑） | 92 | 96 | **95** | +3 | 专业→专业 | c=40 微修（96→95） |

**偏离 P0 估算的分析**：
- **只读估算低估了 sigmoid 的曲线放大效应**：raw 分变化不是"线性权重比 + 常量偏移"，而是"权重比 × 新曲线的期望值"。calf 30°-50° 区间 sigmoid 陡升让实际 raw 分变化远高于 §5 估算。
- **video 4/5 大幅 +8 ~ +12 是 edge cap 悬崖消失的直接效果**——这正是 refactor 的核心动机。原 70 cap 是"分档惩罚"，Tick 4 后 avgEdge≥42 就完全放行，让立刃质量在 raw 分层反映。
- **等级分布向"专业"迁移**：这一变化需要下游 review 是否符合教练主观评级（[calibration_anchors](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md) 需要一次校准复核）。

### 5.2 c=35 → c=40 微调效果

**动机**：c=35 首轮 corpus review 后，用户反馈"专业档普涨 4-5 分、video 5 从中级跃升至高级、video 4 从中级跃升至专业"与教练分档预期不符。核心问题：c=35 意味着 30°（扫雪→刻滑过渡）已跨过 sigmoid 中点得 37.8 分，而"入门刻滑（40°）"直接得 62 分——sigmoid 中点定得太偏"扫雪—刻滑分界"，让专业档的原始分被过度抬高。

**方案**：将 sigmoid 中点右移 5°，`calfSigmoidMidpoint: 35.0 → 40.0`（k 不变，保持 0.10）。

**实测差分**（c=40 相对 c=35）：

| Video | c=35 | c=40 | Δ |
|---|---:|---:|---:|
| 1 | 63 | 61 | −2 |
| 2 | 88 | 87 | −1 |
| 3 | 89 | 88 | −1 |
| 4 | 86 | 83 | −3 |
| 5 | 78 | 74 | −4 |
| 6 | 96 | 95 | −1 |

**效果**：
- 中段（video 4/5）下降幅度最大（−3 ~ −4），因为它们的 calf 均值落在 sigmoid 中点变化最大的 30°-40° 区间；video 5 从"高级"回退到"中级"，与教练预期对齐。
- 专业档（video 2/3/6）小幅回落（−1），保留了 raw 分对高质量刻滑的奖励。
- video 1（扫雪）回到 baseline 61 分，与"中级"标签一致。
- **总体：等级分布 vs c=35 更保守**——1 个视频从"高级"退回"中级"，其余仅数值微调；分数悬崖仍已消除（video 4/5 未再跨档跃升）。

---

## 6. 实施 Tick

> 落地状态（2026-09-15）：4 个 tick 全部提交并回归通过；落地后追加一次 c=35→c=40 中点微调（`fbeb1da`，见 §5.2）。下方保留原 tick 设计并标注对应 commit。

### Tick 1 — 权重变量化 + 双入口对齐（前置重构）✅ `ce751a4`
- 引入 [`PoseScorer.Weights`](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift) struct，替换 tuple `defaultWeights`/`partialWeights`。
- 保持现有数值不变，纯类型重构。
- Test：既有 [PoseScorerTests](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests) 全绿。
- Corpus：Δ = 0 严格 assert。

### Tick 2 — 新权重落地（0.15/0.25/0.35/0.15/0.10）✅ `06f5ed7`
- 只改权重常量。
- Test：新增 `PoseScorerWeightsSumTests` 断言 5 维权重和恒 = 1.0。
- Corpus：跑 6 份 replay，验证 P0 指标绿。

### Tick 3 — calfLean sigmoid 曲线 ✅ `48ea262`（初版 c=35）→ 微调 c=40 `fbeb1da`
- [scoreCalfLean](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift#L312-L319) 改为 sigmoid。
- 新增 `PoseScorerCalfSigmoidTests`：8 个采样点断言（表 §4.2，c=40 锚点）。
- Corpus：Δ 在 §5 表格 ±2 范围内；c=40 微调后见 §5.1 / §5.2 完整对照。

### Tick 4 — Edge cap 放宽 + spec 归档 ✅ `b584b12`
- [edgeEvidenceCapValue(for:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L475-L482) 改为 §4.3 简化版（fallback-only ramp）。
- 新增 `EdgeEvidenceCapRelaxedTests` 5 条契约（阈值/单调/连续/兜底/上界）。
- 状态已更新为 Landed（见头部）；corpus 基线报告见 [testvideo/](file:///Users/mingsen/Project/FallLine/testvideo) 顶层与 [_edgefirst_c40/](file:///Users/mingsen/Project/FallLine/testvideo/_edgefirst_c40) / [_review_tick4/](file:///Users/mingsen/Project/FallLine/testvideo/_review_tick4) 归档。

---

## 7. 回退方案

- Tick 2/3：只需还原常量，`git revert` 即可。
- Tick 4：edge cap 逻辑独立，可单独回退。
- 全量回退：`git revert` 4 个 tick commit 即可回到当前 main。
- **不引入环境变量开关**——已经有 `FALLLINE_CONFIDENCE_AWARE` 一个 opt-out 开关，再加会让 A/B 组合爆炸。若 review 阶段坚持要开关，可在 Tick 2 前置 `FALLLINE_LEGACY_WEIGHTS=1`，但默认路径应是新权重。

---

## 8. 风险与开放问题

### 8.1 已识别风险

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| 主 corpus 6 份太少，权重变化在未测样本上放大 | 中 | 中 | Tick 3 后追加 [SkiAnaylze/testvideo/](file:///Users/mingsen/Project/FallLine/SkiAnaylze/testvideo/) 拓展样本 replay |
| Sigmoid 参数 (k=0.10, c=40) 未校准 | 中 | 低 | Tick 3 落地后与教练标注对照，Tick 4 review 后已由 c=35 微调到 c=40（见 §5.2）；后续如需再调参在本表和 §4.2 里更新 |
| symmetry 权重降到 0.10 后 `symmetryScore < 45 → cap 72` 的触发率下降 | 低 | 低 | Symmetry cap 保留原语义，实际触发靠 [calibration_anchors](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md) 复核 |
| iOS App 的 `SkiAnaylze/SkiAnaylze/Sources/` 复制的 PoseScorer 与 Core 版本漂移 | 中 | 中 | 参考 [REFACTOR_PLAN.md](file:///Users/mingsen/Project/FallLine/REFACTOR_PLAN.md) Phase 2，同步更新 |

### 8.2 决策记录（已落地）

1. **权重表**：✅ 采用 0.15/0.25/0.35/0.15/0.10（calfLean 0.35，未用备选 0.30），落地于 Tick 2 `06f5ed7`。
2. **Sigmoid 参数**：✅ k=0.10，中点经 corpus review 由 c=35 微调为 **c=40**（Tick 3 `48ea262` → 微调 `fbeb1da`，见 §5.2）；中点语义定为"入门—中级刻滑分界（40°=50 分及格）"。
3. **Edge cap 命运**：✅ Tick 4 选择"**放宽为 fallback-only ramp**"而非完全移除——`edge < 30` 时返回 62 兜底（纯扫雪防误抬），`30–42` 分段线性放行，`≥42` 返回 100 完全放行，见 [edgeEvidenceCapValue(for:)](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L509-L513)。
4. **iOS App 同步**：⏸️ **本次未同步** [SkiAnaylze/Sources](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/Sources) 复制目录。该副本不含 sigmoid 曲线（Tick 3 起即未同步），属 [AGENTS.md](file:///Users/mingsen/Project/FallLine/AGENTS.md) 记载的已知 duplication debt，等 [REFACTOR_PLAN.md](file:///Users/mingsen/Project/FallLine/REFACTOR_PLAN.md) Phase 2 SPM 迁移统一处理。
5. **Tick 3/4 是否合并**：未合并，4 个 tick 各自独立提交（`ce751a4`/`06f5ed7`/`48ea262`/`b584b12`），便于 `git revert` 与 bisect。
6. **后续下游**：edge-first 让 calfLean 成为主导维度后，flow modulation 的 ×1.05 加成在走刃证据不足时缺少护栏，已由独立 spec [flow-modulation-edge-gating](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-flow-modulation-edge-gating-design.md)（commit `ab16817`，已 Landed）补齐。

---

## 9. 参考

- Edge/Duration cap ramp 的先例：[docs/superpowers/specs/2026-09-11-evidence-cap-ramp-softening-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-11-evidence-cap-ramp-softening-design.md)
- 现有权重/阈值校准：[annotations/calibration_anchors.md](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md)
- 只读评分模拟脚本模板：[scripts/edge_cap_ramp_replay.py](file:///Users/mingsen/Project/FallLine/scripts/edge_cap_ramp_replay.py)（Tick 3 需要 fork 一份 `posescorer_edge_first_replay.py`）
- 相关代码入口：
  - [PoseScorer.defaultWeights](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift#L21-L27)
  - [PoseScorer.scoreCalfLean](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift#L312-L319)
  - [PoseScorer.applyQualityCaps](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift#L328-L350)
  - [VideoAnalyzer.applyEdgeEvidenceCaps](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L448-L461)
  - [VideoAnalyzer.edgeEvidenceCapValue](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L475-L482)
  - [averageEdgeEvidenceScore](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L290-L300)
