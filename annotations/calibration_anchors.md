# Calibration Anchors

Human feedback from 2026-05-04. These clips are used as reference points when tuning scoring rules.

## False Negatives

| Video | Time | Human label | Previous system label | Calibration note |
|---|---:|---|---|---|
| `video/good/v0200fg10000d7r0017og65qoh1vgeg0.MP4` | `00:00-00:02` | 标准低姿态刻画，姿态和弯形都非常好 | 弯中刃角保持不足 | Low-confidence lower-body detection must not become a negative edge-quality judgment. |
| `video/good/v0200fg10000d7r0017og65qoh1vgeg0.MP4` | `00:09-00:11` | 完美后刃刻画，立刃高，姿态好 | 走刃质量偏弱 | Backside low-carve can hide knee/ankle points; treat as unreliable, not poor. |
| `video/good/v0200fg10000d7r0017og65qoh1vgeg0.MP4` | `00:20-00:22` | 滑得很好，姿态很低 | 最低分片段 | Deep stance should be protected when keypoint confidence is low. |

## False Positives / Over-Scored

| Video | Time | Human label | Previous system label | Calibration note |
|---|---:|---|---|---|
| `video/middle/4a7dfe960f07ac14b06bbd8de3d38aa4.MP4` | overall | 滑得还可以，但腿太直，没有前面倒伏，也没有压低重心 | 综合偏高 | Straight-leg penalty needs to be stronger than the old 100-140 degree knee range. |
| `video/middle/ccfd9967aa6d3ab5abd04fb8991872c7.MOV` | `00:04` | 人不错，但该帧高分过高，需要复查 | 高分且提示不对称 | Score fusion should not let strong edge/pressure hide obvious asymmetry. |

## Accepted Middle Judgments

The following middle videos were broadly accepted as correctly described:

- `video/middle/1c5771fc7dd1ea546eb5bc3e4e01bc48.MP4`
- `video/middle/v0200fg10000d2tcts7og65t6h63ua2g.MP4`
- `video/middle/992f063b79d27b96b471e44a48d8465e.MP4`
- `video/middle/v0300fg10000d4oq6avog65ihr8qf550.MP4`
- `video/middle/v0200fg10000d6a4i57og65mkjkcdpu0.MP4`
- `video/middle/v2800fgi0000d5ehg1vog65tinkepgl0.MP4`
- `video/middle/a7791a475a244c938dd0815e89b1dec5.MP4`
- `video/middle/96001e37e76be9ef6cf7a65e73efcac4.MP4`

## Accepted Current Scores

Human feedback from 2026-05-05 after the full 49-video rerun. These scores were initially flagged for manual review, then accepted as reasonable and should not be tuned down just because they look high relative to their group.

| Video | Current score | Current level | Calibration note |
|---|---:|---|---|
| `video/bad/0b7522e9db823b910ac67727aea726da.MP4` | 65.0 | 中级 | Accepted by human review; this is the top bad-group sample but not considered over-scored. |
| `video/middle/96001e37e76be9ef6cf7a65e73efcac4.MP4` | 85.3 | 专业 | Accepted by human review; high middle-group score is reasonable for this sample. |
| `video/good/v0200fg10000d7r0017og65qoh1vgeg0.MP4` | 94.1 | 专业 | Accepted by human review; low board kinematic confidence should not override the stable low-carve baseline here. |

## 2026-09-15 Recalibration Snapshot (edge-first c=40 + flow gating + direction α)

Full rerun of the 12 anchor clips above with current [release CLI](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI) after the edge-first refactor (`ce751a4..b584b12` + `fbeb1da`), flow modulation edge-confidence gating (`ab16817`), and direction α edge-quality semantics migration (`ed9dac5`). Detailed table + per-clip md/json are in [outputs/calibration_review_20260915/](file:///Users/mingsen/Project/FallLine/outputs/calibration_review_20260915).

| Alias | Video | 2026-05 anchor | 2026-09-15 score | 2026-09-15 stage | Δ | Status |
|---|---|---:|---:|---|---:|---|
| GOOD_A   | video/good/v0200fg10000d7r0017og65qoh1vgeg0.MP4 | 94.1 · 专业 | **86** | 高质量滑行阶段 | **-8.1** | ⚠️ dropped one tier |
| MID_ACC8 | video/middle/96001e37e76be9ef6cf7a65e73efcac4.MP4 | 85.3 · 专业 | **90** | 高阶表现阶段    | **+4.7** | ✅ same pro tier |
| BAD_ACC  | video/bad/0b7522e9db823b910ac67727aea726da.MP4   | 65.0 · 中级 | **83** | 高质量滑行阶段 | **+18.0** | ❌ over-scored, needs cap |
| MID_FP1  | video/middle/4a7dfe960f07ac14b06bbd8de3d38aa4.MP4 | over-scored（腿太直） | **77** | 高质量滑行阶段 | — | ❌ still over-scored |
| MID_FP2  | video/middle/ccfd9967aa6d3ab5abd04fb8991872c7.MOV | over-scored（单帧异常）| **82** | 高质量滑行阶段 | — | ⚠️ duration cap 78 partially works |
| MID_ACC1 | video/middle/1c5771fc7dd1ea546eb5bc3e4e01bc48.MP4 | middle accepted    | **72** | 稳定滑行阶段    | — | ✅ 中级 |
| MID_ACC2 | video/middle/v0200fg10000d2tcts7og65t6h63ua2g.MP4 | middle accepted    | **65** | 稳定滑行阶段    | — | ✅ 中级 |
| MID_ACC3 | video/middle/992f063b79d27b96b471e44a48d8465e.MP4 | middle accepted    | **78** | 高质量滑行阶段 | — | ⚠️ 从 middle 上迁 |
| MID_ACC4 | video/middle/v0300fg10000d4oq6avog65ihr8qf550.MP4 | middle accepted    | **61** | 稳定滑行阶段    | — | ✅ 中级偏下 |
| MID_ACC5 | video/middle/v0200fg10000d6a4i57og65mkjkcdpu0.MP4 | middle accepted    | **81** | 高质量滑行阶段 | — | ⚠️ 从 middle 上迁 |
| MID_ACC6 | video/middle/v2800fgi0000d5ehg1vog65tinkepgl0.MP4 | middle accepted    | **83** | 高质量滑行阶段 | — | ⚠️ 从 middle 上迁 |
| MID_ACC7 | video/middle/a7791a475a244c938dd0815e89b1dec5.MP4 | middle accepted    | **93** | 高质量滑行阶段 | — | ❌ 从 middle 跃到近专业 |

**Systematic bias**：
- Middle-accepted 集合 8 份里有 5 份综合 ≥78（62.5%）上迁到"高质量滑行阶段"，其中 MID_ACC7 到 93。历史"中级 = middle"的语义与当前分档已严重错位。
- GOOD_A 反而从 94 → 86 掉一档，主因 calfLean 48（≈40°）落在 sigmoid c=40 中点，主导权重 0.35 拉低整体分。
- BAD_ACC 从 65 上迁到 83（Δ=+18），edge cap [30,42] 兜底段没兜住（本样本 edge=57>42 直接放行到 100 cap，calfLean=45 主导反而拉高）。
- MID_FP1（教练明确"腿太直、没倒伏"）仍拿 77 分，knee 权重 0.25 无力压制。

**Follow-ups (unblocked)**：
- 报告分档 stage label 阈值需要收紧（当前 avg≥80 → qualitySkiing 过于宽松）。
- edge cap ramp 需要加"calfLean<40 且 edge<50 → cap=72"或类似双维兜底，压制 BAD_ACC 这类样本。
- knee<75 时 knee 维度可考虑动态加权到 0.35，压制 MID_FP1 这类"腿太直"样本。
- 中期需扩样本到 [SkiAnaylze/testvideo/](file:///Users/mingsen/Project/FallLine/SkiAnaylze/testvideo/) 20-30 份 middle 边界样本，才能给分档阈值调参提供统计基础。
- 详细分析见 [outputs/calibration_review_20260915/SUMMARY.md](file:///Users/mingsen/Project/FallLine/outputs/calibration_review_20260915/SUMMARY.md)。

## 2026-09-16 Boundary Annotation Batch (10 unlabeled middle clips)

§4.4 扩样本第一批。均来自 `video/middle/`（教练 middle 桶），用当前 release（edgeQuality cap + §4.3 stage 收紧后）重跑。"算法综合分"以报告综合评分为准；edge/pressure/calf/knee 为算法维度证据。**教练档位 / 是否稳定刻滑 / 备注三列待人工看片填写**。五档：初级<60 · 中级[60,70) · 中级偏上[70,80) · 高质量[80,88) · 专业≥88。

| Alias | 文件 | 算法综合分 | edge(conf) | pressure | calf | knee | sideslip° / carvingCnf% | 帧 | 教练档位 | 稳定刻滑? | 备注 |
|---|---|---:|---|---:|---:|---:|---|---:|---|---|---|
| BND_HI1 | `9714be3aba73f5f94130750c2a15d381.MP4` | 92 | 61.5 (0.8) | 75.4 | 50.5 | 95.4 | 41° / 28% | 231 | **高质量 80-88** | **是** | 数字92越专业线~4；stage 标签=高质量一致；板身代理漏判刻滑 |
| BND_HI2 | `4f9ec73b994b63b0775ccfb7a8ef7e6f.MP4` | 91 | 63.9 (0.7) | 78.5 | 57.1 | 95.4 | 54° / 10% | 152 | **专业 ≥88** | **是** | 算法档位正确；carvingCnf 10% 严重漏判，旧版仅60 |
| BND_HI3 | `b343b317a6689df373085ec85e042480.MP4` | 87 | 62.6 (0.7) | 72.4 | 57.0 | 93.4 | 31° / 41% | 299 | **高质量 80-88** | **是** | 完全一致；校准 GOOD_A=86 合理 |
| BND_M1  | `v0200fg10000d318sovog65g16lolm8g.MP4` | 78 | 59.0 (0.5) | 70.9 | 46.5 | 83.3 | 44° / 20% | 121 | **中级偏上 70-80** | 否（搓雪） | 完全一致；中级顶边界 |
| BND_M2  | `v0200fg10000coc7bcrc77u875h9q7sg.MP4` | 72 | 54.6 (0.6) | 77.6 | 33.7 | 94.4 | 46° / 19% | 495 | **中级 60-70** | 否（搓雪） | ⚠ 高估一档：knee94 顶分但 calf34 立刃浅 |
| BND_M3  | `v0300fg10000d6fe0nnog65jmdun29vg.MP4` | 72 | 48.8 (0.6) | 66.9 | 30.5 | 68.5 | 57° / 19% | 95 | **中级 60-70** | 否（搓雪） | ⚠ 高估一档：knee68/edge49 均弱，属§4.2直腿刃浅类 |
| BND_M4  | `v0d00fg10000cu3omkvog65r22seg0t0.MP4` | 72 | 56.0 (0.6) | 74.5 | 35.1 | 81.4 | 30° / 40% | 61 | **中级偏上 70-80** | 否（搓雪） | 一致；短片 |
| BND_L1  | `v1e00fgi0000d5bksdfog65irrhr4bog.MP4` | 65 | 46.7 (0.6) | 61.0 | 34.6 | 45.6 | 12° / 73% | 103 | **中级 60-70** | 否（推坡） | 一致；carvingCnf73% 假阳性（板对齐但直滑推坡） |
| BND_L2  | `v0300fg10000d5h313fog65nermuqklg.MP4` | 62 | 41.8 (0.6) | 67.6 | 20.3 | 74.3 | 43° / 24% | 79 | **中级 60-70** | 否（搓雪） | 一致；calf20 立刃很浅 |
| BND_L3  | `v2800fgi0000d54jhefog65lbfdhma2g.MP4` | 62 | 45.9 (0.6) | 67.8 | 23.1 | 78.5 | 51° / 12% | 125 | **中级 60-70** | 否（搓雪） | 一致；calf23 立刃很浅 |

### 标注结果分析（2026-09-16，n=10）

**1. 档位一致性：按分数档位边界（<60 / 60-70 / 70-80 / 80-88 / ≥88）严格核算为 7/10 一致，且 3 处偏差全部为高估、无低估**：
- BND_HI1：数字 92 已进专业带（≥88），教练判高质量（80-88），超 ~4 分；报告 stage 因 calf50<65 仍标"高质量"，故 stage 文案与教练一致、数字偏高一档。
- BND_HI2：数字 91 专业带，教练判专业 ✓；但报告 stage 因 calf57<65 未升"高阶"、仍标"高质量"，即**数字对、stage 标签低半档**（advanced 门槛 calf≥65 把这份真刻滑卡住，是后续可复核点）。
- BND_M2 / BND_M3：数字 72 进中级偏上带，教练判中级（60-70），高估半档。
- 其余 6 份（HI3、M1、M4、L1、L2、L3）分数档位与教练完全一致。

**2. 最重要发现：2D 板身代理（carvingConfidence）对"是否刻滑"几乎不可信**。
- 教练确认稳定刻滑的 HI1/HI2/HI3，carvingCnf 只有 **28% / 10% / 41%**（HI2 全场最低）；
- 教练明确推坡（非刻滑）的 L1，carvingCnf 却 **73%（全场最高）**。
- 真刻滑与非刻滑在 carvingCnf 上完全颠倒 → 强力佐证 P8-A 退役 sideslip cap、且板身证据**不能**作为评分硬阈值。

**3. calfLean（小腿倾斜）才是这批里区分刻滑的更可靠信号（待更多样本验证的假设）**：
- 教练"稳定刻滑"3 份 calf = **50.5 / 57.1 / 57.0**（均 ≥50）；
- 教练"非刻滑"7 份 calf = 20.3–46.5（最高 M1=46.5）。
- 存在一条约 **calf≈48-50** 的干净缝隙（margin ~4 分），显著优于 board carvingCnf。n=10 仍小，先记录为候选规则（"稳定刻滑判定 / 高质量档准入"可考虑 calfLean 阈值），扩到 30 份后再决定是否落地。

**4. M2/M3 高估半档的共同特征**：knee 高（94 / 68 偏低）但 calf 浅（≤34）、edge 弱（49-55）。与 §4.2 目标一致，但 M2(calf33.7) 与被认可的 M4(calf35.1) 单维极接近、教练却分两档，说明 70-72 边界仍无稳健单阈值，需更多样本。

**标注重点复核结论**：GOOD_A（edge60.8/calf48.5、教练专业）与 HI1/HI2/HI3（edge61-64、教练高质量-专业且确认为刻滑）同构——**"姿态强 + edge≈62"可以是真刻滑**，板身低证据是测量漏判。因此 §4.1 edgeQuality cap 阈值 57 放行这一带是正确的，不应进一步收紧。

## 2026-09-16 Boundary Annotation Batch 2（good/bad 两桶，15 片人眼看片）

§4.4 扩样本第二批。第一批只覆盖 middle 桶，本批补两端密度：从 `video/good/`（14 份未标）与 `video/bad/`（8 份未标）用同一当前 release 重跑，按信息增益挑 **15 片逐份人眼看片**（good 7、bad 8 全标）；good 桶另有 7 份算法 88.5–95.9 的高分簇未逐一看片，分数附在末尾但**不计入一致性统计**。档位与刻滑判定均为教练人眼。

| Alias | 文件（桶） | 算法综合分 | edge(conf) | pressure | calf | knee | sideslip° / carvingCnf% | 时长 | 教练档位 | 稳定刻滑? |
|---|---|---:|---|---:|---:|---:|---|---:|---|---|
| BND2_TOP | `v1e00fgi0000d2bufenog65temc6sh70.MP4` (good) | 97 | 74.6 (0.68) | 76.9 | 76 | 91 | 27° / 43% | 18s | **专业** | **是** |
| BND2_H4 | `v0200fg10000d6mln8vog65kajcq52dg.MP4` (good) | 89 | 64.4 (0.64) | 72.0 | 58 | 84 | 42° / 26% | 63s | **专业** | **是** |
| BND2_H3 | `v2800fgi0000d7o00ufog65t0ran4h1g.MP4` (good) | 89 | 62.2 (0.70) | 72.7 | 53 | 77 | 70° / 1% | 18s | **专业** | **是** |
| BND2_H2 | `v0300fg10000d7h0ckfog65nmsn20jqg.MP4` (good) | 88 | 60.1 (0.75) | 73.0 | 48 | 86 | 64° / 4% | 38s | **专业** | **是** |
| BND2_H1 | `v1e00fgi0000d5utfk7og65q1chsrq8g.MP4` (good) | 88 | 61.7 (0.63) | 68.9 | 59 | 73 | 62° / 3% | 33s | **专业** | **是** |
| BND2_H0 | `86ae42724c8349913703af0f4140f6d2.MP4` (good) | 84 | 59.8 (0.70) | 70.4 | 51 | 78 | 64° / 3% | 41s | **专业** | **是** |
| BND2_GM | `d63bfbf8978cf8a962f613a489a14420.MP4` (good) | 76 | 55.4 (0.74) | 67.9 | 44 | 76 | 60° / 5% | 74s | **中偏上** | **是** |
| BND2_LB | `v0300fg10000cusoptnog65pkehng280.MP4` (bad) | 65 | 45.7 (0.70) | 70.3 | 26 | 71 | 54° / 10% | 36s | **初级** | 否（搓雪） |
| BND2_L6 | `v0200fg10000d6olrffog65vrste5qqg.MOV` (bad) | 62 | 47.5 (0.72) | 70.4 | 25 | 80 | 40° / 30% | 67s | **初级** | 否（搓雪） |
| BND2_LM | `v0200fg10000d7nnh5vog65i52ermgog.MP4` (bad) | 62 | 46.8 (0.68) | 75.9 | 21 | 95 | 25° / 53% | 18s | **中级** | 否（搓雪） |
| BND2_L5 | `v0300fg10000d664l37og65t6pnbois0.MOV` (bad) | 62 | 48.9 (0.76) | 69.9 | 26 | 78 | 37° / 27% | 6s | **初级** | 否（搓雪） |
| BND2_L4 | `v1e00fgi0000cv786ffog65rtmm48gmg.MOV` (bad) | 62 | 40.6 (0.70) | 56.1 | 30 | 39 | 44° / 10% | 11s | **初级** | 否（搓雪） |
| BND2_L3 | `v2800fgi0000d4v24r7og65oi0fmka5g.MP4` (bad) | 62 | 60.0 (0.63) | 76.0 | 45 | 92 | 59° / 8% | 12s | **初级** | 否（搓雪） |
| BND2_L2 | `v0d00fg10000ctm0ufvog65rqb97g2p0.MP4` (bad) | 61 | 41.9 (0.65) | 65.7 | 18 | 65 | 34° / 37% | 26s | **初级** | 否（搓雪） |
| BND2_L1 | `v0d00fg10000csgr6inog65n8mlpg2m0.MP4` (bad) | 60 | 40.1 (0.70) | 69.8 | 13 | 78 | 54° / 6% | 15s | **初级** | 否（搓雪） |

未逐一看片、不计入统计的 good 高分簇 7 片（算法 88.5–95.9）：`9ed0bb6c…` 96、`3e6f37fe…` 95、`v2800…d6m0mk7…` 93、`3134552b…` 93、`5382da0c….MOV` 91、`641efed0….MOV` 89、`0946ed38…` 89——均落在已被 TOP/H4 锚定的专业簇内，桶标签也是 good，作为弱先验暂记专业。

### 第二批分析（n=15 人眼）

**1. 档位一致性 6/15，偏差呈"两端反向"：6 处高估全部在 bad 低端，3 处低估全部在 good 高端。**
- 高端低估：H0(84→专业)、H1(88→专业)、H2(88→专业) 三份算法落"高质量"带（H1/H2 仅差专业线 0.1–0.4），教练判专业刻滑；H3/H4/TOP 数字对。
- 低端高估：LB(65)、L6/L5/L4/L3(均62)、L2(61) 六份教练判初级，算法给在中级带；仅 L1(60) 数字对，LM(62) 是唯一教练也认中级的 62 分片。
- 连同第一批 HI1(92→高质量，高估)，说明分数在 83–92 专业边界附近与教练判断**非单调**：83.5 可以是专业、92 也可以只是高质量。单纯平移专业线无法同时满足，需要比总分更能反映刃线/弯质的特征，暂不调阈值。

**2. 低端 62 分"地板"机理已定位（关键）**：最终分 = `min(bestThirdAverageScore, …caps)`，`bestThirdAverageScore` 只取最好 1/3 帧，对初学者系统性虚高（本批 bad 达 68.8–84.1）；随后 `boardKinematicHighScoreCap` 的 `lowBoardEvidenceScoreCap=62`（[Utilities.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L172) 板身置信度低 + 可靠姿态片段短）把它们统一压到 **62**。问题是 62 本身落在中级带（≥60），成了穿不过初级线的地板——rawPose 只有 50.8 的 L4 也被 bestThird 68.8 抬上来再压到 62。反例是 LM：bestThird 65→62，教练却认中级。因此**不能简单把该 cap 降到 58**（会误伤 LM 这类真中级）；L3 更证明 edge=60、calf=45、knee=92 仍可能是初级搓雪，低端 62 附近现有 2D 姿态维不可分。真正修复需降低 bestThird 选择偏差（如低分位/全片加权）或引入弯形/刃线质量特征，列入后续，不在本批落地。

**3. calfLean 软信号下修到 ≈45.5（更新第一批的 48–50 假设）**：两批合并 25 片，刻滑组 calf ∈ [44,76]（最低为本批 GM=44）、搓雪组 calf ∈ [13,46.5]（最高为第一批 M1=46.5），两组仅在窄区间 44–46.5 内重叠。取阈值 calf≈45.5 全样本分对 **23/25**，跨界反例仅两个：GM（calf44 但刻滑）与 M1（calf46.5 但搓雪）。edge 重叠明显更严重（刻滑 55.4–74.6、搓雪 40.1–60.0，L3 edge60 却是搓雪）。结论：**calf≈45.5 是显著优于 edgeQuality/boardCnf 的刻滑软信号，但仍有边缘反例，只能作软证据/报告佐证，不能作评分硬门槛**。

**4. 2D 板身 carvingConfidence 二度确认无判别力**：本批刻滑 7 份 cnf ∈ [0.8%, 43%]（H3=1%、H0/H1/H2=3–4% 却是确认刻滑），搓雪 8 份 cnf ∈ [6%, 53%]（LM=53% 搓雪）。两区间完全重叠，继续坚持 P8-A 结论：板身证据不参与评分、不作硬阈值。

**5. good/bad 桶标签只可作弱先验**：good 桶里 GM 只有 76（教练中偏上），bad 桶 LM 是真中级；目录归类 ≠ 精确档位，一切以人眼标注为准。

## 2026-09-18 Boundary Annotation Batch 3（候选池 19 片，待教练看接触表回填）

§4.4 扩样本第三批。前两批 25 片均为「先按信息增益挑片、再逐份人眼看片」，本批把 Phase 2 起步 1 [p2_candidate_contact_sheets.swift](file:///Users/mingsen/Project/FallLine/scripts/p2_candidate_contact_sheets.swift#L28-L48) 的 19 片候选池（good 8 / middle 10 / bad 1）一次性用当前 release 重跑，算法列已填齐（提取脚本 [board_edge_batch3_extract.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_batch3_extract.py)，日志 `outputs/board_edge_p2/batch3_extract.log`、逐片 JSON `outputs/board_edge_p2/batch3_json/`，均已 .gitignore）。**教练档位 / 是否稳定刻滑 / 备注三列待看 `outputs/board_edge_p2/contact_sheets/<alias>.jpg` 后回填**，五档口径同前：初级<60 · 中级[60,70) · 中级偏上[70,80) · 高质量[80,88) · 专业≥88。calf/knee 按 [StageClassifier.averageSubScores](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/StageClassifier.swift#L24-L39) 口径（可靠姿态帧 totalConfidence 加权，min 0.30 门控）。

| Alias | 文件（桶） | 算法综合分 | edge(conf) | pressure | calf | knee | sideslip° / carvingCnf% | 时长 | 教练档位 | 稳定刻滑? | 备注 |
|---|---|---:|---|---:|---:|---:|---|---:|---|---|---|
| CAND_G01 | `0946ed384e732c357a3d55fac77426c0.MP4` (good) | 89 | 67.5 (0.72) | 73.9 | 62.4 | 83.2 | 52° / 13% | 42s | **专业** | 是（刻滑） | 低姿态连续走刃，弯弧干净，前后刃皆稳 |
| CAND_G02 | `3134552bed78447b9f7ba8e2003ce678.MP4` (good) | 93 | 69.0 (0.70) | 74.5 | 64.2 | 89.9 | 40° / 32% | 50s | **专业** | 是（刻滑） | 白衣深折叠，弯中走刃、雪雾沿弧侧喷 |
| CAND_G03 | `3e6f37fe76521781506c19c02c1b97ed.MP4` (good) | 95 | 74.6 (0.66) | 76.3 | 77.0 | 92.9 | 54° / 16% | 25s | **专业** | 是（刻滑） | 面条雪上留下干净细弧线，立刃证据最确凿 |
| CAND_G04 | `5382da0c825e30518ab376505cbcfaf2.MOV` (good) | 91 | 73.6 (0.71) | 77.0 | 71.2 | 94.1 | 39° / 27% | 43s | **专业** | 是（刻滑） | 红衣低姿态连续走刃，刃线清晰 |
| CAND_G05 | `641efed02be271b6d9f014c97d1f8ae0.MOV` (good) | 89 | 67.4 (0.78) | 76.7 | 58.7 | 97.2 | 46° / 21% | 114s | **专业** | 是（刻滑） | 走刃技术教学片：小/中回、滚刃、带转、反脚/倒滑走刃 |
| CAND_G06 | `9ed0bb6c707fc47fce153cee3dcd365e.MP4` (good) | 96 | 69.9 (0.57) | 77.5 | 70.0 | 92.1 | 54° / 14% | 41s | **专业** | 是（刻滑） | 陡坡靠弯型控速，连续走刃，板轴 7/10 |
| CAND_G07 | `v0200fg10000d7r0017og65qoh1vgeg0.MP4` (good) | 86 | 60.8 (0.50) | 79.1 | 48.2 | 97.7 | 50° / 11% | 30s | **专业** | 是（刻滑） | known GOOD_A，竞技深折叠摸雪走刃 |
| CAND_G08 | `v2800fgi0000d6m0mk7og65qamcvgf80.MP4` (good) | 93 | 76.5 (0.59) | 73.0 | 83.3 | 96.1 | 55° / 12% | 37s | **专业** | 是（刻滑） | Gray 品牌片，深折叠八字刻滑，刃线清晰 |
| CAND_M01 | `1c5771fc7dd1ea546eb5bc3e4e01bc48.MP4` (middle) | 55 | 34.5 (0.54) | 61.8 | 6.7 | 47.6 | 44° / 17% | 45s | **初级** | 否（放板） | 夜场高站姿直腿放板，几乎不折叠 |
| CAND_M02 | `4a7dfe960f07ac14b06bbd8de3d38aa4.MP4` (middle) | 77 | 57.7 (0.81) | 68.9 | 46.5 | 74.2 | 41° / 25% | 33s | **中级偏上** | 否（搓雪） | 黑装备流畅小弯、节奏稳，但折叠/立刃不足 |
| CAND_M03 | `96001e37e76be9ef6cf7a65e73efcac4.MP4` (middle) | 90 | 70.7 (0.73) | 78.4 | 65.4 | 97.4 | 37° / 32% | 29s | **专业** | 是（刻滑） | 浅灰低姿态连续小弯，板面干净少雪雾 |
| CAND_M04 | `992f063b79d27b96b471e44a48d8465e.MP4` (middle) | 72 | 54.3 (0.73) | 74.9 | 36.7 | 96.3 | 63° / 4% | 35s | **中级偏上** | 否（搓雪） | 转弯雪雾明显，姿态可控但未走刃 |
| CAND_M05 | `a7791a475a244c938dd0815e89b1dec5.MP4` (middle) | 93 | 64.9 (0.67) | 75.1 | 58.6 | 91.7 | 39° / 31% | 51s | **专业** | 是（刻滑） | 卡其深折叠坐转，弯弧干净、雪雾少 |
| CAND_M06 | `ccfd9967aa6d3ab5abd04fb8991872c7.MOV` (middle) | 82 | 61.4 (0.64) | 74.5 | 51.5 | 84.0 | 53° / 14% | 10s | **中级偏上** | 否（搓雪） | 雪岭背景，中高站姿、转弯雪雾大 |
| CAND_M07 | `v0200fg10000d2tcts7og65t6h63ua2g.MP4` (middle) | 65 | 39.9 (0.63) | 64.1 | 17.7 | 61.3 | 34° / 35% | 22s | **中级** | 否（非刻滑） | 夜场暴雪高站姿张臂直腿，calf 低 |
| CAND_M08 | `v0200fg10000d6a4i57og65mkjkcdpu0.MP4` (middle) | 81 | 63.1 (0.66) | 69.2 | 58.1 | 72.4 | 73° / 0% | 20s | **中级偏上** | 否（粉雪） | 藏王粉雪树林，高站姿、雪墙大（粉雪非刻滑） |
| CAND_M09 | `v0300fg10000d4oq6avog65ihr8qf550.MP4` (middle) | 61 | 38.6 (0.70) | 64.2 | 12.3 | 57.7 | 60° / 5% | 106s | **初级** | 否（放板） | 黄衣高站姿直腿放板，calf 极低，算法 bestThird 抬高 |
| CAND_M10 | `v2800fgi0000d5ehg1vog65tinkepgl0.MP4` (middle) | 83 | 59.0 (0.73) | 74.4 | 46.0 | 86.2 | 45° / 23% | 59s | **高质量** | 是（刻滑） | 八点半走刃教学示范，连续走刃但非竞技级折叠 |
| CAND_B01 | `0b7522e9db823b910ac67727aea726da.MP4` (bad) | 75 | 57.5 (0.56) | 75.9 | 44.8 | 87.8 | 49° / 18% | 49s | **中级** | 否（前刃不稳） | 学员纠错片：踮脚尖/前刃不稳、看山下、片中摔倒，算法 75 高估 |

### 第三批算法侧观察（教练标签 2026-09-19 已回流，复核结论见 spec §12.8）

- **弱先验分与当前 release 偏差显著**，再次证明接触表 hint 不可作档位：good 桶 G01/G02 弱先验 73/72，当前 release 已 **89/93**；middle 桶 M01 弱先验 67 → 实际 **55**（calf 仅 6.7，全集最低端）、M05 74 → **93**、M07 58 → **65**。
- **G07 = 86、edge 60.8、calf 48.2** 与 §4.1 GOOD_A 校准锚点完全一致（同一 known anchor 片），佐证提取脚本综合分 / edge 口径与前批严格对齐。
- **分数带分布（算法）**：≥88 专业带 9 片（G02/G03/G04/G06/G08/M03/M05 + G01 89 + G05 89）；80–88 高质量 3 片（M06/M08/M10）；70–80 中偏上 3 片（M02/M04/B01）；60–70 中级 2 片（M07/M09）；<60 初级 1 片（M01）。**12/19 落专业带、且 calf≥48 的片多达 14 片**——明显高于自然雪场分布，提示候选池在挑片阶段就偏向了高姿态质量片；教练判档后需重点核对这批是否真是专业刻滑，避免 Gate-G2 高端密度虚高。
- **延续前两批结论**：carvingCnf 与真实刻滑仍不对应（G08 calf 83.3 但 cnf 12%、M08 cnf 0%、M07 搓雪姿态 cnf 35%），P8-A 板身证据不参与评分的结论三批一致。
