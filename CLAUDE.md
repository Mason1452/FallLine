# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> Before starting any work, read `WORK_LOG.md` for the latest task context, current goal,
> completed items, next steps, and verification results.

## Build & Test

```bash
swift build -c release          # Build CLI (macOS)
swift run VideoVisionCLI <video> # Run analysis, outputs JSON + Markdown report
swift run VideoVisionCLI --debug-overlay <video>  # Also generate per-frame debug PNGs
swift test                       # Run all tests (61 tests, 0.5s)
swift test --filter <TestName>   # Run a single test
```

## Project architecture

VideoVision analyzes ski posture from video using Apple's Vision framework (`VNDetectHumanBodyPoseRequest`). macOS 14+ is required.

Three targets in `Package.swift`:
- **VideoVisionCore** — shared library (14 source files, ~5,200 lines)
- **VideoVisionCLI** — macOS CLI entry point, depends on VideoVisionCore
- **VideoVisionCoreTests** — 10 test files, depends on VideoVisionCore

Separate iOS app at `SkiAnaylze/` (Xcode project, ~1,800 lines of UI + 2,100 lines of duplicated core code). Not part of the SwiftPM workspace.

## Analysis pipeline

```
Video frame (CGImage, 1fps default)
  → VisionFrameAnalyzer — runs VNDetectHumanBodyPoseRequest (configurable via VisionAnalysisOptions)
  → PoseMetricsCalculator — 8 joint keypoints → angles, hipRatio, signed lean, center coords
  → PoseScorer — 5-dim weighted scoring (forwardLean 20%, kneeBend 25%, calfLean 20%, gravity 20%, symmetry 15%)
  → DetectionResult (per-frame)
  ↓
Post-processing:
  → SkiMetricsCalculator — 3 derived metrics (edge quality, pressure support, fore-aft support)
  → KeyMomentDetector — worst/best frames (≤5, confidence-filtered)
  → BoardDirectionAnalyzer — ankle-proxy board angle, sideslip, carving confidence
  → TurnPhaseDetector — edge signal → transition/initiation/shaping/release phases
  → CenterOfMassFitCalculator — stage-aware hip-ratio target ranges
  → HighlightMomentDetector — best continuous segments (≥3 frames)
  → ReportGenerator — natural-language Markdown report
```

`VideoAnalyzer` orchestrates frame extraction + per-frame analysis. All post-processing happens in `main.swift` (CLI) or `VideoAnalysisManager` (iOS app).

## Key design decisions

- **Confidence gating everywhere**: `AnalysisReliability.minimumPoseScoreConfidence = 0.30` and `minimumSkiMetricConfidence = 0.35` in `Utilities.swift`. Low-confidence frames are kept in JSON output but excluded from scoring conclusions. Reports show "暂不评分" for unreliable data.
- **Stable carving baseline**: When motion stability ≥ 85 AND a continuous ≥5-frame high-score plateau exists covering ≥18% of the video, the system treats the plateau average as the true score. This prevents low-Vision-confidence frames in high-quality carving from being misjudged as poor performance.
- **Evidence caps**: Edge evidence, board kinematic evidence, and reliable frame count each impose progressive score caps to prevent false-high scores from good posture without real edge/carving evidence.
- **VideoSeed uses DJB2 hash** of filename, not Swift's `hashValue` (which is randomized across processes). Ensures deterministic report output for the same video.
- **Board visual line detector is debug-only**: `BoardVisualLineDetector` finds candidate board lines from image texture but `BoardDirectionAnalyzer.selectObservation()` always returns ankle-proxy. Visual candidate is stored in `DetectionResult.visualBoardObservation` for manual calibration review via `--debug-overlay`.

## Code duplication (known technical debt)

`SkiAnaylze/SkiAnaylze/Sources/` has 8 files duplicated from `VideoVisionCore/`. The iOS app compiles these directly instead of importing VideoVisionCore. The `SkiAnaylze/Package.swift` already declares the dependency and excludes `Sources/`, but the Xcode project hasn't been updated to use it. See REFACTOR_PLAN.md Phase 2.

Additionally, utility functions (`weightedAverage`, `average`, `formatTime`, `normalizeAngle`, `medianSampleInterval`, `weightedConfidence`, `weightedStandardDeviation`) are duplicated across multiple files. These should be consolidated into `Utilities.swift` as public functions.

## Scoring thresholds

All thresholds are empirical estimates based on biomechanics principles and coaching experience, not controlled experimental data. Calibration feedback is in `annotations/calibration_anchors.md`. Key ranges:
- Lean angle: ideal 10°–60° (wide range — 2D can't distinguish forward lean from lateral tilt)
- Knee bend: ideal 80°–135°, deep knee penalty light (4pts/10°), straight leg penalty heavy (28pts/10°)
- Calf lean: 0°=0pts, 80°=100pts
- Gravity: continuous `107.5 - hipRatio × 100`, clamped to [10, 100]
- Symmetry: weighted (knee diff 0.5, calf diff 0.3, lean diff 0.2)
- Quality caps: totalScore ≤ 72 when knee < 60 or symmetry < 45

## Stage classification logic

`StageClassifier.determineStage()` uses avgScore, calfScore, kneeScore, and stabilityScore:
- `< 50` → basicDetection
- `50–59` → basicControl
- `70+ calf < 55` → stableSkiing
- `70+ calf ≥ 55 + knee ≥ 70` → carvingEmerging
- `75–79` → qualitySkiing
- `80+ calf ≥ 65` → advanced, else qualitySkiing
