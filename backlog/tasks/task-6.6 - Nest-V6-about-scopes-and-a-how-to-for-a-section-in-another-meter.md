---
id: TASK-6.6
title: 'Nest V6: about scopes, and a how-to for a section in another meter'
status: Done
assignee: []
created_date: '2026-11-22T09:50:00Z'
updated_date: '2026-11-23T00:46:00Z'
labels:
  - nest
  - docs
milestone: m-2
dependencies:
  - TASK-6.1
  - TASK-6.2
  - TASK-6.5
parent_task_id: TASK-6
priority: medium
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: the user understands views, folds and narrowing as one model, and can follow a guide to work on a section in another meter. This is V6 of nest.md.

What to write:
- docs/explanation/about-scopes.md: a scope is a view of the one project (tracks x time); entered, folded or open are three ways to show the same thing; why folds are not undo steps; why a scope never copies (one model, one undo tree); what a subproject adds later (its own tracks). Plain writing; no comparison with other programs (the owner asked so for explanation pages).
- docs/how-to/work-on-a-section-in-another-meter.md: the 6/8 bridge of nest.md 3.5 (`:region Bridge`, `:timesig 6/8 at 17`, `znar`, the local bars, `]z`, `zw`, `zfar`), with its test in tests/guides_howto.lua.
- docs/reference/narrowing.md, grammar.md and keys.md checked against the code of V3 to V5; docs/README.md lists the new pages.

Read first: .claude/skills/diataxis-docs, .claude/skills/plain-writing; nest.md sections 1 and 3; the merged V1 to V5 commits; docs/how-to/work-on-one-section-of-a-song.md (do not repeat it: link it).

Depends on: TASK-6.1, TASK-6.2 (it absorbed TASK-6.3), TASK-6.5.
Do not touch: code.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 docs/explanation/about-scopes.md exists and docs/README.md lists it
- [ ] #2 docs/how-to/work-on-a-section-in-another-meter.md exists and its steps run in tests/guides_howto.lua
- [ ] #3 nix develop -c tools/vale.sh reports 0 errors on the changed pages
- [ ] #4 The report gives the search for 'narrowed tab' and 'tab.scope' in README.md, docs/, extensions and .claude/skills, and no stale sentence is left
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-ad4005f9bb8453ce3, commits 7a747a3b (vzoom: paw.keymap in its Paw record, a fix of the merge of TASK-125 with TASK-123) and 179ecd8c (the docs). It merges TASK-125, TASK-6.5, TASK-116 and TASK-7.11 first. New: docs/explanation/about-scopes.md, docs/how-to/work-on-a-section-in-another-meter.md with the test 'guide: work on a section in another meter' in tests/guides_howto.lua. Changed: grammar.md (zn, zf, ]z, @9|, jumps), keys.md (K on a scope), narrowing.md (no REAPER comparison, a link), docs/README.md. Doc comments: 'narrowed tab' is now 'narrowed window'. Search for 'narrowed tab' and 'tab.scope' in README.md, docs, extensions and .claude/skills: 0 hits. Found: the ruler of a subproject with meter=own draws bars of 4 beats, but 3| uses 6/8.
<!-- SECTION:NOTES:END -->
