---
id: TASK-237.3
title: 'Audio clip view: a spectrogram mode'
status: To Do
assignee: []
created_date: '2026-11-23T07:13:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - media
  - views
  - blocked-by-plan
milestone: m-14
dependencies:
  - TASK-237.1
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
parent_task_id: TASK-237
priority: low
ordinal: 298000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician sees the spectrum of a clip over time (a spectrogram) to find a noise, a hum or a click, as in Audacity or REAPER.

**paw now.** The `meter` device gives a spectrum in bands (`paw.params.read(m, "spectrum", n)`, docs/reference/devices.md). paw-measure measures the spectrum in octave bands (docs/reference/source-tree.md). No view shows a spectrogram.

**What to build.** A mode of the audio clip view that draws a spectrogram as a picture (cells in half blocks where the terminal has no pictures). The spectrogram is a bake of the clip, made off the kernel thread and kept by the media cache (TASK-10), so a key never waits.

**Out of scope.** Spectral edit (paint out a noise). The design doc ranks it low; it needs an owner decision.

**Core or extension.** The FFT frames come from a generic paw.api measurement (core). The mode can be core in the view, or an extension through a view hook. Prefer an extension if the view gives a hook, because few users need it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: the spectrogram frames of a generated sine sweep peak at the right band at each time
- [ ] #2 Test with real keys: the mode key shows the spectrogram (golden screen in the terminal, half blocks without pictures)
- [ ] #3 The bake does not run on a key: the view shows the waveform until the bake is ready
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
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): The audio clip view is an editor of the clip kind audio (paw.editor.define, bundle B7) and draws the built-in kind through the API (bundle B6). architecture-plan.md V2.10 m-14. ADR 0018. Unblocked by: B6 and B7.
<!-- SECTION:NOTES:END -->
