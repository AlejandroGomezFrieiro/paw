---
type: C4 Component
title: Roll draw
status: stable
groma:
  id: roll-draw
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/roll_draw.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_controls, paw.api.clip_get, paw.api.clip_notes, paw.api.clip_notes_edit, paw.api.clip_set_controls | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_current, paw.api.undo_join, paw.api.undo_label | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/chords.tl](../../../../../../runtime/lua/paw/chords.tl) | Invokes supplied callbacks: paw.chords.offer, paw.chords.parse, paw.chords.stack | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.mix, paw.draw.note_style, paw.draw.track_colour | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callback: paw.ext.caller | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend, paw.frontend.refresh | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.at, paw.harmony.degree, paw.harmony.degree_pitch, paw.harmony.key, paw.harmony.key_name, paw.harmony.marked_key, paw.harmony.parse_key, paw.harmony.project_key, paw.harmony.set_key, paw.harmony.step | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.getreg, paw.keymap.mode, paw.keymap.mode_changed, paw.keymap.set, paw.keymap.set_mode | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers.add, paw.markers.default_name | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.name, require("paw.music") | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callbacks: paw.pick, require("paw.pick") | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/roll_clips.tl](../../../../../../runtime/lua/paw/roll_clips.tl) | Invokes supplied callback: paw.roll_clips | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.keep, require("paw.seats") | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | Invokes supplied callback: paw.snippet.pick | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | Invokes supplied callbacks: paw.step.ask_input, paw.step.held_text, paw.step.paused, paw.step.refresh, paw.step.said, paw.step.source, paw.step.target, paw.step.velocity, require("paw.step") | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callbacks: paw.tempo.at, paw.tempo.bar_of, paw.tempo.bar_start, paw.tempo.is_bar_line, paw.tempo.set, paw.tempo.set_signature, paw.tempo.signature_at | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callback: require("paw.theme") | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.focused, paw.ui.hl, paw.ui.input, paw.ui.notify, paw.ui.poke, paw.ui.views | teal |
| [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.by_order, paw.util.clamp, require("paw.util") | teal |
