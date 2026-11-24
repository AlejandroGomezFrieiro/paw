---
id: TASK-215
title: >-
  Runtime: timers, a message sink and the command registry move below the upper
  layers
status: Done
assignee: []
created_date: '2026-11-23T06:42:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - architecture
  - runtime
  - layers
milestone: m-10
dependencies: []
priority: medium
ordinal: 243000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the Groma coupling report (TASK-209): 283 upward references; paw.notify (25), paw.defer (16), paw.cancel (12), paw.try (5), paw.every (4) and the like live in paw/init.lua (top layer) and paw/ui.tl (screen layer) but low layers need them. Move the timers to the kernel layer and notify to a message sink in the data layer that ui reads. About 79 exceptions of tools/layers-allowed.txt go (28%), and most two-way module pairs with them. Data: scratchpad/upnames.tsv. AC: the exceptions are removed from layers-allowed.txt; no behavior change; the suite passes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The timers (paw.defer, paw.cancel, paw.every, paw.try and the like) live in a module of the kernel layer; paw/init.lua only re-exports them
- [x] #2 paw.notify writes to a message sink in the data layer; paw/ui.tl reads the sink and shows the messages as before
- [x] #3 The upward references that these moves remove are gone from tools/layers-allowed.txt, and luajit tools/layers.lua passes
- [x] #4 The full Lua suite passes with no change of behavior; docs that name the moved functions are searched and fixed; Vale reports 0 alerts
- [x] #5 (TASK-216) The command registry (paw.command, paw.commands) is in a module below the project layer, and the commands keep their names and behavior
- [x] #6 (TASK-216) The 33 upward references to paw.command and paw.commands are gone from tools/layers-allowed.txt, and luajit tools/layers.lua passes
- [x] #7 (TASK-216) The full Lua suite passes; extensions.md and api.md are true; Vale reports 0 alerts
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
Branch worktree-agent-a2c0acb26131f5b52, commit 22dd762c, follow-ups in 1d3f0c43 (apidoc test reads paw.command.define; apidoc drops the unused paw.messages alias that the strict Teal check counted). timers, messages and command are in the data layer, not the kernel layer: timers need limit.timed (data). Allow-list 278 names/201 lines -> 186 names/142 lines.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (22dd762c, 1d3f0c43). Timers, messages and the command registry are in the data layer (timers need limit.timed, so not the kernel layer); paw/init.lua re-exports them. layers-allowed.txt 278 names/201 lines to 186 names/142 lines. Full suite passed on c04f8ae9.
<!-- SECTION:FINAL_SUMMARY:END -->
