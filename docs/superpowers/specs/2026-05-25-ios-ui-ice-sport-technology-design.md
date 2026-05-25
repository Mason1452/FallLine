# FallLine iOS UI Redesign: Ice Sport Technology

Date: 2026-05-25
Status: Approved design direction, not yet implemented

## Goal

Redesign the FallLine iOS app so it feels clearly connected to skiing and more premium than the current generic dark-card UI.

The approved direction is **Ice Sport Technology**: a ski-motion analysis product that feels like an on-slope AI coaching cockpit. The visual language should communicate cold mountain air, speed, carving tracks, pose detection, and credible sports analytics.

## First Principles

FallLine is not a generic video uploader. Its value is that it interprets skiing posture and gives coaching feedback. The UI should therefore make three things obvious at first glance:

1. This is a skiing product.
2. This is an analysis tool, not a decorative media app.
3. The result is trustworthy enough to support training decisions.

The redesign should avoid adding ornamental snowflakes as the main theme. Skiing should appear through slope geometry, carving lines, motion traces, body-pose overlays, snowfield depth, and coaching metrics.

## Visual Direction

### Personality

- Professional, sharp, cold, fast, technical.
- Premium sports-tech rather than playful fitness app.
- Cool enough to feel exciting, but not so neon-heavy that it becomes a game UI.

### Color System

Use a cold, high-contrast base:

- Deep night: `#02070D`
- Alpine navy: `#06111E`
- Panel blue: `#0B1B2A`
- Ice text: `#F3FDFF`
- Snow secondary: `#BFEFFF`
- Primary cyan: `#29D7FF`
- Success mint: `#6DFFBF`
- Data blue: `#7AB7FF`
- Warning amber: `#FFC15E`
- Problem red: `#FF6363`

The interface should not be dominated by flat dark blue cards. Backgrounds should combine dark alpine depth, subtle snowfield gradients, slope silhouettes, grid overlays, and motion traces. Warm colors are reserved for warnings and important coaching callouts.

### Materials

- Use translucent glass panels with thin ice-blue borders for metric surfaces.
- Prefer restrained glow around active data, scan states, and carving traces.
- Keep cards compact and purposeful; avoid stacking generic rounded cards everywhere.
- Use 16-20 pt corner radii for major glass panels, smaller radii for internal rows.

### Iconography

Reduce generic SF Symbols such as `house.fill`, `video.fill`, and `clock.fill` as the primary brand signals. Replace the main visual cues with:

- Carving line / fall-line trace
- Pose skeleton / body joints
- Slope grid / scanning reticle
- Video HUD
- Score ring
- Training archive
- Share report card

SF Symbols can still be used where they are semantically clear, but the app should not rely on them for ski identity.

## Screen Designs

### 1. Home

Purpose: Make the app immediately feel like a skiing AI coach and make video upload the clear primary action.

Layout:

- Full-screen alpine night background with subtle mountain silhouette and grid.
- Hero copy: `Carve Sharper.` with a smaller `AI Ski Motion Coach` label.
- A curved cyan carving trace runs through the hero/background.
- A compact last-session glass panel shows total score, edge score, and support score.
- Primary CTA: `选择滑雪视频`, rendered as a glowing ice-gradient pill.
- Bottom navigation should feel more like a tool switcher than default tab chrome.

### 2. Video Confirmation

Purpose: Confirm that the selected video is suitable before analysis.

Layout:

- Large video preview panel with a snowfield-like thumbnail treatment or actual video preview.
- Three compact metadata tiles: duration, aspect ratio/resolution, estimated analysis frames.
- `Quality scan` glass panel with check/warning rows:
  - Person visible
  - Pose detectable
  - Person could occupy more of the frame
- Primary CTA: `开始 AI 分析`.

The screen should feel like a preflight scan, not a plain confirmation modal.

### 3. Analysis Progress

Purpose: Show that real technical work is happening and reduce perceived wait time.

Layout:

- Central circular scan ring with percent progress.
- Stage label: pose detection, edge direction, center-of-mass, report generation.
- Step list in a glass panel with done/active/pending states.
- Subtle background grid and mountain silhouette.
- Cancel action remains available but visually secondary.

Avoid a plain progress bar as the dominant element. The core visual should be a scanning instrument.

### 4. Report Detail

Purpose: Make results feel credible, inspectable, and actionable.

Layout:

- Video player at the top with HUD treatment:
  - Pose skeleton overlay style
  - Carving trace
  - Moment label such as `00:14 Best edge moment`
- Main score panel:
  - Ring score, not just a large number
  - Level label, e.g. `中级 · 有刻滑雏形`
  - Compact bars for edge, support, stability
- Key moment rows:
  - Small thumbnail
  - Time and moment type
  - Short coaching explanation
- Problem and training advice sections should remain readable and calm; do not over-style long text.

Report detail is the most important screen. It should balance visual excitement with coaching trust.

### 5. History

Purpose: Let users compare sessions and return to useful reports.

Layout:

- Training-record language rather than generic document history.
- Each row uses a mini score ring, filename/session label, level, and primary issue.
- Optional filter/search affordance can be introduced later, but not required for the first redesign.

### 6. Share Card

Purpose: Produce a social-ready result card that still feels like FallLine.

Layout:

- Vertical card with dark alpine background, light trace, and large score.
- Include level, best moment, and FallLine branding.
- Optional QR/link area at bottom.

The share card should be more polished than the current text-only generated image.

## Component Set

Core components to implement:

- `FallLineBackground`: alpine night gradient, subtle mountain silhouette, optional grid and trace.
- `GlassPanel`: translucent dark panel with ice-blue border and blur.
- `PrimaryIceButton`: cyan/ice/mint gradient CTA.
- `MetricTile`: compact value + label tile.
- `ScoreRing`: ring visualization for 0-100 scores.
- `MetricBar`: horizontal metric indicator.
- `AnalysisStepRow`: progress step state.
- `MomentRow`: key-moment thumbnail + time + feedback.
- `HistoryReportRow`: mini score ring + session summary.

Keep these components simple. The goal is consistency, not a broad design-system rebuild.

## Implementation Scope

The first implementation pass should update only the iOS app UI layer:

- `SkiAnaylze/SkiAnaylze/AppTheme.swift`
- `SkiAnaylze/SkiAnaylze/ContentView.swift`
- `SkiAnaylze/SkiAnaylze/Views/HomeView.swift`
- `SkiAnaylze/SkiAnaylze/Views/AnalysisProgressView.swift`
- `SkiAnaylze/SkiAnaylze/Views/HistoryView.swift`
- `SkiAnaylze/SkiAnaylze/Views/ReportDetailView.swift`

Do not change scoring logic, analysis models, persistence, or duplicated core analysis files as part of this UI redesign.

## Out Of Scope

- Reworking the scoring algorithm.
- Changing the analysis pipeline.
- Adding account systems, leaderboards, subscriptions, or cloud sync.
- Large navigation rewrites beyond visual treatment.
- Replacing the duplicated iOS core code.

## Verification Criteria

The redesign is considered done when:

1. The app builds for iPhone Simulator.
2. The main screens show the Ice Sport Technology visual language consistently.
3. Text remains readable on common iPhone widths.
4. The upload, confirmation, analysis progress, report viewing, history, delete, and share flows still work.
5. The demo report still loads on first launch when no history exists.
6. No scoring or analysis output behavior changes.

Visual review should check that the UI feels ski-specific without relying on generic snowflake decoration.

## Open Decisions

No blocking design decisions remain. During implementation, the exact SwiftUI drawing strategy can be chosen pragmatically:

- Pure SwiftUI shapes for mountain silhouettes, grids, traces, and rings.
- SF Symbols where they are semantically useful.
- No new third-party UI dependency unless a concrete implementation blocker appears.
