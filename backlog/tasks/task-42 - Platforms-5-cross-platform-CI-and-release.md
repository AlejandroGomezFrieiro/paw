---
id: TASK-42
title: 'Platforms 5: cross-platform CI and release'
status: To Do
assignee: []
created_date: '2026-11-21T19:33:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - platforms
  - ci
  - release
milestone: m-1
dependencies:
  - TASK-38
priority: low
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A release pipeline that builds, tests (Lua suite, Rust tests, a smoke test with --audio null) and packages every supported target from one tag; checksums; the docs' install page per platform. The e2e suite runs at the release check (owner rule).
<!-- SECTION:DESCRIPTION:END -->

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
Better testing (2026-11-22): the nightly tier runs in CI only (owner). TASK-145 writes the tiers; TASK-151 writes the CI matrix (release and dev build, -j 1, -j 4 --shuffle) and the TAP or JUnit output; TASK-155 sets INSTA_UPDATE=no in CI; TASK-159 builds the fuzz targets in CI and runs them nightly. Add a bench report of the key times against rule 7 to the release check, as a report and not a failure (test-suite-review.md, question 3).

TASK-145 (2026-11-23): the CI matrix is in the skill paw-code, part 7: release and dev build, each with suite.sh -j 1 and suite.sh -j 4 --shuffle; keep target/test-scratch/suite.tap and times.txt as artifacts. The nightly tier (CI only) is in the same table.
<!-- SECTION:NOTES:END -->
