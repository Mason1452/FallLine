# Visual Candidate Review Round 1

本轮目标：从 `good` / `middle` / `bad` 三个类别中各挑一个最高置信紫色候选线，让人工先按 `true_board` / `snow_texture` / `uncertain` 判断。

选择规则：
- 主排序：`bestVisualConf` 最高。
- 同分时：用 `avgVisualConf` 更高的样本作为本轮主候选。
- 每段原视频片段约 3 秒，候选帧位于片段中间附近；`0s` 候选从视频开头开始截取。

| id | group | sample | source video | candidate time | clip | overlay | best conf | best length | human label |
| --- | --- | --- | --- | ---: | --- | --- | ---: | ---: | --- |
| A | bad | `bad_0b7522e9db823b910ac67727aea726da` | `video/bad/0b7522e9db823b910ac67727aea726da.MP4` | 41.00s | `A_bad_0b7522e9_best_41s.mp4` | `A_bad_0b7522e9_best_41s_overlay.png` | 1.00 | 0.22 | `snow_texture` |
| B | good | `good_0946ed384e732c357a3d55fac77426c0` | `video/good/0946ed384e732c357a3d55fac77426c0.MP4` | 4.00s | `B_good_0946ed_best_4s.mp4` | `B_good_0946ed_best_4s_overlay.png` | 1.00 | 0.26 | `snow_texture` |
| C | middle | `middle_992f063b79d27b96b471e44a48d8465e` | `video/middle/992f063b79d27b96b471e44a48d8465e.MP4` | 0.00s | `C_middle_992f06_best_0s.mp4` | `C_middle_992f06_best_0s_overlay.png` | 1.00 | 0.26 | `snow_texture` |

人工判断口径：
- `true_board`：紫色线贴合真实雪板/板身方向，位置和角度都合理。
- `snow_texture`：紫色线主要落在雪面纹理、滑痕、阴影、雪雾或背景线条上。
- `uncertain`：画面遮挡、板身不可见、线只贴合局部，或无法稳定判断。

备注：`good` 和 `middle` 内都有多个 `bestVisualConf = 1.00` 的样本，本轮先取 `avgVisualConf` 更高者。若第一轮规则不足，再补看同分候选。

Round 1 人工结论：
- A/B/C 当前看到的紫色线都不是板身，而是在板身或脚附近的误检。
- 这些样本归入 `snow_texture`，更准确的子类是 `near_board_false_positive`：位置接近脚/雪板，但没有贴合真实板身区域。
- 下一轮过滤规则不能只奖励“靠近脚踝”或“方向接近脚踝代理线”，必须增加位置贴合或连续性约束。
