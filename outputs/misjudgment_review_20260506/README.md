# Misjudgment Review 2026-05-06

Purpose: quick follow-up after the duplicate-utility cleanup regression. This pack checks whether any remaining high-risk scoring cases need a new rule change.

## Regression Baseline

- `swift test`: 65 tests, 0 failures.
- Anchor videos stayed aligned with accepted scores: 65/85/94 in CLI rounded display, corresponding to 65.0/85.3/94.1 in the TSV summary.
- Full 49-video rerun: `outputs/all_video_scores_20260506_150537/`, failures 0.
- Diff vs `outputs/all_video_scores_20260505_210424/score_summary.tsv`: 0 changed fields.

## Candidate Sheets

| candidate | reason | score | sideslip | current read |
| --- | --- | ---: | ---: | --- |
| `good_9ed0bb6c707fc47fce153cee3dcd365e_sheet.jpg` | high score with high sideslip metric | 79.1 | 54.6 | Stable-platform report keeps score but sideslip confidence is low; no immediate cap change. |
| `middle_b343b317a6689df373085ec85e042480_sheet.jpg` | high sideslip at 70 | 70.0 | 41.9 | Report already warns and caps as横滑/推坡-like, acceptable for now. |
| `middle_v2800fgi0000d54jhefog65lbfdhma2g_sheet.jpg` | high sideslip at 70 | 70.0 | 54.4 | Evidence confidence is low and report stays conservative; no immediate rule change. |
| `good_86ae42724c8349913703af0f4140f6d2_sheet.jpg` | good-labeled sample near 70 | 70.9 | 13.8 | Possible low estimate from visibility/keypoint stability, needs human confirmation before changing scoring. |
| `good_5382da0c825e30518ab376505cbcfaf2_sheet.jpg` | good-labeled sample near 70 with higher sideslip | 70.0 | 39.7 | Report warns about board/travel angle and posture issues; no immediate rule change without human confirmation. |
| `bad_v2800fgi0000d4v24r7og65oi0fmka5g_sheet.jpg` | bad-labeled sample scoring 62 | 62.0 | 16.1 | Short clip with limited reliable frames; existing conservative cap reads reasonable. |

## Notes

- These are preliminary model/operator observations from overlay sheets, not final human annotations.
- If a new calibration pass starts, focus first on `good_86ae...` and `good_5382...`; they are the only reviewed candidates that might plausibly be under-scored.
- Do not promote the purple visual board candidate into scoring from this pack; this review is about current ankle-proxy behavior.
