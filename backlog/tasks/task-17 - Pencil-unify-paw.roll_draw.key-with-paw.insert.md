---
id: TASK-17
title: 'Pencil: unify paw.roll_draw.key with paw.insert'
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-23T00:46:00Z'
labels:
  - insert-mode
  - extensions
milestone: m-4
dependencies: []
priority: medium
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: the pencil's keys (`paw.roll_draw.key`) and the insert kinds of the arrange view (`paw.insert`) are registered the same way, and both go away when their extension unloads.

Today: `paw.insert` keeps `ext` on each kind (`copy.ext = paw.ext.caller()`), and ext.lua has a registry for it (`keyed("insert", ...)`). `paw.roll_draw.key` sets a keymap entry (which unloads) and an entry in `paw.roll_draw.keys` (which stays after the unload, so the key bar and help still list it).

Decision: a common interface in contracts.tl, named `OwnedEntry` with `desc: string`, `order: integer`, `ext: string`. `PencilKey` and `InsertKind` both are `OwnedEntry`. (Do not use the name `KeyEntry`: contracts.tl uses it for keymap entries. Do not use `ExtEntry`: contracts.tl uses it now for a loaded extension, `paw.ext.loaded`.) `paw.roll_draw.key` sets `ext` and `order`. ext.lua gets a registry for `paw.roll_draw.keys`, as it has for `paw.insert.kinds`. The key bar and `:help` list pencil keys and insert kinds by `order`, then by keys.

Read first:
- runtime/lua/paw/roll_draw.tl: `PencilKey` (near line 213), `M.keys` (near line 233), `M.key` (near line 2144), `M.articulation` (near line 1348).
- runtime/lua/paw/insert.tl: `add`, `remove`, `set` (near lines 182 to 270).
- runtime/lua/paw/ext.lua: `M.registries` (near line 178), `keyed` (near line 148), the insert registry (near line 337).
- runtime/lua/paw/contracts.tl: `KeyEntry` (near line 342), `InsertKind` (near line 1116), `ExtEntry` (near line 1819).
- docs/reference/insert-mode.md, docs/how-to/personalize-insert-mode.md; .claude/skills/teal.

Depends on: nothing.
Do not touch: the step target in roll_draw.tl (TASK-60, done).

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test (tests/extensions_api.lua or tests/insertmode.lua): an extension that adds a pencil key and an insert kind, then paw.ext.unload: both keys stop working and paw.roll_draw.keys has no entry for it
- [ ] #2 Test: the key bar of the pencil lists an extension's key with its desc, in its order
- [ ] #3 tools/tlcheck.sh passes with no any; docs/reference/api.md is generated again; insert-mode.md says how order works; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
OwnedEntry (contracts.tl, is util.Ordered: key, order; plus desc, ext) is the common interface of PencilKey and InsertKind. paw.roll_draw.key sets key, order (default 50), ext. ext.lua has a 'pencil' registry for paw.roll_draw.keys (the 'keys' registry already removes the mappings). Pencil key bar lists extension keys by order then key (paw.roll_draw.list, util.by_order); arrange and pencil key bars share short_desc. paw.insert.add sets ext and places a new key in paw.opt.insertkeys by order (order had no effect before). :help/'?' still sort keymap entries by key (keymap.list): not changed. Test: tests/extensions_api.lua 'an extension's pencil keys and insert keys work, show in the key bar by order, and go when it unloads'. Docs: insert-mode.md (order), piano-roll.md, api.md regenerated. Branch worktree-agent-a095f07baa668dc01, commit 8beeea34.
<!-- SECTION:NOTES:END -->
