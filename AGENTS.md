# AGENTS.md

> Before any work, read `WORK_LOG.md` for current state, goal, and next steps.

## Build & Test

```bash
swift build -c release          # Build CLI (macOS)
swift run FallLineCLI <video> # Run analysis → JSON + Markdown report
swift run FallLineCLI --debug-overlay <video>  # + per-frame debug PNGs
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
  → BoardDirectionAnalyzer (ankle-proxy → sideslip, carving confidence)
  → TurnPhaseDetector (transition/initiation/shaping/release)
  → CenterOfMassFitCalculator (stage-aware hip-ratio targets)
  → HighlightMomentDetector (best continuous segments)
  → FlowMetricsCalculator (optical flow: coherence, stability, smoothness)
  → Flow modulation (±13% score adjustment)
  → ReportGenerator (Markdown report)
```

`VideoAnalyzer` orchestrates frame extraction + per-frame analysis. Post-processing in `main.swift`.

## Key design decisions

- **Confidence gating**: minimumPoseScoreConfidence=0.30, minimumSkiMetricConfidence=0.35. Low-confidence excluded from scoring. Reports show "暂不评分".
- **Stable carving baseline**: stability ≥85 + continuous ≥5-frame plateau ≥18% of video → plateau average as true score. Prevents low-confidence carving frames from being misjudged.
- **Evidence caps**: edge/board/时长 evidence each cap the score. Duration-based thresholds (seconds), not frame counts (5fps).
- **Optical flow (Phase 1)**: `VNGenerateOpticalFlowRequest` on cached frame pairs. Three metrics modulate evidence-capped score ±13%. Stability thresholds context-aware: low score + high stability → boost; high score + low stability → penalty.
- **Score transparency**: `VideoSummary` includes rawPoseAverageScore, bestThirdAverageScore, evidenceCappedScore, flowModulationFactor. Reports show decomposition.
- **VideoSeed**: DJB2 hash of filename for deterministic output.
- **Board detection**: ankle-proxy is primary; visual line detector is debug-only (near_board_false_positive issue).

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

- **Pipeline**: `VideoAnalyzer.swift`, `main.swift`
- **Flow**: `FlowMetricsCalculator.swift` (compute, computeModulation, applyModulation)
- **Models**: `Models.swift` — read by keyword, not whole file
- **Reports**: `ReportGenerator.swift` — `buildContext()` is entry point
- Skip full reads of `PoseMetrics.swift`, `PoseScorer.swift`, `DebugOverlayRenderer.swift`
- Use `rg "keyword" Sources/` for lookups; `git diff --stat` before expanding diffs
