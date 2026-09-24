# FallLine Work Log

## Current State (2026-09-24 项目体积优化：outputs 746M 移出版本库 + git-filter-repo 重写历史清除 outputs，.git 1.6G→888M；视频语料按决策保留。314/314 + release build 通过，force push 完成)

**审计 → 决策 → 落地**：工作区原 3.3G，大头为 `.git` 1.6G、`video` 829M、`outputs` 824M、`.build` 450M、`testvideo` 196M。关键发现：`.git` 的大并非"删错残留"，而是 746M outputs 历史 debug/review 产物（748 PNG + 293 log + 6 mp4）在 114 commits 反复堆积；历史最大 blob 与当前文件一致。用户拍板：**outputs 移出跟踪 + 整体忽略 + 重写历史清除；视频语料保留在仓库；清理本地 .build/未跟踪产物**。

**本地清理（约 516M，可再生）**：删除 `.build`（450M Swift 缓存）、`outputs/board_edge_p2`（66M）、`outputs/perf_3d_baseline`（20K）；还原被本地分析污染的陈旧报告 `video/middle/1c…48.md`。

**outputs 移出版本库**：`git rm -r --cached outputs`（1156 文件、tracked 746M），磁盘文件保留；[.gitignore](file:///Users/mingsen/Project/FallLine/.gitignore) 用单条 `outputs/` 替换此前分散的 outputs 规则（视频符号链 / 接触表 / 日志等子规则合并）。

**历史重写（破坏性，已备份）**：
- 重写前先 `git bundle create ../FallLine_backup_before_slim.bundle --all`（1.6G 全历史备份，位于仓库外）。
- `brew install git-filter-repo`（2.47.0）；`git filter-repo --path outputs/ --invert-paths --force` 清除 outputs 的**全部历史版本**，视频与代码不动。
- 结果：`.git` **1.6G → 888M**（pack 877M）；`git rev-list --objects --all` 中 outputs 对象归零；视频 90 个 tracked 文件完整保留。
- **所有 commit hash 已重写**（原 `1fd2dc2`→`9e8df0c`、新结构提交 `3cfdd04`）。剩余 877M pack 主要是保留的视频语料——若未来要把 `.git` 再压到几十 M，需把视频也外移并配 fetch 脚本（同 [models/fetch.sh](file:///Users/mingsen/Project/FallLine/models/fetch.sh) 思路），但本轮明确不做。
- filter-repo 自动移除 origin，已重加 `git@github.com:Mason1452/FallLine.git` 并 `git push --force origin main` 成功（`1fd2dc2...3cfdd04 forced update`）。GitHub 对 70.4M / 53.6M 两个视频仅 GH001 大文件警告（未阻止，硬限 100M）。

**验证**：`swift build -c release` Build complete（从零编译 19.4s）；`swift test` **314/314（0 failures）**；远端 `ls-origin/main` = `3cfdd04173ab572b7d83fe734ad12f1a78dd2f71`。源码 / 评分 / JSON 零改动（本次仅删产物与重写历史，未碰任何 Swift 源文件）。

**下一步（待用户）**：确认其他机器 / 协作者需重新 clone（旧历史作废）；确认无误后可删除仓库外备份 `../FallLine_backup_before_slim.bundle`；候选 F zero-shot 流程不变（fetch 模型 → export → dry-run）。

## Previous State (2026-09-22 候选 F 骨架落地：yolov8n-seg + .pt + fetch.sh + 项目开源；models/ 目录 + CoreMLBackend 实现就绪，不投模型二进制、未跑推理)

**用户拍板骨架配置（"1n 2pt 3fetch 4 开源"）**：候选 F CoreML 板边分割 spike 选用 **YOLOv8-seg nano**（3.4M 参数、M1 Pro 约 10–15ms/帧、COCO mask mAP 30.5），format = `.pt`（fetch）+ `.mlpackage`（本机 export），走 `fetch.sh` 一键补齐 + SHA256 校验，SkiAnaylze 项目开源可承接 **AGPL-3.0**（若切闭源商用改 YOLO-NAS-seg 或 DeepLabV3+ MobileNetV2）。本轮**只落骨架、不下载模型、不跑推理、不触碰生产代码**（评分/JSON 零变化）。

**目录 / 脚本**（详见 [spec §12.14.1](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L833) 与 [delta_update 2026-09-22](file:///Users/mingsen/Project/FallLine/delta_update.md)）：
- 新增 [models/](file:///Users/mingsen/Project/FallLine/models/)：[README.md](file:///Users/mingsen/Project/FallLine/models/README.md)（目录清单、许可、fetch 用法、SHA256 表待回填、`yolo export` 命令、zero-shot 判据、版本 pin）+ [fetch.sh](file:///Users/mingsen/Project/FallLine/models/fetch.sh)（`curl -L` 拉 Ultralytics v8.2.0 tag 的 `yolov8n-seg.pt` + `shasum -a 256`、`--verify`、`--model <name>` 切换骨架、退出码 0/1/2/3）+ `yolov8n-seg/.gitkeep`。
- 更新 [.gitignore](file:///Users/mingsen/Project/FallLine/.gitignore)：`models/**/*.pt`、`models/**/*.mlpackage/`、`.mlmodel`、`.onnx`、`.venv-coreml/` 全部排除，**模型二进制永不入库**。
- 升级 [board_edge_coreml_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_coreml_spike.py) 的 `CoreMLBackend` 从占位换为真实实现：`coremltools` lazy import（`--check-plan` 在无 venv 环境仍可跑）、ffmpeg 抽帧（`/opt/homebrew` → `/usr/local` 回退）、单帧 predict、COCO 30/31（skis+snowboard）联合 mask、可选 `gt_mask` 出 IoU、per-frame 推理耗时；`SegmentationReport` 加 `median/p95/max_inference_ms` + `inference_le_20ms_ratio`；新增 `--dry-run`（每片 5 帧 zero-shot 快检）与 IoU≥0.65 / medianInferenceMs≤20ms 自检门槛提示。**PCA 主轴与 fallback 逐帧对齐仍留 TODO**，等 IoU 门槛过后再补。

**下一步（待用户）**：本机 `bash models/fetch.sh` → 建 `.venv-coreml` 装 `ultralytics/coremltools` → `yolo export model=yolov8n-seg.pt format=coreml half=True nms=True imgsz=640` → `python3 scripts/board_edge_coreml_spike.py --model models/yolov8n-seg/yolov8n-seg.mlpackage --dry-run`。首版 IoU ≥0.55 有希望 → 投 100 帧 GT 微调冲 0.65；<0.30 换骨架。三条硬门槛（IoU≥0.65 / 推理≤20ms / farShot 恢复率≥50%）与 100 帧 GT 最小集维持。

## Previous State (2026-09-22 全局性能优化：流式光流消除全片帧缓存 + 3D 两阶段按需 + 复用 CIContext + autoreleasepool + 并发批默认 8→4。对真实提交版 HEAD：峰值 RSS 417→295MB（-29%）、user 39.7→34.6s（-13%）、sys 11.9→6.7s（-44%）；314/314 + 两片 JSON bit-identical，评分零变化)

**证据驱动的热点审计**：对同一片（1080×1920，CLI 5fps，205 次抽帧）隔离测量——默认 2D+3D 35.0s/user 37.6s/RSS 217MB；`--no-3d` 仅 2D 25.7s/**user 2.8s**/RSS 93MB；关光流 28.0s/user 36.5s；光流 medium 精度几乎不省 CPU。**结论：3D 姿态请求是 CPU/内存绝对大头（约 34s user、~124MB），2D 走 ANE/GPU；全片 CGImage 帧缓存是常驻内存与 OOM 根因；光流非 CPU 瓶颈**。

**本轮降本（相对真实提交版 HEAD，全部零评分变化）**：
1. **光流改流式滑动窗（内存主收益）**：删除旧 `frameCache` 全片 CGImage 驻留，只留相邻一帧的 `previousFlowFrame`，经有状态 `FlowAccumulator`（addPair/finalize）逐对算完即释放，常驻 O(帧数×图)→**O(1)**。修复 iOS 30fps 下 60s 约 2GB 触发 jetsam 的崩溃。
2. **3D 改两阶段按需调用（CPU 主收益）**：旧实现 2D/3D 同一 handler 一次批量发出，但 `PoseMetrics3DAdapter.fuse` 只在 2D 也检出姿态的帧采用 3D，2D 未检出（本片 61/205 ≈ 30%）的 3D 结果被丢弃、纯属浪费。改为先跑 2D，**仅当 2D 检出才补跑 3D**，同一图像独立推理输出一致；并显式固定 `revision = .revision1`，跳过每帧 revision 枚举。
3. **autoreleasepool** 包裹抽帧 / 姿态 perform / 光流 perform，回收 AVFoundation/Vision 临时对象，压低瞬时内存（iOS 关键）。
4. **复用 CIContext（两处）**：`downscaleImageForFlow` 不再每帧新建，改 analyzer 级 `lazy sharedCIContext`；另修掉 [BoardEdgeDetector.instanceAlpha](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L429)（board-edge 前景 mask→CGImage）漏网的每实例 `CIContext()`，改枚举级 `static let sharedCIContext`（44 片 `--board-edge` 数千次重建消除）。
5. **并发批 8→4（默认值调优）**：对 43.6s 片（218 帧）扫 batch 1/2/4/8——8: 36.2s/user 39.6s/**RSS 236MB**；4: 38.6s/user 33.7s/**RSS 193MB**；2: 45.8s/177MB；1: 58.9s/168MB。4→8 墙钟仅快 7% 却 RSS **+22%**、user **+18%**，故取拐点 **4**。

**曾尝试后放弃（记录以免重复踩坑）**：① 复用 `VNDetectHumanBodyPose3DRequest` —— 3D 请求带时序跟踪状态，复用会改变关键点置信度/坐标，放弃（改为两阶段 + 固定 revision）；② 复用 2D `VNDetectHumanBodyPoseRequest`（对象池+串行锁）—— 省 CPU 有限且与批量并发锁竞争，回退为每帧新建；③ visual 候选线只解码踝下 ROI 瓦片 —— 瓦片边缘裁掉线端点采样，使 lengthRatio/center 漂移、boardAngle 融合角变化（非 bit-identical），而全帧 PixelImage 缓冲在流式帧流下只活单帧、不累积，故整体回退 ROI，恢复全帧解码。

**验证（权威口径）**：`swift test` **314/314**、`swift build -c release` 过；用 `git stash` 临时回退到真实提交版 HEAD 构建取基线，最终版两片（good 43.6s / middle 10.5s）JSON 与真实 HEAD **bit-identical**（非与被污染中间态比）。总量收益：峰值 RSS **417→295MB（-29%）**、user **39.7→34.6s（-13%）**、sys **11.9→6.7s（-44%）**、墙钟 40.1→39.0s（-2.7%）。iOS 经 `import FallLineCore` 直接消费包依赖（`VideoAnalyzer(videoURL:)` 走默认 batch=4 + 流式光流），全部优化自动生效、无需同步副本。调参钩子 `FALLLINE_BATCH_SIZE`、`FALLLINE_FLOW_ACCURACY=medium`（均非默认）。详见 [delta_update 2026-09-22](file:///Users/mingsen/Project/FallLine/delta_update.md)。

**下一步（待用户，更大降本属评分权衡）**：若要向 2D-only（user 2.8s/RSS 93MB）进一步靠拢，需默认关 3D 或自适应按需 3D，但 3D 以 0.9 置信覆盖膝角、默认关会改评分（本片 84→76），须重校锚点；放松抽帧 zero-tolerance 可压 25s 墙钟硬底但帧会偏移。候选 F 决策标准维持，模型选型等用户测试结论。

## Previous State (2026-09-22 光流改流式滑动窗，修复 iOS OOM：frameCache 全片驻留消除，314/314 + 真实视频 bit-identical)

**iOS OOM 修复（架构性变更，评分零变化）**：用户真机跑 App 启动分析即被 jetsam 杀、无崩溃日志。根因是旧 `VideoAnalyzer.frameCache` 把全片每帧 CGImage 全程驻留；默认 `sampleInterval` 已升到 1/30(30fps)，帧数 ×6，60s 视频光流图缓存峰值约 **2GB** 超真机上限（macOS 内存宽松未暴露）。改造：[FlowMetricsCalculator](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift) 新增有状态 `FlowAccumulator`（addPair/finalize，归约逐行对齐原实现）；[VideoAnalyzer](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift) 删除全片 frameCache/frameCacheTimes/computeFlowMetrics()，改为只留相邻一帧的 `previousFlowFrame` 滑动缓冲，算完一对即释放，analyze 收尾 finalize、generateSummary 读缓存；新增 `flowSampleRadius` 参数透传（默认 3）。光流常驻内存 O(帧数×图)→**O(1)**（两张相邻图，数 MB）。验证：`swift build` debug+release 过、`swift test` **314/314**、零诊断；BND2_TOP/BND2_L1/BND_HI2 新 release 与 3b860da 旧版 JSON 除 `videoPath` 临时路径外 **bit-identical**。无 JSON 字段增减、对外接口不变。详见 [spec §12.15.4 ADR-005](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L934) 与 [delta_update 2026-09-22](file:///Users/mingsen/Project/FallLine/delta_update.md#L30)。

**下一步（待用户）**：真机重跑确认不再 OOM；候选 F 决策标准（IoU≥0.65 / 推理≤20ms / farShot 恢复率≥50%）与 100 帧 GT 最小集维持，模型选型继续等用户测试结论。

## Previous State (2026-09-21 方向 C 时序聚合 S4 完成：44 片实测 Gate-G2 **NO-GO**（方向反转），字段留诊断，下一步激活候选 F CoreML 板边分割)

**刃线/轨迹检测 Phase 2 — §12.15 S4 落地，Gate-G2 硬闸门判 NO-GO（评分零污染）**：release 构建 + `--board-edge` 44 片 8364 帧全量重跑（JSON 全部含 `summary.boardTrajectory`，持久化 `outputs/board_edge_p2/trajectory_json/`）；扩展 [lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py) 新增 `--trajectory`（margin + LOOCV + 景别残差）。核心结果 mean stableWindowRate：high=0.384 / mid=0.328 / low=**0.405**——连续性不随刻滑质量上升、反而弱负相关；主口径 high(21) vs low(10) 最强时序特征 margin=−0.13σ、LOOCV=45.2%、专业误伤 11，低端11片对照 −1.03σ 同向反转；最强单一信号 farShotFrac 0.75σ/71% 仍不达标。**margin 1.5σ / LOOCV 90% / 专业零误伤三 FAIL → NO-GO**，日志 [gate_g2_trajectory_44.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g2_trajectory_44.log)，详见 [spec §12.15.3](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L911) 与 [delta_update S4](file:///Users/mingsen/Project/FallLine/delta_update.md#L17)。

**机理（非 bug、非景别假相关）**：推坡直滑板轴恒定朝坡下→PCA 主轴天然稳（多 low 片 board% 50–75%、swr 0.55–0.83）；刻滑连续换弯→板轴转动更易 IQR>5° 被拒。"轴方向不变"≠"沿弧线走刃"且弱负相关，根因同 P7-A/P8-A 与 §10.2——2D 几何天花板。去 farShot 残差 margin≈0（0.08σ）排除景别伪信号；foldCrossingRate 全片 0，真实换弯大转角被 unstableIQR 吃掉。

**下一步（当前口径，待用户）**：候选 F 三条硬门槛已锁定（IoU≥0.65 / 推理≤20ms / farShot 恢复率≥50%，spec §12.14）；**模型选型搁置，等用户自行测试后再决定**；**GT 规模已锁定 100 帧最小集**（≈0.83 人时、含 QA ≈1–1.5 人时），先验证 IoU 0.65，临界再补标。实际选帧 / 标注启动待用户指示。Gate-G1 v3 FAIL 结论与门槛不动。

## Previous State (2026-09-21 方向 C 时序聚合 S3 完成：24 条单测落地，314/314 全绿)

**刃线/轨迹检测 Phase 2 — §12.15.2 阶段 S3 落地（评分零污染）**：新增 [BoardTemporalAxisAggregatorTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardTemporalAxisAggregatorTests.swift) **24 个 test**，覆盖 §12.15.2 清单全部 14 项（稳定窗 / 候选不足 / IQR 5°·6° 边界 / 源多数派 tie / candidate 提取 / fold-crossing 保守拒绝与有向重建 / 跨簇阻断 run / 片首边界 / 全拒绝流 / 偶数中位 / 空片单帧 / 2000 次确定性 fuzz / JSON round-trip / includeAllPoints）。生产代码零改动。验证 **`swift test` 314/314（0 failures）＝290+24** + 零诊断。详见 [delta_update 2026-09-21（S3）](file:///Users/mingsen/Project/FallLine/delta_update.md#L17)。

**S4 必须关注（写测试确认的语义）**：混合簇窗（如 10°+70° 同窗）一律保守拒绝 → 弯形快速切换区可能少计，S4 需量化 foldCrossingRate（刻滑样本 >10% 先补有向重建）；IQR 索引分位口径与 §12.12 一致。

**下一步（S4，待确认）**：`swift build -c release` → `--board-edge` 44 片重跑（新 JSON 含 boardTrajectory）；扩展 [lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py) 读 boardTrajectory 出 Gate-G2 margin + LOOCV + 景别残差核对；结果回流 outputs/board_edge_p2/。GO → Phase 3；NO-GO → 激活候选 F（ADR-003）。

## Previous State (2026-09-21 方向 C 时序聚合 S2 接线完成：generateSummary 挂 boardTrajectory，290/290 全绿；下一步 S3 单测)

**刃线/轨迹检测 Phase 2 — §12.15.2 阶段 S2 落地（评分零污染）**：[VideoAnalyzer.generateSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L464-L479) 在 `computeFlowMetrics()` 后、return 前，仅当 `enableBoardEdge` 时调用 `BoardTemporalAxisAggregator.aggregate` 并挂到 VideoSummary 新字段 `boardTrajectory`；稀疏光流方向按精确时间戳对齐全量 results（无匹配 nil，折叠窗保守拒绝）。逐帧 / 评分 / cap / flow / report 零改动，复用 `--board-edge`。验证：`swift build` 过 + **`swift test` 290/290（0 failures）** + 零诊断。详见 [delta_update 2026-09-21（S2）](file:///Users/mingsen/Project/FallLine/delta_update.md#L17) 与 [spec §12.15](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L829)。

**下一步（S3，待确认）**：新增 `BoardTemporalAxisAggregatorTests` ≥14 条；之后 S4 release 44 片 + 扩展 [lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py) 读 boardTrajectory 出 Gate-G2 margin/LOOCV + 景别残差核对。

## Previous State (2026-09-21 方向 C 时序聚合 S1 完成：Models + 纯函数聚合器落地不接线，swift build 通过；下一步 S2 接线)

**刃线/轨迹检测 Phase 2 — §12.15.2 阶段 S1 落地（评分零污染）**：新增时序聚合所需模型与纯函数聚合器，**不接线、不改任何调用方**，`swift build` Build complete（5.99s）+ 零诊断。详见 [spec §12.15](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L829) 与 [delta_update 2026-09-21（S1）](file:///Users/mingsen/Project/FallLine/delta_update.md#L17)：
- [Models.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift) 新增 4 类型（BoardTemporalRejectReason / BoardTemporalAxisPoint / BoardTrajectoryConfigEcho / BoardTrajectoryMetrics），`VideoSummary` 加可选 `boardTrajectory`（默认 nil，后向兼容）。
- [BoardEdgeConfig](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L19-L120) 补 5 时序参数（W=5 / minCount=3 / IQR=5° / fold 20·70）。
- 新增 [BoardTemporalAxisAggregator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardTemporalAxisAggregator.swift)（约 220 行纯函数）：board→conf 1.0 / fallback→合成轴；因果前向窗 ≥3 候选 + IQR≤5°；fold-crossing 用行进方向有向重建，无信号保守拒绝；median/IQR 口径对齐 §12.12；rejectHist 固定语义顺序保证确定性。
- 未跑 `swift test`（无行为变更、聚合器无调用方），留 S2 后连同新单测。

**下一步（S2，待确认）**：在 [generateSummary()](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L371) 仅当 `enableBoardEdge` 时调用聚合器（travelDirections 传 flow 行进方向），挂 summary.boardTrajectory；逐帧 / 评分 / flow / report 零改动。之后 S3 ≥14 条单测、S4 release 44 片 + Gate-G2 裁决。

## Previous State (2026-09-21 方向 C 时序累积重定位：ADR-004 Accepted + 四阶段 spike 计划就绪，Design only)

**刃线/轨迹检测 Phase 2 — 方向 C 时序累积的正式 ADR 与生产级 spike 计划起草完成（本轮零代码变更）**：用户在 v3 FAIL 的三条路径中选择"按候选 D 执行"，本轮把 §12.12 的离线结论**重新定位**并落成 [spec §12.15](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L829)（ADR-004 + spike 计划）。编号说明：ADR-003 保留给候选 F（§12.14），本决策 = **ADR-004**。核心设计：
- **定位翻转（核心）**：时序累积不再以"把 effCov 顶过 Gate-G1"为目标（§12.12 已 NO-GO、§12.13 v3 双 FAIL）；改为产出**刃线连续性时序质量信号**作为 **Gate-G2 新增候选特征**。IQR 稳定性门的 pass/fail 二值序列与连续 pass 段长，正是 Gate-G2 §6 第 3 条点名的"连续弧 / 刃线证据"——§12.12 中被视作"代价"的覆盖率损失，在 Gate-G2 语境下就是**被测物理量本身**。Gate-G1 v3 门槛与 FAIL 结论**不回改、不再松绑**。
- **聚合器设计**：新增纯函数 `BoardTemporalAxisAggregator`（新文件），从全片 `boardEdgeObservation`（board 取 axisAngle / fallback 取 fallbackAxis）做因果前向窗 **W=5（1s）+ minCount=3 + IQR≤5°**，产出 medianAngle/Confidence、源多数派（tie→ankle）、rejectReason；显式处理 PCA unsigned 0–90° 的 **fold-crossing**（有向重建，方向信号不可用则保守拒绝并计 foldCrossingRate）。
- **片级度量 → summary 新字段 `boardTrajectory`（`BoardTrajectoryMetrics`）**：stableWindowRate、longestStableRunFrames/Seconds、stableRunCount/MeanSeconds、stableFrameCoverage、foldCrossingRate、rejectHist、configEcho、帧对齐 points。
- **spike 计划四阶段**：S1 Models + 聚合器（不接线）→ S2 `generateSummary()` 后处理接线（逐帧/评分/flow/report 零改动，复用 `--board-edge`）→ S3 ≥14 条单测（290 基线）→ S4 release 重跑 44 片 + 扩展 [lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py) 读 boardTrajectory 跑 margin/LOOCV + 景别混淆残差核对。
- **验收**：GO = margin≥1.5σ + LOOCV≥90% + 方向正确 + 景别残差通过 + 专业档零误伤 + bit-identical + 性能≈0% → Phase 3 立项；NO-GO = 不可分或被景别解释 → 字段留诊断 + **激活候选 F（ADR-003）**。熔断：`enableBoardEdge` 整体关即可回退。

**最高危风险**：机位 / 景别混淆（§10.2 相机补偿 2.0σ 假 margin 教训），S4 必须做 subjectFraction / farShot 占比 / 机位的残差核对；以及 foldCrossingRate 在已确认刻滑样本上若 >10% 需先补有向重建。

**下一步（待用户确认是否进入 S1）**：按 §12.15.2 阶段 S1 落地 Models + `BoardTemporalAxisAggregator.swift`（不改调用方，`swift build` 通过即可）。

## Previous State (2026-09-20 候选 E v3 44 片 8364 帧实测 → 双门槛结构性 FAIL，三条判定路径待拍板)

**刃线/轨迹检测 Phase 2 — 候选 E v3 44 片重跑收官（评分零污染）**：release CLI（含 ADR-002 默认 `ankleOnly + floor 0.40`）× 3 轮 × 44 片 = 132 次 CLI 全量跑完，[outputs/board_edge_p2/gate_g1_probe_v3.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g1_probe_v3.log) + [outputs/board_edge_p2/gate_g1_probe_v3_summary.json](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g1_probe_v3_summary.json) 回流；spec §12.13 尾追加"v3 44 片 8364 帧实测"小节 + §12.4 检查表 v3 重跑条勾掉。核心数字：
- **总账**：44 片 / 8364 帧 / board 1638 / effV2=effV3 = **2582**（v3 生产默认 `floor 0.40` 未额外剔除任何 fallback 帧，验证 v2/v3 差异只在 pick 策略而非 floor）。
- **Gate-G1 v3 主判定（ADR-002）**：
  - **v3-B**：片级 effCov≥25% 占比 **26/44 = 59.1%** vs 门槛 ≥60% → **FAIL**（差 0.9pp / **1 片**，极临界）；
  - **v3-A**：帧加权可用性（cap 60%）**30.64** vs 门槛 ≥40 → **FAIL**（差 9.36pp，结构性）；
  - **v3 总判定：FAIL**（A/B 二选一）。
- **Gate-G1 v2 对照**：v2-A 22/44 = 50.0% FAIL、v2-B 30.64 FAIL；v2-B 与 v3-A 数字一致（同 cap 60%），差异只在片级 cov 阈值（30% → 25%）。
- **确定性 & 性能**：bit-identical 8364/8364 → **PASS**；perf avg = **1.049**（+4.9%）/ median = 1.050 / max = 1.079，远低于 ≤1.30 → **PASS**。
- **临界桶**（22.1%~24.8% 有 7 片：BND_HI3 22.1 / CAND_M05 21.7 / BND2_H2 22.5 / CAND_G05 23.2 / BND2_LB 23.2 / BND2_H1 23.5 / BND_L3 24.8）：任一片被抬到 ≥25% 即可 PASS，但**不推荐**再下调 v3-B 到 24%（损伤 §12.13 "精度优先" ADR 可信度）。
- **9 片 effV3 < 20% 结构性远景 / 低置信桶**（BND_L1 0 / BND2_L4 7.4 / BND_L2 7.6 / CAND_M09 7.7 / BND2_L2 8.5 / CAND_M01 9.0 / BND2_H3 12.5 / CAND_G07 15.4 / CAND_M08 17.8 / BND_HI2 19.7）：光靠 ankleOnly + floor 无法拉起，需要候选 F CoreML 分割。

**下一步（三条判定路径，等用户拍板；2026-09-21 已拍板 → 用户选"按候选 D 执行"，即方向 C 时序累积重定位，见上 Current；注意：实际 ADR-004 用于时序累积重定位，而非下方路径 3 预想的 Gate-G1 降级，ADR-003 仍保留给候选 F）**：
1. **激活 §12.14 候选 F CoreML spike**：跳出 2D 姿态几何天花板，正式启动 ADR-003 撰写 + CoreMLBackend 实现；
2. **保留 v3 定义不动，走 Gate-G2 直判**：让 `lowend_separability_audit.py`（LOOCV + 1.5σ margin）直接承担"低覆盖率下的可分性证明"；
3. **追加 ADR-004**：显式承认"Gate-G1 v3 FAIL + 走 Gate-G2 直判"路径，把 Gate-G1 判定的必要性从"硬闸门"降级为"可用性观察"。

## Previous State (2026-09-20 候选 E ADR-002 落地 + 候选 F 设计骨架并行，Phase 2 主体准入待 44 片 v3 重跑)

**刃线/轨迹检测 Phase 2 — 候选 E + 候选 F 并行推进（评分零改动）**：候选 E（Gate-G1 v3 门槛松绑）已完成从 spec ADR、探针脚本 v3 双口径、生产默认接线到单测的完整闭环；候选 F（CoreML 板边分割 spike）落地设计骨架。详见 [spec §12.13](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L712) + [§12.14](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L751) 与 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-20（E+F 并行）条：
- **候选 E ADR-002（Accepted）**：Gate-G1 从"覆盖率闸门"翻转为"精度优先的可用性闸门"，fallback 链路收敛到 `ankleOnly + floor 0.40 + W=5 + IQR≤5°`；v3 门槛二选一——v3-A 帧加权可用性 ≥40%（保持）或 v3-B 片级 effCov ≥25% 占比 ≥60%（从 v2-B 30/60 下调）。答辩：§12.10 v2 双微差 + §12.11 GT 三策略 FAIL + §12.12 时序累积 NO-GO 三轮连续 FAIL，只能结构性下调门槛或换视觉信号（候选 F）。
- **生产接线（本轮 Sources 变更）**：[BoardEdgeConfig](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L19-L100) 默认 `fallbackConfidenceFloor: 0.30 → 0.40`、`fallbackPickStrategy: .ankleOnly`；新增 `BoardFallbackPickStrategy` 枚举（`.confMax` 保留 v2 语义、`.ankleOnly` 是 v3 默认）；`synthesizeFallback` 按策略 switch 决定膝对是否参与，其余逻辑不变。生产帧级 `boardEdgeObservation` **不叠加时序聚合**（W=5/IQR≤5° 只在离线 [board_edge_fallback_temporal_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_fallback_temporal_spike.py) 用）。
- **探针脚本 v3 升级**：[board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py) 引入 `FALLBACK_CONFIDENCE_FLOOR_V3=0.40` / `GATE_G1_V3_CLIP_COV=25.0` / `GATE_G1_V3_CLIP_RATIO=0.60` / `GATE_G1_V3_WEIGHTED=40.0` / `GATE_G1_V3_WEIGHTED_CAP=60.0`，v3-A/B 双口径判定，保留 v2 对照。
- **单测（e4 收官）**：[BoardEdgeDetectorTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardEdgeDetectorTests.swift) 修复因默认策略变更失效的 5 个 v2 用例（显式传入 `confMax + floor 0.30` 还原语义），新增 4 条 ADR-002 用例（默认基线、ankleOnly 跳过更强膝对、ankleOnly 踝缺失结构性拒绝、floor 0.40 边界拒绝且 v2 对照通过）；`swift test` 全量 **290/290 通过**（Phase 1+ADR-001 基线 285 + 本轮 +5）。
- **候选 F 设计骨架（Design only）**：[§12.14](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L751) 落 4 模型对比表（DeepLabV3+ MobileNetV2 / U-Net tiny / SAM2 tiny / YOLOv8-seg nano，初选 YOLOv8-seg nano 或 DeepLabV3+）、GT 标注方案（100–300 帧板身像素级 mask，~4 人时）、6 条决策标准（IoU ≥0.65、推理 ≤20ms、GT 准入 ≥90%、farShot 恢复率 ≥50%、bit-identical、总人力 ≤20 人时）、成本预算与决策路径（v3+Gate-G2 通过则降级到 Phase 3+；v3 通过 Gate-G2 失败则升到 P0）。新增 [scripts/board_edge_coreml_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_coreml_spike.py) 骨架脚本（`NoopBackend` 占位、`--check-plan` 打印 §12.14 决策标准、`--list-clips` 与 v3 探针共用 44 片、`--model` 参数留位但显式退出码 2 → 未实现），**不引入模型二进制、不改 [Package.swift](file:///Users/mingsen/Project/FallLine/Package.swift)**。
- **验证**：`swift test` 全量 290/290 通过；Sources 变更集中在 [BoardEdgeDetector.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift) 默认参数与 fallback 分派（评分零污染，`boardEdgeObservation` 仅诊断），Models 消费方零改动。
- **下一步（待用户决策）**：① 用 v3 版探针脚本对 44 片重跑，出 v3-A / v3-B 判定表（探针已就绪，等 CLI 8364 帧实跑）；② 判定 PASS 则进 Gate-G2（用新特征跑 `lowend_separability_audit.py`，margin ≥1.5σ / LOOCV ≥90%）；③ 判定 FAIL 则激活候选 F spike。

## Previous State (2026-09-20 候选 D 时序累积离线 spike NO-GO：Phase 2 主体前置候选缩到 E / F 二选一)

**刃线/轨迹检测 Phase 2 — 候选 D 收官（评分零改动）**：完成 §12.11 下一步「候选 D 方向 C 时序累积」离线 spike，全 44 片 × 3 策略 × 3 floor × {1,5,7} 窗 × {5°,8°,∞} IQR = **81 组合扫描**，结论 **NO-GO**——时序聚合确实能把散点误差压掉（准入 87.2% → 91.2% 最好），但代价是窗口候选帧数腰斩，v2-A/B 反而更差。详见 [spec §12.12](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L663) 与 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-20（尾段）条：
- **新脚本 [board_edge_fallback_temporal_spike.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_fallback_temporal_spike.py)**（约 220 行，纯 stdlib）：复用 §12.11 [fallback_gt_cache.json](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/fallback_gt_cache.json)，前向 W 帧滑窗 + 中位滤波 + IQR 稳定性门控（通过条件：候选数 ≥ ⌈W/2⌉ 且 IQR ≤ 门限）；对 board 帧用 [f-W, f-1] 前向窗聚合与 `ba` 比误差；W=1 作 baseline 校准（与 §12.11 单帧数字逐位一致）。**不重跑 CLI、不改生产代码**。
- **最强组合**：`ankleOnly + floor 0.35 + W=5 + IQR≤5°` → 准入 **91.2%** ✅ 但 GT 帧只有 57、effCov **26.90%**、v2-A **40.9%** / v2-B **26.76**（门槛 60% / 40）。所有 81 组合均"GT 过 / v2 差"或双差，**无一同时通过**。
- **关键洞察**：① 时序累积机理有效（准入首次过 90%），但门控天然把 60% 候选帧剔了；② effCov 从 35% 掉到 25–27%，v2 双门槛更远；③ W=7 全线劣于 W=5（更严 → 更少 GT）；④ 短片风险 = 0（W=1/5/7 三档下 0/44 片帧数 < W），失败原因不是"短片没窗口"，是**几何精度天花板 vs Gate-G1 v2 40/60 门槛的结构性矛盾**。
- **回流回落 [fallback_temporal_spike.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/fallback_temporal_spike.log)**（.gitignore，96 行 = 81 组合 + 8 行短片索引 + 表头）。
- **验证**：本轮零 Sources / 生产代码变更（仅新增脚本 + spec §12.12 / §12.4 检查表 / 首行状态 + WORK_LOG + delta_update）；`py_compile` 通过；`swift test` 未跑（无 Sources 变更，Phase 1+ADR-001 285 通过基线不变）。
- **下一步（二选一，等确认）**：① **候选 E Gate-G1 v3 口径松绑**——接受 v2 数字下移，在 §6 落 ADR-002 v3-A ≥40% / v3-B ≥25，可直接以 `ankleOnly + floor 0.40 + W=5 + IQR≤5°` 通过；需先答辩「覆盖率不再是主指标」。② **候选 F CoreML 板边分割 spike**——不再在 2D 姿态几何天花板下叠加规则，另起视觉信号；投入产出未知。**不再建议**：候选 D 独立推进（本轮已证）、fallback 规则再迭代（§12.11 已扫尽 24 组合，§12.12 又证时序聚合触到同一天花板）。

## Previous State (2026-09-20 fallback GT 精度小闸门收官：三策略结构性 FAIL，Phase 2 主体前置需在 §6 三选一)

**刃线/轨迹检测 Phase 2 — GT 小闸门定谳（评分零改动）**：完成 §12.10 下一步①闭环，全 44 片 8364 帧三策略 × 八 floor GT 小闸门跑通，结论**结构性 FAIL**——不是 floor 或 pick 策略问题，是 2D 踝对作为板轴代理的几何精度天花板。详见 [spec §12.11](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L617) 与 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-20（下半段）条：
- **脚本升级 [board_edge_fallback_gt_gate.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_fallback_gt_gate.py)**：从 bodyPose 关键点精确复现 [synthesizeFallback](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift#L232-L300) 后与生产 JSON 逐位交叉验证（1332/1332 OK）；引入 JSON 缓存（[fallback_gt_cache.json](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/fallback_gt_cache.json)，按视频+binary mtime/size 失效）+ 三策略模拟（confMax=生产现状 / anklePreferred / ankleOnly），policy×floor 组合切换 0 CLI 重跑。首跑 25 分钟，后续瞬时。
- **三策略结果（board 帧 pick↔真实 board 角配对；参照 GT）**：
    - confMax（生产）：med **3.75°** PASS / 准入 **85.1%** FAIL；选踝 89.9% vs 选膝 55.3%——**膝对是准入拖累主力**（弯中双膝内扣 5–15° 系统性偏差）。
    - anklePreferred（踝 conf≥0.40 优先）：med 4.00° / 准入 82.9%，反而更差。
    - ankleOnly（丢弃膝对）：med **3.53°** / 准入 **87.2%**——三者最好但仍差 90% 门槛 2.8pp。
- **floor 扫描（confMax 0.30 → 0.70）**：精度-覆盖率强负相关，两端够不到：floor 0.30 时准入 92.2%（GT 单项过）但 v2-A 56.8% / v2-B 34.9 双差；floor 0.40 准入 94.4% 但 v2-A/B 崩到 50% / 30.7；floor 0.70 准入 98.2% 但 v2-B 只有 22。**无 floor+pick 组合可同时过关**。
- **回流回落 [fallback_gt_gate_44.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/fallback_gt_gate_44.log)**（.gitignore）：三策略 × 8 floor = 24 组合日志齐全。
- **验证**：本轮零 Sources / 生产代码变更（仅脚本升级 + spec §12.11 + WORK_LOG + delta_update）；`py_compile` 通过；`swift test` 未跑（无 Sources 变更，Phase 1+ADR-001 285 通过基线不变）。
- **下一步（三选一，等确认）**：① **候选 D 方向 C 时序累积**——连续 ≥5 帧稳定合成轴 + 中位滤波，把 [0.30, 0.40) 桶的散点误差压下去；风险是短片窗口缺样。② **候选 E Gate-G1 v3 口径松绑**——接受 v2 数字下移，在 §6 落 ADR-002 把门槛调到 v3-A ≥50% / v3-B ≥30；需先答辩「为什么覆盖率不再是主指标」。③ **候选 F CoreML 板边分割 spike**——ADR-001 Consequences 已列作 fallback FAIL 后备选，先小规模投入产出评估。三条路线互斥，先决策后进 Phase 2 主体。

## Previous State (2026-09-20 方向 A 实现闭环：44 片 v2 度量完成——确定性/性能 PASS，v2-A/B 微差 FAIL，等 GT 精度校准)

**刃线/轨迹检测 Phase 2 — fallbackAxis 落地 + 全量度量（评分零改动）**：ADR-001 ①–④ 前半已实现并度量，详见 [spec §12.10](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L586) 与 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-20 条：
- **已落地**：Models（FallbackAxis/BoardFallbackSource/.fallback，Codable 双向兼容）；BoardEdgeDetector `detect()` 分派 + `synthesizeFallback` 双源纯函数（踝对 1.0 / 膝对 0.6，取高者；三级门控）；overlay board 青轴/fallback 黄轴；两探针脚本 v2 口径。**全量 285 测试通过**，release 重建通过。
- **44 片 / 8364 帧结果**：raw board **19.58%**（与 v1 逐位一致，重构无污染）；effective（board+fb≥0.30）**35.51%**（救回 1332 帧，+15.93pp，其中 farShot 回流占 67.7%）；确定性 **8364/8364 bit-identical** PASS；性能 avg **+4.51%** / max +7.56% PASS。
- **Gate-G1 v2 判定：FAIL（微差）**——v2-A 片级 effCov≥30% 占比 **25/44=56.8%**（门槛 60%，差 2 片）；v2-B 帧加权可用性 **34.90**（门槛 40，差 5.1）。当前为 GT 精度小闸门之前的乐观上界，正式数字只会更低。CAND_G05 29.5%/BND2_TOP 29.2% 压线。
- **下一步（等确认）**：① fallback GT 精度小闸门（同帧 board vs fallback 角度：中位误差 ≤12°、精度 ≥90%），据结果校准 floor；② GT 后重判 v2-A/B，仍 FAIL 则按 ADR-001 回 §6 重评（方向 C 时序 / CoreML），不放宽门槛；③ Gate-G1 过才进 Gate-G2。

## Previous State (2026-09-19 方向 A 设计闭环：ADR-001 Accepted + fallbackAxis 实现规格定稿)

Gate-G1 v2 决策与降级链路实现规格定稿（评分零改动，仅文档），落在 [spec §12.9](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L483)，§6 同步 v1/v2 双口径：ADR-001 Accepted（v2 = 降级后有效帧 + 片级可用性二选一；fallback 进统计前先过 GT 精度小闸门）；几何勘误（板长轴一阶=双踝连线、二阶=双膝连线 0.6 权重，confidence=点 cnf×min(间距×12,1)×源权重）；数据模型与 Codable 兼容方案定稿；实施顺序 ① Models+纯函数+单测 → ② Detector 接线 → ③ overlay → ④ GT 校准+44 片度量 → ⑤ 回写。

## Previous State (2026-09-19 Batch 3 档位回填闭环：全 44 片 audit 证伪"只改门槛"，下一步 = A 降级链路)

**刃线/轨迹检测 Phase 2 — Batch 3 回填 + 全量 audit（评分零改动）**：19 张接触表判档回填完成，边界集 25 → **44 片全部有教练档位**；全量 reason audit 第三次复现 ~20% 覆盖率，并证伪 §12.6 方向 B（门槛重定义）可单独成立。详见 [spec §12.8](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L458) 与 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-19 条：
- **回填结果（[Batch 3 表](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md#L153)）**：专业 10 / 高质量 1 / 中级偏上 5 / 中级 1 / 初级 2；确认刻滑 11 片。典型错档：B01 算法 75→中级纠错片（踮脚尖、片中摔倒）、M09 61→初级放板（bestThird 抬高）、M01 calf 6.7 坐实初级。两脚本 CLIPS 的 `tbd` 已全部换成实际 group（high=专业/高质量刻滑、mid=中级/中级偏上、low=初级）。
- **全 44 片 audit（8364 帧，`outputs/board_edge_p2/reason_audit_44.log`，.gitignore）**：board **19.58%**（25 片 19.56% → 19 片 19.61% → 44 片 19.58%，三度复现）。分档：high board18%/farShot38%/noMask9%；mid board26%/rejectVertical+rejectLength 各 8%；low board16%/rejectOwnership6%。
- **新负结论**：方向 B 两个重定义门槛在 44 片上同样 FAIL——片级 cov≥30% 占比实测 **27.3%**（门槛 60%）、加权可用性 **19.4%**（门槛 40%，因片 cov 均 <60% 而数学退化为普通覆盖率）。**"只改统计口径"证伪，方向 A 降级链路（ankleProxy 几何合成 fallbackAxis，覆盖 farShot/ankleLowCnf/noMask 合计 64.4% 拒绝帧）成为 Gate-G1 v2 唯一前置**。
- **验证**：本轮零 Sources 变更（19 行标注回填 + 两脚本 CLIPS/group 文案 + 三份文档）；2 个 py 脚本 `py_compile` 通过；release binary 不变，`swift test` 未跑（Phase 1 274 通过基线不变）。

## Previous State (2026-09-18 §4.4 第三批扩边界集：19 片算法列 + Gate-G1 预跑完成，等教练看接触表回填档位)

**刃线/轨迹检测 Phase 2 — 扩边界集（评分零改动）**：把 Phase 2 起步 1 的 19 片接触表候选池（good 8 / middle 10 / bad 1）一次性纳入 §4.4 第三批。算法列已用当前 release 重跑填齐，**教练档位 / 稳定刻滑两列留空，正在看接触表回填**。详见 [calibration_anchors.md Batch 3](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md#L153) 与 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-18 第三批条：
- **新脚本 [scripts/board_edge_batch3_extract.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_batch3_extract.py)**（纯 stdlib，约 200 行）：19 片跑当前 release 基线 CLI，提取综合分 / edge(conf) / pressure / calf / knee / sideslip / carvingCnf / 时长；calf/knee 按 [StageClassifier.averageSubScores](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/StageClassifier.swift#L24-L39) 口径（可靠姿态帧 totalConfidence 加权），旧片校验 knee 精确复现、calf 有 ~1.5 版本微漂（score=92 精确对齐）；G07=86/edge60.8/calf48.2 与 GOOD_A 锚点完全一致，佐证口径对齐。产物 `outputs/board_edge_p2/batch3_extract.log` + `batch3_json/<alias>.json`（.gitignore）。
- **算法列初步观察**：弱先验分与当前 release 偏差大（G02 72→**93**、M01 67→**55** calf 仅 6.7、M05 74→**93**），hint 不可作档位；12/19 落专业带、calf≥48 达 14 片，候选池偏高姿态质量，回填时需重点核对是否真专业刻滑，防 Gate-G2 高端密度虚高。
- **Gate-G1 预跑（[board_edge_reason_audit.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_reason_audit.py) group=tbd，spec §12.7）**：19 片 4218 帧 board 覆盖率 **19.61%**，与旧 25 片 **19.56%** 几乎逐位相同——两个独立候选池同得 ~20%，**坐实 60% 门槛结构性不可达、非抽样偶然**，再次支撑 §12.6 方向 B/A（门槛重定义 + 降级链路）。第三批 reason：farShot 37.2% / ankleLowCnf 22.1% / **noMask 7.6%（升为第三大项，G02 59% 前景分割失败）** / rejectVertical 仅 0.71%（二度证伪放宽夹角门控）。片级高覆盖：M06 56% / G06 48% / M10 44% / B01 41%。
- **探针 CLIPS 已扩到 44 片**：[gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py) 与 [reason_audit.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_reason_audit.py) 新增 19 片 group=`tbd`（不与 high/mid/low 混桶，audit 已改为动态 group 排序）。回填后把 tbd 换成实际档位即可重跑，覆盖率数字不随档位变。
- **验证**：本轮零 Sources 变更（新脚本 + 文档 + 探针 CLIPS）；release build 通过；3 个 py 脚本 `py_compile` 通过；`swift test` 未跑（无生产代码变更，Phase 1 274 通过基线不变）。
- **下一步（等教练回填）**：① 看 `outputs/board_edge_p2/contact_sheets/<alias>.jpg` 回填 §4.4 第三批 19 片档位/刻滑；② 我把两脚本 group=tbd 改成实际档位，重跑 reason audit 补分档对比；③ 全 44 片重跑 Gate-G1 三合一确认确定性/性能仍 PASS、覆盖率按方向 B 片级口径统计；④ 回写 §12.7 / WORK_LOG / delta_update。

## Previous State (2026-09-18 Phase 2 起步 3 完成：Gate-G1 reason audit 翻转下一步方向，证伪"放宽板轴门控"路线)

**刃线/轨迹检测 Phase 2 起步 3（评分零改动）**：Gate-G1 reason 分布 audit 脚本落地并对 §4.4 全 25 片跑通，输出**"下一步方向翻转"**的关键负结论——§12.5 结尾曾把"放宽 `farShot=0.02→0.01` / `rejectVertical=45°→55°`"作为覆盖率修复主方向，本轮 audit 证伪：`farShot` 29.8% 是最大项符合猜测，但 **`ankleLowCnf` 27.6% 与 `farShot` 量级相当**且是完全独立的踝点定位问题，`rejectVertical` 仅 4.8% 远低于预期，即使把两个板轴几何门控完全砍掉理论覆盖率上限也只到 54%，够不到 60%。详见 [spec §12.6](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L415) 与 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-18（Phase 2 起步 3）条：
- **新脚本 [scripts/board_edge_reason_audit.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_reason_audit.py)**（约 210 行，纯 stdlib）：单轮 CLI（`--board-edge`），按 [`BoardEdgeStatus`](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L594-L617) 11 枚举做分片直方图，聚合出全集总账 + 分档位 high/mid/low + 每片最大拒绝路径 + Top-5 拒绝路径；不做 bit-identical / 耗时对比（已在 §12.5 PASS）。支持 `ONLY=<alias>,...` 与 `-n <k>`。
- **25 片全量 Top-5 拒绝路径**（4146 帧口径）：`farShot` 29.76% / `ankleLowCnf` 27.59% / `rejectLength` 5.79% / `rejectVertical` 4.80% / `noMask` 4.51%。
- **分档位对比**：high 桶 farShot 42% + ankleLowCnf 28%（远拍专业滑手）；mid 桶 ankleLowCnf 28% + rejectVertical 14% + rejectLength 10%（中间地带踝点 + 板轴几何双失）；low 桶 farShot 27% + ankleLowCnf 25% + rejectOwnership 7%（雪场群拍背景他人板/裤腿）。
- **每片最大拒绝路径归类**（25 片）：`ankleLowCnf` 主导 **12 片**（近半样本，含 BND_L1 66%/BND_M3 65%/BND2_L4 63%/BND2_LB 57%/BND_HI2 57%）；`farShot` 主导 **7 片**（BND_HI1 74%/BND2_L6 63%/BND_HI3 62%）；`rejectOwnership` 主导 2 片；`rejectVertical` 主导仅 1 片（BND_M2 25%，全集唯一）；`noMask`/`rejectBlob` 各 1 片；1 片纯 board。
- **Phase 2 主体方向重定义**（[spec §12.6](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L439)）：**A 降级链路** — 在 `status ∈ {ankleLowCnf, farShot, noMask}` 时用踝-膝矢量 + 髋高度合成 `boardEdgeObservation.fallbackAxis`（复用 [`BoardObservationSource.ankleProxy`](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L555-L557)），不新增模型推理；**B Gate-G1 门槛重定义** — 从全帧口径 ≥60% 改为"每片可用性 = min(cov%, 60%)，加权 ≥40%" 或 "片级 cov% ≥30% 占比 ≥60%"（当前 7/25=28%），需在 §6 落 ADR；**C 时序特征以连续 board 片段为输入** — 要求"连续 ≥5 帧板轴稳定"窗口，BND2_L1/LM/L3/M4/L5 5 片已具备。
- **不建议做的方向**：**放宽 `farShot / rejectVertical` 阈值不再是下一步选项**（收益 <5% + 引入远景假阳/雪杖误识 + Phase 0 §10.4 已决策拒绝）。
- **产物**：[outputs/board_edge_p2/reason_audit.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/reason_audit.log)（`.gitignore` 已排除，25 片单轮日志）。
- **Gate-G1/G2 前置检查表**（[spec §12.4](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L387)）：✅ 接触表脚本 ✅ Gate-G1 三合一探针 ✅ 跨次 bit-identical ✅ 耗时 ≤+30% ✅ reason audit（本轮） ⬜ ADR "覆盖率不是唯一门槛" + 降级链路 A ⬜ 候选池 ≥9 片教练判档回流 ⬜ §4.4 扩到 ≥20 ⬜ Gate-G2 margin ≥1.5σ / LOOCV ≥90%。
- **验证**：本轮零生产代码改动（仅新增 audit 脚本 + 更新 spec/WORK_LOG/delta_update）；release binary 已存在（同 Phase 2 起步 2 一致），`swift test` 未跑（无 Sources 变更），Phase 1 274 通过基线不变。
- **下一步（未开始，等确认）**：① 在 spec §6 落 ADR "Gate-G1 覆盖率不是唯一门槛，v2 门槛 = 降级链路后覆盖率 + 片级可用性下限"；② 起草 `BoardEdgeObservation.fallbackAxis` Codable 后向兼容改造（评分零改动，只加字段）；③ Phase 2 主体开工。

## Previous State (2026-09-18 Phase 2 起步 2 完成：Gate-G1 三合一探针跑通 25 片，确定性/性能 PASS、覆盖率 FAIL 待扩集+门控调参)

**刃线/轨迹检测 Phase 2 起步 2（评分零改动）**：Gate-G1 三合一探针脚本落地并对 §4.4 全 25 片跑通，输出**确定性 / 性能双 PASS、覆盖率 FAIL** 的负结论。详见 [spec §12.5](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L401) 与 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-18（Phase 2 起步 2）条：
- **探针脚本已落地**：[scripts/board_edge_gate_g1_probe.py](file:///Users/mingsen/Project/FallLine/scripts/board_edge_gate_g1_probe.py)。每片 CLI 跑三轮：`--board-edge` × 2 + 基线 × 1；从 JSON `boardEdgeObservation` 逐帧提取 status/reason，同时算 ①**覆盖率** = `status=board` 帧数 / 总帧数 ②**确定性** = 两轮 `--board-edge` 逐帧 `board_flag / axis_angle_deg / axis_length_norm / confidence / near_body_shape / obs_confidence / reason` bit-identical ③**性能** = `--board-edge` 均耗时 / 基线耗时。支持 `ONLY=<alias>,...` 单片过滤、`-n <k>` 前 k 片抽样。
- **25 片全量结果**：
    - 覆盖率：全帧口径 **811/4146 = 19.56%**（Gate-G1 门槛 ≥60%）→ **FAIL**；片级 ≥60% 仅 **1/25**（BND2_L1 = 75%，其次 BND2_LM 57% / BND2_L3 50%）。
    - 确定性：**4146/4146 = 100%** bit-identical → **PASS**。
    - 性能：`--board-edge` 开对总耗时 **avg +5.9% / median +5.2% / max +19.7%**（门槛 ≤30%）→ **PASS**。
- **Gate-G1 结论**：**确定性 & 性能达到 Phase 2 主体准入水位；覆盖率不达标属"门控阈值层面的负结论"，不是可靠性问题**。BND2_L1 75% / BND2_LM 57% 证明近景初级/中级雏形可稳定输出板轴；BND_L1 = 0/103（金色夕阳远景）与 [outputs/edge_spike/](file:///Users/mingsen/Project/FallLine/outputs/edge_spike) 一致（诚实拒绝，符合 §11 P1 "默认关、纯诊断"），主要拒绝路径是 `farShot` + `rejectVertical`，正是需要 Phase 2 时序特征补齐的场景。
- **产物**：[outputs/board_edge_p2/gate_g1_probe.log](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/gate_g1_probe.log)（`.gitignore` 已排除），CLIPS 表初版三片错定位到 `video/good/` 已修正为 `video/middle/`（BND_HI1-3）。
- **Gate-G1/G2 前置检查表**（[spec §12.4](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L387)）：✅ 接触表脚本 ✅ Gate-G1 探针脚本 ✅ 跨次 bit-identical ✅ 耗时 ≤+30% ⬜ 候选池 ≥9 片教练判档回流 ⬜ §4.4 扩到 ≥20 ⬜ 覆盖率 ≥60% ⬜ 时序特征 JSON 独立命名空间 ⬜ Gate-G2 margin ≥1.5σ / LOOCV ≥90%。
- **验证**：本轮零生产代码改动（仅新增探针脚本 + 更新 spec/WORK_LOG/delta_update）；`swift build -c release` 通过（15.46s），`swift test` 未跑（无 Sources 变更），Phase 1 274 通过基线不变。
- **下一步（未开始，等确认）**：① reason 分布 audit（`farShot` / `rejectVertical` / `axisTooShort` / `elongTooLow` 分片直方图，量化最大拒绝路径）；② 结合 §12.2 优先次序回流 9 片教练判档 → §4.4 扩到 ≥34 → 重跑探针；③ 或改按"每片可用性 = min(cov%, 60%)"重定义 Gate-G1 门槛（须在 spec §6 决策）；④ 覆盖率闭环后进 Phase 2 主体（时序特征 + Gate-G2）。

## Previous State (2026-09-18 Phase 2 起步 1 完成：19 片候选池接触表已生成，等待教练判档回流)

**刃线/轨迹检测 Phase 2 起步 1（评分零改动）**：接触表脚本落地并对 19 片候选池全跑通。详见 [spec §12.3](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L379) 与 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-18（Phase 2 起步 1）条：
- **接触表脚本已落地**：[scripts/p2_candidate_contact_sheets.swift](file:///Users/mingsen/Project/FallLine/scripts/p2_candidate_contact_sheets.swift)。沿用 [p0_board_axis_dense_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_board_axis_dense_spike.swift) 的 Vision bodyPose + foregroundInstanceMask + 踝下 ROI PCA + `BoardEdgeConfig.standard` 门控（`G_MIN_LEN=0.07`）。每片一张 5×2 拼图（10 均匀抽帧 0.08–0.92），每帧 300×533，绘 ROI 黄框 + 板轴（board=绿 / rejected=红）+ verdict/cnf/subj/ang/elong/L 状态文本 + 顶栏 hint/score/命中计数。支持 `ONLY=<alias>,...` 单片过滤，纯 Swift、无 ffmpeg。
- **19 片全跑通命中率**（`verdict==board`/10）：good 桶 21/80=26%（G06=7 最优、G05=0 需目检）；middle 桶 11/100=11%（M03/M05/M08=0，中间地带主要被 farShot/rejectVertical 拒）；bad 桶 B01=5/10=50%。整体 37/190≈19%。middle 覆盖率显著低于 Phase 0 主 corpus 5-6/10，符合"中间地带远景 + 站姿飘忽"的先验，正是需要教练判档 + Phase 2 时序特征补齐的场景；此批接触表**不能**当 Gate-G1 覆盖率证据（后者需 `--board-edge` 5fps 全帧生产口径统计）。
- **产物**：[outputs/board_edge_p2/contact_sheets/](file:///Users/mingsen/Project/FallLine/outputs/board_edge_p2/contact_sheets) 19 张 JPG（`.gitignore` 已排除，不入库；教练本地看图 + 回流后再删）。目检 CAND_M06 拼图：绿轴精确覆盖 #2/#3/#4 板身，rejectLength/farShot 状态文字清晰、无误画青轴。
- **候选池 & 优先次序（沿用上轮盘点）**：good 8 / middle 10 / bad 1，共 19 片，教练至少判 9 片以扩边界集 n=11→≥20。3 桶信息增益优先次序：中间地带 60–70 分 4 片、专业候补 2 片、中偏上 72–78 3 片。
- **Gate-G1/G2 前置检查表**（[spec §12.4](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L387)）：✅ 接触表脚本落地 → ⬜ 候选池 ≥9 片教练判档回流 → ⬜ §4.4 表扩到 ≥20 → ⬜ CLI `--board-edge` 覆盖率 ≥60% (G1) → ⬜ 跨次 bit-identical + 耗时 ≤+30% (G1) → ⬜ 新特征 margin≥1.5σ 且 LOOCV≥90% (G2)。
- **验证**：本轮零生产代码改动（仅新增脚本 + 更新 spec/WORK_LOG/delta_update）；`swift build`/`swift test` 未跑（无 Sources 变更），Phase 1 274 通过基线不变。
- **下一步（未开始，等教练回流）**：教练判档后同步扩 §4.4 边界表 + [bestthird_aggregator_audit.py CLIPS](file:///Users/mingsen/Project/FallLine/scripts/bestthird_aggregator_audit.py#L38-L64) + [lowend_separability_audit.py BEGINNER/EMERGING](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py#L41-L42)，再启动 Phase 2 主体（时序特征 + Gate-G1/G2）。

## Previous State (2026-09-18 Phase 2 起步：扩样候选池已盘点入 spec §12，等待教练判档回流)

**刃线/轨迹检测 Phase 2 起步（评分零改动）**：Phase 1 观测器已上线（默认关、纯诊断），本轮完成 Phase 2 前置的扩样盘点与 spec 更新。详见 [spec §12](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L339) 与 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-18（Phase 2 起步）条：
- **候选池盘点**：[video/](file:///Users/mingsen/Project/FallLine/video) 库 44 片视频，已标注 25 片（BND* + BND2_* 见 §4.4），剩余 **19 片候选池**未打教练档位。分布 good 8 / middle 10 / bad 1；扩集目标 n≥20 至少需教练判 9 片。
- **优先次序**（信息增益 3 桶）：中间地带 60–70 分 4 片（对低端 cap 最有信息量）、专业候补 2 片（v0200…d7r0017=GOOD_A、96001e… 2026-05 已认专业但未入 §4.4）、中偏上 72–78 3 片（中级/专业过渡带补密）。
- **接触表脚本待落地**：[scripts/p2_candidate_contact_sheets.swift](file:///Users/mingsen/Project/FallLine/scripts/p2_candidate_contact_sheets.swift)，沿用 [p0_board_axis_dense_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_board_axis_dense_spike.swift) 的 AVAssetImageGenerator + Vision + `BoardEdgeDetector` 生产链路 + [p0_gt_contact_sheets.py](file:///Users/mingsen/Project/FallLine/scripts/p0_gt_contact_sheets.py) 的 5×2 拼图布局，纯 Swift、无 ffmpeg 依赖；产物写 `outputs/board_edge_p2/contact_sheets/`（`.gitignore` 已排除）。
- **Gate-G1/G2 前置检查表**（[spec §12.4](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md#L386)）：候选池 ≥9 片教练判档回流 → 边界集扩到 ≥20 → CLI `--board-edge` 覆盖率 ≥60% (G1) → 跨次 bit-identical + 耗时 ≤+30% (G1) → 新特征重跑 [lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py) margin≥1.5σ 且 LOOCV ≥90% (G2)。
- **验证**：本轮零代码改动，仅 spec/WORK_LOG/.gitignore；`swift build` 与 `swift test` 未跑（无 Swift 变更），Phase 1 冒烟结果不变。
- **下一步（未开始，等确认）**：① 落 [p2_candidate_contact_sheets.swift](file:///Users/mingsen/Project/FallLine/scripts/p2_candidate_contact_sheets.swift) 生成候选池 19 片接触表 JPG；② 教练判档回流后同步扩 §4.4 表 + [bestthird_aggregator_audit.py CLIPS](file:///Users/mingsen/Project/FallLine/scripts/bestthird_aggregator_audit.py#L38-L64) + [lowend_separability_audit.py BEGINNER/EMERGING](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py#L41-L42)；③ 再进 Phase 2 主体（时序特征 + Gate-G1/G2）。

## Previous State (2026-09-18 Phase 1 完成：生产级板身刃线观测器落地，默认关、纯诊断、零评分接触，可进 Phase 2)

**刃线/轨迹检测 Phase 1 本轮完成：把候选 A（前景分割 + 踝下 ROI PCA）从离线原型升级为生产代码并接入分析管线与 CLI/overlay。全程不改评分、聚合器、报告结构与 iOS UI；默认关闭，仅 `--board-edge` 显式开启时产出诊断观测。详见 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-18（Phase 1）条**：
- **新增 [BoardEdgeDetector.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/BoardEdgeDetector.swift)**：`BoardEdgeConfig`（阈值公开，`.standard` = Gate-G0 校准值 `minAxisLength=0.07`）+ `AxisGeometry`（纯数值，Equatable）+ `BoardEdgeDetector.detect`。落实 Phase 0 两条必修：**实例归属校验**（姿态框 vs 前景实例框 IoU，≥0.15 取最高，否则 rejectOwnership）、**站姿状态门控**（躯干倾角 + 髋高于踝，摔倒/坐姿 rejectPosture）。门控链 ankleLowCnf→noMask→rejectOwnership→farShot(<0.02)→rejectPosture→noAxis/rejectVertical(>45°)/rejectLength/rejectBlob(<2.0)→board。
- **模型/管线**：[Models.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift#L594-L661) 新增 `BoardEdgeStatus`(11 态) 与 `BoardEdgeObservation`(归一几何、Codable、字段钳制)，`DetectionResult` 加可选字段；[VideoAnalyzer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L343-L354) 加 `enableBoardEdge`(默认 false)/`boardEdgeConfig`，同帧检测且**诊断失败局部隔离**（`try?`→.noMask，不拖垮姿态帧）；[PoseSmoother.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseSmoother.swift) 三处重建透传该字段。
- **CLI / overlay**：[main.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI/main.swift) 新增 `--board-edge`；[DebugOverlayRenderer.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI/DebugOverlayRenderer.swift#L359-L380) 对 board 帧画青色板轴。
- **验证**：新增 [BoardEdgeDetectorTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardEdgeDetectorTests.swift) 21 用例；`swift build` 通过；`swift test` 全量 **274 通过 0 失败**（基线 253 + 21）。真实冒烟 `testvideo/1.MP4`：farShot 92 / rejectLength 10 / **board 8** / ankleLowCnf 6 / rejectVertical 1，8 个 board 轴角 3.4–10.4°、elong 4.6–8.4，与 Phase 0 GT 一致；debug-overlay 目检青色轴精确落在真实雪板上。
- **下一步（未开始，等确认）**：**Phase 2 弯形/刃线跨弯时序特征**（板轴方向序列 + 轨迹曲率 + 速度-方向耦合），在边界集上以 **Gate-G2（margin≥1.5σ + LOOCV≥90%）** 验证；前置中优先**扩边界集 n=11→≥20**（盘点候选池 + 接触表供教练标注）。远景帧继续诚实输出不可用。Gate-G2 通过前不接触评分。

## Previous State (2026-09-18 Phase 0 Gate-G0 通过：板轴几何 A 路 go，相机补偿 C1 路 no-go)

**刃线/轨迹检测立项的 Phase 0 离线可行性验证：110 帧（11 片 × 10 均匀抽帧，AVAssetImageGenerator 精确取帧）+ 逐帧人工 GT，生产代码与评分零改动。结论 Gate-G0 = PASS（A 路成立），详见 spec §10 与 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-18（Phase 0）条**：
- **候选 A（foreground mask + 踝下 ROI PCA 板轴）GO**：[p0_board_axis_dense_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_board_axis_dense_spike.swift)。近景门控子集 52/110 帧；Gate-G0 三指标——①**检出率 73%**（`G_MIN_LEN` 从先验 0.10 按 GT 校准到 **0.07**：放行 38/52，新增 10 帧逐帧核对全真板；0.10 口径 54%）；②**角度中位目测误差 ≤8°**（28 board 绝大多数 ≤5°，全部 ≤10°，阈值 ≤12°）；③**门控精度 100%**（28 board 全在近景子集，非近景 58 帧 0 误放；rejectVertical 成功拦雪杖/裤腿/竖直他人）。**零硬假阳**，远景（金色夕阳/雪雾）诚实输出不可用。两处 Phase 1 必修：实例归属校验（L5#7 的 28° 轴对准背景中他人板，物理真板但错对象）、站姿状态联合门控（LB 摔倒/坐姿帧板轴不代表刃线质量）。
- **候选 C1（相机补偿 + 踝轨迹弯形）NO-GO**：全图配准 [p0_camera_registration_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_camera_registration_spike.swift) 成功率 75–100%，背景掩膜版 [p0_camera_registration_bg_spike.swift](file:///Users/mingsen/Project/FallLine/scripts/p0_camera_registration_bg_spike.swift) 70–100%，两版向量一致（y 相关≈1.0）。全图补偿后 turnStd margin 0.38→**2.00σ 系机位混淆假阳性**（雏形踝中点 S 弧多反而转角大、初级近景跟拍被压平；方向与假设相反）；[p0_loo_classify.py](file:///Users/mingsen/Project/FallLine/scripts/p0_loo_classify.py) LOO 决定性判定：raw/全图/背景三口径最好分别 6/6/5 错分，无可用泛化。C2/C3 降为 Phase 1 可选增强，不做主线。
- **产物**：[outputs/edge_spike/gt_sheets/](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/gt_sheets)（11 片逐帧 GT 接触表）、[p0_board_axis_dense.tsv](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/p0_board_axis_dense.tsv)、[p0_camera_motion.tsv](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/p0_camera_motion.tsv)/[p0_camera_motion_bg.tsv](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/p0_camera_motion_bg.tsv)、补偿轨迹图 [p0_comp_track_sheet.png](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/p0_comp_track_sheet.png)/[_bg.png](file:///Users/mingsen/Project/FallLine/outputs/edge_spike/p0_comp_track_sheet_bg.png)。spec 状态 Proposed → Gate-G0 PASS：[2026-09-18-board-edge-trajectory-detection-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md)。
- **下一步**：**Phase 1 生产级板轴观测器**（候选 A，默认关、诊断 JSON 命名空间 + debug overlay，不接触评分字段；落实实例归属/站姿状态双门控 + `G_MIN_LEN=0.07` + 踝下 ROI 全分辨率裁剪缓存）；**未开始，等确认**。中优先：扩边界集 n=11→≥20（Gate-G2 前置），盘点候选池并出接触表供教练标注。

## Previous State (2026-09-18 低端 62 分地板归因闭环：bestThird 修正证伪，刃线/轨迹检测立项)

**低端 62 分地板问题（2026-09-16 两批人眼标注 n=25 定位）本轮完成归因闭环，不改评分，两个审计脚本 + 产物归档（详见 [delta_update.md](file:///Users/mingsen/Project/FallLine/delta_update.md) 2026-09-18 条）**：
- **bestThird 选择偏差修正证伪**：[bestthird_aggregator_audit.py](file:///Users/mingsen/Project/FallLine/scripts/bestthird_aggregator_audit.py) 离线复刻完整封顶链路（25 片 sim vs JSON max Δ=0.00），扫描 18 种聚合器——**当前 top1/3 聚合本身最优**（13/25 档位命中、越界 MAE 1.08、全在 ±1 档），wmean/median 等全片化聚合器中高端大面积低估（最差跨 3 档）。地板机制是 `min(top33, edge cap 62)`，top33 虚高只是被截中间量，换聚合器要么穿不透 cap、要么误伤中高端。
- **现有 2D 信号不可分推坡初级 vs 平行雏形中级**：[lowend_separability_audit.py](file:///Users/mingsen/Project/FallLine/scripts/lowend_separability_audit.py) 对 7 初级 + 4 中级雏形（同 60-65 分带）穷尽 25 维 7 类特征（聚合分布/flow/姿态维度/跨弯时序结构：倒伏换弯·横移与膝屈伸节律自相关·弯段数/几何代理：踝膝投影·犁式站姿宽度·travelAngle·edgeSignal）。1D 最强 sym 仅 81.8%（margin −0.73σ）；2D 合取规则 8 个能在 n=11 全对但最强 margin 仅 **0.50σ**，均属测量噪声内的小样本过拟合，不可上线（同 knee 动态加权 margin 0.44 教训）。
- **用户决策：立项新检测能力——可靠板身刃线 / 轨迹检测**（实例分割或线段检测提刃线、跨弯轨迹曲率、速度-方向耦合）；新特征须回本审计以 ≥1.5σ margin 分开 11 片边界集后，才谈低端 cap/聚合器联动。calf≈45.5 软信号维持只分刻滑/搓雪。产物：[outputs/bestthird_rerun/](file:///Users/mingsen/Project/FallLine/outputs/bestthird_rerun)（18 聚合器 ×25 片 TSV + 15 份重跑日志）。
- **立项 spec 已创建（2026-09-18，Proposed，评分零改动）**：[2026-09-18-board-edge-trajectory-detection-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-18-board-edge-trajectory-detection-design.md)。固化 4 项 spike 证据——ROI 像素预算（脚下中位 585–1022px 充足但站姿宽仅 2–46px）、雪面静态脊线方向两类重叠不可分（entropy 0.588–0.894 / peak3 0.099–0.158）、踝 2D 轨迹弯形不可分（相机运动主导）、前景实例分割近景含板而中远景丢板（带门控候选）。方向矩阵：A=foreground mask+VNDetectContours 板轴几何（近景门控）、B=CoreML 板身专项（A 不达标才升级）、C=图像配准补偿相机+滑者尾迹归属+跨弯弯形描述子（远景主线）。分 4 期，Gate-G0 可行性 / G1 覆盖率+确定性+性能 / **G2 margin≥1.5σ + LOOCV≥90%（进入评分讨论硬闸门）** / G3 评分联动另立项。下一步 Phase 0：扩边界集到 ≥20 片 + A/C1 离线原型，**尚未开始，等确认**。

## Previous State (2026-09-15 方向 α edgeQuality 取代 sideslip 语义 已落地)

**方向 α（Foot-Plant 诊断证伪后的替代方向）**：走刃结论正式由姿态派生的 `edgeQualityScore/Confidence` 承担，sideslip 几何量降级为原始诊断（不参与走刃语义、不参与评分、报告显式标注）。改动**只发生在展示/语义层**，综合分链路（flow 门控 + 62 分时长 cap 仍独立消费 `boardKinematicConfidence`）零改动。
- 触发依据：[scripts/footplant_diagnose.py](file:///Users/mingsen/Project/FallLine/scripts/footplant_diagnose.py) 证伪低速锚定假设——低速窗 sideslip 反而更大、boardAngle 帧跳无改善、sideslip 与 edgeQuality 弱相关；确认 2D 光流方向不携带质量信息，与 P8-A 退役 sideslip cap 同根因。
- [ReportGenerator.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift#L302-L312)：命名恒定"走刃质量"（旧双轨"走刃质量/走刃倾向"下线），`edgeConfidence` 直接用 `ski.edgeQualityConfidence`（不再与 `boardKinematicConfidence` 取 min，v1/v2/v4/v6 走刃行从"暂不评分"恢复正常给分）；[boardSummaryLine](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/ReportGenerator.swift#L968-L979) 重写为"板身-行进夹角（2D 几何）· 原始诊断，不代表走刃/搓雪"，删除 `boardKinematicsLabel`。
- 契约测试：[ReportGeneratorEdgeQualitySemanticsTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/ReportGeneratorEdgeQualitySemanticsTests.swift) 5 条用例锁定"几何低置信度不再压制走刃行"、"edgeQualityConfidence 低时几何高置信度不得补救"、命名恒定、sideslip 段无走刃语义。

**PoseScorer edge-first 重构（把 calfLean 立刃证据从"外部 cap"升级为评分主导维度，commit `ce751a4`→`b584b12` + 微调 `fbeb1da`）**：
- Tick 1 `ce751a4` [PoseScorer.Weights](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseScorer.swift) struct 前置重构（数值不变）；Tick 2 `06f5ed7` 权重重分配 lean/knee/calf/gravity/symmetry = 0.15/0.25/**0.35**/0.15/**0.10**（calf 主导、symmetry 降到 0.10）；Tick 3 `48ea262` calfLean 改 sigmoid；Tick 4 `b584b12` edge cap 放宽为 fallback-only ramp。
- **sigmoid 中点 c=35→c=40（`fbeb1da`，corpus review 后微调）**：`calfSigmoidScore = 100/(1+exp(-0.10·(angle-40)))`，40°=50 分（及格，"入门—中级刻滑分界"），30-50° 段陡度 ~2.31 分/°，端点 0°→1.8/80°→98.2。c=35 曾让专业档普涨、v5 中级→高级、v4 中级→专业，c=40 后 v5 回落中级。
- edge cap [edgeEvidenceCapValue](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift#L509-L513)：`edge<30→62` 兜底 / `30–42` 线性放行 / `≥42→100`，悬崖软化、纯扫雪防误抬。
- Spec 已 Landed：[2026-09-15-posescorer-edge-first-refactor-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-posescorer-edge-first-refactor-design.md)。

**Flow modulation 走刃置信度门控（edge-first 的下游护栏，`ab16817` + 归档 `31950a5`）**：
- [computeModulation](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/FlowMetricsCalculator.swift) 扩 6-param：`boardKinematicConfidence < 0.30 → min(modulation,1.0)`（只禁上行 ×1.05、不扣分）；方案 (c) 低分保护 `evidenceCappedScore < 60` 关门控（防 v1 跨中/初档）。[VideoSummary](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Models.swift) 加 `flowModulationGated: Bool?`；报告 gated=true 追加"（走刃证据不足，未加成）"。
- Tick 4 release CLI 复核：`gated=true` 集合精确 **{v4,v6}**，v1 保护不掉档；阈值 0.30 处 [0.30,0.50] 稳定平台且为覆盖 v6(boardC=0.280) 的最小值。Spec Landed：[2026-09-15-flow-modulation-edge-gating-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-flow-modulation-edge-gating-design.md)。

**当前主 corpus 顶层分数**（c=40 叠加 gating，[testvideo/](file:///Users/mingsen/Project/FallLine/testvideo)）：v1 61 · v2 87 · v3 88 · v4 79 · v5 74 · v6 90（edge-first 前基线 61/83/85/74/70/92）。对照归档：[_review_tick4](file:///Users/mingsen/Project/FallLine/testvideo/_review_tick4)(c=35)、[_edgefirst_c40](file:///Users/mingsen/Project/FallLine/testvideo/_edgefirst_c40)(c=40 无门控)、[_tick4_gated](file:///Users/mingsen/Project/FallLine/testvideo/_tick4_gated)(c=40+门控)。

**评分确定性基线（2026-09-15 探针，未提交）**：新增 [scripts/repeatability_probe.py](file:///Users/mingsen/Project/FallLine/scripts/repeatability_probe.py)，对标 SportsReflector ±3.0 pts 方法（同视频 ×10 次全新 release 进程）。主 corpus 6×10=60 次运行**全部 bit-identical**（JSON 剔除 videoPath 后 SHA256 唯一），最大跨次 **SD=0.000**，`--deep` 逐帧 totalScore 也全部一致。结论：task group 并发 + Vision 熔断在固定输入下不引入跨次非确定性；分数变化只能来自代码/输入/工具链变化，跨次实验对比可信。该基线作为后续重构（自适应抽帧、归约并行化等）的守门探针。

**验证状态**：`swift build` 0 warning；`swift test` **240 tests, 0 failures**（本轮新增 [ReportGeneratorEdgeQualitySemanticsTests](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/ReportGeneratorEdgeQualitySemanticsTests.swift) 5 条契约用例）；主 corpus 6 份 release 重跑 → 综合分及 rawPose/bestThird/evidenceCapped/flowFactor/gated/edgeScore/edgeConf/boardConf/sideslip 全部字段与基线**逐字段 bit-identical**，仅 md 报告文案按 α 契约刷新。**edge-first + flow gating + 方向 α 共 13 个 commit 已 fast-forward 推送 origin/main**（`ce751a4..1fcff10`）：Tick 1-4 权重/sigmoid/edge cap 重构 + `fbeb1da` c=40 微调 + gating 集成 `ab16817` + gating spec Landed `31950a5` + edge-first spec Landed `21a24f8` + `e362a76` 日志、`a60d93e`/`80d80e8` baseline 归档、`ed9dac5` 方向 α 报告改写、`f524b25` α 日志归档、`1fcff10` 诊断脚本入库。方向 α spec 归档：[2026-09-15-edgequality-carving-semantics-design.md](file:///Users/mingsen/Project/FallLine/docs/superpowers/specs/2026-09-15-edgequality-carving-semantics-design.md)（Landed）。

**下一步候选**（不阻塞）：
- ~~采样率 5fps → 视频原生 30fps~~：**已实验，用户判定效果不好，暂缓**（2026-09-15），代码维持 5fps；重启需先补对照数据。
- ~~Foot-Plant Stabilisation~~：**已诊断证伪**（2026-09-15，见 [footplant_diagnose.py](file:///Users/mingsen/Project/FallLine/scripts/footplant_diagnose.py)）——低速窗 sideslip 反而更大、与 edgeQuality 弱相关；改走**方向 α**（本轮落地，见 Current State），走刃语义正式移交 edgeQuality。
- ~~**calibration anchors 教练标注校准复核**~~：**已完成**（2026-09-15，见 [outputs/calibration_review_20260915/SUMMARY.md](file:///Users/mingsen/Project/FallLine/outputs/calibration_review_20260915/SUMMARY.md) 与 [annotations/calibration_anchors.md#L43](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md#L43-L73) 快照）。12 锚点 + 主 corpus 6 份 = **18 份联合交叉核对**（由固化脚本 [scripts/calibration_cross_check.py](file:///Users/mingsen/Project/FallLine/scripts/calibration_cross_check.py) 一键复现），档位不一致率 **9/12 = 75%**（7 上迁 + 2 下迁），Pearson r 六维：**edge=+0.959 / calf=+0.949 / knee=+0.894 / lean=+0.639 / gravity=+0.509 / sym=-0.657**。核心归因 **calf 权重 0.35 + sigmoid c=40 主导抬分**：
  1. **middle-accepted 上迁**：8 份 middle 里 5 份（62.5%）综合 ≥78 落入"高质量滑行阶段"，MID_ACC7 达 93。历史"中级=middle"语义与当前分档错位。
  2. **GOOD_A 反向掉档**（94.1→86，Δ=-8.1）：calfLean 48 (≈40°) 落在 sigmoid c=40 中点，主导权重 0.35 拉低整体分。
  3. **BAD_ACC 严重上迁**（65→83，Δ=+18）：edge cap [30,42] 兜底段没兜住（edge=57>42 直接放行到 100 cap），calfLean=45 主导反而拉高。
  4. **MID_FP1（腿太直）未收敛**：仍 77 分，knee=74 但 knee 权重 0.25 无力压制。
  5. **文案-分数自相矛盾** 5 份（MID_ACC5/6/7、MID_FP1、BAD_ACC）：算法自动"主要问题"文本明确说"搓雪弯 / 走刃不稳定 / 立刃不一致"，但综合分给到 77-93，评分口径与语义口径分裂。
  6. **sym r=-0.657 反相关**：18 份里越高分样本对称性反而越低，怀疑运动幅度未归一化，需要单独排查。
- **calibration follow-ups 执行结果（2026-09-15/16）**：
  - **【✅ §4.1 已落地】edge cap 双维兜底**：改为基于复合 edgeQualityScore 的 ramp（`<57→72` / `57–61 线性放行` / `≥61→100`），原 `edge≥42 && calfLean<40` 单条规则实证无法命中目标。BAD_ACC 83→75，专业样本保护。触点：[edgeQualityCapValue](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/VideoAnalyzer.swift)。
  - **【⛔ §4.2 否决】knee 动态加权不落地**：[knee_separability_analysis.py](file:///Users/mingsen/Project/FallLine/scripts/knee_separability_analysis.py) 证明权重转移方向与预期压制相反；唯一能分离的析取规则 margin 仅 0.44（压 BAD_ACC pressure=75.9 vs 保 v6=76.8），在测量噪声内属过拟合。留待扩样本。
  - **【✅ §4.3 已落地 · 缩小范围】stage classifier 收紧**：只改低边界 `avg≥75 → qualitySkiing` 为 `avg≥75 且 calf≥55`（BAD_ACC/MID_FP1 落回稳定滑行，~8 margin 稳健）；高边界 `avg≥80` 不硬分离（GOOD_A 与 MID_ACC6 avg/calf 仅差 2.1/1.7，过拟合）；撤销 sym 条件。删除 ReportGenerator 重复死副本。新增 [StageClassifierTests](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/StageClassifierTests.swift)。
  - **【✅ §4.5 已排查】sym 反相关非 bug**：[symmetry_correlation_audit.py](file:///Users/mingsen/Project/FallLine/scripts/symmetry_correlation_audit.py) 拆 knee/calf/lean 三子分量全负；根源 `r(edgeQuality,sym)=-0.539`——初学者楔形站姿对称（sym 89-91）、刻滑内外腿分工天然不对称（GOOD_A sym63 为全场最低）。帧内 |L−R| 无法区分功能性不对称，**不做归一化/硬 cap**，真正修复待跨弯（左转 vs 右转）一致性特征。
  - **【✅ §4.4 两批标注完成 2026-09-16 · n=25 人眼】**登记表+分析见 [calibration_anchors.md](file:///Users/mingsen/Project/FallLine/annotations/calibration_anchors.md) 两个 "Boundary Annotation Batch"（真实样本池在根目录 video/，`SkiAnaylze/testvideo/` 为空）。第一批 middle 10 片：分数档位 7/10。第二批 good/bad 15 片（另 7 片 88.5-95.9 good 高分簇未看片、不入统计）：**6/15 一致，偏差两端反向——6 处高估全在 bad 低端、3 处低估全在 good 高端**。三条固化结论：**(a) 板身 carvingConfidence 两批均无判别力**（刻滑 0.8-43%、搓雪 6-53% 完全重叠），坚持 P8-A 不作硬阈值；**(b) calfLean≈45.5 是更可靠的刻滑软信号**（25 片分对 23，仅 GM=44 刻滑、M1=46.5 搓雪跨界），但仍只作软证据不作硬门槛；**(c) 低端 62 分"地板"机理已定位**：初学者 bestThird（最好1/3帧）虚高到 69-84，再被 `lowBoardEvidenceScoreCap=62`（[Utilities.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L172)）统一压到 62，而 62 落在中级带、穿不过初级线，6 份教练判初级的 bad 片被顶在 60-65；反例 LM 同 62 却真中级，故不能简单降 cap。~~真正修复要减小 bestThird 选择偏差（低分位/全片加权）或引入弯形刃线特征~~ **2026-09-18 已闭环（见顶部 Current State）：18 种聚合器扫描证明 bestThird 非可修复成因（top1/3 本身最优），25 维 2D 特征穷尽审计证明推坡/雏形不可分（最强 margin 0.50σ），用户拍板立项可靠刃线/轨迹检测新能力，不改评分。** 高端 83.5 可专业 / 92 可高质量（HI1）证明专业边界非单调，亦暂不调阈值。
- iOS 端已 SPM 化（主线 B `94ce905` 起），[SkiAnaylze/SkiAnaylze/Views](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/Views) 通过 `import FallLineCore` 复用 Core，本轮方向 α 的 sigmoid/权重/edge cap/gating/α 报告文案会随下次 iOS 重编译自动同步。UI 卡片直接读 `output.skiMetrics.edgeQualityScore` 等字段，不消费 `boardAnalysis.summary` 那段板身诊断文案，因此 α 报告改写对 iOS UI 无副作用；仅 [ReportDetailView](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift) 分享/导出用的 `ReportGenerator.generate` 长文会随之更新。仅有的旧代码副本残余是 [SkiAnaylze/SkiAnaylze/Sources/DemoData.swift](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/Sources/DemoData.swift)（demo 用固定 AnalysisOutput），也不含 Core 逻辑。
- 关键点拓扑升级（3D 骨架 / 板身分割）以修复 sideslip 2D 几何偏差，方向 α 只是把 sideslip 从走刃语义中拆走、并未修复几何测量本身。

## Previous State (2026-09-10 P6-B / P6-B-r3 / P9-A / P9-B 已落地)

**P6-B（光流窗采样，commit `3681dc2`）+ P6-B-r3（radius 2→3，commit `b25c082`）**：`FlowMetricsCalculator` hip/ankle 光流从单点采样改为 (2r+1)×(2r+1) 邻域均值，默认 radius=3（7×7 窗）。与 P6-A 时序 median 形成"空间+时序"双层抗噪；`averageFlowWindow` 作为纯函数供单测直接验证；radius=0 保留紧急回退。主 corpus 5 份重跑：视频 2 velocitySmoothness 81→84（+3），视频 3 43→47（+4），其他 3 份 coherence/smoothness/finalScore 全部稳定。

**P9-A（TurnPhase 报告文案 tie-break，commit `70f2149`）**：`ReportGenerator.dominantPhaseRawValue(from:)` 替换 `phaseDistribution.max { ... }`。同频 tie 时按语义优先级 shaping > initiation > release > transition 二次排序。`ReportGeneratorPhaseTieBreakTests` 9 条用例（含 2000 次稳定性 fuzz）守护。**只影响文案标签，不影响任何评分或 JSON 结构**。

**P9-B（重心主问题 tie-break，commit `f092025`）**：`CenterOfMassFitCalculator.dominantIssue(from:)` 同型 bug，抖动面比 P9-A 更大（作用在整个视频顶层 `mainIssue`）。同频 tie 时按语义优先级 **偏高 > 过低** 二次排序，理据：`score(hipRatio:targetRange:)` 里偏高每 0.24 单位掉 100 分（≈416 分/单位）远高于过低（≈305 分/单位），教练视角上"跟不上刃角"是刻滑典型缺陷。`CenterOfMassFitCalculatorTieBreakTests` 9 条用例（含 2000 次稳定性 fuzz）守护。**同样只影响文案标签**。

**dict/set 无序迭代审计（未落库）**：本轮全 `Sources/` 审计命中 12+ 处，其中 11 处为 Array-based（`Array.max/min/sorted(by:)` 语义保证稳定或返回首个最大值），唯一必修高风险点是 P9-B 的 `CenterOfMassFitCalculator.dominantIssue`，已修复。`AGENTS.md` "Report determinism" 条目已升级为通用规约：**任何依赖 `Dictionary`/`Set` 归约影响用户可见输出的位置必须显式声明 tie-break 顺序**。

**验证状态**：`swift test` **173 tests, 0 failures**（149 → 155 → 164 → 173）；`swift build -c release` PASS（未在当轮显式跑，P9-B 已过 diagnostics）。

**下一步候选（09-10 时点，部分已过时）**：
- 采样率 5fps → 视频原生 30fps（WORK_LOG Next Steps #1，深度研究确认 200ms 帧间隔 → 20° 膝角误差）
- travelAngle 输出链路精简（P8-A 已退役 sideslip 高分 cap，横滑角展示还留着）
- ~~confidence-weighted 时序平滑~~：**已落地**——1€ Filter 的 α 方案（`useConfidenceAwareFiltering` 默认 true），见 [PoseSmoother](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/PoseSmoother.swift)。
- 最新候选以顶部 2026-09-15 Current State 为准。

## Previous State (2026-09-08 P6-A + P7-A 落地)

**P6-A（velocitySmoothness avg→median，commit `be59c7c`）**：修复 velocitySmoothness 在 6 份主 corpus 100% 塌陷为 0。corpus 重跑后恢复 40.8~78.7，flowMod/averageScore 不变（恢复值均高于 penalty 阈值 40）。

**P7-A（退役 directionalStability 评分调制，commit `256d3f2`）**：诊断证实 6 种 2D 统计口径全部无法区分 corpus 质量排序（换刃天然 ~180° 摆动 + 相机运动主导光流方向），用户拍板方案 A。`computeModulation` 移除 stability 分支，报告标注 `*不参与评分`。corpus 分数 Δ=0.00（零行为变化正式化）。**光流调制有效范围现为 ±5%**（coherence +0.05 / smoothness -0.05）。

**自 2026-09-01 以来的稳定性提交**（未逐轮记录，见 git log）：P2 flow 熔断、P3 sideslip 5 帧中值、P4-A 短缺口插补、P5-A/B 膝盖评分、P0-A/P0b/P0-D/P0-E despike 系列、P6-A、P7-A。

## Previous State (2026-09-01 CLI 复核方案 A)

**方案 A 生产数据复核**：用 [FallLineCLI](file:///Users/mingsen/Project/FallLine/Sources/FallLineCLI) 重跑 6 份主 corpus 视频，坐实 audit 预测。仅报告文本改动，无生产代码变化。

**本轮变更概要**（详见 `delta_update.md` 的"2026-09-01（CLI 复核方案 A）"条目）：
- 逐份跑 `swift run -c release FallLineCLI testvideo/N.MP4` × 6
- Python 对照 pre/post 的 `averageScore` / `evidenceCappedScore` / `boardKinematicHighScoreCap` / `flowModulationFactor`
- 3.json：**averageScore 55.10 → 73.91，Δ=+18.81**（与 audit 预测 Δ=18.4 高度吻合，微差来自 flowMod 抖动）
- 其他 5 份：0 变化（4 份 obsCnf<0.55 pre 就不 cap，1 份 evidence-cap 与 boardCap 巧合等价）
- 均值：66.34 → 69.47（+3.13）

**用户可见变化**（[testvideo/3.md](file:///Users/mingsen/Project/FallLine/testvideo/3.md)）：
- 综合评分 **55/100 → 74/100**
- 阶段判断"基础控速阶段" → **"刻滑雏形阶段"**
- ⚠️ "板身/滑行方向夹角偏大"警告：**消失**
- 高光时刻：无 → 2 段

**改动文件**：
- [testvideo/1.md](file:///Users/mingsen/Project/FallLine/testvideo/1.md) / [3.md](file:///Users/mingsen/Project/FallLine/testvideo/3.md) / [4.md](file:///Users/mingsen/Project/FallLine/testvideo/4.md) / [5.md](file:///Users/mingsen/Project/FallLine/testvideo/5.md)（21 行 diff）
- JSON 是 [.gitignore](file:///Users/mingsen/Project/FallLine/.gitignore) 排除的，只在本地存在

**验证**：
- 用户本地已确认方案 A 效果
- 未跑 `swift test`（本轮无代码改动，测试跑分保持上一轮的 106 tests 全绿）

## Previous State (2026-09-01 补 TrendAnalytics 边界用例)

**hotfix 后续 nice-to-have**：补齐 `weekly.count == 1` 真空区回归。仅测试文件改动，无生产代码变化。详见 `delta_update.md` 的"2026-09-01（补边界用例）"条目。

- [TrendAnalyticsTests.swift#L180-L219](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift#L180-L219) 新增 `test_detectMilestones_singleWeek_noWeeklyImprovementNoStreakNoCrash`
- `swift test`：Executed 106 tests, with 0 failures

## Previous State (2026-09-01 hotfix：TrendAnalytics 空 weekly 崩溃兜底)

**运行时崩溃 hotfix**：上一轮方案 A 落地后本机首次跑 `swift test` 触发。iOS App 首次打开"进步"Tab（无 session）会走 `TrendAnalytics.detectMilestones(sorted: [], weekly: [])` → `for i in 1..<0` 触发 `Fatal error: Range requires lowerBound <= upperBound` SIGABRT。**上一轮 [test_analyze_emptySessions_returnsAllEmptyOrNil](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift) 就应该拦下，但沙箱 XCTest 阻塞 → 只跑 `swift build --build-tests` 没跑运行时**。教训：仅编译不跑测试无法拦运行时崩溃。

- [TrendAnalytics.swift#L235-L243](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/TrendAnalytics.swift#L235-L243)：加 `if weekly.count >= 2` 兜底
- 顺便清查所有 `1..<...` 模式：VideoAnalyzer / TurnPhaseDetector / TrendAnalytics#L288 均已有兜底，仅 L236 漏网

## Previous State (2026-08-30 方案 A 落地)

**travelAngle 阈值决策方案 A 已落地** —— 从"决策前置"进入"生产落地"。改动最小（1 行常量 + 边界回归 2 用例 + 3 处文档同步），由测试守护"真横滑仍会 cap"这条主线。详见 `delta_update.md` 的"2026-08-30（方案 A 落地）"条目。

- [Utilities.swift](file:///Users/mingsen/Project/FallLine/Sources/FallLineCore/Utilities.swift#L144) `minimumBoardKinematicConfidenceForHighScore`: `0.55 → 0.7`
- [BoardDirectionAnalyzerTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/BoardDirectionAnalyzerTests.swift#L137-L201)：新增 2 条边界回归用例
- `python3 scripts/travel_angle_audit.py` 复跑：**cap 触发数 8 → 0**（24 份 corpus）

**量化影响预估**：
- 24 份 corpus 里 8 次 sideslip 分支 cap 触发全部消失
- 3.json 类样本（raw 76 → cap 58，Δ=-18.4 分）现在 raw 76 可以透传
- **不影响**低置信度短片 62 cap 保护
- **不影响**真横滑（obsCnf ≥ 0.7 + sideslip ≥ 30°）—— 用例守护

**当前项目定位**（本轮起有变化）：
- iOS App = Core 唯一消费方（SwiftPM 本地依赖）
- Core 对外契约就绪（Package.swift products + AnalysisOutput: Identifiable）
- 进步曲线闭环：埋点 → UserDefaults → 里程碑 → 本地推送 → 折线图
- Vision 稳定性：iOS 已用 warmUp + espresso 熔断 + CPU 后备
- 算法层测试覆盖：TrendAnalytics 13 用例 + BoardDirectionAnalyzer 边界 2 用例
- **travelAngle 阈值方案 A 已上线**：0.55 → 0.7，audit 脚本作为持续对照基线

**下一步（用户本地）**：
1. `swift test` 本机复验 103 用例全通过
2. `swift run FallLineCLI <video>` 重跑 corpus，生成新一批 JSON 产物
3. `python3 scripts/travel_angle_audit.py` 对新产物再跑一次，确认实际 averageScore 变化符合预期
4. 若变化符合预期 → 主线 B 收官清单完全清空

**后续可优化方向（不阻塞）**：
- 方案 B（`sideslipStd > 25°` 高波动豁免）暂搁置，等 A 上线跑通后视 corpus 表现决定是否叠加
- 方案 C（弃用 travelAngle）：需要先复原旧 hipCenter 2D 位移代码跑 audit 对比才好决策
- 方案 D（IMU 融合）：长线独立技术栈
- 拓展 corpus：添加更多真实用户视频做 A/B 对照

## Previous State (2026-08-30 决策前置)

**travelAngle 链路误判决策已量化前置** —— 清单里最后一项优化的量化基线搭好、决策候选 A/B/C/D 已根据 24 份 corpus 拉齐。

**变更概要**（详见 `delta_update.md` 的"2026-08-30 (决策前置)"条目）：
- 新增 [scripts/travel_angle_audit.py](file:///Users/mingsen/Project/FallLine/scripts/travel_angle_audit.py)：只读扫描 24 份 corpus，与 Core `boardKinematicHighScoreCap` 完全一致口径复现 cap 判定
- 量化结论 5 条硬事实：cap 触发率 33.3%、travelStd 大多 >100°、无样本 avgObsCnf ≥ 0.6、最大惩罚 Δ=-18.4 分、cap 抹平 3D 融合优化
- 决策候选 A/B/C/D 拉齐，推荐方案 A（本轮已落地）

## Previous State (2026-08-30 TrendAnalytics 测试覆盖)

**TrendAnalytics 单元测试覆盖落地（+13 用例）** —— 主线 B 收官后清单里的第 2 项可选优化完成。仅新增 [TrendAnalyticsTests.swift](file:///Users/mingsen/Project/FallLine/Tests/FallLineCoreTests/TrendAnalyticsTests.swift) 1 个测试文件，无生产代码改动。

**当轮变更概要**（详见 `delta_update.md` 的"2026-08-30：TrendAnalytics 单元测试覆盖"条目）：
- 新增 13 个 XCTest 用例，覆盖 7 大能力域
- 测试用固定时间锚 + `session(offsetDays:score:level:)` helper 保证确定性
- 每个用例都与 `TrendAnalytics.swift` 源码具体行号交叉核对

## Previous State (2026-08-29 收官后 +1)

**iOS 已切换到 `analyzeWithResilience()`** —— 主线 B 收官后清单里的第 1 项可选优化已落地。单文件改动 [VideoAnalysisManager.swift](file:///Users/mingsen/Project/FallLine/SkiAnaylze/SkiAnaylze/VideoAnalysisManager.swift#L134-L165)。

**当轮变更概要**（详见 `delta_update.md` 的"2026-08-29 (收官后 +1)"条目）：
- `analyzer.analyze()` → `analyzer.analyzeWithResilience(progressHandler:)`：接入 Vision espresso 上下文预热 + CPU 后备 + 连续 3 帧失败熔断
- 用 `progressHandler` 把 Core 抽帧真实进度映射到 App 进度条 0.2→0.75 区间，替代原两段 500ms 假 sleep
- `AnalysisError.visionUnavailable` / `.noReliableFrames` 各自转 `NSError` 沿现有错误弹窗链路展示

## Previous State (2026-08-29 收官)

**主线 B（iOS SPM 化）+ 进步曲线全链路接入完成**。3 个 commit 已推送到 `origin/main`：

```
efd7843  feat(trend): 进步曲线接入主流程
264a1b2  feat(core): AnalysisOutput 支持 Identifiable，兼容 SwiftUI sheet(item:)
94ce905  feat(ios): 主线 B 完成 - iOS SPM 化，消除 8 个复制文件
```

本轮变更明细见 `delta_update.md` 的"2026-08-29 (收官)"条目。

## Previous State (2026-08-29 再续)

**主线 B（iOS SPM 化）Core 端就绪 + 进步曲线 c1/c2/c3 骨架已入库**。3 个 commit 推送到 `origin/main`：

```
b825c7f  feat(trend): c3 里程碑本地推送 - TrendNotificationCenter
18436c0  feat(trend): 进步曲线 - Core 算法层 + iOS 骨架
2c5ef8d  feat(core): 主线 B iOS SPM 化 - Core 端就绪
```

**本阶段完成的**：
- Core 层 iOS 兼容改造（`Package.swift` iOS 17 平台，`VisionFrameAnalyzer.usesCPUOnly + warmUp`，`VideoAnalyzer.AnalysisError + analyzeWithResilience`）
- 进步曲线骨架（`TrendAnalytics.swift` 220 行 + `TrendStore.swift` UserDefaults 持久化 + `TrendView.swift` Charts 折线图 + `TrendNotificationCenter.swift` UNUserNotificationCenter 推送）
- `scripts/setup_ios_deps.sh` --dry / --yes / --rollback + 备份机制

**已由 2026-08-29 收官轮接管**：SPM 化真正落地、8 个复制文件删除、iOS App 接入 3 处。

## Previous State (2026-08-29 续)

**算法准确度 P0/P1/P2 + iOS 熔断已入库**（commit `45dad57`，已推送 `origin/main`）。核心引擎按 2026-06-05 深度研究结论完成采样率、软置信度、travelAngle 门控、板身线仲裁、3D 融合五处改动；iOS 端补齐 Vision warmUp/CPU 回退/熔断与错误 UI。详细变更见 `delta_update.md` 的"2026-08-29 (续)"条目。

**验证状态（当轮）**：
- `swift build -c release` PASS；`swift test` 沙箱限制未跑
- 6 个测试样本被证据封顶卡在 58/55/66 三档，收益体现在内部指标（stabilityScore、kneeBendScore、rawPoseAverageScore）
- 三阶段对照快照保留：`testvideo/_p1_baseline/`、`testvideo/_c_2d/`、`testvideo/_b_3d_baseline/`

## Previous State (2026-06-05)

**仓库清理**：`.gitignore` 已加入 `UserInterfaceState.xcuserstate`，用于忽略 Xcode 用户界面状态文件。注意：该文件当前已在 Git 索引中且处于未合并状态，ignore 规则不会自动解除跟踪或解决冲突。

**深度研究完成：算法准确度提升方向**。通过 deep-research 工作流（5 角度搜索 → 22 来源 → 75 声明 → 3 票对抗验证 → 7 综合发现），梳理了单目姿态估计和光流运动分析在滑雪场景下的准确度瓶颈与改进路径。完整报告见 Journal。

**iOS 开屏页面已实现**（2026-05-28）：`SkiAnaylze/` 新增滑雪主题开屏动画，3 秒自动进入主页面，可跳过，预留广告接口。编译通过，模拟器验证通过。

**验证状态**：
- `xcodebuild -project SkiAnaylze/SkiAnaylze.xcodeproj -scheme SkiAnaylze -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`：`** BUILD SUCCEEDED **`
- `swift test`：88 tests, 0 failures（待确认：与上次验证间隔 8 天，其间代码可能有变更）

**变更文件**（开屏）：
- 新增 `SkiAnaylze/SkiAnaylze/Services/AdProvider.swift` — 广告接口协议 + 默认空实现
- 新增 `SkiAnaylze/SkiAnaylze/Views/SplashView.swift` — 4 阶段开屏动画 + 跳过按钮 + 广告位
- 新增 `SkiAnaylze/SkiAnaylze/Views/RootView.swift` — splash → content 状态切换
- 修改 `SkiAnaylze/SkiAnaylze/SkiAnaylzeApp.swift` — ContentView → RootView

**变更边界**：只改 iOS SwiftUI UI 层，不改 FallLineCore/CLI 的分析逻辑、评分模型或持久化行为。

### 深度研究关键发现

**高置信度（3-0 投票通过）**：

1. **姿态规范化（3DPCNet）**：混合 GCN-Transformer 将单目姿态旋转误差从 >20° 降至 3.4°，MPJPE 降低 27%。Estimator-agnostic——可直接操作 3D 关节点坐标，无需修改底层检测器。[arXiv:2509.23455](https://arxiv.org/html/2509.23455) (ICASSP 2026)

2. **2D 透视误差公式**：E = 100 × d / (D − d)%。简单乘性修正只能纠正平动运动学（位移、速度），**无法纠正关节角度**。透视误差是系统误差（非随机），无法通过平滑消除。[Yokoi & Okada 1994](https://cir.nii.ac.jp/crid/1390001204309690752)

3. **Apple Vision 硬限制**：VNDetectHumanBodyPoseRequest 腿部链终止于脚踝，iOS 18+ 的 3D 变体也未增加足部关键点。脚踝代理方法是当前框架下的最优解——立刃角度检测有理论上限。

4. **时序精度**：跑步步态中 20ms 事件检测偏差 → 20° 膝关节角度误差。当前 5fps（200ms 帧间隔）远超此阈值，提高采样率可能比算法改进更有效。[Mundt et al. 2024](https://pubmed.ncbi.nlm.nih.gov/38984681/)

**中置信度（2-1 投票通过）**：
- 滑雪专项 AlphaPose 微调：98% PCK，10.32px MPJPE（仅 2 受试者训练，通用性存疑）
- 2D+3D 融合 + 骨长约束 + Kalman 滤波：MPJPE -10.2%，关节角误差 -16.6%（理疗数据集，非滑雪，arXiv 预印本）

**已剔除声明（≥2 票反对）**：共 14 条，包括 "100Hz 是 2D 分析最低采样率"、"Kalman 可从 2D 恢复 47 DOF 全身关节角" 等。

## Previous State (2026-05-25)

**iOS App Icon 已更新（2026-05-27）**：`SkiAnaylze/` 的 AppIcon 已替换为已确认的 **Alpine scan-reticle / 山地扫描准星** 方向。图标保留 Ice Sport Technology 的深色山地背景、冰蓝刻滑轨迹和扫描准星，不使用 “AI” 文本。生成脚本见 `scripts/generate_fallline_app_icon.swift`，资产位于 `SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/`。

**iOS App UI redesign implemented**：`SkiAnaylze/` 已按 **Ice Sport Technology / 冰雪运动科技** 方向完成第一轮 SwiftUI 改造。视觉语言覆盖首页/壳层、视频确认、分析进度、报告详情、历史记录和分享卡：雪山剪影、坡线轨迹、数据 HUD、冰蓝玻璃面板、环形评分仪表。规格见 `docs/superpowers/specs/2026-05-25-ios-ui-ice-sport-technology-design.md`，计划见 `docs/superpowers/plans/2026-05-25-ios-ui-ice-sport-technology.md`。

**验证状态**：
- App Icon PNG：Default/Dark/Tinted 均为 1024×1024。
- `xcodebuild -project SkiAnaylze/SkiAnaylze.xcodeproj -scheme SkiAnaylze -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`：`** BUILD SUCCEEDED **`
- `swift test`：88 tests, 0 failures
- iPhone 16 Pro Simulator：启动成功，首页/训练记录/报告页可渲染；用户已确认视觉效果“可以”。

**变更边界**：本次只改 iOS SwiftUI UI/主题文件和项目文档，不改 `Sources/FallLineCore/`、`Sources/FallLineCLI/`、`SkiAnaylze/SkiAnaylze/Sources/` 的分析逻辑、评分模型或持久化行为。

## Previous State (2026-05-21)

**--output-video 功能已完成（含每帧独立分析）**，88 tests 全通过，`swift build -c release` 通过。

**运动方向（cyan 箭头）稳定性待解决**：已从 hipCenter 位移切换为光流方案，有改善但仍不可靠。低置信度帧的角度跳动很大（-4.7° ↔ 112.4°）。核心矛盾：画面 2D 像素运动 ≠ 雪板实际行进方向。

**已完成功能**：
- `--output-video` CLI 开关：将姿态分析覆盖图渲染为 MP4 (H.264) 视频
- 直接复用 `renderOverlay()` 绘制逻辑，与 `--debug-overlay` 的 PNG 覆盖图内容一致
- 输出原视频**每一帧**（原生帧率），**每帧独立跑 Vision 姿态检测**，标注数据随帧实时更新
- `AVAssetImageGenerator` 精确帧提取：`requestedTimeToleranceBefore/After = .zero`（修复前几秒帧重复 bug）
- `VideoAnalyzer` 采样间隔下限从 0.1s 降至 1/60s，支持原生 60fps 分析
- `--output-video` 启用时自动检测视频原生帧率作为采样间隔
- AVAssetWriter 管线：NSBitmapImageRep → CVPixelBuffer (BGRA, IOSurface backed) → H.264 Baseline 3Mbps
- 默认输出路径：原视频同目录 `<视频名>_analyzed.mp4`

**iOS App 模拟器测试支持（2026-05-21）**：
- 新增 `DemoData.swift`：基于 testvideo/3.MP4 分析数据构建默认演示 AnalysisOutput（72.57 分，"中级"）
- `VideoAnalysisManager` 新增 AnalysisOutput 持久化（`analyses.json`），首次启动自动注入 demo 条目
- `HistoryView` 删除操作同步清理持久化数据
- `ReportDetailView` 视频播放器改为 9:16 竖屏比例铺满宽度

**之前完成的优化（2026-05-13）**：
- 批次并行帧分析（batchSize=8，TaskGroup 并发）
- 帧缓存降采样（640x480，mem ~400MB → ~60MB）
- main.swift 四个检测器 async let 并发
- generateSummary 内 reliableFrames 缓存复用

**未验证**：并行优化在真实视频上的加速效果，以及输出一致性。
**光流调制也未验证**：需要批量跑 49 个视频对比调制前后分数。

**最新批量基线**：`outputs/all_video_scores_20260511_224820/` — bad=57.6, good=74.7, middle=66.4, testvideo=64.7, 全体 67.1。

## Current Goal

Current iOS UI redesign goal is complete. Next UI work should start from the implemented Ice Sport Technology SwiftUI components and preserve existing analysis behavior.

Previous analysis goal:

Phase 1 光流增强：Apple Vision `VNGenerateOpticalFlowRequest` 产出三个运动指标，以 ±13% 调制系数修正姿态总分，提升泛化性。Phase 1 仅做后处理调制，后续验证有效后可纳入 PoseScorer 作为独立维度（Phase 2）。

## Context Snapshot

- 光流在 `generateSummary()` 内计算，利用 `analyze()` 缓存的帧对。不改 `DetectionResult`/`PoseScorer`。
- `FlowMetricsCalculator` 三指标：motionCoherence（髋-踝方向差）、directionalStability（髋部 circular variance）、velocitySmoothness（光流幅值变化率）。
- 调制公式：stability 阈值依赖 poseScore 上下文——低分高 stability → 提分，高分低 stability → 扣分。范围 ±13%。
- `VideoSummary` 含评分拆解字段：rawPoseAverageScore → bestThirdAverageScore → evidenceCappedScore → flowModulationFactor → 最终分。报告显示拆解行。
- `sampleInterval` 默认 0.2s（5fps），帧数阈值已改为时长阈值。
- 板身判断用脚踝代理线；紫色图像候选线仅 debug，存在 near_board_false_positive 问题。
- 帧分析改为批次并行（batchSize=8），AVAssetImageGenerator 非线程安全故提取串行、分析并行。
- 帧缓存降采样至 640x480 再入光流，大幅降低内存。

## Existing Review Assets

- `outputs/edge_debug_review/` — 9 个样本（3 good, 3 middle, 3 bad），紫色线复核
- `outputs/misjudgment_review_20260506/` — 6 个疑似误判候选
- `outputs/all_video_scores_20260511_224820/` — 最新 50 视频批量跑分（含光流指标和 Ablation）
- 三个锚点：bad=65.0, middle=85.3, good=94.1（已确认合理，不要动）
- 代码重复已消除：7 个工具函数收敛到 `Utilities.swift`

## Completed (chronological)

- 紫色线复核：Round 1 确认 A/B/C 均为 near_board_false_positive，暂不升级为主证据
- 板身/滑行方向夹角接入封顶：≥30° 保守，≥45° 按横滑处理
- 高横滑角接入高光过滤 + 报告文案更新
- 49 视频批量回归：bad=57.3, middle=66.6, good=76.8
- Phase 1 光流增强：FlowMetricsCalculator + 帧缓存 + async generateSummary + 调制集成
- sampleInterval 1.0→0.2s，帧数阈值→时长阈值
- 评分拆解字段 + 报告拆解行
- 新增 `file_manifest.md`，用于快速定位项目文件与产物目录
- 将新增文件索引及引用说明改为中文
- 新增 `delta_update.md`，约束每轮结束只记录增量变化
- 统一使用 `delta_update.md` 作为增量记录文件名
- 88 tests, 0 failures
- 流水线性能优化：并行帧分析 + 帧缓存降采样 + async let 并发后处理 + reliableFrames 缓存复用
- CLAUDE.md 更新为启动时同时读取 WORK_LOG.md + file_manifest.md + delta_update.md
- --output-video 功能：独立 CLI 开关 → renderVideoOverlay → AVAssetWriter H.264 MP4，每帧独立跑 Vision 姿态检测，标注数据随帧实时更新。修复了帧提取容差和采样间隔下限两个 bug
- iOS App 模拟器测试支持：新增 DemoData.swift（72.57分 demo 数据）、AnalysisOutput 持久化到 analyses.json、首次启动注入 demo 条目、HistoryView 删除同步清理、ReportDetailView 视频播放器竖屏比例

## Recorded: 待优化点

### 高优先级
1. **运动方向（travelAngle）不可靠** — 光流方案低置信度帧角度跳动大。travelAngle → sideslipAngle → carvingConfidence → boardKinematicHighScoreCap（62分封顶）这条链路如果 travelAngle 不准，封顶可能误判。选项：A) 删除整条链路，edgeQualityScore 独立已够；B) 光流高置信度时启用，低时退化为不封顶；C) 继续优化光流采样方式。**深度研究确认：2D 透视误差是系统误差（E=100d/(D-d)），无法通过平滑消除——这说明 A 或 B 比 C 更合理。**
2. **5fps 采样率过低** — 深度研究确认：20ms 事件检测偏差 → 20° 膝关节角度误差（Mundt et al. 2024）。当前 200ms 帧间隔远超此阈值。**提高采样率到原生帧率（≥30fps）可显著提升关键事件（换刃/入弯）的时序精度。**
3. **Apple Vision 缺少足部关键点** — 官方文档确认腿部链终止于脚踝，iOS 18+ 也未增加。**脚踝代理方法是当前框架的理论上限，立刃角度检测存在不可消除的信号丢失。** 长期需考虑光流追踪雪板边缘或 IMU 融合。

### 中优先级
1. SkiAnaylze 代码重复 — 8 文件落后于 FallLineCore，`scripts/setup_ios_deps.sh` 写好删除逻辑
2. 光流信号薄弱 — 只用髋+踝 2 关键点，circularVariance 硬编码边界未文档化
3. 置信度阈值分散 — 五处各自定义（0.30/0.35/0.15/0.65），无单一来源。**深度研究推荐：参考 Anipose 的 confidence-weighted IK 方案，低置信度关节点降低权重而非直接丢弃帧。**
4. ReportGenerator 种子溢出 — `abs(Int.min)` 可能崩溃
5. 报告优势/问题阈值不对称 — 系统性负面偏见
6. "重心旧分"与"重心阶段适配"并存 — 用户易困惑

### 低优先级
1. CI/CD 缺失 — 无 GitHub Actions、无 lint、无覆盖率
2. 输出资产膨胀 — edge_debug_review/（399 MB）、misjudgment_review/（242 MB）
3. 4 个过期批量跑分目录可清理
4. TemporalSmoother 孤文档 — 设计已写但从未实现。**深度研究为时序平滑提供了三个参考方案：SmoothNet（SOTA plug-and-play）、Anipose Viterbi filter（confidence + 运动先验）、Sports2D pipeline（Hampel 异常值剔除 + GCV 样条 + Kalman）。**
5. DebugOverlayRenderer.swift:115 唯一 `!` 强制解包
6. 提交信息风格不一致

## Next Steps

### 算法准确度提升（来自 2026-06-05 深度研究）

**立即做**：
1. **提高采样率**：从 5fps 升至视频原生帧率（≥30fps）。200ms 帧间隔远超 20ms/20° 的时序误差阈值。可批量处理、降低 per-frame 分辨率来平衡 Vision API 性能。

**短期（1-2 周）**：
2. **升级到 VNHumanBodyPose3DObservation**（iOS 17+）：获取 3D 关节点，为后续规范化步骤和视角校准提供基础。当前返回的 2D 关键点无法进行有意义的透视修正（公式确认关节角度无法通过简单比例修正）。
3. **实现 confidence-weighted 时序平滑**：替代当前的简单置信度门控（<0.30 丢弃）。参考方案：Anipose 的 Viterbi filter（confidence 先验 + 预期运动 std）或 Sports2D 的 pipeline（Hampel 异常值剔除 → GCV 样条 → Kalman）。

**中期（1-2 月）**：
4. **决定 travelAngle 链路去留**：深度研究确认 2D 透视误差是系统误差、无法通过平滑消除 → 选项 A（删除链路）或 B（光流高置信度时启用）比 C（继续优化光流采样）更合理。

**长期**：
5. **探索滑雪场景透视误差估计**：基于 Yokoi & Okada 公式 E=100d/(D-d)，假设雪面为标定面来估计 2D 光流与真实 3D 行进方向之间的系统偏差。需验证在非正交相机角度下的适用性。
6. **评估 3DPCNet 规范化**：在滑雪视频上验证高度 crouch/旋转姿态下的退化程度。如可用，可大幅减少不同拍摄角度下的一致性差异。
7. **Phase 2 光流纳入 PoseScorer**：前提是完成 travelAngle 去留决策和采样率提升。

### 之前待办（未被取代）
- 批量跑 49 视频，对比光流调制前后分数，重点看变化 >5 分的
- 同期验证并行优化的输出一致性（JSON/MD 与优化前对比）

## Important Files

### 进步曲线（2026-08-29 再续）
- `Sources/FallLineCore/TrendAnalytics.swift` — Core 纯计算模块（SessionEntry / WeeklySummary / Milestone / TrendReport / TrendAnalytics）
- `SkiAnaylze/SkiAnaylze/TrendStore.swift` — iOS UserDefaults 持久化 + record/refreshReport 单一 API
- `SkiAnaylze/SkiAnaylze/Views/TrendView.swift` — Charts 折线图 UI（三段：统计卡 → 折线图 → 里程碑徽章）
- `SkiAnaylze/SkiAnaylze/TrendNotificationCenter.swift` — UNUserNotificationCenter 里程碑推送封装
- `scripts/setup_ios_deps.sh` — iOS SPM 化辅助脚本（--dry / --yes / --rollback + 备份 + Xcode 7 步说明）

### 深度研究（2026-06-05）
- `outputs/research/2026-06-05-pose-estimation-accuracy-deep-research.md` — 完整研究报告（7 发现 + 4 开放问题 + 5 建议）
- 关键来源: [3DPCNet](https://arxiv.org/html/2509.23455) / [透视误差](https://cir.nii.ac.jp/crid/1390001204309690752) / [时序精度](https://pubmed.ncbi.nlm.nih.gov/38984681/) / [Apple Vision 文档](https://developer.apple.com/documentation/Vision/detecting-human-body-poses-in-images) / [滑雪专项微调](https://ciss-journal.org/article/view/11530)
- 工作流 run ID: `wf_64680db7-fce`，104 agents，~300 万 token

### iOS UI
- `docs/superpowers/specs/2026-05-25-ios-ui-ice-sport-technology-design.md` — iOS UI redesign approved design spec
- `docs/superpowers/plans/2026-05-25-ios-ui-ice-sport-technology.md` — iOS UI redesign implementation plan
- `SkiAnaylze/SkiAnaylze/AppTheme.swift` — UI redesign theme/component entry point
- `SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/` — iOS App Icon assets (Alpine scan-reticle)
- `scripts/generate_fallline_app_icon.swift` — reproducible generator for the AppIcon PNGs
- `SkiAnaylze/SkiAnaylze/Views/HomeView.swift` — redesigned home/upload flow target
- `SkiAnaylze/SkiAnaylze/Views/AnalysisProgressView.swift` — redesigned analysis progress target
- `SkiAnaylze/SkiAnaylze/Views/HistoryView.swift` — redesigned training records target
- `SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift` — redesigned report/detail/share target
- `SkiAnaylze/SkiAnaylze/Views/SplashView.swift` — 开屏动画视图（新增）
- `SkiAnaylze/SkiAnaylze/Views/RootView.swift` — 根视图状态管理（新增）
- `SkiAnaylze/SkiAnaylze/Services/AdProvider.swift` — 广告接口协议 + 默认实现（新增）

### FallLineCore / CLI
- `Sources/FallLineCore/VideoAnalyzer.swift` — 管线编排（含批次并行 + 帧缓存降采样）
- `Sources/FallLineCore/FlowMetricsCalculator.swift` — Phase 1 光流
- `Sources/FallLineCLI/main.swift` — CLI 入口（含 async let 并发后处理 + --output-video 分支）
- `Sources/FallLineCLI/DebugOverlayRenderer.swift` — 调试图渲染（PNG 帧 + MP4 视频覆盖图）
- `Sources/FallLineCore/Models.swift` — 数据结构
- `Sources/FallLineCore/ReportGenerator.swift` — 报告生成
- `Sources/FallLineCore/BoardDirectionAnalyzer.swift` — 板身判断
- `Tests/FallLineCoreTests/FlowMetricsCalculatorTests.swift` — 19 tests

### 文档与产物
- `docs/superpowers/specs/2026-05-11-optical-flow-scoring-enhancement-design.md`
- `docs/superpowers/specs/2026-05-17-output-video-overlay-design.md`
- `docs/superpowers/plans/2026-05-11-optical-flow-scoring-enhancement.md`
- `docs/superpowers/plans/2026-05-17-output-video-overlay-plan.md`
- `delta_update.md` — 每轮增量变化记录（含中低优待办清单）
- `file_manifest.md` — 项目文件索引
- `outputs/all_video_scores_20260511_224820/score_summary.tsv`
