---
type: C4 Component
title: Articulations extension
status: stable
groma:
  id: articulations-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/articulations/init.lua
      symbol: with_notation
    - scanner: teal
      file: extensions/articulations/lua/articulations/commands.lua
    - scanner: teal
      file: extensions/articulations/lua/articulations/diagnostics.lua
    - scanner: teal
      file: extensions/articulations/lua/articulations/gen.lua
    - scanner: teal
      file: extensions/articulations/lua/articulations/init.lua
    - scanner: teal
      file: extensions/articulations/lua/articulations/linked.lua
    - scanner: teal
      file: extensions/articulations/lua/articulations/m2.lua
    - scanner: teal
      file: extensions/articulations/lua/articulations/maps.lua
    - scanner: teal
      file: extensions/articulations/lua/articulations/measure.lua
    - scanner: teal
      file: extensions/articulations/lua/articulations/notation.lua
      symbol: extra
    - scanner: teal
      file: extensions/articulations/lua/articulations/roll.lua
    - scanner: teal
      file: extensions/articulations/lua/articulations/toml.lua
    - scanner: teal
      file: extensions/articulations/manifest.lua
      symbol: articulations
  group: Bundled extensions
  technology: Lua
description: Gives each note an articulation.
---

The articulation of a note is its MIDI 2.0 attribute, so the clip data stays MIDI. Maps give the articulations a name for each instrument. For an instrument that reads only MIDI 1.0, the extension sends the articulation as a keyswitch.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/articulations/init.lua](../../../../../../extensions/articulations/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/articulations/init.lua](../../../../../../extensions/articulations/init.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [extensions/articulations/init.lua](../../../../../../extensions/articulations/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_notes | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_call, paw.api.device_get | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [crates/paw-core/src/api/midi.rs](../../../../../../crates/paw-core/src/api/midi.rs) | Invokes supplied callback: paw.api.midi_send | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: paw.api.decode | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.read_dir | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_checkpoint | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callbacks: paw.audition.phrase, paw.audition.revert, paw.audition.try | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.exec, paw.commands.get | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.clip, paw.cursor.track | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | Invokes supplied callbacks: paw.ex.field, paw.ex.items, paw.ex.selection_range | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.selection, paw.keymap.set, paw.keymap.set_mode, paw.keymap.textobject | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.clip | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/roll_clips.tl](../../../../../../runtime/lua/paw/roll_clips.tl) | Invokes supplied callback: paw.roll_clips.ids | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.notify, paw.ui.page, paw.ui.views | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/articulations/lua/articulations/commands.lua](../../../../../../extensions/articulations/lua/articulations/commands.lua) | [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | Invokes supplied callback: require("paw.views.cmdline") | teal |
| [extensions/articulations/lua/articulations/diagnostics.lua](../../../../../../extensions/articulations/lua/articulations/diagnostics.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list, paw.api.clip_notes | teal |
| [extensions/articulations/lua/articulations/diagnostics.lua](../../../../../../extensions/articulations/lua/articulations/diagnostics.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [extensions/articulations/lua/articulations/diagnostics.lua](../../../../../../extensions/articulations/lua/articulations/diagnostics.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [extensions/articulations/lua/articulations/diagnostics.lua](../../../../../../extensions/articulations/lua/articulations/diagnostics.lua) | [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | Invokes supplied callbacks: paw.diagnostic.set, paw.diagnostic.setqflist | teal |
| [extensions/articulations/lua/articulations/diagnostics.lua](../../../../../../extensions/articulations/lua/articulations/diagnostics.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/articulations/lua/articulations/diagnostics.lua](../../../../../../extensions/articulations/lua/articulations/diagnostics.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [extensions/articulations/lua/articulations/diagnostics.lua](../../../../../../extensions/articulations/lua/articulations/diagnostics.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [extensions/articulations/lua/articulations/gen.lua](../../../../../../extensions/articulations/lua/articulations/gen.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [extensions/articulations/lua/articulations/gen.lua](../../../../../../extensions/articulations/lua/articulations/gen.lua) | [runtime/lua/paw/attr.tl](../../../../../../runtime/lua/paw/attr.tl) | Invokes supplied callback: paw.attr.describe | teal |
| [extensions/articulations/lua/articulations/gen.lua](../../../../../../extensions/articulations/lua/articulations/gen.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.name, paw.music.pitch | teal |
| [extensions/articulations/lua/articulations/gen.lua](../../../../../../extensions/articulations/lua/articulations/gen.lua) | [runtime/lua/paw/zip.tl](../../../../../../runtime/lua/paw/zip.tl) | Invokes supplied callback: paw.zip.read | teal |
| [extensions/articulations/lua/articulations/init.lua](../../../../../../extensions/articulations/lua/articulations/init.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_notes | teal |
| [extensions/articulations/lua/articulations/init.lua](../../../../../../extensions/articulations/lua/articulations/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_set | teal |
| [extensions/articulations/lua/articulations/init.lua](../../../../../../extensions/articulations/lua/articulations/init.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [extensions/articulations/lua/articulations/init.lua](../../../../../../extensions/articulations/lua/articulations/init.lua) | [runtime/lua/paw/attr.tl](../../../../../../runtime/lua/paw/attr.tl) | Invokes supplied callbacks: paw.attr, paw.attr.m2 | teal |
| [extensions/articulations/lua/articulations/init.lua](../../../../../../extensions/articulations/lua/articulations/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event | teal |
| [extensions/articulations/lua/articulations/init.lua](../../../../../../extensions/articulations/lua/articulations/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.clip | teal |
| [extensions/articulations/lua/articulations/init.lua](../../../../../../extensions/articulations/lua/articulations/init.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/articulations/lua/articulations/linked.lua](../../../../../../extensions/articulations/lua/articulations/linked.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_controls, paw.api.clip_get, paw.api.clip_set_controls | teal |
| [extensions/articulations/lua/articulations/linked.lua](../../../../../../extensions/articulations/lua/articulations/linked.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands, paw.commands.exec | teal |
| [extensions/articulations/lua/articulations/linked.lua](../../../../../../extensions/articulations/lua/articulations/linked.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.clip | teal |
| [extensions/articulations/lua/articulations/linked.lua](../../../../../../extensions/articulations/lua/articulations/linked.lua) | [runtime/lua/paw/curves.tl](../../../../../../runtime/lua/paw/curves.tl) | Invokes supplied callback: paw.curves.provide | teal |
| [extensions/articulations/lua/articulations/linked.lua](../../../../../../extensions/articulations/lua/articulations/linked.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.set | teal |
| [extensions/articulations/lua/articulations/linked.lua](../../../../../../extensions/articulations/lua/articulations/linked.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.views | teal |
| [extensions/articulations/lua/articulations/linked.lua](../../../../../../extensions/articulations/lua/articulations/linked.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
| [extensions/articulations/lua/articulations/linked.lua](../../../../../../extensions/articulations/lua/articulations/linked.lua) | [runtime/lua/paw/views/curve.lua](../../../../../../runtime/lua/paw/views/curve.lua) | Invokes supplied callback: require("paw.views.curve") | teal |
| [extensions/articulations/lua/articulations/maps.lua](../../../../../../extensions/articulations/lua/articulations/maps.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [extensions/articulations/lua/articulations/maps.lua](../../../../../../extensions/articulations/lua/articulations/maps.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.read_dir | teal |
| [extensions/articulations/lua/articulations/maps.lua](../../../../../../extensions/articulations/lua/articulations/maps.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [extensions/articulations/lua/articulations/maps.lua](../../../../../../extensions/articulations/lua/articulations/maps.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/articulations/lua/articulations/maps.lua](../../../../../../extensions/articulations/lua/articulations/maps.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/articulations/lua/articulations/maps.lua](../../../../../../extensions/articulations/lua/articulations/maps.lua) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callback: paw.ext.list | teal |
| [extensions/articulations/lua/articulations/maps.lua](../../../../../../extensions/articulations/lua/articulations/maps.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.name, paw.music.pitch | teal |
| [extensions/articulations/lua/articulations/measure.lua](../../../../../../extensions/articulations/lua/articulations/measure.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [extensions/articulations/lua/articulations/measure.lua](../../../../../../extensions/articulations/lua/articulations/measure.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.env, paw.api.sound_envelope | teal |
| [extensions/articulations/lua/articulations/measure.lua](../../../../../../extensions/articulations/lua/articulations/measure.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list, paw.api.track_set | teal |
| [extensions/articulations/lua/articulations/measure.lua](../../../../../../extensions/articulations/lua/articulations/measure.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/articulations/lua/articulations/measure.lua](../../../../../../extensions/articulations/lua/articulations/measure.lua) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callbacks: paw.audition.revert, paw.audition.try | teal |
| [extensions/articulations/lua/articulations/measure.lua](../../../../../../extensions/articulations/lua/articulations/measure.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [extensions/articulations/lua/articulations/measure.lua](../../../../../../extensions/articulations/lua/articulations/measure.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track | teal |
| [extensions/articulations/lua/articulations/measure.lua](../../../../../../extensions/articulations/lua/articulations/measure.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.flush | teal |
| [extensions/articulations/lua/articulations/measure.lua](../../../../../../extensions/articulations/lua/articulations/measure.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.time, paw.objects.track | teal |
| [extensions/articulations/lua/articulations/measure.lua](../../../../../../extensions/articulations/lua/articulations/measure.lua) | [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | Invokes supplied callback: paw.render | teal |
| [extensions/articulations/lua/articulations/measure.lua](../../../../../../extensions/articulations/lua/articulations/measure.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.notify, paw.ui.page, paw.ui.views | teal |
| [extensions/articulations/lua/articulations/measure.lua](../../../../../../extensions/articulations/lua/articulations/measure.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/articulations/lua/articulations/notation.lua](../../../../../../extensions/articulations/lua/articulations/notation.lua) | [extensions/notation/lua/notation/marks.lua](../../../../../../extensions/notation/lua/notation/marks.lua) | Invokes supplied callbacks: notation.marks.art_of, notation.marks.extra, notation.marks.listen, require("notation.marks") | teal |
| [extensions/articulations/lua/articulations/notation.lua](../../../../../../extensions/articulations/lua/articulations/notation.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/articulations/lua/articulations/roll.lua](../../../../../../extensions/articulations/lua/articulations/roll.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.str_width | teal |
| [extensions/articulations/lua/articulations/roll.lua](../../../../../../extensions/articulations/lua/articulations/roll.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/articulations/lua/articulations/roll.lua](../../../../../../extensions/articulations/lua/articulations/roll.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.g, paw.draw.hue, paw.draw.note_style, paw.draw.track_hue | teal |
| [extensions/articulations/lua/articulations/roll.lua](../../../../../../extensions/articulations/lua/articulations/roll.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.chosen_notes | teal |
| [extensions/articulations/lua/articulations/roll.lua](../../../../../../extensions/articulations/lua/articulations/roll.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/articulations/lua/articulations/roll.lua](../../../../../../extensions/articulations/lua/articulations/roll.lua) | [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | Invokes supplied callbacks: paw.roll_draw, paw.roll_draw.articulation | teal |
| [extensions/articulations/lua/articulations/roll.lua](../../../../../../extensions/articulations/lua/articulations/roll.lua) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callback: require("paw.theme") | teal |
| [extensions/articulations/lua/articulations/roll.lua](../../../../../../extensions/articulations/lua/articulations/roll.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.hl, paw.ui.views | teal |
| [extensions/articulations/lua/articulations/roll.lua](../../../../../../extensions/articulations/lua/articulations/roll.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.fit | teal |
| [extensions/articulations/lua/articulations/toml.lua](../../../../../../extensions/articulations/lua/articulations/toml.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callbacks: paw.api.decode, paw.api.encode | teal |
| [extensions/articulations/lua/articulations/toml.lua](../../../../../../extensions/articulations/lua/articulations/toml.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/articulations/manifest.lua](../../../../../../extensions/articulations/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
