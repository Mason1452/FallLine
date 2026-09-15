# P2 — Evidence Cap 悬崖软化设计（Piecewise Linear Ramp）

> 状态：**设计草案，等待审阅**。当前落地（confidence-aware smoothing α 方案）**暂不提交**。
> 目标：在不改变现有 cap 语义的前提下，把 [applyEvidenceCaps](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L441-L453) / [applyEdgeEvidenceCaps](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L455-L477) / [applyBoardEvidenceCaps](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L479-L487) 三个阶梯函数改成分段线性 (piecewise linear) 映射，消除微小输入抖动跨档突变的“阈值悬崖”。

---

## 1. 背景

### 1.1 触发问题
- `confidence-aware smoothing (α)` A/B 显示 video 4 掉档：`averageEdgeEvidenceScore` 从 **53.07 → 47.05**（跨过 50 阈值），触发 [applyEdgeEvidenceCaps](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L455-L477) 的 `< 50 → cap 70` 分支，`evidenceCappedScore` 从 **82.42 → 70.00**、`averageScore` 从 **86.54 → 73.50**，档位 “专业 → 中级”。
- 事后审计确认：这次评分下沉是“合理修正”（低置信度突刺被平滑器抹平），但**跨档突变的幅度**（-13 分）远大于**输入变化量**（-6 分 edgeEvidence），根源是 evidence cap 阶梯函数本身。
- 结论：不管 α 方案是否上线，evidence cap 悬崖都是**独立于任何输入源的高风险点**：任何一个后续微调（3D 融合、光流平滑度、confidence 门限）只要在阈值附近扰动 1–2 分，都可能把评分从 100 拉到 70。

### 1.2 目标
- **消除“阈值悬崖”**：让 cap 输出对 edge/duration 输入连续单调、导数有界。
- **不改变 cap 语义**：所有阈值命中样本（阈值右侧平台点）得分保持不变，仅在阈值内侧一段线性过渡区上给出**温和封顶**。
- **不引入新的偏置**：即在“无输入抖动”场景下，主 corpus 分数漂移 ≤ ±1 分（除非该样本本来就在悬崖内侧）。

---

## 2. 悬崖清单（P1 完成）

来源：[VideoAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift)、[Utilities.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift)。

### A. `applyEvidenceCaps`（时长证据）
输入：`reliableDuration`（秒，可靠帧的 `sampledDuration`）

| # | 阈值 (`< s`) | Cap (分) | 悬崖高度（跨档 Δ） |
|---|---|---|---|
| 1 | `sparseReliableScoreDuration = 5.0` | **55** | — |
| 2 | `limitedReliableScoreDuration = 8.0` | **65** | **+10** @ 5.0s |
| 3 | `fullReliableScoreDuration = 12.0` | **78** | **+13** @ 8.0s |
| 4 | `≥ 12.0` | **100** (无 cap) | **+22** @ 12.0s |

### B. `applyEdgeEvidenceCaps`（立刃证据）
输入：`averageEdgeEvidence`（分，`averageEdgeEvidenceScore(from:)` 输出，值域 0–100）

| # | 阈值 (`< s`) | Cap (分) | 悬崖高度 |
|---|---|---|---|
| 1 | `< 38` | **58** | — |
| 2 | `< 42` | **65** | **+7** @ 38 |
| 3 | `< 50` | **70** | **+5** @ 42 |
| 4 | `≥ 50` | **100** (无 cap) | **+30** @ 50 ← **最大悬崖** |
| — | `edge=nil` fallback | **65** | 保护通道 |

> **关键洞察**：`< 50 → cap 70` 与 `≥ 50 → 100` 之间存在 30 分悬崖。这是本轮 video 4 掉档的直接来源，也是本次软化的核心目标。

### C. `applyBoardEvidenceCaps`（板身/运动学证据）
输入：`boardKinematicHighScoreCap(from:)` 返回值。

P8-A 之后只保留一支：`summary.confidence < 0.7 && reliablePoseDuration < 10.0 → cap 62`。**这是一个 all-or-nothing 门（要么 cap 62，要么无 cap）**，不是阶梯。软化空间有限，本轮**不动**（详见 §5.3）。

---

## 3. 探针结果（P2 完成）

只读 replay：[edge_cap_ramp_replay.py](file:///Users/mingsen/Project/FallLine/scripts/edge_cap_ramp_replay.py) 已能精确复现主 corpus 6 份（OFF + ON 各 12 份）的 stair 版评分，模型误差 |Δ| 均值 = 0.000，max = 0.000（stair 预测 vs. JSON 实测）。

**当前中间量与阈值距离表**（OFF / ON 汇总）：

| stem | branch | edge | dur | 距最近 edge 阈值 | 距最近 dur 阈值 | 悬崖状态 |
|---|---|---|---|---|---|---|
| 1 | OFF | 15.94 | 23.40 | -22.06 (远离 38) | +11.40 | 平稳（strong cap 58） |
| 1 | ON  | 15.81 | 23.40 | -22.19 | +11.40 | 平稳 |
| 2 | OFF | 65.01 | 16.00 | +15.01 (远离 50) | +4.00 | 平稳 |
| 2 | ON  | 64.69 | 16.00 | +14.69 | +4.00 | 平稳 |
| 3 | OFF | 60.95 | 16.80 | +10.95 | +4.80 | 平稳 |
| 3 | ON  | 61.48 | 16.80 | +11.48 | +4.80 | 平稳 |
| **4** | OFF | **50.06** | 14.80 | **+0.06 ← 悬崖上沿** | +2.80 | **极度不稳定** |
| **4** | ON  | **45.90** | 14.80 | **-4.10 ← 掉入悬崖底部** | +2.80 | **已跨档** |
| **5** | OFF | 42.47 | 11.60 | **+0.47 ← 悬崖上沿** | **-0.40 ← 也在 12 悬崖内** | **双悬崖** |
| **5** | ON  | 42.01 | 11.60 | **+0.01 ← 悬崖上沿** | -0.40 | **双悬崖** |
| 6 | OFF | 63.70 | 31.40 | +13.70 | +19.40 | 平稳 |
| 6 | ON  | 62.31 | 31.40 | +12.31 | +19.40 | 平稳 |

**结论**：
- 6 份 corpus 里 **video 4 与 video 5 均处于 edge 50 阈值悬崖内侧 ±5 分**；
- video 5 的 duration = 11.60s，还同时贴着 `fullReliableScoreDuration = 12.0` 悬崖（-0.40s），任何一个平滑改动都可能让它多跌 22 分；
- video 1/2/3/6 距离所有阈值都 >10 分，处于绝对平稳区。

---

## 4. 软化方案（P3 完成）

### 4.1 通用公式

将“阶梯函数”替换为“阈值内侧向下延伸的分段线性映射”：

- 阈值 `x_th` 与其下一档 cap 值 `y_low` / 本档 cap 值 `y_high` 之间，取过渡带宽 `hw ∈ [1, 8]`；
- `x ∈ [x_th - hw, x_th]`：`cap(x) = linear(x, x_th - hw, x_th, y_low, y_high)`
- `x ≥ x_th`：`cap(x) = y_high`（平台，保持原语义）
- `x < x_th - hw`：`cap(x) = y_low`（平台，保持原语义）

设计原则：
1. **`hw` 与悬崖高度成正比**：悬崖 5–7 分 → `hw = 1–2`；悬崖 ≥ 20 分 → 用**整段跨越**（`hw = 阈值间距`）。
2. **不能只软化 1 分**：小悬崖上局部软化仍会保留“悬崖边”的斜率突变；大悬崖必须整段过渡，让斜率有界。
3. **阈值右侧不动**：`cap(x_th) = y_high`，保证平台样本得分完全一致，不引入偏置。

### 4.2 具体常量

#### B. Edge Evidence Cap（本轮重点）

```
if x < 37: return 58
if x < 38: return linear(x, 37, 38, 58, 65)    // hw = 1
if x < 40: return 65
if x < 42: return linear(x, 40, 42, 65, 70)    // hw = 2
if x < 50: return linear(x, 42, 70, 70, 100)   // hw = 8（整段跨越 30 分悬崖）
return 100
```

- 阈值 38（悬崖 7）→ hw = 1
- 阈值 42（悬崖 5）→ hw = 2
- 阈值 50（悬崖 30）→ hw = 8（**整段跨越**，从 42 开始线性抬升到 100）

**注意**：50 阈值的过渡带覆盖 `[42, 50]`，恰好接在 42 平台之上，全曲线单调不减、导数有界（最大斜率 = 30/8 = 3.75 分/edge 分）。

#### A. Duration Cap（同型软化，`hw = 0.5s`）

```
if x < 5.0:                    return 55
if x < 5.5:                    return linear(x, 5.0, 5.5, 55, 65)   // hw = 0.5s
if x < 8.0:                    return 65
if x < 8.5:                    return linear(x, 8.0, 8.5, 65, 78)   // hw = 0.5s
if x < 12.0:                   return 78
if x < 12.5:                   return linear(x, 12.0, 12.5, 78, 100)// hw = 0.5s
return 100
```

- 时长悬崖高度 10/13/22 分，但用户输入是“视频总时长”，短片段本身就属于结构性证据不足，**不宜整段跨越**（会让 4s → 8s 全部匀速涨分，鼓励拍空镜）；
- 折中：只在阈值上侧 0.5s 做小过渡，消除“5.00s ↔ 4.99s” 差 10 分的极端悬崖。
- **P4 replay 显示 corpus 里没有样本落入 duration ramp 区**（最近的是 video 5 的 11.60s，处在 12.0 阈值下方，也未落入 `[12.0, 12.5]`）；此改动是**结构性防御**，不为当前 corpus 服务。

#### C. Board Kinematic Cap
**本轮不动**（P8-A 已重构成单条 all-or-nothing 门；`confidence < 0.7` 是硬门槛，`hw` 化会稀释保护语义。留待 P8-B 单独讨论）。

### 4.3 实现粒度

- 修改文件（仅 1 个）：[VideoAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift)
  - `applyEdgeEvidenceCaps(score:reliableFrames:stableBaseline:)`：把 4 组 `if x < ...` 改为按 §4.2.B 的 6 段 piecewise linear。
  - `applyEvidenceCaps(score:reliableFrames:)`：把 3 组 `if x < ...` 改为 §4.2.A 的 6 段 piecewise linear。
- 抽两个 `fileprivate` 静态方法便于测试：
  ```swift
  fileprivate static func edgeEvidenceCapValue(_ x: Double) -> Double
  fileprivate static func durationCapValue(_ x: Double) -> Double
  ```
  在 `applyEdgeEvidenceCaps` / `applyEvidenceCaps` 里直接 `min(score, cap(x))`。
- **无常量新增**：所有过渡带宽以文字表述在设计文档里，代码中直接以字面量出现（避免 Utilities.swift 常量污染）。
- **无签名变化**：`applyEvidenceCaps` / `applyEdgeEvidenceCaps` 保持 `private` 与原 signature，不影响任何外部调用点。

---

## 5. 回归预估（P4 完成）

### 5.1 Corpus 6 份 replay 结果（stair vs. ramp）

| stem | branch | edge | dur | 实测 | stair 预 | ramp 预 | Δ(ramp − stair) | 档位变化 |
|---|---|---|---|---|---|---|---|---|
| 1 | OFF | 15.94 | 23.40 | 60.90 | 60.90 | 60.90 | 0.00 | — |
| 1 | ON  | 15.81 | 23.40 | 60.90 | 60.90 | 60.90 | 0.00 | — |
| 2 | OFF | 65.01 | 16.00 | 84.53 | 84.53 | 84.53 | 0.00 | — |
| 2 | ON  | 64.69 | 16.00 | 82.88 | 82.88 | 82.88 | 0.00 | — |
| 3 | OFF | 60.95 | 16.80 | 85.93 | 85.93 | 85.93 | 0.00 | — |
| 3 | ON  | 61.48 | 16.80 | 85.22 | 85.22 | 85.22 | 0.00 | — |
| 4 | OFF | 50.06 | 14.80 | 86.54 | 86.54 | 86.54 | 0.00 | — |
| **4** | **ON**  | 45.90 | 14.80 | 73.50 | 73.50 | **81.81** | **+8.31** | **中级 → 高级** ✱ |
| **5** | **OFF** | 42.47 | 11.60 | 70.00 | 70.00 | **71.77** | **+1.77** | 中级 → 中级 |
| 5 | ON  | 42.01 | 11.60 | 70.00 | 70.00 | 70.03 | +0.03 | — |
| 6 | OFF | 63.70 | 31.40 | 93.34 | 93.34 | 93.34 | 0.00 | — |
| 6 | ON  | 62.31 | 31.40 | 91.61 | 91.61 | 91.61 | 0.00 | — |

### 5.2 结论

- **9/12 样本 Δ = 0**：处于阈值平台的样本完全不受影响，无偏置引入。
- **video 4/ON 从 73.50 → 81.81（+8.31）**：本次 α 平滑造成的 -13 分掉档被软化到 -4.7 分，档位从“中级”回升到“高级”，接近平滑前的“专业”边缘，符合“合理修正但不跨档突变”的目标。
- **video 5/OFF 从 70.00 → 71.77（+1.77）**：edge=42.47 处于 [42, 50] 过渡带早段，只吃到 1.77 分红利，档位不变。
- **video 5/ON 从 70.00 → 70.03（+0.03）**：edge=42.01 刚过 42 平台上沿，几乎无变化。
- **未观察到向下漂移**：ramp 版对所有 12 份样本的评分都 ≥ stair 版，符合 §4.1 “阈值右侧不动 + 阈值内侧向下延伸” 的单调性。
- **未观察到跨档负向变化**：所有档位变化都是向上（video 4/ON 中级 → 高级），没有任何“专业 → 高级”式的降档。

### 5.3 α 平滑 + ramp 组合评估

如果同一批次里 α + ramp 都上线：
- video 4：ON 从 73.50 恢复到 81.81 分（-4.73 vs. 原基线 86.54）——**掉档修复**，仍保留“平滑器抹掉噪声突刺”的合理修正。
- video 1/2/3/6：α + ramp 都不再触发 cap 分支，效果等同只上 α。
- video 5：α 已经把两版都压到 70 平台，ramp 只让 OFF/ON 分开约 1.7 分，方向正确。

**推荐先落 ramp、后决定 α**：ramp 是评分**结构性防御**，对当前 corpus 无 corpus 副作用；α 是**信号平滑**，效果与副作用都更强。两者独立生效，但先上 ramp 可以让 α 的 A/B 更干净（去掉“跨档突变”这一层噪声）。

---

## 6. 单测方案

新增测试文件：`Tests/FallLineCoreTests/EvidenceCapRampTests.swift`

由于 `applyEdgeEvidenceCaps` / `applyEvidenceCaps` 是 `private`，测试路径有两种：

**方案 1（推荐）**：把 §4.3 里抽出的两个静态方法改为 `internal`（默认 access）+ `@testable import`，直接单测。

**方案 2**：通过组合 `[DetectionResult]` 输入间接测试。工作量大且脆弱。

采用**方案 1**，单测覆盖：

### 6.1 单调性契约
- 100 个均匀采样点 `x ∈ [0, 100]`：`cap(x_i) ≤ cap(x_{i+1})`（非严格单调不减）。
- 100 个均匀采样点 `x ∈ [0, 20]`（duration）：同上。

### 6.2 平台点等价（保证 §4.1 原则 3）
- `edgeEvidenceCapValue(38) == 65` / `edgeEvidenceCapValue(42) == 70` / `edgeEvidenceCapValue(50) == 100`
- `edgeEvidenceCapValue(37 - ε) == 58` / `edgeEvidenceCapValue(40 - ε) == 65` / `edgeEvidenceCapValue(42 - ε) == 70`
- `durationCapValue(5.0) == 65` / `durationCapValue(8.0) == 78` / `durationCapValue(12.0) == 100`

### 6.3 过渡带中点
- `edgeEvidenceCapValue(46) ≈ 85`（[42, 50] 中点，(70+100)/2 = 85）
- `edgeEvidenceCapValue(37.5) ≈ 61.5`（[37, 38] 中点，(58+65)/2 = 61.5）
- `durationCapValue(5.25) ≈ 60`（[5.0, 5.5] 中点，(55+65)/2 = 60）

### 6.4 边界钳位
- `edgeEvidenceCapValue(-1) == 58`（小于最左平台）
- `edgeEvidenceCapValue(200) == 100`（大于最右平台）
- `durationCapValue(0) == 55` / `durationCapValue(100) == 100`

### 6.5 corpus replay 兜底测试
- 硬编码 6 份 corpus 的 `(edge, dur)` 数值与 §5.1 的 ramp 预测分，运行 `min(uncapped, ramp)` 组合验证 ±0.05 精度。
- 保证任何将来对 `edgeEvidenceCapValue` 常量的修改都会被回归测试立即捕获。

---

## 7. 提交计划（等待用户批准）

1. **仅代码修改**（不动任何常量与 API）：`VideoAnalyzer.swift` +30 行左右，抽 2 个 fileprivate 静态方法。
2. **单测**：`EvidenceCapRampTests.swift`（约 25 条 case）。
3. **文档更新**：本文件 + `AGENTS.md` 增加一行 “Evidence cap ramp” 决策注释；`WORK_LOG.md` 加本轮 delta。
4. **验证命令**：
   - `swift test --filter EvidenceCapRampTests` → 25/25 pass
   - `swift test 2>&1 | tail -5` → 173+25 = 198 tests pass, 0 fail
   - `python3 scripts/edge_cap_ramp_replay.py` → 12 行 corpus 表输出与 §5.1 完全一致
5. **不重跑 Swift 主 corpus 分析**：因为 ramp 只影响 `min(score, cap)` 逻辑，且 stair 模型误差已经 0.000，replay 结果就是真实预期。

**当前 P2 状态**：设计完成，Python replay 验证通过。等待用户审阅后再动 Swift 代码。
