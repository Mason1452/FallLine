# Calibration Anchors 复核（2026-09-15，最终版）

主 corpus [testvideo/](../../testvideo) 的 v2/v3/v6 在 edge-first + c=40 + flow gating + 方向 α 后跃到"专业档"（🏆 综合评分 87/88/90）。本次用当前 release CLI 重跑 [calibration_anchors.md](../../annotations/calibration_anchors.md) 的 12 个锚点视频，验证当前评分与 2026-05-04/05 教练主观锚点是否仍然对齐，并与主 corpus 联合做交叉核对。

## 一、原始数据（18 份视频，5 个关键维度）

| Alias | 教练标签 (2026-05) | 锚点分 | **当前分** | edge | calf | knee | flow | 当前档 |
|---|---|---:|---:|---:|---:|---:|---:|---|
| v1        | 主 corpus 无锚点        | — | **61** | 37 | 8  | 60 | ×1.05 | 中级 |
| v2        | 主 corpus 无锚点        | — | **87** | 72 | 72 | 94 | ×1.00 | 高质量 |
| v3        | 主 corpus 无锚点        | — | **88** | 69 | 66 | 97 | ×1.00 | 专业 |
| v4        | 主 corpus 无锚点        | — | **79** | 55 | 45 | 66 | ×1.00★ | 中级偏上 |
| v5        | 主 corpus 无锚点        | — | **74** | 52 | 37 | 80 | ×1.00 | 中级偏上 |
| v6        | 主 corpus 无锚点        | — | **90** | 72 | 70 | 90 | ×1.00★ | 专业 |
| GOOD_A    | good accepted-current  | 94.1 | **86** | 61 | 48 | 98 | ×1.05 | 高质量 |
| MID_ACC1  | middle accepted        | —    | **55** | 35 | 7  | 48 | ×1.05 | 中级偏下 |
| MID_ACC2  | middle accepted        | —    | **65** | 40 | 18 | 61 | ×1.05 | 中级 |
| MID_ACC3  | middle accepted        | —    | **78** | 54 | 37 | 96 | ×1.00 | 中级偏上 |
| MID_ACC4  | middle accepted        | —    | **61** | 39 | 12 | 58 | ×1.00 | 中级 |
| MID_ACC5  | middle accepted        | —    | **81** | 63 | 58 | 72 | ×1.00★ | 高质量 |
| MID_ACC6  | middle accepted        | —    | **83** | 59 | 46 | 86 | ×1.05 | 高质量 |
| MID_ACC7  | middle accepted        | —    | **93** | 65 | 59 | 92 | ×1.05 | 专业 |
| MID_ACC8  | middle accepted-current| 85.3 | **90** | 71 | 65 | 97 | ×1.00 | 专业 |
| MID_FP1   | middle over-scored FP  | —    | **77** | 58 | 47 | 74 | ×1.00 | 中级偏上 |
| MID_FP2   | middle over-scored FP  | —    | **82** | 61 | 52 | 84 | ×1.05 | 高质量 |
| BAD_ACC   | bad accepted-current   | 65.0 | **83** | 57 | 45 | 88 | ×1.00 | 高质量 |

★ = `flowModulationGated=true`（走刃证据不足未加成）。分档定义：<60 初级 / [60,70) 中级 / [70,80) 中级偏上 / [80,88) 高质量 / [88+] 专业。

## 1.5 · 逐视频微观复核（文案 vs 分数一致性）

本节做**报告内部一致性**核对：算法给出的"主要问题"文案是否与综合分自洽。如果报告说"板尾扫雪 / 搓雪弯 / 立刃提前释放"，但综合分给到 80+，说明评分被 calf 拉飞、文案没跟上。

| Alias | 综合分 | 算法自动给出的主要问题（原文摘录） | 文案与分数自洽？ |
|---|---:|---|:---:|
| GOOD_A   | 86 | 立刃有基础，但刃角保持时间不足，弯中容易提前释放 | ✅ 文案"有基础"匹配高质量档 |
| MID_ACC1 | 55 | 板尾扫雪明显，更像搓雪弯而不是刻滑；膝盖过直 | ✅ 文案"搓雪弯"匹配中级偏下 |
| MID_ACC2 | 65 | 靠横向刮雪，刃没持续咬雪；膝盖过于直立 | ✅ 文案"刮雪"匹配中级 |
| MID_ACC3 | 78 | 控速可以但走刃质量跟不上；弯中承压不稳 | ⚠️ 文案说"走刃质量跟不上"但分数已到 78（中级偏上顶） |
| MID_ACC4 | 61 | 雪板横向滑移偏多，用刃不稳定；膝盖过直 | ✅ 文案"横向滑移"匹配中级 |
| MID_ACC5 | 81 | 弯中承压不稳；刃角距持续走刃还有距离；下压幅度可更大 | ❌ 文案 3 条全是"待改进"却给到高质量档 |
| MID_ACC6 | 83 | 刃角尚可，但距持续稳定的走刃还有一段路 | ❌ 文案明说"距稳定走刃还有距离"但分数 83 |
| MID_ACC7 | 93 | 刃角距持续走刃还有距离；重心阶段适配一般 | ❌❌ 分数 93 但文案还在"距稳定还有距离"，最严重的自相矛盾 |
| MID_ACC8 | 90 | 重心高度大体能用，但与转弯阶段配合不够精细 | ⚠️ 文案偏正面（"大体能用"），90 分基本自洽 |
| MID_FP1  | 77 | 重心对阶段支持不够；立刃全程不一致（好坏交替）；膝盖有下压空间没利用 | ❌ 文案 3 条负面，77 分明显偏高 |
| MID_FP2  | 82 | 立刃有基础，但刃角保持时间不足 | ⚠️ 文案偏正面，82 分半自洽 |
| BAD_ACC  | 83 | 板尾扫雪明显，更像搓雪弯而不是刻滑 | ❌❌ 文案明说"搓雪弯"但分数 83（高质量档），严重矛盾 |

### 微观复核发现（补 §1.5）

**关键新证据**：**5 份视频（MID_ACC5/6/7、MID_FP1、BAD_ACC）出现"文案-分数自相矛盾"**：算法自动生成的"主要问题"文本明确指出这是"搓雪弯 / 走刃不稳定 / 立刃不一致"，但综合分却给到 77-93。这不是教练与算法的分歧，**而是算法自己内部的评分口径与语义口径已经分裂**：
- 评分侧的 calf 主导路径把分数拉到高质量档；
- 文案侧的 `ReportGenerator` 基于走刃质量 + 重心 + 主问题标签，仍按教练视角给出"待改进"结论。

这个证据比 §2.1 的档位不一致更强——**用户会先读到"综合评分 93 · 高阶表现阶段"再读到"主要问题：距稳定走刃还有距离"，直接会怀疑系统在自相矛盾**。

## 二、交叉核对定量结果

### 2.1 档位不一致率 = 75%

12 锚点里 **9/12 (75%)** 与教练锚点档位不一致：

| 类别 | 数量 | 名单 |
|---|---:|---|
| 上迁（比锚点高一档以上） | 7 | MID_ACC3, MID_ACC5, MID_ACC6, **MID_ACC7**, MID_FP1, MID_FP2, **BAD_ACC** |
| 下迁（比锚点低一档以上） | 2 | **GOOD_A**, MID_ACC1 |
| 一致 | 3 | MID_ACC2, MID_ACC4, MID_ACC8 |

### 2.2 三个有精确锚点分数的样本 Δ

| Alias | 锚点分 (2026-05) | 现分 (2026-09-15) | Δ | 方向 |
|---|---:|---:|---:|---|
| GOOD_A   | 94.1 | 86 | **-8.1** | ⬇️ 下迁 |
| MID_ACC8 | 85.3 | 90 | **+4.7** | ⬆️ 小上迁 |
| BAD_ACC  | 65.0 | 83 | **+18.0** | ❌ 大幅上迁 |

### 2.3 维度相关性（18 份样本 Pearson r，由 [scripts/calibration_cross_check.py](../../scripts/calibration_cross_check.py) 输出）

| 维度 | r | 解读 |
|---|---:|---|
| **edge**（走刃质量） | **+0.959** | 极强正相关 → 报告首屏指标，与综合分同步变化 |
| **calf**（立刃小腿角） | **+0.949** | 极强正相关 → 权重 0.35 + sigmoid c=40 让它成为**主导评分维度** |
| knee（膝盖弯曲） | +0.894 | 强正相关，但由于权重 0.25 + 门限式打分，**压不住 calf 抬分** |
| lean（身体前倾） | +0.639 | 中等正相关 |
| gravity（重心高度） | +0.509 | 中等正相关 |
| **sym**（动作对称） | **-0.657** | **反相关**（高分样本 sym 反而偏低）→ 需要排查评分逻辑 |

**结论**：
- edge/calf/knee 三大立刃相关维度都对综合分高度正相关（r>0.89），但 **calf 权重占优（0.35）+ sigmoid c=40 把 42° 之后的分数迅速拉起**，是抬分的最直接来源。edge 相关性看似最高（0.959），但 edge 本身有 [30,42] cap 兜底，属于**结果指标**，其相关性一部分是"分数高 → edge 也高"的反向共线性。
- **sym 出现 r=-0.657 的反相关**是重要意外发现：本应作为质量门槛的对称性维度，18 份里越高分样本 sym 反而越低，直觉是"高分样本运动幅度大 → 左右不对称放大"。建议在下一轮打开 sym 详细分数看是否需要"运动幅度归一化"或"低 sym 硬 cap"。
- 综合看：**综合分 ≈ f(edge, calf, knee)** 但 calf 是最容易被"提前立刃 c=40 sigmoid"抬起来的一维。这解释了：
  - BAD_ACC calf=45 → 综合 83（calf 恰好卡在 sigmoid 拐点右侧）
  - MID_FP1 knee=74（应压制"腿太直"） → 综合仍 77（knee 权重 0.25 不敌 calf 0.35）
  - GOOD_A calf=48 → 综合 86（calf 中点附近拉不起 94 分锚点，被 sigmoid 拐点惩罚）

### 2.4 分数分布直方图（18 份样本）

```
<60      1 █
60-69    3 ███
70-79    4 ████
80-87    6 ██████       ← 峰值
88+      4 ████
```

18 份里 **10 份 (55%) ≥80**，教练视角这个比例应远低（原 middle-accepted 8 份里 5 份 ≥78 是核心佐证）。当前分布明显重心右偏。

## 三、系统性偏差归因

### 3.1 primary bias：calf 单一维度过度主导

由 §2.3 定量证据：calf 与综合分 r=0.949，权重 0.35 + sigmoid c=40 让 calf 60 分（≈42°）就能把综合分拉到 80+。所有中级偏高样本都是这条路径踩中的：
- MID_ACC7 calf 59 → 综合 93（middle 到近专业档）
- MID_ACC6 calf 46 → 综合 83
- BAD_ACC calf 45 → 综合 83（bad 顶到高质量档）

### 3.2 secondary bias：edge cap ramp 没兜住"calf 中低段"

BAD_ACC edge=57 > 42 直接放行到 100 cap，edgeCappedScore 83.4 = bestThird 直通。edge cap 的 [30,42] 兜底段设计初衷是防"完全无走刃"（edge<30 一律 cap 62），但没考虑"edge 中等但 calf 中低"的组合——这类样本在教练视角是"中级典型"，当前算法给到高质量档。

### 3.3 tertiary bias：knee 权重不足以形成硬门槛

knee 与综合分 r=0.894 看似同步，但权重仅 0.25 且不参与 `knee-based hard cap`。MID_FP1 knee=74 恰好卡在评分下限（80° 是理想区间下沿），因此没被打入 cap 逻辑；同时 sigmoid c=40 把 calf 侧的分数抬到 68 附近，最终 knee 弱势没能压下综合分，得到 77。

### 3.4 分档语义漂移

历史校准（2026-05）建立"85≈中级顶 / 94≈专业"时，evidence cap 是主要"证据封顶"来源。edge-first 后 evidence cap 变宽松（[30,42] ramp），加上 sigmoid 拉高中位数，导致"教练视角中级偏上"样本落入 stage classifier 的 `avg≥80 → qualitySkiing` 桶。

## 四、结论

**edge-first + c=40 sigmoid + flow gating + 方向 α 的评分体系在 2026-09-15 主 corpus 上表现良好，但在 12 锚点上有 75% 的档位不一致**。核心问题是：
1. calf 单一维度的相关性过强（r=0.949），综合分几乎沦为 calf 的单调函数
2. edge cap 兜底段有盲区（edge ≥ 42 但 calf 中低组合逃逸）
3. knee 权重不足以压制"腿太直"这类经典中级 FP

**建议的三个动作**（按优先级）：

### 4.1 【已落地 · 2026-09-15】edgeQuality 双维兜底 ✅

**实现修正**：原 spec 静态规则 `edge≥42 && calfLean<40 → cap=72` 在真实字段上**无法触发**——BAD_ACC 真实 calfLeanScore=45（非<40）、MID_FP2=52。落地时用 18 份样本真实字段重新定位，发现唯一能干净分离 **GOOD_A（edgeQuality=61，须保护）与 BAD_ACC（edgeQuality=57，须下压）** 的轴是复合 **edgeQualityScore**（报告首屏"走刃质量"），故改为独立 ramp：

```
edgeQuality < 57        → cap = 72
edgeQuality ∈ [57,61]   → linearRamp(72 → 100)
edgeQuality ≥ 61        → 100（无 cap）
nil                     → 100（由上游 65 cap 兜底）
```

触点：[VideoAnalyzer.edgeQualityCapValue(for:)](../../Sources/FallLineCore/VideoAnalyzer.swift#L540-L557) + [Utilities.averageEdgeQualityScore(from:stability:)](../../Sources/FallLineCore/Utilities.swift#L302-L329)（直接从 poseScore 现算，不依赖 `generateSummary` 之后才挂载的 skiMetrics，口径与 `SkiMetricsCalculator.average` 严格一致）。

**实测 Δ（18 份，2026-09-15 release CLI）**：

| 样本 | edgeQuality | 前分 | 现分 | 说明 |
|---|---:|---:|---:|---|
| BAD_ACC | 57.47 | 83 | **75** | 落 ramp 段（72+0.47/4×28=75.3），回到中级偏上 |
| v4 | 55 | 79 | **72** | 触顶 |
| v5 | 52 | 74 | **72** | 触顶 |
| MID_ACC3 | 54 | 78 | **72** | 触顶，落回中级偏上 |
| GOOD_A | 61 | 86 | **86** | 恰好放行，保持高质量档 |
| MID_ACC8 | 71 | 90 | **90** | 无影响 |
| v2/v3/v6 | 69-72 | 87/88/90 | **不变** | 专业档无影响 |
| v1 | 37 | 61 | **61** | bestThird 57.8 已低于 cap，cap 非约束 |

246 tests 全部通过（新增 6 条 edgeQuality ramp 契约，含锚点回放）。

### 4.2 【已分析 · 2026-09-15】knee 动态加权方向错误 + 无稳健分离规则 ⛔（不落地）

把 spec 的 knee 动态加权放到 18 份真实数据上，发现三重问题（分析脚本：[scripts/knee_separability_analysis.py](../../scripts/knee_separability_analysis.py)）：

**(a) 权重转移方向相反**：规则 `knee<75 → w.knee +0.10 / w.calf −0.10` 的单帧效应是 `0.10×(knee−calf)`。目标样本里 knee 反而**高于** calf：

| 样本 | knee | calf | 转移后 Δ | 期望 |
|---|---:|---:|---:|---|
| MID_FP1 | 74 | 47 | **+2.7（升到 ~80）** | 应下降 |
| MID_ACC5 | 72 | 58 | **+1.4（升到 ~83）** | 应回中级 |

**(b) 修正分组后，唯一的分离结构是"析取放行"**：正确语义是"立刃或承压任一证据强即放行，两者皆弱才 cap"（因为教练专业样本 GOOD_A 靠 pressure=79.1，而主 corpus 刻滑样本 v2/v3/v6 靠 edgeQuality=69~72）。网格搜索确实找到 324 组可行阈值（Te≈66.8, Tp≈76.4），模拟结果完美：GOOD_A/MID_ACC8/v2/v3/v6 全保留，BAD_ACC/MID_FP1/MID_ACC5→72，MID_FP2/MID_ACC6/MID_ACC7→75.6，低分样本不被抬分。

**(c) 但该规则不可辩护（故不落地）**：可行窗口极窄、margin 极小——

```
edge 阈值可行域：     Te ∈ (64.92, 68.62]   宽 3.69
pressure 阈值可行域： Tp ∈ (75.90, 76.84]   宽 0.94   ← 最小单边 margin 仅 0.44
```

也就是说，"压 BAD_ACC（pressure=75.9）"与"保 v6（pressure=76.8）"取决于 **0.9 分的测量差**，这在 2D 光流/姿态测量的噪声范围内，属对 18 份样本的过拟合。任何 cap 若压 MID_ACC7（教练=中级），其姿态特征在每一维都 ≥ GOOD_A（教练=专业），只能靠这 0.9 分的 pressure 缝隙区分。

**结论**：在当前特征集下不存在稳健的多维硬规则；该问题应留到 §4.4 扩样本（拿到统计分布、而非单点阈值）后再解决。knee 维度本身并非漏判根源（直腿严重的样本 edgeQuality 都已很差、分数已低）。

### 4.3 【已落地 · 2026-09-15】stage classifier 收紧（仅低边界，高边界保留）✅

**原方案**：`avg≥80 → qualitySkiing` 改为 `avg≥82 且 calf≥55 且 sym≥70`，advanced 提到 `calf≥65 && knee≥85 && sym≥75`。

**实证复核后调整落地范围**（避免重蹈 §4.2 过拟合 + §4.5 sym 反相关）：

1. **落地的收紧（低边界）**：`avg≥75 → qualitySkiing` 改为 `avg≥75 且 calf≥55`。
   - 影响面：仅 BAD_ACC（avg75.3/calf46.1）与 MID_FP1（avg76.5/calf46.8），两者距阈值有 ~8 margin，稳健；阶段落回 **稳定滑行阶段**。
   - release 重跑确认：BAD_ACC 75 分 · 稳定滑行阶段；MID_FP1 77 分 · 稳定滑行阶段。
2. **高边界 `avg≥80` 不做硬分离**：想压的 MID_ACC5/6（81-83, calf47-59）与必须保护的 GOOD_A（avg85.6/calf48.5）在 avg 上仅差 2.1、calf 上仅差 1.7，任何硬阈值都属过拟合，留待 §4.4 扩样本。GOOD_A 经重跑保持 86 分 · **高质量滑行阶段**。
3. **撤销 sym 条件**：§4.5 已证 sym 与立刃深度负相关，GOOD_A sym≈65、MID_ACC8 sym≈74.5，加 `sym≥70/75` 会把头号专业样本压档。
4. 该 stage 只影响报告标签与重心适配展示分（`cogStageFitScore`），**不进入综合总分**（综合分仍用帧级旧 gravityScore）。
5. 顺手删除了 [ReportGenerator.swift](../../Sources/FallLineCore/ReportGenerator.swift) 中与 StageClassifier 重复、已无调用的私有 `determineStage` 死副本，消除双份逻辑漂移。

单测：[Tests/FallLineCoreTests/StageClassifierTests.swift](../../Tests/FallLineCoreTests/StageClassifierTests.swift)（7 用例，覆盖基础档 / 低边界收紧 / 高边界保留 / 阈值边界）。`swift test` 全量 253 通过。

### 4.4 【长期】扩样本 + 建立分档基准
当前 12 锚点密度过低（middle 边界"中级 vs 高质量"几乎没有样本）。建议：
- 从 [SkiAnaylze/testvideo/](../../SkiAnaylze/testvideo/) 系统抽 20-30 份 middle 样本二次标注
- 建立 "middle 顶 = 78 / middle 中 = 68 / middle 底 = 58" 的三级锚点基准
- 用扩展锚点重训 sigmoid c 参数（当前 c=40 是主 corpus 拍脑袋值）

### 4.5 【已排查 · 2026-09-15】sym 负相关是"功能性不对称"误判，无需归一化/硬 cap ⛔（不改评分）

排查脚本：[scripts/symmetry_correlation_audit.py](../../scripts/symmetry_correlation_audit.py)。

**发现 1：负相关确认，且三个子分量全为负**（聚合口径，n=18）：

```
r(final, sym     ) = -0.549   （原报告 -0.657 为不同聚合口径，负相关一致）
r(final, kneeSym ) = -0.550
r(final, leanSym ) = -0.529
r(final, calfSym ) = -0.377
```

**发现 2：负相关的结构性根源——对称性与立刃深度几乎同等负相关**：

```
r(edgeQuality, sym    ) = -0.539
r(edgeQuality, leanSym) = -0.577
```

散点呈明确两极：
- **低立刃初学者**（MID_ACC1/v1/MID_ACC4，edge 35-39）对称性反而最高 **89-91**——对称犁式/楔形站姿天然 L-R 对称；
- **高立刃刻滑样本**（GOOD_A，edge 61）对称性最低 **63.1（左右膝差 20°）**——刻滑弯外腿伸展承压、内腿折叠，天然不对称。GOOD_A 正是因深度刻滑站姿才拿全场最低 sym，而它是教练头号专业样本。

**发现 3：现有硬 cap（sym<45 → 综合≤72）当前无样本触发**（最低 GOOD_A 63.1），处于休眠；但一旦未来误触发，会优先压到 GOOD_A 这类专业刻滑样本。

**判断与决策**：sym 负相关**不是评分 bug**，而是该指标把"刻滑功能性不对称（内外腿分工）"误当成"缺陷"。帧内 `|L−R|` 角度差无法区分"刻滑弯内外腿分工"与"真正左右失衡"。真正的对称质量应衡量 **左转弯 vs 右转弯的跨弯一致性**（需新增跨弯特征），而非帧内角度差。因此：
- **现在不做**归一化、**不新增**硬 cap，也**不提高** sym 权重（edge-first 已 .15→.10）；
- sym 硬 cap 继续保留为休眠兜底（无样本触发，不改变现状）；
- 真正修复（跨弯对称特征）随后续迭代落地。

## 五、GOOD_A 分数的现状与处理

GOOD_A 从教练锚点 94.1 降到当前 **85.6**（§4.1 edgeQuality cap 后仍为此值——其 pressure=79.1 属保护维度，未被压），仍是本次唯一显著下迁样本。

**当前判断**：GOOD_A 是"深度刻滑站姿"（姿态干净、承压强，但单帧立刃角度 edgeQuality=61 不算深）。其掉分主因是 sigmoid c=40 让 calf=48 只得中位分、权重 0.35 拉低整体，而非任何 cap。由于 §4.2 的 knee/多维硬规则因 margin 仅 0.44 被否决，GOOD_A 目前维持 85.6（专业档下限）。

是否把 GOOD_A 拉回 90+，本质取决于"立刃不深但姿态/承压极强"该如何计分——这与 §4.5 的跨弯特征、§4.4 扩样本后的统计分布绑定。在拿到更多专业锚点前，**不单独为 GOOD_A 调 sigmoid**（c=40 同时是防止主 corpus v5 跃档的必要值）。

## 六、原始产物

- [aliases.txt](aliases.txt)：12 锚点 alias → 源视频路径
- `{ALIAS}.md` / `{ALIAS}.log`：每锚点报告 / CLI 日志（12 份，`MID_ACC1.log` 已补齐）
- 交叉核对脚本已固化为 [scripts/calibration_cross_check.py](../../scripts/calibration_cross_check.py)：直接运行 `python3 scripts/calibration_cross_check.py` 即可复现 §1/§2/§4/§5/§6 的原始表格与相关性数字（本文档所有 Pearson r、档位一致率、直方图均由该脚本产出并冻结）
- `outputs/**/*.json`、`outputs/**/*.MP4` / `outputs/**/*.MOV` 符号链已通过 [.gitignore](../../.gitignore) 排除，仅保留 md/log/txt 便于版本管理

## 七、待办同步

- [x] 12 锚点重跑并保存产物 (`outputs/calibration_review_20260915/*`)
- [x] MID_ACC1 补跑 CLI，`.log` 齐全
- [x] 交叉核对（档位一致性 + Δ + 维度相关性 + 直方图 + 文案-分数自洽性）
- [x] 微观复核（§1.5，逐视频文案 vs 分数）
- [x] 交叉核对逻辑固化为 [scripts/calibration_cross_check.py](../../scripts/calibration_cross_check.py)
- [x] `.gitignore` 排除 `outputs/**/*.json` 与视频符号链
- [x] 快照回写 [calibration_anchors.md](../../annotations/calibration_anchors.md#L43-L73)
- [x] follow-ups 同步到 [WORK_LOG.md](../../WORK_LOG.md#L29-L34)
- [ ] 【下一步】评估 §4.1（edge cap 双维兜底）落地成本，做一次 corpus + 锚点联合回放
- [ ] 【下一步】评估 §4.2（knee 动态加权）落地成本
- [ ] 【新增】排查 §2.3 sym r=-0.657 反相关：确认对称性评分逻辑是否被大幅运动误伤
- [ ] 【中期】扩样本到 20-30 份 middle 边界视频
