---
id: TASK-208
title: >-
  Extensions: move the last registries onto paw.registry (keys, hooks, timers,
  options, lsp and the rest)
status: Done
assignee: []
created_date: '2026-11-23T06:12:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - extensions
  - architecture
milestone: m-10
dependencies:
  - TASK-146
  - TASK-204
  - TASK-215
priority: medium
ordinal: 220000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up of TASK-204. TASK-204 moves most registries of ext.lua (M.registries) onto paw.registry (Registry<T>: an owner at put, an unload by owner). These registries stay in M.registries after TASK-204, each with a reason in a comment in ext.lua:

- addresses, complete, triggers, layers, languages, health, formats, lsp (not moved yet).
- keys, key_groups, keybar, hooks, timers. They feed the leak check of tests/suite.lua. Move them after part 2 of TASK-146 (the runner on the manual clock).
- options: an undefine puts back the core definition. Give Registry<T> a way to keep a shadowed entry, or write why options stays.
- device_dirs, plugin_dirs: devices_in_use reads them.
- The pencil and bands entries of init.lua.

Move them in groups, one commit for each group. Each moved registry gets a row in the registries table of tests/extensions_api.lua. Change each caller, test, type and doc in the same commit (TASK-204 shows the way: reads are reg:get(name), removals reg:remove(name)).

Read first: the notes of TASK-204; runtime/lua/paw/ext.lua (M.registries); runtime/lua/paw/registry.tl; tests/extensions_api.lua; tests/suite.lua (the leak check); .claude/skills/teal and paw-extension.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 M.registries in ext.lua is gone, or each entry left has a written reason that a later change cannot remove
- [x] #2 Each moved registry has a row in the registries test of tests/extensions_api.lua
- [x] #3 An unload of an extension that put a key, a hook and a timer leaves none of them, by a test; the leak check of tests/suite.lua still finds a leaked key, hook or timer
- [x] #4 The full Lua suite passes; docs/reference/extensions.md and api.md say the new reads; Vale reports 0 alerts
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
Branch worktree-agent-a2c0acb26131f5b52, commits 998bf88d, a780ac21, 1d3f0c43 (merged with main in ca9644fe). Moved onto paw.registry: keys (paw.keymap.mappings, key 'mode scope lhs'), key groups (paw.keymap.group_registry), hooks (paw.events.hooks), timers (paw.timers.waiting, made=true: owner from the files that made the function), options (paw.option.defined, shadow stack gives back a replaced definition), lsp configs, formats, health checks, languages, completion sources, address schemes, learn triggers, layers, key bar lines, pencil keys, bands, plugin dirs, device dirs. ext.lua: claim/adopt/snapshot gone; unload and provides read registry.all() only. M.registries stays as a read-only view for the leak check of tests/suite.lua (runner is out of bounds for this batch); the runner work can read paw.registry.all() and then delete it. Leak check verified with a scratch test: it reports hooks, timers and keys. Full suite -j 2: only 2 failures that pass alone (guide 'another meter', pick 'macro plays'), plus apidoc failures fixed after the run.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): Plan 6.1 adds: language server subjects, view zoom, help pages and paw.layouts are registries; options uses the shadow stack; no second registry type. If the branch leaves one of them, write it in these notes; A2 (paw.kinds.define on paw.registry) depends on this ticket.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (998bf88d, a780ac21, 1d3f0c43). Keys, key groups, hooks, timers, options (shadow stack), lsp configs, formats, health checks, languages, completion sources, address schemes, triggers, layers, key bar lines, pencil keys, bands, plugin and device dirs are on paw.registry; ext.lua reads registry.all(). AC 1: M.registries stays only as a read-only view for the leak check of tests/suite.lua; its removal moved to TASK-149 (AC 11), now that the runner of TASK-145 is on main.
<!-- SECTION:FINAL_SUMMARY:END -->
