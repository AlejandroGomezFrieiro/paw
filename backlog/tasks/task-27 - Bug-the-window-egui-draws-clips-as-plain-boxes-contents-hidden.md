---
id: TASK-27
title: 'Bug: the window (egui) draws clips as plain boxes, contents hidden'
status: Done
assignee: []
created_date: '2026-11-21T19:27:00Z'
updated_date: '2026-11-22T05:24:00Z'
labels:
  - bug
  - gui
  - arrange
milestone: m-6
dependencies: []
priority: high
type: bug
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In the graphical window (paw-gui), arrange-view clips show as plain filled boxes: their contents (MIDI notes, audio waveform/peaks, names) are not visible, as seen in the GIFs (docs/images/gui-arrange.gif and the gui stills remade 2026-11-21). The terminal draws the clip contents. One view, two frontends: the window should draw what the scene sends. Check what the arrange scene sends for a clip (paw-scene props/roles), and how crates/paw-gui/src/roles.rs paints the clip role (fill over the content? missing note/peak layer? wrong z-order or alpha?). Compare with the terminal frontend.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 In the window, a MIDI clip shows its notes and an audio clip its waveform, as the terminal does
- [ ] #2 A paw-gui test (crates/paw-gui/tests) fails before the fix and passes after
- [ ] #3 gui-arrange.gif and the gui stills are made again and show the contents
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixed on branch worktree-agent-a781a3f69b807e341 (be4960cc code+test, 1b42f619 images). Two root causes: (1) paw-core scene_open converted role props with mlua defaults, so an empty Lua table (a clip's warps = {}) went as a JSON map; ClipProps failed to deserialize and props::parse fell back to defaults (no id/content/label/colour), so every clip was a plain box. Now encode_empty_tables_as_array. (2) paw-gui: a role under the pointer is repainted over the still layer, so a lane's ground under the pointer hid the clips on it; roles after a hovered role that overlap it now move with it. Test: window.rs a_clip_shows_its_name_and_its_notes_or_its_waveform (fails without either fix). Images remade with make.sh. Pre-existing, not fixed: gui-arrange.sh/stills.sh pointer positions assume 90-high rows but rows are ~68, so the Ctrl-drag/double-click miss the melody clip.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged e27cc7bb: two causes (empty Lua tables sent as JSON maps dropped all clip props; hovered lane repaint hid its clips); window test added; GUI GIFs and stills remade.
<!-- SECTION:FINAL_SUMMARY:END -->
