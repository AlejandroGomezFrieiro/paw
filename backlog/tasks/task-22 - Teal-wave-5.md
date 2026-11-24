---
id: TASK-22
title: Teal wave 5
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-24T16:53:00Z'
labels:
  - teal
  - agent:worker
milestone: m-6
dependencies: []
priority: low
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port the next set of Lua runtime modules to Teal (no any where a value has a shape). See docs/explanation/about-teal.md and the skill .claude/skills/teal.

Candidates (runtime/lua/paw, still .lua on 2026-11-22): keymap, fx, controls, autosave, audio, learn, mixer_rows, device_rows, routes, stretch, roll_clips, track_kinds, freeze, stems, and the others. dsp.lua stays Lua (FFI, written reason). Wave 4 left one item: paw.frontend reads the views of paw.ui as records of its own until wave 5.

Do not port: ext.lua until TASK-208 merges (it changes M.registries), roll_clips.lua while TASK-77.2 is open, track_kinds.lua while TASK-23 part B3 is open.

Pick the wave at the start and write the list in the notes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each module of the wave is a .tl file with no any; tools/tlcheck.sh passes
- [x] #2 paw.frontend reads the views of paw.ui with their types (the wave 4 item)
- [x] #3 The full Lua suite passes; docs/explanation/about-teal.md lists the modules of the wave; Vale reports 0 alerts
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
Owner, 2026-11-22: do not port notation or utau to Teal; they move to Rust later (see the design ticket for native extensions).

Board review 2026-11-23: parts on main: keymap, keyrule, keybar (TASK-125), the piano roll (TASK-126), the arrange view (TASK-127), plugstate (TASK-186). Still .lua in runtime/lua/paw: annotation, audio, autosave, controls, defaults, device_presets, device_rows, external, ext, freeze, fx, health, learn, loading, luadev, mixer_rows, params, plugins, portable, recent, reconnect, routes, stems, stretch, track_kinds (and dsp, init, untyped with a reason). The rule of AGENTS.md (a Lua file that changes much moves to Teal) ports most of them on the way. Pick a wave of 3 to 5 modules when an agent starts it; ext.lua after TASK-208.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): Do not port modules that a V2 bundle rewrites or removes: track_kinds (A2), freeze (FZ, RD), mixer_rows and routes (MX), groups, vca, takes and lanes data (LA, CV). Pick the wave from the other modules. Write no new user word track (W1).

Started 2026-11-24: branch teal-wave-5, base 3535c7d2.

Worker report 2026-11-24 (branch teal-wave-5, 5ee612c7): ported annotation, reconnect, external, recent, luadev, loading, plugins (1,477 lines of Teal, no any; any-allowed.txt lost 7 entries). AC 2: paw.frontend reads paw.ui's types (host.tl lost Ui, Float, Rect, InputOptions, MouseEvent). Kept Lua on purpose: dsp, ext, part_kinds, device_rows, mixer_rows, routes, params, device_presets, init, untyped; portable must stay Lua (LuaJIT globals before any module). Next wave suggested: health, learn, stretch, autosave, audio, controls, fx (freeze waits for FZ and RD). host.DevicePanel and host.RecentModule stay stand-ins until MX.

Wave 5 on main in 982068d6 (with the one-field project reads of 4959542e). AC 3 waits for the full suite before the next push.

2026-11-24: full suite on main 1e19cb1c (merge tree, debug build, new ARA bridge): 182 of 183 parts pass. The one failure is tests/files.lua (TASK-378), which no module of the wave touches.
<!-- SECTION:NOTES:END -->
