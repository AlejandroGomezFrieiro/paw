---
id: TASK-133
title: 'Tools: apidoc in Teal as readers and writers; its check in the flake'
status: Done
assignee: []
created_date: '2026-11-22T19:00:00Z'
updated_date: '2026-11-23T23:03:00Z'
labels:
  - architecture
  - lua-review
milestone: m-8
dependencies: []
priority: medium
ordinal: 145000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port `tools/apidoc.lua` to Teal with readers that fill one model and one writer for each of the 8 outputs. Add `apidoc check` to `nix flake check`. Make `tools/tlcheck.sh` and `paw.lang.check` use the same rules.

Read first: backlog/docs/designs/architecture-review-lua.md, the finding L9 and its proposal P11.

Overlaps: TASK-96, TASK-67 (done), TASK-22.
Dependencies: none; easier after the first area of TASK-96.

Owner decisions (2026-11-22): the review's recommendations are accepted. notation and utau are not ported to Teal: they move to Rust as native extensions later (a separate ticket).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 the outputs are the same bytes as before the port
- [x] #2 `nix flake check` fails on a stale declaration
- [x] #3 one set of Teal rules, written in the teal skill
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
Better testing (2026-11-22): TASK-157 (contract test of the API boundary) can read the API list through the reader of this ticket.

PO 2026-11-23 (plan V2 bundles): A2 (TASK-306) depends on it. Run it before T96 (TASK-96): both change tools/apidoc.lua.

Done on branch worktree-agent-a42bd289022a1888f, commit dda6677c. tools/apidoc/ in Teal: read/rust.tl, read/lua.tl and read/teal.tl fill model.tl, and write/ has one writer for each of the 11 files. Outputs are byte-identical to the old generator (same binary; base tree and batch-19 tree). tools/tlcheck.lua is the one strict check, run by tlcheck.sh, tests/teal.lua and the flake. New flake checks apidoc and teal, both run paw. AC 1-3 met; evidence in the report. ADR 0006 is not edited (accepted); the new guard is a Target row in architecture section 10.

Merge note: batch 19 fixed tools/apidoc.lua rust_records to read pub(crate) and pub(super) structs (commit 5322d9ba; TASK-98 made the event structs pub(crate)). The Teal port's read/rust.tl must do the same when TASK-133 merges after batch 19, or events/kernel.tl loses its events.

On main in batch 20 (5041115e, pushed 2026-11-24 with the tag pre-parts). Full suite passed after one test fix (5041115e: three tests and the time-axis test expected the null backend); nix flake check passed.

PO 2026-11-24: ACs checked against main: tools/apidoc/ in Teal (read/, write/), tools/tlcheck.lua, flake checks teal and apidoc.
<!-- SECTION:NOTES:END -->
