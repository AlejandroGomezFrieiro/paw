---
id: TASK-99
title: 'Kernel: Shared in parts, host services behind a native feature'
status: To Do
assignee: []
created_date: '2026-11-22T10:38:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-10
dependencies: []
priority: medium
ordinal: 102000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: the shared state of the kernel (Shared) in parts, and the host services of paw-core (sockets, helper processes, TLS, file watch, ffmpeg) behind a default cargo feature native, so that the kernel builds without them for the web. Finding F5 of the architecture review (backlog/docs/designs/architecture-review.md).

Today: Shared (crates/paw-core/src/api/mod.rs, lines 48 to 112) has 26 fields; api/screen.rs uses only the screen fields. Shared holds io (Unix helper processes and sockets) and clients (tokio sockets, TLS): the paw-core blockers that backlog/docs/designs/web.md lists.

Change:
1. Structs Screen (grid, sizes, caps, seat, highlights, dirty flags, frames, snapshot, redraws, attached, cursor), Timers, Seats (clients, input_from, detach), Inbox (MIDI in) inside Shared; each api area reads its part.
2. Feature native (default) gates rpc, tls, io, io_runtime, bake::helper, session::encode, session::files_watch. Without it the paw.api functions exist and fail with a clear message (for example "helper programs are not in this build").
3. cargo check -p paw-core --no-default-features passes on Linux (wasm32 is TASK-30).

Read first: the review, F5 and F9; crates/paw-core/src/api/mod.rs; rpc.rs; io.rs; backlog/docs/designs/web.md (Blockers by crate); TASK-44, TASK-30, TASK-51.
Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Shared groups its fields in Screen, Timers, Seats and Inbox
- [ ] #2 cargo check -p paw-core --no-default-features passes; CI runs it
- [ ] #3 Without native, each gated paw.api function gives a clear error; a test calls one
- [ ] #4 With default features the Lua suite passes unchanged
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
Board review 2026-11-23: still open. Priority medium: m-10 comes after m-2, m-3 and m-12 (owner focus), and the web build (m-0) that needs the native feature is not in the focus.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): Run after EL1 (TASK-292): EL1 deletes Shared::turn and changes the same struct. Not in the same batch as EL1 or EL2.
<!-- SECTION:NOTES:END -->
