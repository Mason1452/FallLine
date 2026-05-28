# iOS App Icon Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the iOS app icon with the approved D1 Alpine scan-reticle direction.

**Architecture:** Keep the change in the asset layer. Add a small Swift generator script for reproducible PNG export, update `AppIcon.appiconset/Contents.json`, and record the asset change in project context docs.

**Tech Stack:** Swift/AppKit/CoreGraphics, Xcode asset catalog, existing iOS Xcode project.

---

### Task 1: Generate And Wire App Icon Assets

**Files:**
- Create: `scripts/generate_fallline_app_icon.swift`
- Modify: `SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/AppIcon-Default.png`
- Create: `SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png`
- Create: `SkiAnaylze/SkiAnaylze/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted.png`

- [ ] Add the Swift icon generator.
- [ ] Run the generator to export three 1024x1024 PNGs.
- [ ] Add `filename` entries to the three universal iOS AppIcon slots.
- [ ] Verify image dimensions with `sips`.
- [ ] Build the iOS app with `xcodebuild`.

### Task 2: Update Context Docs

**Files:**
- Modify: `WORK_LOG.md`
- Modify: `CLAUDE.md`
- Modify: `AGENTS.md`
- Modify: `delta_update.md`
- Modify: `file_manifest.md`

- [ ] Record that the approved D1 Alpine scan-reticle app icon is now installed.
- [ ] Keep the notes short and current.
