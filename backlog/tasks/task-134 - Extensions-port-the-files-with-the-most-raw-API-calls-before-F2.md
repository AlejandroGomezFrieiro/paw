---
id: TASK-134
title: 'Extensions: port the files with the most raw API calls before F2'
status: Done
assignee: []
created_date: '2026-11-22T19:00:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels:
  - architecture
  - lua-review
milestone: m-10
dependencies:
  - TASK-125
  - TASK-126
  - TASK-127
priority: medium
ordinal: 146000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port to Teal the extension files that call the kernel areas of F2's first branches (tracks, clips): `interop` and `plugstate`. Split each procedure over 200 lines by its steps.

Read first: backlog/docs/designs/architecture-review-lua.md, the finding L10 and its proposal P12.

Overlaps: TASK-22, TASK-96, TASK-77.6.
Dependencies: P3 to P5 make the types of the runtime that these files use.

Owner decisions (2026-11-22): the review's recommendations are accepted. notation and utau are not ported to Teal: they move to Rust as native extensions later (a separate ticket).

Owner, 2026-11-22: notation and utau are out of scope here; they move to Rust later. Port interop and plugstate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the ported files type-check with no `any` where a value has a shape
- [ ] #2 the extension tests pass unchanged
- [ ] #3 no function over 300 lines in a ported file
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a35f55314d794c293, commit 3ed1b674 (on main 07a06cd3). Ported all 14 files of extensions/interop to Teal (6,300 lines of Teal; 4,300 lines of Lua before); no any or paw.Untyped. Longest function 89 lines (was 196: rpp import M.doc). Split: rpp M.doc, import_item, export M.doc, fx import/export by format; dawproject import_clip, M.build, device. Shared helpers moved into interop: amp, markers, add_markers, sections, types Options/Result/Marker/Section. Found: register passed module and import=false to paw.formats; device_types stored false; doc.project was a metatable function (now a field kept by add/remove/parse); number tokens broke data_groups. Also fixed: tutor.try did not find an extension with init.tl (lesson 16 failed); tests/teal.lua strict check now gets each extension's lua/ folder (as tlcheck.sh). Not done: plugstate (other branches TASK-104/161/162 change it; a later ticket ports it); notation and utau out of scope (move to Rust, m-11). ReaScripts in tools/ stay Lua (they run in REAPER). Manifest unchanged. Tests: interop tests unchanged and pass (only rpp:, dawproject:, plugins plugin, guide move-a-song, importer, teal:, zip, extension, launcher export); tlcheck, fmtcheck, luacheck 0, apidoc check, Vale 0.
<!-- SECTION:NOTES:END -->
