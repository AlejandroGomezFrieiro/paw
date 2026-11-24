---
id: TASK-239
title: Track meters show RMS or loudness, not only peaks
status: To Do
assignee: []
created_date: '2026-11-23T07:14:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-S
  - mix
  - engine
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 300000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician sees which track is loud in the mix, not only which track peaks. A peak meter shows the drums high and the pad low, even when the pad is louder to the ear.

**Other DAWs.** REAPER and Ardour have RMS or loudness track meters (design doc, gap 9 and matrix row "LUFS meter": P).

**paw now (checked 2026-11-23).** The design doc says "Per-track loudness ... (peak only now)". **That is partly wrong.** The `meter` device on any track gives momentary, short-term and integrated LUFS, RMS, correlation and a spectrum (docs/reference/devices.md). The mixdiag extension measures what one track adds to the mix (`<Space>mk`). What is true: the track meters of the mixer and of the track headers are peaks only (crates/paw-engine/src/engine/mod.rs keeps the peak of each block; docs/reference/limits.md "the track meters are peaks").

**What to build.** An option of the meters (for example `paw.opt.track_meter = "peak" | "rms" | "lufs"`). RMS over 300 ms is cheap in the engine. Momentary LUFS for each track costs a K-weighting filter for each track: measure the cost in bench/ before the choice to offer it. The mixer shows the value and the peak hold.

**Core or extension.** Core: the engine measures the tracks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: with the RMS mode, a generated sine at -12 dBFS peak gives -15 dB RMS +/- 0.1 on the track meter
- [ ] #2 tests/no_alloc.rs passes in each mode
- [ ] #3 Test with real keys: :set track_meter=rms changes the mixer meters (golden screen)
- [ ] #4 bench/ has the cost of each mode with 64 tracks, with the spread
- [ ] #5 docs/reference/mixer-view.md, options.md and limits.md say it; Vale reports 0 alerts
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Each acceptance criterion is met, and the notes give its evidence
- [ ] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [ ] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [ ] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [ ] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [ ] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [ ] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [ ] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): After MX the meters belong to strips and buses (nodes). Build it on the meter values of today; MX moves them. Write strip, not track, in new text.
<!-- SECTION:NOTES:END -->
