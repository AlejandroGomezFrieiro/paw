---
id: TASK-7.17
title: >-
  Subprojects S12c: kinds of subproject from extensions (paw.nest.define_kind)
  and nest events
status: Done
assignee: []
created_date: '2026-11-23T06:14:00Z'
updated_date: '2026-11-23T11:08:00Z'
labels:
  - nest
  - subprojects
  - extensions
milestone: m-2
dependencies:
  - TASK-7.6
parent_task_id: TASK-7
priority: medium
ordinal: 230000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: an extension can define a kind of subproject, for example a drum pattern that opens in its step grid. Split from TASK-7.15 on 2026-11-23.

What to build (nest.md 4.11):
- paw.nest.define_kind(name, spec) with title, letter, create(region), enter(nest) (which view opens), describe(nest). The kind's data is in nest.meta under the extension's key. Typed as NestKind<D> in contracts.tl, with no any. Register the kinds on paw.registry (Registry<T>, as TASK-204 does for clip kinds), so that an unload removes them.
- Without the extension, the nest is plain: it plays and the arrange view edits it (rule 4 of AGENTS.md).
- Events NestEnter, NestLeave, NestChanged.

Read first: Design: backlog/docs/designs/nest.md, section 4.11; the owner accepted every recommended answer (Q1 to Q30). Words: subproject for the user, nest in commands and code (Q18). runtime/lua/paw/contracts.tl, runtime/lua/paw/clip_kinds.tl (how a clip kind registers), runtime/lua/paw/registry.tl, docs/reference/extensions.md, .claude/skills/paw-extension and teal.

Do not touch: the playback; projdiff (TASK-7.15).

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test: a fixture extension defines a kind; :nest.new with it calls create, and entering opens its view
- [x] #2 Test: with the extension unloaded, the project opens, plays, and the arrange view edits the nest
- [x] #3 Test: NestEnter and NestLeave come once for each enter and leave with real keys; NestChanged comes once for each edit inside
- [x] #4 contracts.tl types NestKind with no any; tools/tlcheck.sh passes; extensions.md and api.md say it; Vale reports 0 alerts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a1cd05696a2f78a57 (commits 8463f8cc, 70719871, merges 88f66ee9 and 2a895e9e with main 8e91e5b0). paw.nest.define_kind(name, spec) with title, letter, create(region), enter(nest), describe(nest); typed as contracts.NestKind<D> and contracts.NestRegion, no any. Kinds live on the registry paw.nest.kinds, so ext.unload removes them (row in tests/extensions_api.lua). Data in nest.meta[kind name]; paw.nest.data/set_data/kind/letter. :nest.new kind=<name> runs create before the window enters, a kind with no track gets one empty track, a failing create or an unknown kind leaves the project as it was (undo_discard). Blocks show the letter after the nest glyph; K adds the kind's title and describe. Events nest.enter, nest.leave (per window, from scope.changed, which now carries level and is exported as paw.scope.changed) and nest.changed (once per undo step per nest, from edit.after; removed tracks through a cache). No Rust change. Tests: tests/nest_kinds.lua (3 tests). Docs: extensions.md (Kinds of subproject, registry row), subprojects.md, events.md and api.md (generated), paw-extension skill. Shared files: nest.tl, scope.tl, contracts.tl, views/arrange_track.tl.

Merged to main in batch 15 (2f970bba); full suite and checks passed.
<!-- SECTION:NOTES:END -->
