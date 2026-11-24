---
id: TASK-294
title: >-
  Event loop S3+S4: an agenda of upkeep, the doorbell, quiet defined in the
  kernel (EL2)
status: Done
assignee: []
created_date: '2026-11-23T13:26:00Z'
updated_date: '2026-11-24T03:24:00Z'
labels:
  - event-loop
  - bundle
milestone: m-10
dependencies:
  - TASK-292
references:
  - architecture/decisions/0017-architecture-plan-as-target.md
  - backlog/docs/designs/architecture-plan.md
documentation:
  - backlog/docs/designs/event-loop-review.md
priority: high
ordinal: 356000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle EL2 of backlog/docs/designs/architecture-plan.md (V2.11; section 6.3 gives the criteria). It merges TASK-295 (S4).

Design: backlog/docs/designs/event-loop-review.md S3 and S4, with rust-architecture.md 5.2 and architecture-plan.md E3, E4, M5, M6. An Upkeep trait with its implementations, wake-ups in place of the 16 ms poll (a mio doorbell), quiet in the kernel. It fixes the latent bug: with needs_idle false, a finished bake, hash or file change waits for the next key.

No other bundle that edits Session::idle in its batch. It can run beside W1 (it touches no Lua docs and no model). MD4 (TASK-10.1) builds the bake scheduler as an Upkeep on it.

Read first: the skill .claude/skills/architecture, architecture/06-runtime.md, the design, the notes of TASK-295. Size: L. One Opus agent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 trait Upkeep { fn kind(&self) -> Woken; fn poll(&mut self, now, &mut Vec<Outcome>); fn agenda(&self, now) -> Agenda; } with its implementations in Upkeeps; Session::idle loops over them and applies the outcomes. needs_idle and the fixed 16 ms poll are gone
- [ ] #2 Doorbell with mio::Waker: worker threads ring, the audio thread only marks. The main loop waits in mio::Poll; the inotify descriptor is a token and its thread is gone. The browser build keeps recv_timeout behind one #[cfg]
- [ ] #3 For each Upkeep, a Rust test with a fake worker sees its bit after the work ends (EVL I4), with no sleep
- [ ] #4 A quiet session after settle has no next_due, nothing in flight, and the loop waits with no timeout (EVL I3)
- [ ] #5 The safety tick (250 ms while work is in flight; 16 ms only for a controller that asks) counts missed wakes; the suite fails on a missed wake
- [ ] #6 (TASK-295) api.settle(), api.clock() and api.pending() with ready and quiet. T.settle calls api.settle; T.until_ fails on quiet with no due time. working, busy, POLL_TURNS, the collector name and MANUAL = api.now() == 0 are gone from the runner
- [ ] #7 Idle jobs (paw.slices, the collector, help) mark their timers idle = true
- [ ] #8 bench: wakes a second and CPU over 30 s with a plugin, before and after, in bench/RESULTS.md
- [ ] #9 Docs: the lua-testing skill, the how-to on tests and The order of a turn are true; Vale reports 0 alerts
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
EL2 in ef272758 (branch worktree-agent-a12d95492ea2ea886, base 82f0aad0): agenda (trait Upkeep, 9 parts in session/upkeep.rs), Doorbell (mio, doorbell.rs; paw_engine::Bell; inotify fd on mio), quiet (no timeout when idle; 16 ms tick only when a part asks, 250 ms safety tick with work in flight), api.settle/api.clock/api.pending (ready, quiet, in_flight, missed_wakes), idle timers (slices opts.idle). 13 new Rust tests. AC8 (bench) waits for the orchestrator's build. Deviations: stateless Upkeep parts with &mut Session (proposed ADR 0038), 11 doorbell kinds, browserpod waiter polls every 5 ms, CLAP main-thread requests only mark. api.md and api.d.tl hand-edited: regenerate after build. Architecture edits staged in scratchpad/pending-arch/EL2.md.

PO 2026-11-24: built, waits to merge (batch 21 or 22); status In Progress until it is on main.

Fix f508eaa2 (cherry-picked into batch 22 as cab47711): a plugin is never work in flight (a pending state or block request waits for the next block, which on the stepped backend comes only when the clock moves); plugins_tick is pure in session/upkeep.rs; Rust test a_plugin_that_waits_for_its_next_block_is_looked_at_each_frame_and_is_not_in_flight. Pending.in_flight no longer lists plugins (06-runtime edits: drop it if listed).

On local main in batches 21+22 (4300ace4, 2026-11-24, not pushed). Full suite passed after two fixes (cab47711 a plugin is not work in flight; 4300ace4 the pick test waits for the walk); nix flake check passed.
<!-- SECTION:NOTES:END -->
