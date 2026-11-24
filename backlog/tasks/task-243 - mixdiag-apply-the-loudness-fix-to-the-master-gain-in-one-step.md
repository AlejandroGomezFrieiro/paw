---
id: TASK-243
title: 'mixdiag: apply the loudness fix to the master gain in one step'
status: To Do
assignee: []
created_date: '2026-11-23T07:15:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-S
  - extensions
  - mix
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 305000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** After a check of the mix against a target (Spotify, EBU R 128), the musician applies the gain that the check proposes, in one key, and hears the result. Ardour has this as the Loudness Assistant.

**Other DAWs.** Ardour Loudness Assistant (design doc, section 4.4: "mixdiag: delivery targets", low).

**paw now (checked 2026-11-23).** The design doc proposes "delivery targets in one command". **That already exists:** extensions/mixdiag has targets (`:mix.target ebu`, `<Space>mt`, the option `mixdiag_target`, custom targets in `mixdiag.targets`) and measures the song (`<Space>ma`). What is missing: mixdiag/README.md says "Fixes are advice only. Nothing in the project changes."

**What to build.** A fix action for the loudness finding: set the gain of the master (or of the `limiter` input on the master) by the difference to the target, as one undo step, and measure again. It shows in `<Space>la` (the fixes of the view) for the finding.

**Core or extension.** Extension (mixdiag).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lua test: after a measure of a generated song that is 3 LU under the target, the fix raises the master gain by 3 dB and a second measure is within the tolerance
- [ ] #2 Test with real keys: <Space>la on the finding offers the fix; u removes the gain change in one step
- [ ] #3 The fix refuses to raise the gain when the true peak would pass the ceiling of the target, with a clear message
- [ ] #4 The README says it; the README test passes
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
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): After MX the master gain is the fader of the Master node of the root part. Valid now; MX moves the reader.
<!-- SECTION:NOTES:END -->
