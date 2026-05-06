# VideoVision Work Log

## Current Goal
收敛板身判断主线：使用左右脚踝连线作为板身方向代理，用板身方向与滑行方向的夹角判断走刃/横滑。夹角大时按横滑、推坡或搓雪处理，不能给高刻滑结论。紫色图像候选线只保留为 debug 证据。

## Context Snapshot
- 紫色线 = `visualBoardObservation` / `BoardObservationSource.visualCandidate`，来自 `BoardVisualLineDetector`。
- 黄色线 = 当前板身分析实际采用的 `BoardObservation`，现在主要还是 `ankleProxy`。
- README 的调试覆盖图颜色约定：绿色人体核心/重心，白色双踝代理线，紫色图像级板身候选线，黄色实际采用板身线，青色运动方向。
- `BoardDirectionAnalyzer.PreparedFrame.selectObservation` 当前明确只返回 `ankle`，图像候选线暂不参与评分或横滑计算。
- 这样做的原因是实际样本里紫色候选线可能抓到雪面纹理、滑痕、阴影或其他噪声，需要人工标定稳定后再考虑升级为主证据。
- 当前采用的主判断：`板身方向 = 左右脚踝连线方向`，`滑行方向 = 连续帧身体中心/脚踝中心位移方向`。夹角越小越像沿板走刃，夹角越大越像横滑/推坡。
- 分档口径：`<=15°` 沿板身移动明显，`15°-30°` 有走刃倾向，`30°-45°` 横滑偏多，`>=45°` 以横滑为主。

## Existing Review Assets
- 复核输出目录：`outputs/edge_debug_review/`
- 样本汇总：`outputs/edge_debug_review/visual_candidate_summary.tsv`
- 每个样本目录包含逐帧 overlay PNG 和 `manifest.tsv`。
- 当前代表样本共 9 个：3 个 `good`，3 个 `middle`，3 个 `bad`。

## Completed
- 已确认 `outputs/edge_debug_review` 下存在 9 个样本目录。
- 已确认 `visual_candidate_summary.tsv` 汇总了每个样本的帧数、紫色候选出现帧数、平均/最佳置信度、候选长度和最佳帧图片路径。
- 已确认 `DebugOverlayRenderer` 会把紫色候选线画到 overlay PNG，并把 `visualBoardAngle`、`visualBoardConfidence`、`visualBoardLength` 写入 `manifest.tsv`。
- 已确认当前评分逻辑仍不使用紫色图像候选线。
- 已生成第一轮人工复核包：`outputs/visual_candidate_review_round1/`。该轮从 `bad` / `good` / `middle` 三类各挑一个最高置信紫色候选，并生成 3 秒原视频片段、对应 overlay PNG 和 `README.md` 复核索引。
- Round 1 人工结论：A/B/C 看到的紫色线都不是板身，而是在板身或脚附近的误检。已在 `outputs/visual_candidate_review_round1/README.md` 标为 `snow_texture`，子类记为 `near_board_false_positive`。
- 已将板身/滑行方向夹角接入保守封顶：`>=30°` 不能保留高刻滑分，`>=45°` 基本按横滑/推坡封顶。
- 已将高横滑角接入高光过滤：如果没有稳定刻滑基线，且脚踝代理给出可信高横滑角，则不输出“最佳刻滑/高质量”高光。
- 已更新报告文案：高横滑角时明确提示“板身/滑行方向夹角偏大，更像横滑或推坡，不能按刻滑高分处理”。
- 已补测试并通过 `swift test`：65 tests, 0 failures。
- 已批量重跑 `video/` 下 49 个视频，失败数 0。汇总输出在 `outputs/all_video_scores_20260505_210424/score_summary.md` 和 `score_summary.tsv`；本次分组均分：`bad=57.3`、`middle=66.6`、`good=76.8`、`root=65.0`。
- 人工复核确认以下三个原本疑似需校准的分数没有问题：`video/bad/0b7522e9db823b910ac67727aea726da.MP4` = 65.0，`video/middle/96001e37e76be9ef6cf7a65e73efcac4.MP4` = 85.3，`video/good/v0200fg10000d7r0017og65qoh1vgeg0.MP4` = 94.1。已写入 `annotations/calibration_anchors.md` 的 accepted current scores。

## Next Steps
- 下一步不再针对上述三个样本降分；后续校准应优先找新的误判样本，而不是压低这三个已接受锚点。
- 紫色线分支暂不继续推进为过滤规则；保留 round1 作为“高置信图像候选仍可能是假阳性”的证据。
- 如后续要恢复图像板身检测，必须先解决 `near_board_false_positive`，不能只用靠近脚踝、方向接近脚踝代理线、长度或图像对比强作为可用板身证据。

## Important Files
- `README.md`
- `Sources/VideoVisionCore/BoardVisualLineDetector.swift`
- `Sources/VideoVisionCore/BoardDirectionAnalyzer.swift`
- `Sources/VideoVisionCore/Models.swift`
- `Sources/VideoVisionCore/Utilities.swift`
- `Sources/VideoVisionCore/VideoAnalyzer.swift`
- `Sources/VideoVisionCore/HighlightMomentDetector.swift`
- `Sources/VideoVisionCore/ReportGenerator.swift`
- `Sources/VideoVisionCLI/DebugOverlayRenderer.swift`
- `outputs/edge_debug_review/visual_candidate_summary.tsv`
- `outputs/visual_candidate_review_round1/README.md`

## Working Tree Note
当前工作区已有多处未提交改动和未跟踪输出，包括 `BoardVisualLineDetector.swift`、`DebugOverlayRenderer.swift`、相关测试和 `outputs/edge_debug_review/`。后续任务应先读 `git status --short`，不要回退不属于当前任务的改动。

## Update Rule
每次长任务开始或结束时更新本文件。保持短小，只记录可恢复上下文：目标、关键结论、改动文件、跑过的验证、剩余步骤和风险。
