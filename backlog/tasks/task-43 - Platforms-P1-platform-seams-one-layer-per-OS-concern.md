---
id: TASK-43
title: 'Platforms P1: platform seams (one layer per OS concern)'
status: To Do
assignee: []
created_date: '2026-11-21T19:52:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - platforms
milestone: m-1
dependencies: []
priority: medium
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Dirs, child processes (dies with parent, priority, kill tree), local IPC, shared memory + doorbell, random, CPU/disk stats, file watching behind traits; Linux implementations only, no behavior change. Size L. Unblocks macOS and Windows. Design: backlog/docs/designs/platforms.md.
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
Architecture review 2026-11-22 (backlog/docs/designs/architecture-review.md, F9 and the table of platform seams): one adapter in a build -> a module chosen at compile time (std::sys pattern: #[cfg_attr(target_os, path)] mod imp with the same signatures), not a dyn trait (doorbell, shm, child dies with parent, local socket, thread class, CPU/disk stats). A trait or enum only where one build holds two adapters (audio backend: cpal + null + offline (+ worklet); MIDI: ALSA + none; tty: crossterm + xterm.js; device providers TASK-97). Crates, not seams: etcetera, notify, ring/getrandom, fs4, sysinfo. One crate paw-sys used by paw-core, paw-plugins, paw-tui, paw-gui, paw-mcp: 'child dies with parent' exists in 5 places today (io.rs, bake/helper.rs, session/encode.rs, paw-mcp kernel.rs, paw-gui client.rs without cfg).
<!-- SECTION:NOTES:END -->
