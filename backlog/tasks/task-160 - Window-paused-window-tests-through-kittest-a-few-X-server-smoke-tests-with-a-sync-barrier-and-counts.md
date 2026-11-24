---
id: TASK-160
title: >-
  Window (paused): window tests through kittest, a few X-server smoke tests with
  a sync barrier and counts
status: To Do
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - tests
  - better-testing
milestone: m-13
dependencies:
  - TASK-146
priority: low
ordinal: 172000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
This ticket waits until the owner starts the work on the window again (owner, 2026-11-22: "We are deprioritizing work on paw-gui, we focus on terminal-first right now. Tests for paw-gui should not be run until we decide to work on it again. It should also not be built until then."). Do not start it before then.

Source: backlog/docs/designs/test-suite-review.md, finding T8 (the window part), ticket P7; backlog/docs/designs/testing-practices.md, practice U3, gap G13, ticket BT8. The two are merged here: kittest replaces the request `window.texts()` of the review (owner, 2026-11-22: the recommendations of both documents).

`crates/paw-gui/tests/window.rs` (45 tests) finds text by OCR (tesseract, 30 calls), waits 0.15 to 0.4 s after each gesture (`pause`, 42 uses), and checks shares of a processor (lines 1660, 1702, 1726, 1781).

What to do:
- Move each window test that finds text by OCR or waits after a gesture to kittest in the crate, with the fixture kernel of `src/gestures.rs`.
- Keep at most 5 X-server smoke tests (the window opens, draws text, takes a key, closes).
- A control request `window.sync` (an `XSync` and a marker event that the window echoes) for the smoke tests, and `window.counts()` (frames drawn, wakes). "An idle window does no work" becomes a count between two barriers. The shares of a processor go to `bench/profile`.
- Move or delete the `#[ignore]` OCR measurement (`window.rs:2177`).

Read first: backlog/docs/designs/test-suite-review.md, sections 3.2 (seam F), 4 (T8). backlog/docs/designs/testing-practices.md, sections 2.5 (U3), 6 (BT8).

Overlaps: TASK-42 (CI).

Size: L.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 At most 5 tests use tesseract
- [ ] #2 No pause() after a gesture in a test
- [ ] #3 No assertion on a share of a processor; idle is a count between two barriers
- [ ] #4 cargo test -p paw-gui passes three times in a row at load 30 or more
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
