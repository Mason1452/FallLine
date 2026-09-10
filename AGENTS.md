# AGENTS.md

> Before any work, read `WORK_LOG.md` for current state, goal, and next steps.

## Build & Test

```bash
swift build -c release          # Build CLI (macOS)
swift run FallLineCLI <video> # Run analysis → JSON + Markdown report
swift run FallLineCLI --debug-overlay <video>  # + per-frame debug PNGs
swift run FallLineCLI --output-video <video>  # + annotated MP4 (native FPS, per-frame Vision)
swift test                       # 155 tests
swift test --filter <TestName>
swift test 2>&1 | tail -5        # Summary only
```

## Project architecture

FallLine analyzes ski posture from video using Apple Vision. macOS 14+.

- **FallLineCore** — 15 source files
- **FallLineCLI** — macOS CLI, depends on FallLineCore
- **FallLineCoreTests** — 11 test files
- `SkiAnaylze/` — iOS app with duplicated core code (known debt, not in SwiftPM workspace)

## Analysis pipeline

```
Video frame (CGImage, sampleInterval 0.2s = 5fps)
  → VisionFrameAnalyzer (VNDetectHumanBodyPoseRequest)
  → PoseMetricsCalculator (8 keypoints → angles, hipRatio, lean, center)
  → PoseScorer (5-dim: lean 20%, knee 25%, calf 20%, gravity 20%, symmetry 15%)
  → DetectionResult (per-frame)
  ↓
Post-processing in generateSummary():
  → SkiMetricsCalculator (edge quality, pressure support, fore-aft)
  → KeyMomentDetector (best/worst frames)
  → FlowMetricsCalculator (optical flow: coherence, stability, smoothness, travel directions)
  → BoardDirectionAnalyzer (ankle-proxy + flow travel angle → sideslip, carving confidence)
  → TurnPhaseDetector (transition/initiation/shaping/release)
  → CenterOfMassFitCalculator (stage-aware hip-ratio targets)
  → HighlightMomentDetector (best continuous segments)
  → Flow modulation (±13% score adjustment)
  → ReportGenerator (Markdown report)
```

`VideoAnalyzer` orchestrates frame extraction + per-frame analysis. `FlowMetricsCalculator.computeWithDirections()` 单次光流遍历同时产出 FlowMetrics 和行进方向。Post-processing in `main.swift`.

## Key design decisions

- **iOS UI redesign (2026-05-25)**: `SkiAnaylze/` has completed the first **Ice Sport Technology** SwiftUI redesign pass. Visual keywords: mountain silhouettes, carving traces, pose skeletons, data HUD, ice-blue glass panels, and score rings. Spec: `docs/superpowers/specs/2026-05-25-ios-ui-ice-sport-technology-design.md`; plan: `docs/superpowers/plans/2026-05-25-ios-ui-ice-sport-technology.md`. Future UI work should stay in iOS SwiftUI UI/theme files and must not change scoring logic, analysis models, or persistence behavior.
- **iOS App Icon (2026-05-27)**: `SkiAnaylze/` AppIcon uses the Ice Sport Technology **Alpine scan-reticle** direction: dark alpine background, mountain silhouette, cyan carving trace, and scan-reticle badge. Do not use text such as "AI" in the icon. Regenerate via `scripts/generate_fallline_app_icon.swift`.
- **Confidence gating**: minimumPoseScoreConfidence=0.30, minimumSkiMetricConfidence=0.35. Low-confidence excluded from scoring. Reports show "暂不评分".
- **Stable carving baseline**: stability ≥85 + continuous ≥5-frame plateau ≥18% of video → plateau average as true score. Prevents low-confidence carving frames from being misjudged.
- **Evidence caps**: edge/board/时长 evidence each cap the score. Duration-based thresholds (seconds), not frame counts (5fps).
- **Optical flow (Phase 1)**: `VNGenerateOpticalFlowRequest` on cached frame pairs. Three metrics modulate evidence-capped score ±13%. Stability thresholds context-aware: low score + high stability → boost; high score + low stability → penalty. **2026-09-10 P6-B**: hip / ankle 光流采样从单点 → 窗均值（`FlowMetricsCalculator.flowSampleRadius`），在输入层给 coherence / velocitySmoothness 去噪；radius=0 保留紧急回退；纯窗函数 `averageFlowWindow` 供单测直接验证。与 P6-A 时序 median 形成"空间+时序"双层抗噪。**2026-09-10 P6-B-r3 微调**：默认 radius 从 2（5×5）上调到 3（7×7）；主 corpus 5 份重跑显示 velocitySmoothness 2 份显著 +3~+4（视频 2、3），4/5 samples 的 coherence 及全部 final score 保持稳定，无评分回归。
- **Score transparency**: `VideoSummary` includes rawPoseAverageScore, bestThirdAverageScore, evidenceCappedScore, flowModulationFactor. Reports show decomposition.
- **VideoSeed**: DJB2 hash of filename for deterministic output.
- **Git hygiene**: Ignore Xcode user interface state file `UserInterfaceState.xcuserstate`. If already tracked, remove it from the index separately; `.gitignore` does not untrack existing files.
- **Board detection**: ankle-proxy is primary; visual line detector is debug-only (near_board_false_positive issue).
- **Travel direction**: 光流 (`computeWithDirections`) 采样髋+踝位置的像素运动向量作为行进方向，替代了 hipCenter 2D 位移。已知问题：低置信度帧角度跳动大，画面 2D 像素运动 ≠ 雪板实际行进方向。**2026-08-30 决策方案 A 落地**：`scripts/travel_angle_audit.py` 对 24 份 corpus 的量化表明，阈值 0.55 会把 obsCnf 0.58~0.59 的样本误 cap（最大 Δ=-18.4 分），已把 `minimumBoardKinematicConfidenceForHighScore` 从 0.55 → 0.7，corpus 里 sideslip 分支 cap 触发数 8 → 0。**2026-09-08 P8-A 落地**：进一步诊断证实 sideslip 测量带 ~40-50° 系统性偏差（主 corpus 6 份全部 42-53°，含已确认刻滑样本），2D 光流方向不携带质量信息（与 P7-A 退役 directionalStability 同根因）。`boardKinematicHighScoreCap` 的 sideslip 两分支（58/70）已退役，仅保留低置信度短片段的 62 分时长证据 cap；`hasHighSideslipEvidenceForHighScore` 及其报告警告文案一并移除；横滑角展示保留但标注"不参与评分"。由 `BoardDirectionAnalyzerTests` / `StableCarvingBaselineTests` / `HighlightMomentDetectorTests` 的 P8-A 用例守护。

## Code duplication

`SkiAnaylze/SkiAnaylze/Sources/` has 8 files duplicated from FallLineCore/. `SkiAnaylze/Package.swift` declares the dependency but Xcode project not updated. See REFACTOR_PLAN.md Phase 2. Utilities already consolidated (2026-05-06).

## Scoring thresholds

Empirical, not experimental. Calibration anchors in `annotations/calibration_anchors.md`.
- Lean: ideal 10°–60° (2D can't distinguish forward vs lateral tilt)
- Knee: ideal 80°–135° (deep penalty 4pts/10°, straight penalty 28pts/10°)
- Calf: 0°=0pts, 80°=100pts
- Gravity: `107.5 - hipRatio × 100`, [10, 100]
- Symmetry: weighted (knee 0.5, calf 0.3, lean 0.2)
- Quality caps: totalScore ≤72 when knee<60 or symmetry<45

## Reading guide

- **增量记录**：`delta_update.md` — 每轮结束只记录本轮变化、验证和遗留问题，不重讲全量项目
- **文件索引**：`file_manifest.md` — 源码、测试、iOS App、文档、脚本和生成产物清单
- **Pipeline**: `VideoAnalyzer.swift`, `main.swift`
- **Flow**: `FlowMetricsCalculator.swift` (compute, computeModulation, applyModulation)
- **Models**: `Models.swift` — read by keyword, not whole file
- **Reports**: `ReportGenerator.swift` — `buildContext()` is entry point
- **iOS UI redesign**: implemented in `SkiAnaylze/SkiAnaylze/AppTheme.swift`, `ContentView.swift`, and `Views/`. Read `docs/superpowers/specs/2026-05-25-ios-ui-ice-sport-technology-design.md` and `docs/superpowers/plans/2026-05-25-ios-ui-ice-sport-technology.md` before changing those UI files
- **iOS App Icon**: `SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/` and `scripts/generate_fallline_app_icon.swift`
- Skip full reads of `PoseMetrics.swift`, `PoseScorer.swift`, `DebugOverlayRenderer.swift`
- Use `rg "keyword" Sources/` for lookups; `git diff --stat` before expanding diffs
