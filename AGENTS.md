# AGENTS.md

> Before any work, read `WORK_LOG.md` for current state, goal, and next steps.

## Build & Test

```bash
swift build -c release          # Build CLI (macOS)
swift run FallLineCLI <video> # Run analysis → JSON + Markdown report
swift run FallLineCLI --debug-overlay <video>  # + per-frame debug PNGs
swift run FallLineCLI --output-video <video>  # + annotated MP4 (native FPS, per-frame Vision)
swift test                       # 88 tests
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
- **Confidence gating**: minimumPoseScoreConfidence=0.30, minimumSkiMetricConfidence=0.35. Low-confidence excluded from scoring. Reports show "暂不评分".
- **Stable carving baseline**: stability ≥85 + continuous ≥5-frame plateau ≥18% of video → plateau average as true score. Prevents low-confidence carving frames from being misjudged.
- **Evidence caps**: edge/board/时长 evidence each cap the score. Duration-based thresholds (seconds), not frame counts (5fps).
- **Optical flow (Phase 1)**: `VNGenerateOpticalFlowRequest` on cached frame pairs. Three metrics modulate evidence-capped score ±13%. Stability thresholds context-aware: low score + high stability → boost; high score + low stability → penalty.
- **Score transparency**: `VideoSummary` includes rawPoseAverageScore, bestThirdAverageScore, evidenceCappedScore, flowModulationFactor. Reports show decomposition.
- **VideoSeed**: DJB2 hash of filename for deterministic output.
- **Board detection**: ankle-proxy is primary; visual line detector is debug-only (near_board_false_positive issue).
- **Travel direction**: 光流 (`computeWithDirections`) 采样髋+踝位置的像素运动向量作为行进方向，替代了 hipCenter 2D 位移。已知问题：低置信度帧角度跳动大，画面 2D 像素运动 ≠ 雪板实际行进方向。travelAngle → sideslip → carvingConfidence → boardKinematicHighScoreCap (62分封顶) 链路可能误判，待决策。

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
- Skip full reads of `PoseMetrics.swift`, `PoseScorer.swift`, `DebugOverlayRenderer.swift`
- Use `rg "keyword" Sources/` for lookups; `git diff --stat` before expanding diffs
