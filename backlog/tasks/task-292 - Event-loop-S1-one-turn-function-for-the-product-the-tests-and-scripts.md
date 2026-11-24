---
id: TASK-292
title: >-
  Event loop S1+S2+S5: one turn function, one clock rule, an honest stepped
  backend (EL1)
status: Done
assignee: []
created_date: '2026-11-23T13:26:00Z'
updated_date: '2026-11-23T23:03:00Z'
labels:
  - event-loop
  - bundle
milestone: m-10
dependencies:
  - TASK-147
references:
  - architecture/decisions/0017-architecture-plan-as-target.md
  - architecture/decisions/0016-portable-core.md
  - backlog/docs/designs/architecture-plan.md
documentation:
  - backlog/docs/designs/event-loop-review.md
priority: high
ordinal: 354000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle EL1 of backlog/docs/designs/architecture-plan.md (V2.11; section 6.2 gives the criteria). It merges TASK-293 (S2) and TASK-296 (S5).

Design: backlog/docs/designs/event-loop-review.md S1, S2 and S5, with the Rust shapes of rust-architecture.md 5.2 and architecture-plan.md E1, E2, E5. Kernel::turn is the one turn for run, step, wait and request. One clock rule: the schedule clock for every 'when' in Rust, and a lint. The stepped backend reports Step.

Start on main with batch 18 (TASK-147). TASK-95.1 (P95) runs at the same time and gives Document the time as an argument: P95 passes `now` as a plain value; EL1 owns the Clock and ScheduleTime types. Agree on this in the notes. TASK-99 waits for this bundle.

Read first: the skill .claude/skills/architecture, architecture/06-runtime.md, the design, the notes of TASK-293 and TASK-296. Size: L. One Opus agent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Kernel::turn(now: ScheduleTime) -> Agenda is the one turn. run, api.step, api.wait and request (through close_turn and agenda) use it. Shared::turn, the second IDLE_PERIOD and the work inside api.events_take are gone. A Rust test with a recording frontend and Clock::Manual records the same order of steps through run and through api.step (EVL I1)
- [x] #2 The order of a turn has a slot for ExternJobs after the sync (E5), empty until TASK-75.3
- [x] #3 enum Clock { Wall, Manual } and ScheduleTime replace Arc<dyn Clock>. The five clock fields of the session go; Upkeep-style polls get now
- [x] #4 crates/paw-core/clippy.toml refuses Instant::now with a reason; each budget site has #[expect(clippy::disallowed_methods, reason)]; cargo clippy passes
- [x] #5 The sweep merge and the touch release run on the schedule clock, each with a test on the manual clock that steps the clock
- [x] #6 StreamInfo reports Backend::Step; null_steps is gone; api.wait_blocks on a backend that is not stepped gives an error; :engine threads= does not wait 500 ms
- [x] #7 A reference page The order of a turn in docs/reference/ names the same steps as the test of AC 1; Vale reports 0 alerts
- [x] #8 The full Lua suite passes. The tests whose result changed with the order (MIDI before timers in scripts) are listed in the notes
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
Owner 2026-11-23 15:40 accepted the agents' recommendations: the open questions of event-loop-review.md take their recommendation (model name 'a reactor with an agenda plus a real-time engine'; plugin idle only when a plugin asks, after a measurement of five common plugins; the 250 ms safety poll stays; record/replay as a message log only, after S1; edit.before order in its own ticket).

EL1 done on branch worktree-agent-ad30129949da073ee, commit 77f110c9 (base 93d55dbf). One turn: Reactor::turn (kernel/reactor.rs) for Kernel::run, api.step, api.wait (both clocks); request() closes through Reactor::close_turn; Shared::turn, the second IDLE_PERIOD and the work in events_take are gone; a nested turn handles only MIDI and helper output. Upkeep (Session::idle) runs each turn; the wall wait blocks on the channel. New api.flush; Lua K.settle became K.close_turn. Step backend: StreamInfo.backend == Step, stepped/null_steps removed, engine_restart without a backend keeps the running one, wait_blocks errors when not stepped, suite.sh passes --audio step, :engine threads= no longer waits 500 ms. Rust tests pass; the Lua suite waits for a build. Architecture 06 edits staged in scratchpad/pending-arch/EL1-06-runtime.md, applied at merge.

PO 2026-11-23 (after batch 18+19): TASK-331 (plugins with their own threads on the stepped backend, three quarantined tests) starts after this bundle merges.

On main in batch 20 (5041115e, pushed 2026-11-24 with the tag pre-parts). Full suite passed after one test fix (5041115e: three tests and the time-axis test expected the null backend); nix flake check passed.

PO 2026-11-24: ACs checked against main 5041115e: Reactor::turn in kernel/reactor.rs, enum Clock in clock.rs, clippy.toml refuses Instant::now, touch release test on the schedule clock (session/write.rs), docs/reference/the-order-of-a-turn.md, Backend::Step; suite passed in batch 20. AC2: the slot for jobs of extensions is in step 4 of the turn (none yet). AC8: the notes do not list the tests whose result changed with the order; fix 5041115e names three tests and the time-axis test.
<!-- SECTION:NOTES:END -->
