---
id: TASK-341
title: 'Rust: no constant helpers and no per-value serde defaults'
status: To Do
assignee: []
created_date: '2026-11-24T05:11:00Z'
updated_date: '2026-11-24T16:41:00Z'
labels: []
milestone: m-10
dependencies: []
priority: medium
ordinal: 410000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The owner found functions such as fn yes() -> bool { true } (paw-core attr_map.rs, paw-engine device.rs) and fn one() -> f64 { 1.0 } (model.rs, model/chain.rs), each used as #[serde(default = "yes")] / "one", with copies in several files. Apply the rust-skills skill: struct-level #[serde(default)] with one impl Default (or a field type whose Default is right); no function that only returns a constant; no duplicated helpers. Audit all crates except paw-gui for the same pattern and for other anti-patterns of the skill that the same search finds (zero-argument functions that return a literal, is_true/is_one style skip helpers that a shared generic could replace). Keep the file bytes: saved projects must not change (golden tests).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 git grep finds no #[serde(default = "...")] that names a constant helper, and no function whose body is only a literal, in crates/ except paw-gui
- [ ] #2 The golden file tests of project folders and racks keep their bytes
- [ ] #3 A check in the suite or the flake (or a clippy lint if one fits) refuses a new constant helper
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
Done inside TASK-342 (the one sweep-fix bundle, owner 2026-11-24).

2026-11-24: set back to To Do. It was In Progress with no agent and no branch.
<!-- SECTION:NOTES:END -->
