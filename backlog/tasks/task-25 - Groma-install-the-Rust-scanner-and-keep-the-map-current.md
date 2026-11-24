---
id: TASK-25
title: 'Groma: C# lint findings and map upkeep'
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-23T06:11:00Z'
labels:
  - local-tools
milestone: m-7
dependencies: []
priority: low
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
groma lint reports 99 findings, mostly C# compile warnings because the OpenUtau packages are not resolved for the scanner. Resolve or exclude them; keep the map current after big merges. The Lua/Teal scanner is TASK-26. Keep groma/ local.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Result (2026-11-22)

Groma 0.7.8 changed where the C# warnings show. `groma lint` now reports only possible duplicate logic. The C# compile warnings (about 750: CS0246, CS0103, CS1061, ...) were scan diagnostics in the `groma scan` report.

Cause: the C# scanner never restores NuGet packages (MessagePack, SharpCompress) and never reads a project outside its files. The OpenUtau projects that `PawUtau.Engine.csproj` references (`../../third_party/OpenUtau`) come from a flake input and are not in the tree. Both projects (Engine and Protocol) give the warnings. They cannot be resolved without OpenUtau and the packages in the tree.

Action: the `csharp` entry in `groma/config.json` excludes `/extensions/utau/engine/` (its own exclude list, last line). The scanner stays configured; remove that line to scan the engine again. Groma keeps the `paw-utau-engine` container, its 5 components, their Code links and their meaning. The engine part of the map is not refreshed while the exclusion is there.

Lint before: 98 findings (exit 1): 7 in C# (utau engine), 91 in Rust; 26 identical copies, 72 near copies. Scan report before: 7 C# warning groups.
Lint after: 91 findings (exit 1), all Rust (crates/paw-core 49, paw-engine 19, paw-plugins 8, paw-gui 5, other 10); 26 identical copies, 65 near copies. The `teal` scanner adds none (it reports no body tokens). Scan report after: no C# warnings; only the rust info line, the rust `paw-tui/src/args.rs` compilation-context warning and the teal scope line.
The 91 findings are review questions about Rust code. To fix them is code work, not map upkeep.

Map upkeep: the scan of 2026-11-22 added 13 Rust components for new files (save.rs, project_files.rs, file_check.rs, promote.rs, the nests files, undofile.rs, undo_file.rs, startuptime.rs, midi_filter.rs, rest.rs). They are in the paw system, group "Unidentified container" (library files have no entry fact). Proposal, not applied: move each to `paw-kernel` and combine it with its owner (for example session/save.rs and project_files.rs with `project-files`, the nests files in one "Nested projects" component, midi_filter.rs with `midi-io`, rest.rs with `audio-graph`, startuptime.rs with `kernel-loop`).

To keep the map current after a big merge: `groma scan` in the main checkout, then `groma view paw --plain` for components in "Unidentified container".

Board review 2026-11-23: the C# part is done (the csharp scanner excludes /extensions/utau/engine/). Map upkeep after a big merge is a routine (groma scan, then groma view paw --plain), not open work. The 91 Rust duplicate findings of groma lint are code work: TASK-206 (the codebase improvement run) takes them.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
groma lint has no C# findings now: the csharp scanner excludes the utau engine, whose OpenUtau packages are not in the tree. The 91 Rust duplicate findings go to the codebase improvement run (TASK-206).
<!-- SECTION:FINAL_SUMMARY:END -->
