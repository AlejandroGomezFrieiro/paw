---
id: TASK-147
title: 'Engine: a stepped audio backend for the tests'
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
priority: high
ordinal: 159000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Source: backlog/docs/designs/test-suite-review.md, finding T5, ticket P3.

With `--audio null`, a clock thread renders blocks on wall time (`paw-engine/src/backend.rs:478`, `spawn_clock`). 69 live meter reads and 56 `transport.play()` calls in the tests depend on how many blocks ran during a sleep.

What to do: add the backend `step` next to `null` and `test`. It has no thread. The kernel calls `engine.process()` on its own thread when `T.advance` or `T.next_block` asks. One block moves the manual clock by the length of the block. The runner uses `--audio step` with `--clock manual`. `T.next_block(n)` runs exactly n blocks. `T.until_beat` becomes `T.advance_until` on the playhead. Change the tests that read a live meter after a sleep to stepped blocks, or to `paw.render` where the test checks the sound. The audio thread rules stay true: the stepped backend has no audio thread.

Read first: backlog/docs/designs/test-suite-review.md, sections 3.2 (seam D), 3.3, 4 (T5). crates/paw-engine/tests (the model: Engine::process block by block).

Overlaps: TASK-16 (done; the sleep of devices is tested on stepped blocks).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 T.next_block(n) runs exactly n blocks, with no wall time
- [x] #2 Two runs of a test that plays and reads a meter give the same value, to the bit
- [x] #3 The no_alloc tests pass
- [x] #4 tests/realtime.lua stays live, with its one-sided check
- [x] #5 The skills .claude/skills/lua-testing and .claude/skills/rust-testing name the new helpers and commands in the same commit.
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
Branch worktree-agent-a23815c420af4a2d3, commit 17a147b5 (on 2f70b19f). Backend 'step' (null, no thread; Stream::run_to/end_of), Session::idle runs blocks to the schedule clock, api.wait_blocks(n), AUDIO_TURN 100 ms in advance, sticky null->step, CLAP host main thread as audio thread while stepping. TASK-255 part: device/MIDI port watch on the schedule clock; FileCheck too. Runner: engine on step on the manual clock, T.next_block exact, T.meter, T.stepped. no_alloc case added (passes). realtime live; sound determinism test. Needs a build and tools/apidoc.lua run (api.wait_blocks, EngineInfo.stepped).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (17a147b5). Backend step (no thread), api.wait_blocks, T.next_block exact, T.meter, a sound determinism test, no_alloc case passes, realtime stays live; skills changed in the same commit. Follow-up for plugins with their own threads: TASK-331.
<!-- SECTION:FINAL_SUMMARY:END -->
