---
id: TASK-342
title: 'Rust sweep fixes: one bundle (core and rest)'
status: Done
assignee: []
created_date: '2026-11-24T06:00:00Z'
updated_date: '2026-11-24T14:15:00Z'
labels:
  - rust
  - refactor
  - agent:builder
milestone: m-10
dependencies: []
priority: high
ordinal: 411000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Rust sweep of 2026-11-24 (reports: backlog/docs/designs/rust-sweep-core-2026-11-24.md and rust-sweep-rest-2026-11-24.md) found anti-patterns of the rust-skills skill. The owner: fix them at once, in the next batch, with one agent. Parts that a running agent already touches go to that agent (see notes). This ticket takes TASK-341 in full.

Scope here: CORE-0 items 2 and 5 (checks; the leftovers are already removed in f4d81913), CORE-1 items 1-8 except the files of M1 (model.rs, model/overrides.rs), CORE-2, CORE-3 items 3-4 (long functions, bool flags; the Shared split last, after T96 lands), R1, R2, R3, R5, R6, R7 and the lints and rustlint checks of both reports. R4 (typed errors, Method enum): propose the ADR only. R8: not in scope. Mapper split (CORE-3 item 2): not in scope (TASK-312). CORE-4 sleep loops: TASK-331.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each bundle above meets the acceptance criteria that its report section gives (rg checks, no saved byte changes, same error texts)
- [x] #2 tools/rustlint.sh runs in nix flake check: no constant serde helper, no tracked .orig/.rej, model does not name sync/session/api/kernel, no new is_zero/is_one style helper outside one serde_util
- [x] #3 The workspace lints of the reports are on (too_many_lines 100, excessive bools, allow_attributes_without_reason, unwrap_used outside tests) with a written #[expect(.., reason)] at each kept site, and clippy reports 0 warnings
- [x] #4 Golden files, insta snapshots, the sandbox wire JSON, WAV render bytes and the Lua-visible error texts do not change
- [x] #5 R4 has a proposed ADR in the report (Changes for the orchestrator), not code
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
Retro 2026-11-24: the lint mechanism (workspace lints, rustlint.sh, the ratchet file) moved to the new Rust idiom ratchet ticket. Here: pay the counts down only. AC #2 and #3 are covered there.

On local main (fabe6c16, 2026-11-24, not pushed), merged with the other of 342/348. Reviews: merge (342 after the H1 lost-events and H2 RESET_ON_FORK fixes). Merge-check: apidoc 0, workspace clippy -D warnings clean, nextest 709/709, suite words all passed, ast-grep rules pass, expect debt 631. Follow-ups: TASK-350, TASK-354, rule gaps on TASK-352.
<!-- SECTION:NOTES:END -->
