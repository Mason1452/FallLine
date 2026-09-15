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
