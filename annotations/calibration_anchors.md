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
