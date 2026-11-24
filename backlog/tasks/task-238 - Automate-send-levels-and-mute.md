---
id: TASK-238
title: Automate send levels and mute
status: To Do
assignee: []
created_date: '2026-11-23T07:14:00Z'
updated_date: '2026-11-23T16:17:00Z'
labels:
  - parity
  - size-M
  - automation
  - blocked-by-plan
milestone: m-14
dependencies:
  - TASK-315
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: medium
ordinal: 299000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A musician rides the reverb send up on the last word of a phrase, or a delay throw on one snare hit, and mutes a track for four bars with automation. Most DAWs automate send levels and mute.

**Other DAWs.** Ardour and REAPER automate send levels, send pan and mute. The design doc marks automation as partial (matrix row "Automation": P) and names the send levels from docs/reference/limits.md.

**paw now (checked 2026-11-23).** The lane target in crates/paw-core/src/model.rs (`enum Target`) has `Volume`, `Pan`, `Param` and `State` only. A send (`struct Send`: `target`, `level`, `pre`) has no lane, and the track `mute` has no lane. limits.md: "Send levels and clip gain are not curves yet."

**What to build.**
- A send level lane: a new target that names the send by its destination track. It plays as the fader lane does, writes in the automation modes, and shows in the curve editor.
- A mute lane: a lane of two states, as a state lane holds a state up to the next point (docs/reference/automation.md "State lanes").
- `<Space>al` lists the sends and mute among what to automate.

**Core or extension.** Core: lanes and the engine are the model (docs/explanation/about-core-and-extensions.md: "automation lanes ... they are the model").

**Size.** M. Two subtasks if more than a day: send level, then mute.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rust test: a send level lane moves the level of the send at its points in a render (null render, no plugins)
- [ ] #2 Test with real keys: <Space>al offers the send to the bus and mute; a fader move of the send in touch mode writes the lane; u removes the write in one step
- [ ] #3 Rust test: a mute lane mutes the track from its point and unmutes at the next point, at the frame
- [ ] #4 Test: a project with the new lanes saves, loads and saves the same bytes
- [ ] #5 docs/reference/automation.md, curve-editor.md and limits.md say it; Vale reports 0 alerts
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
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): Automation becomes lanes of kind curve that feed a node parameter (ADR 0027); a send is a node. Rewrite the criteria for curve lanes on a send node when CV starts. architecture-plan.md V2.14. Unblocked by: CV.
<!-- SECTION:NOTES:END -->
