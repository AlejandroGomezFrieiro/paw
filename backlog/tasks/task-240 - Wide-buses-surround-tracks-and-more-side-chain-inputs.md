---
id: TASK-240
title: 'Wide buses: surround tracks and more side-chain inputs'
status: To Do
assignee: []
created_date: '2026-11-23T07:14:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-L
  - engine
  - design
  - blocked-by-plan
milestone: m-14
dependencies:
  - TASK-317
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 301000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician mixes for 5.1 or ambisonics, or uses a plugin with more than one side-chain input (a multiband ducker, a vocoder with two keys).

**Other DAWs.** Ardour and REAPER have wide buses and surround panners (design doc, gap 8, matrix row "Surround": importance L).

**paw now.** docs/reference/limits.md: "Plugins with main buses wider than stereo (surround), and inputs other than the main pair and one side-chain." The engine mixes stereo tracks.

**What to build.** First a design (the subtask). It answers: the channel count of a track and a bus, the panner, the render of more than two channels, plugin bus layouts (CLAP audio ports, VST3 speaker arrangements, LV2), more side-chain inputs, and what the terminal shows. The implementation tickets come after the owner approves the design.

**Core or extension.** Core: the engine and the plugin hosts.

**Priority.** Low: few users of paw (keyboard and terminal musicians) mix in surround.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The design subtask is done and the owner approved it
- [ ] #2 The implementation tickets exist, each with acceptance criteria
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
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): A lane type has a channels property and ports declare the type that they need (ADR 0028). Wide buses build on TY. architecture-plan.md V2.10 m-14. Unblocked by: TY.
<!-- SECTION:NOTES:END -->
