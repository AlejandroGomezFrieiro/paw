---
id: TASK-158
title: 'Tests: one check helper and text fixtures for key tests'
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - tests
  - better-testing
milestone: m-12
dependencies:
  - TASK-146
priority: low
ordinal: 170000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/testing-practices.md, practices R1 and R2, ticket BT10, rank 9.

What to do: a fixture format for a small project in a Lua string (tracks, clips with notes, a cursor and a selection marker) and a helper `T.check_keys(fixture, keys, expected_fixture)`. Move the key tests of one area (the piano roll motions) to it as the first user.

Read first: backlog/docs/designs/testing-practices.md, sections 2.1 (R1, R2), 5.2 ("One check per feature"), 6 (BT10).

Overlaps: TASK-121 (T.start).

Size: S to M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The format has a reference comment in tests/suite.lua
- [x] #2 A failure prints the actual fixture, ready to paste
- [x] #3 The moved tests are shorter (lines in the commit)
- [x] #4 The skills .claude/skills/lua-testing and .claude/skills/rust-testing name the new helpers and commands in the same commit.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built with TASK-145 on branch worktree-agent-a8062e24546374fe4, commit 29d60d1d. T.check_keys(fixture, keys, expected, what), T.fixture, T.fixture_text in tests/tools/fixture.lua; format reference in tests/suite.lua; a failure prints the project as a fixture. The piano roll grammar test in tests/modal.lua moved to it (15 cases, plus x on chosen notes and gA).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main with TASK-145 (29d60d1d). T.check_keys, T.fixture, T.fixture_text in tests/tools/fixture.lua; format reference in tests/suite.lua; a failure prints the fixture; the piano roll grammar test moved to it; skills name the helpers.
<!-- SECTION:FINAL_SUMMARY:END -->
