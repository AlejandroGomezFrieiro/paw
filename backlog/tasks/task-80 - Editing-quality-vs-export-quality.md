---
id: TASK-80
title: Editing quality vs export quality
status: Done
assignee: []
created_date: '2026-11-22T08:09:00Z'
updated_date: '2026-11-23T11:09:00Z'
labels:
  - performance
  - engine
milestone: m-3
dependencies: []
priority: medium
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: as Blender has viewport and render settings, paw has a switch that lowers costly settings while you edit, and always renders, exports and freezes at full quality.

User-visible behavior:
- `paw.opt.quality`: `"full"` (default) or `"edit"`. `:set quality=edit` changes it at once, with no click.
- In `"edit"`, live playback lowers costly settings of the built-in devices: oversampling of `saturation` and `utility` goes to 1x. Measure the other built-in devices (reverb, chorus, compressor) and lower only those that cost much; write the list in docs/reference/engine.md.
- A render, an export, stems, a freeze and a bounce always run at full quality, whatever the option says.
- The status line shows `edit q` while the option is `"edit"`, so the user knows that the sound is not the final sound.
- Not in this ticket: stretch quality (the rough preview already plays until a bake is ready, media.md section 15, decision 3), and plugins' own quality parameters (no generic way).

Read first:
- docs/reference/devices.md (saturation, utility: `oversample`), docs/reference/engine.md, docs/reference/render.md, docs/reference/freezing.md.
- crates/paw-engine/src/devices/dsp.rs (oversampling), devices/utility.rs, devices/reverb.rs.
- crates/paw-core/src/session/render.rs, session/offline.rs, freeze.rs (the render paths).
- runtime/lua/paw/options.tl (`options.define`), runtime/lua/paw/statusline.tl.
- .claude/skills/rust-skills: the audio thread rules.

Depends on: nothing.
Do not touch: the sleep of silent devices (TASK-16, done): keep the changes to process.rs small.

Size: M.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test: a render with quality = edit is bit-identical to a render with quality = full (tests/export.lua or a Rust test in paw-core)
- [x] #2 Rust test: live, with quality = edit, a saturation set to 4x processes at 1x; the change happens at a block boundary with no allocation (tests/no_alloc.rs passes)
- [x] #3 Test with real keys: :set quality=edit shows edit q in the status line, :set quality=full removes it
- [x] #4 bench: 16 saturations at 4x playing, audio thread time with edit and with full, in bench/RESULTS.md with the spread
- [x] #5 docs/reference/options.md, engine.md and render.md document it; Vale 0 errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-ae67802dd5285aa65: commit a5c96d95, merge of main a4a361c7. paw.opt.quality full|edit; Msg::SetQuality -> ProcessCtx::quality; saturation without oversampling in edit (same latency); render engines never get the message, so renders, exports, stems, freezes and bounces are full. Status line flag 'edit q'. Reverb/chorus/compressor measured (bench/quality.lua, RESULTS 2026-11-23) and not lowered. Not on main before: nothing of it. After the build: run apidoc (api entries hand-written), cargo nextest -p paw-engine (no_alloc, a_change_of_quality_takes_effect_from_the_next_block, saturation_in_edit_quality_*), suite only quality / statusline, and bench/quality.lua 16 3 5 for AC #4's edit vs full numbers.

Merged to main in batch 15 (2f970bba); full suite and checks passed.

Code merged in batch 15 (2f970bba). Left: the measurement in its criteria (orchestrator runs it on the build).

2026-11-23: bench measured on cd367da1: full 36.19 % of a core (34.72-37.48), edit 4.45 % (4.04-5.05), in bench/RESULTS.md (9a5a460e). Other criteria checked on main: tests/fx.lua bit-identical render, no_alloc.rs edit quality, tests/statusline.lua edit q, docs.

PO 2026-11-23 (after batch 16): AC #4 is on main: bench/RESULTS.md, commit 9a5a460e (full 36.19 %, edit 4.45 % of a core, ranges do not overlap). All criteria are met.
<!-- SECTION:NOTES:END -->
