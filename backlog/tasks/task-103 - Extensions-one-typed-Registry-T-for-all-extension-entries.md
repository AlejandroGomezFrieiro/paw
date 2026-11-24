---
id: TASK-103
title: 'Extensions: one typed Registry<T> for all extension entries'
status: Done
assignee: []
created_date: '2026-11-22T10:39:00Z'
updated_date: '2026-11-23T05:00:00Z'
labels:
  - extensions
  - teal
milestone: m-10
dependencies:
  - TASK-17
priority: medium
ordinal: 106000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: one typed registry module in Teal (paw.registry, Registry<T>) that every module that takes extension entries uses, so that ext.lua owns entries by owner and no longer copies about 36 tables before and after each load. Finding E2 (F10) of the architecture review (backlog/docs/designs/architecture-review.md). Generalizes TASK-17; helps TASK-3.

Today: runtime/lua/paw/ext.lua (846 lines) makes each registry with keyed(kind, title, get, put) (lines 148 to 176, entries 249 to 410); each get reads another module's table by name; ownership is a diff of copies.

Change: paw.registry.new<T>(kind, title) gives put(key, value, owner), remove, get, entries, owned_by. The registry records the owner at put (paw.ext.caller()). ext.lua lists the registries and unloads by owner. Move the modules one by one (pickers first); TASK-17's OwnedEntry is the entry type (ExtEntry is now the name of a loaded extension in contracts.tl) where desc and order are needed.

Read first: the review, E2; runtime/lua/paw/ext.lua; runtime/lua/paw/contracts.tl; TASK-17; TASK-3 and backlog/docs/designs/lazy-brief.md; docs/reference/extensions.md (What an extension owns); .claude/skills/teal and paw-extension.
Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 paw.registry exists in Teal with no any; tools/tlcheck.sh passes
- [ ] #2 ext.lua has no snapshot diff for the moved registries; unload removes entries by owner
- [ ] #3 tests/extensions_api.lua: load, unload and load again leave no entry behind for each moved registry
- [ ] #4 docs/reference/extensions.md and the paw-extension skill say how a module adds a registry
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a833c9017d40fc552, commit e796d2d4 (on b48920a4 + batch 8 34c30f68). paw.registry (runtime/lua/paw/registry.tl, layer data, no any): new(kind, title, {label, changed}) gives put(key, value, owner?), get, remove, entries, owned_by; an entry put over another keeps it below (remove/unload gives it back; unload of the lower owner leaves the top). paw.ext sets registry.owner = paw.ext.caller and registry.replaced (overrides for checkhealth), lists registry.all() in provides and unloads each by owner. Moved: pickers (paw.pick.sources:put/get/remove/entries; public API change, docs and utau changed) and status line components (paw.statusline.components; changed -> ui_redraw). Tests: tests/extensions_api.lua table 'registries' (one row per moved registry: load, unload, load again) and the stacking test with the checkhealth warning; both fail when ext.lua skips reg:unload. FOLLOW-UP (still snapshot-diffed in ext.lua M.registries): commands, keys, key_groups, views, keybar, buftypes, textbuf_kinds, track_kinds, clip_kinds, roles, query_fields, ex_fields, ex_views, completers, trackcolumn, trackcolumn_signs, barlabel, insert, grep, curves, addresses, complete, triggers, layers, languages, health, formats, lsp, hooks, options, timers, device_dirs, plugin_dirs, and init.lua's pencil and bands. hooks/timers/keys also feed the leak check of tests/suite.lua (TASK-146 area). Pre-existing on main: 'tutor: skipping a step never makes the tutor jump over the next one' fails under 'only ext' (passes alone).

Orchestrator 2026-11-23: merged to main d5127487 (batches 8-10); full suite with plugins, Rust tests and static checks pass.
<!-- SECTION:NOTES:END -->
