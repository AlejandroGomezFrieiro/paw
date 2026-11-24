---
type: C4 Component
title: Notation extension
status: stable
groma:
  id: notation-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/notation/init.lua
      symbol: weigh
    - scanner: teal
      file: extensions/notation/lua/notation/bench.lua
    - scanner: teal
      file: extensions/notation/lua/notation/breaks.lua
    - scanner: teal
      file: extensions/notation/lua/notation/cells.lua
    - scanner: teal
      file: extensions/notation/lua/notation/doc.lua
    - scanner: teal
      file: extensions/notation/lua/notation/engrave.lua
    - scanner: teal
      file: extensions/notation/lua/notation/export.lua
    - scanner: teal
      file: extensions/notation/lua/notation/files.lua
    - scanner: teal
      file: extensions/notation/lua/notation/gui.lua
    - scanner: teal
      file: extensions/notation/lua/notation/init.lua
    - scanner: teal
      file: extensions/notation/lua/notation/keys.lua
    - scanner: teal
      file: extensions/notation/lua/notation/layout.lua
    - scanner: teal
      file: extensions/notation/lua/notation/lilypond.lua
      symbol: write
    - scanner: teal
      file: extensions/notation/lua/notation/marks.lua
    - scanner: teal
      file: extensions/notation/lua/notation/midi.lua
    - scanner: teal
      file: extensions/notation/lua/notation/model.lua
    - scanner: teal
      file: extensions/notation/lua/notation/musicxml.lua
    - scanner: teal
      file: extensions/notation/lua/notation/objects.lua
    - scanner: teal
      file: extensions/notation/lua/notation/operators.lua
    - scanner: teal
      file: extensions/notation/lua/notation/page.lua
    - scanner: teal
      file: extensions/notation/lua/notation/part_keys.lua
      symbol: musicxml
    - scanner: teal
      file: extensions/notation/lua/notation/parts.lua
    - scanner: teal
      file: extensions/notation/lua/notation/popover.lua
    - scanner: teal
      file: extensions/notation/lua/notation/roll.lua
    - scanner: teal
      file: extensions/notation/lua/notation/score.lua
    - scanner: teal
      file: extensions/notation/lua/notation/search.lua
    - scanner: teal
      file: extensions/notation/lua/notation/skyline.lua
    - scanner: teal
      file: extensions/notation/lua/notation/smufl.lua
      symbol: font
    - scanner: teal
      file: extensions/notation/lua/notation/staves.lua
    - scanner: teal
      file: extensions/notation/lua/notation/step.tl
    - scanner: teal
      file: extensions/notation/lua/notation/tab.lua
    - scanner: teal
      file: extensions/notation/lua/notation/tui.lua
    - scanner: teal
      file: extensions/notation/lua/notation/write.lua
    - scanner: teal
      file: extensions/notation/manifest.lua
      symbol: notation
  group: Bundled extensions
  technology: Lua
description: Shows a MIDI clip as staff notation and edits it.
---

A view of a MIDI clip as staves, in the terminal and in the window. The clip data stays MIDI: the extension keeps its own data in meta. It reads and writes MusicXML.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/notation/init.lua](../../../../../../extensions/notation/init.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callback: paw.layout.window_keep | teal |
| [extensions/notation/init.lua](../../../../../../extensions/notation/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.dock, paw.ui.layout, paw.ui.view | teal |
| [extensions/notation/lua/notation/bench.lua](../../../../../../extensions/notation/lua/notation/bench.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_add, paw.api.clip_remove | teal |
| [extensions/notation/lua/notation/bench.lua](../../../../../../extensions/notation/lua/notation/bench.lua) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.json_encode | teal |
| [extensions/notation/lua/notation/bench.lua](../../../../../../extensions/notation/lua/notation/bench.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.real_ms | teal |
| [extensions/notation/lua/notation/bench.lua](../../../../../../extensions/notation/lua/notation/bench.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_add | teal |
| [extensions/notation/lua/notation/bench.lua](../../../../../../extensions/notation/lua/notation/bench.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callback: paw.canvas.paint | teal |
| [extensions/notation/lua/notation/bench.lua](../../../../../../extensions/notation/lua/notation/bench.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.flush | teal |
| [extensions/notation/lua/notation/cells.lua](../../../../../../extensions/notation/lua/notation/cells.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/notation/lua/notation/doc.lua](../../../../../../extensions/notation/lua/notation/doc.lua) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.json_decode | teal |
| [extensions/notation/lua/notation/doc.lua](../../../../../../extensions/notation/lua/notation/doc.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: paw.api | teal |
| [extensions/notation/lua/notation/doc.lua](../../../../../../extensions/notation/lua/notation/doc.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [extensions/notation/lua/notation/export.lua](../../../../../../extensions/notation/lua/notation/export.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/notation/lua/notation/files.lua](../../../../../../extensions/notation/lua/notation/files.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_new, paw.api.project_set | teal |
| [extensions/notation/lua/notation/files.lua](../../../../../../extensions/notation/lua/notation/files.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_reset | teal |
| [extensions/notation/lua/notation/files.lua](../../../../../../extensions/notation/lua/notation/files.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [extensions/notation/lua/notation/files.lua](../../../../../../extensions/notation/lua/notation/files.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.index, paw.cursor.set_track | teal |
| [extensions/notation/lua/notation/files.lua](../../../../../../extensions/notation/lua/notation/files.lua) | [runtime/lua/paw/formats.tl](../../../../../../runtime/lua/paw/formats.tl) | Invokes supplied callback: paw.formats.register | teal |
| [extensions/notation/lua/notation/files.lua](../../../../../../extensions/notation/lua/notation/files.lua) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callback: paw.harmony.set_key | teal |
| [extensions/notation/lua/notation/files.lua](../../../../../../extensions/notation/lua/notation/files.lua) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers.add, require("paw.markers") | teal |
| [extensions/notation/lua/notation/files.lua](../../../../../../extensions/notation/lua/notation/files.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.project, paw.objects.tracks | teal |
| [extensions/notation/lua/notation/files.lua](../../../../../../extensions/notation/lua/notation/files.lua) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callbacks: paw.tempo.at, paw.tempo.points, paw.tempo.set_points, paw.tempo.signatures | teal |
| [extensions/notation/lua/notation/files.lua](../../../../../../extensions/notation/lua/notation/files.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/notation/lua/notation/files.lua](../../../../../../extensions/notation/lua/notation/files.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas, paw.canvas.cell, paw.canvas.close, paw.canvas.hit_list, paw.canvas.open_views, paw.canvas.palette, require("paw.canvas") | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | Invokes supplied callback: paw.complete.current | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | Invokes supplied callbacks: paw.diagnostic.get, paw.diagnostic.places | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.track_colour | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.roll | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.human, paw.keymap.mode, paw.keymap.normal, paw.keymap.selection, paw.keymap.set_mode, paw.keymap.visual_start | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.hide, paw.ui.menu, paw.ui.notify | teal |
| [extensions/notation/lua/notation/gui.lua](../../../../../../extensions/notation/lua/notation/gui.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list, paw.api.clip_notes, paw.api.clip_notes_edit, paw.api.clip_set | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callback: paw.api.tempo_points | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas, paw.canvas.open | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.clip | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.fresh, paw.harmony.key, paw.harmony.key_name, paw.harmony.project_key | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callback: paw.layout.clip_named | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.notify, paw.ui.poke, paw.ui.views | teal |
| [extensions/notation/lua/notation/init.lua](../../../../../../extensions/notation/lua/notation/init.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address, paw.address.clip, paw.address.find_note, paw.address.location, paw.address.note, paw.address.parse | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | Invokes supplied callbacks: paw.complete, paw.complete.accept, paw.complete.current | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | Invokes supplied callback: paw.diagnostic.jump | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.roll | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | Invokes supplied callback: paw.ex.view | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callbacks: paw.frontend, paw.frontend.menus | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callback: paw.harmony.set_key | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.after_next, paw.keymap.classic, paw.keymap.getreg, paw.keymap.group, paw.keymap.human, paw.keymap.mode, paw.keymap.normal, paw.keymap.operator, paw.keymap.set_mode, paw.keymap.setreg, paw.keymap.textobject | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callback: paw.layout.back | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | Invokes supplied callbacks: paw.lsp, paw.lsp.code_actions, paw.lsp.show_hover | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time, paw.objects.tracks | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.input, paw.ui.keybar, paw.ui.locator, paw.ui.locators, paw.ui.notify, paw.ui.page | teal |
| [extensions/notation/lua/notation/keys.lua](../../../../../../extensions/notation/lua/notation/keys.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge | teal |
| [extensions/notation/lua/notation/marks.lua](../../../../../../extensions/notation/lua/notation/marks.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.log | teal |
| [extensions/notation/lua/notation/marks.lua](../../../../../../extensions/notation/lua/notation/marks.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.poke | teal |
| [extensions/notation/lua/notation/marks.lua](../../../../../../extensions/notation/lua/notation/marks.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/notation/lua/notation/midi.lua](../../../../../../extensions/notation/lua/notation/midi.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_notes, paw.api.clip_notes_edit, paw.api.clip_set | teal |
| [extensions/notation/lua/notation/midi.lua](../../../../../../extensions/notation/lua/notation/midi.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/notation/lua/notation/midi.lua](../../../../../../extensions/notation/lua/notation/midi.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/notation/lua/notation/musicxml.lua](../../../../../../extensions/notation/lua/notation/musicxml.lua) | [runtime/lua/paw/xml.tl](../../../../../../runtime/lua/paw/xml.tl) | Invokes supplied callbacks: paw.xml.child, paw.xml.children, paw.xml.decode, paw.xml.number, paw.xml.text | teal |
| [extensions/notation/lua/notation/musicxml.lua](../../../../../../extensions/notation/lua/notation/musicxml.lua) | [runtime/lua/paw/zip.tl](../../../../../../runtime/lua/paw/zip.tl) | Invokes supplied callbacks: paw.zip.read, paw.zip.write | teal |
| [extensions/notation/lua/notation/operators.lua](../../../../../../extensions/notation/lua/notation/operators.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/notation/lua/notation/operators.lua](../../../../../../extensions/notation/lua/notation/operators.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.roll | teal |
| [extensions/notation/lua/notation/operators.lua](../../../../../../extensions/notation/lua/notation/operators.lua) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callback: paw.ext.build_has | teal |
| [extensions/notation/lua/notation/operators.lua](../../../../../../extensions/notation/lua/notation/operators.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.setreg | teal |
| [extensions/notation/lua/notation/operators.lua](../../../../../../extensions/notation/lua/notation/operators.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/notation/lua/notation/operators.lua](../../../../../../extensions/notation/lua/notation/operators.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge | teal |
| [extensions/notation/lua/notation/page.lua](../../../../../../extensions/notation/lua/notation/page.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [extensions/notation/lua/notation/page.lua](../../../../../../extensions/notation/lua/notation/page.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.canvas_export | teal |
| [extensions/notation/lua/notation/page.lua](../../../../../../extensions/notation/lua/notation/page.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [extensions/notation/lua/notation/part_keys.lua](../../../../../../extensions/notation/lua/notation/part_keys.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/notation/lua/notation/part_keys.lua](../../../../../../extensions/notation/lua/notation/part_keys.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas, paw.canvas.open, paw.canvas.open_views | teal |
| [extensions/notation/lua/notation/part_keys.lua](../../../../../../extensions/notation/lua/notation/part_keys.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.feed, paw.keymap.group, paw.keymap.set | teal |
| [extensions/notation/lua/notation/part_keys.lua](../../../../../../extensions/notation/lua/notation/part_keys.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.notify | teal |
| [extensions/notation/lua/notation/parts.lua](../../../../../../extensions/notation/lua/notation/parts.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [extensions/notation/lua/notation/parts.lua](../../../../../../extensions/notation/lua/notation/parts.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_set | teal |
| [extensions/notation/lua/notation/parts.lua](../../../../../../extensions/notation/lua/notation/parts.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_checkpoint, paw.api.undo_current | teal |
| [extensions/notation/lua/notation/parts.lua](../../../../../../extensions/notation/lua/notation/parts.lua) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups, paw.groups.of | teal |
| [extensions/notation/lua/notation/parts.lua](../../../../../../extensions/notation/lua/notation/parts.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.tracks | teal |
| [extensions/notation/lua/notation/parts.lua](../../../../../../extensions/notation/lua/notation/parts.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/notation/lua/notation/parts.lua](../../../../../../extensions/notation/lua/notation/parts.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/notation/lua/notation/parts.lua](../../../../../../extensions/notation/lua/notation/parts.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/notation/lua/notation/popover.lua](../../../../../../extensions/notation/lua/notation/popover.lua) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.json_encode | teal |
| [extensions/notation/lua/notation/popover.lua](../../../../../../extensions/notation/lua/notation/popover.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [extensions/notation/lua/notation/popover.lua](../../../../../../extensions/notation/lua/notation/popover.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [extensions/notation/lua/notation/popover.lua](../../../../../../extensions/notation/lua/notation/popover.lua) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callbacks: paw.audition.revert, paw.audition.try | teal |
| [extensions/notation/lua/notation/popover.lua](../../../../../../extensions/notation/lua/notation/popover.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.exec | teal |
| [extensions/notation/lua/notation/popover.lua](../../../../../../extensions/notation/lua/notation/popover.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.selection, paw.keymap.set, paw.keymap.set_mode, paw.keymap.with_selection | teal |
| [extensions/notation/lua/notation/popover.lua](../../../../../../extensions/notation/lua/notation/popover.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/notation/lua/notation/popover.lua](../../../../../../extensions/notation/lua/notation/popover.lua) | [runtime/lua/paw/views/cmdline.lua](../../../../../../runtime/lua/paw/views/cmdline.lua) | Invokes supplied callbacks: paw.views.cmdline.open, paw.views.cmdline.remember, paw.views.cmdline.state, require("paw.views.cmdline") | teal |
| [extensions/notation/lua/notation/roll.lua](../../../../../../extensions/notation/lua/notation/roll.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callback: paw.layout.windows | teal |
| [extensions/notation/lua/notation/roll.lua](../../../../../../extensions/notation/lua/notation/roll.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.layout, paw.ui.views | teal |
| [extensions/notation/lua/notation/search.lua](../../../../../../extensions/notation/lua/notation/search.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [extensions/notation/lua/notation/search.lua](../../../../../../extensions/notation/lua/notation/search.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [extensions/notation/lua/notation/search.lua](../../../../../../extensions/notation/lua/notation/search.lua) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callback: paw.address.clip | teal |
| [extensions/notation/lua/notation/search.lua](../../../../../../extensions/notation/lua/notation/search.lua) | [runtime/lua/paw/grep.tl](../../../../../../runtime/lua/paw/grep.tl) | Invokes supplied callback: paw.grep.source | teal |
| [extensions/notation/lua/notation/search.lua](../../../../../../extensions/notation/lua/notation/search.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/notation/lua/notation/smufl.lua](../../../../../../extensions/notation/lua/notation/smufl.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.smufl | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [runtime/lua/paw/canvas.tl](../../../../../../runtime/lua/paw/canvas.tl) | Invokes supplied callbacks: paw.canvas, paw.canvas.open, paw.canvas.open_views | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands, paw.commands.get | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [runtime/lua/paw/ex.tl](../../../../../../runtime/lua/paw/ex.tl) | Invokes supplied callback: paw.ex.views | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups.is_group, paw.groups.rows | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.every, paw.keymap.last_visual, paw.keymap.selection, paw.keymap.set, paw.keymap.visual | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.clip | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope.find, paw.scope.tracks | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.notify | teal |
| [extensions/notation/lua/notation/staves.lua](../../../../../../extensions/notation/lua/notation/staves.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.merge | teal |
| [extensions/notation/lua/notation/step.tl](../../../../../../extensions/notation/lua/notation/step.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/notation/lua/notation/step.tl](../../../../../../extensions/notation/lua/notation/step.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_current, paw.api.undo_join | teal |
| [extensions/notation/lua/notation/step.tl](../../../../../../extensions/notation/lua/notation/step.tl) | [runtime/lua/paw/contracts.tl](../../../../../../runtime/lua/paw/contracts.tl) | Invokes supplied callback: paw.contracts.StepAction | teal |
| [extensions/notation/lua/notation/step.tl](../../../../../../extensions/notation/lua/notation/step.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/notation/lua/notation/step.tl](../../../../../../extensions/notation/lua/notation/step.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.mode_changed, paw.keymap.set_mode | teal |
| [extensions/notation/lua/notation/step.tl](../../../../../../extensions/notation/lua/notation/step.tl) | [runtime/lua/paw/step.tl](../../../../../../runtime/lua/paw/step.tl) | Invokes supplied callbacks: paw.step.held, paw.step.refresh, paw.step.target | teal |
| [extensions/notation/lua/notation/step.tl](../../../../../../extensions/notation/lua/notation/step.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui | teal |
| [extensions/notation/lua/notation/tab.lua](../../../../../../extensions/notation/lua/notation/tab.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/notation/lua/notation/tab.lua](../../../../../../extensions/notation/lua/notation/tab.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.pitch | teal |
| [extensions/notation/lua/notation/tab.lua](../../../../../../extensions/notation/lua/notation/tab.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/notation/lua/notation/tui.lua](../../../../../../extensions/notation/lua/notation/tui.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [extensions/notation/lua/notation/tui.lua](../../../../../../extensions/notation/lua/notation/tui.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/notation/lua/notation/tui.lua](../../../../../../extensions/notation/lua/notation/tui.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [extensions/notation/lua/notation/tui.lua](../../../../../../extensions/notation/lua/notation/tui.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.mix, paw.draw.track_colour, paw.draw.track_hue | teal |
| [extensions/notation/lua/notation/tui.lua](../../../../../../extensions/notation/lua/notation/tui.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.selection, paw.keymap.set_mode, paw.keymap.visual_start | teal |
| [extensions/notation/lua/notation/tui.lua](../../../../../../extensions/notation/lua/notation/tui.lua) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callbacks: paw.mouse.grab, paw.mouse.has, paw.mouse.hint, paw.mouse.wheel | teal |
| [extensions/notation/lua/notation/tui.lua](../../../../../../extensions/notation/lua/notation/tui.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [extensions/notation/lua/notation/tui.lua](../../../../../../extensions/notation/lua/notation/tui.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/notation/lua/notation/tui.lua](../../../../../../extensions/notation/lua/notation/tui.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/notation/lua/notation/tui.lua](../../../../../../extensions/notation/lua/notation/tui.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.keybar, paw.ui.menu, paw.ui.titlebar | teal |
| [extensions/notation/lua/notation/tui.lua](../../../../../../extensions/notation/lua/notation/tui.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
| [extensions/notation/lua/notation/write.lua](../../../../../../extensions/notation/lua/notation/write.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/notation/lua/notation/write.lua](../../../../../../extensions/notation/lua/notation/write.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.roll | teal |
| [extensions/notation/lua/notation/write.lua](../../../../../../extensions/notation/lua/notation/write.lua) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.at, paw.harmony.chords, paw.harmony.set_key | teal |
| [extensions/notation/lua/notation/write.lua](../../../../../../extensions/notation/lua/notation/write.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.mode | teal |
| [extensions/notation/lua/notation/write.lua](../../../../../../extensions/notation/lua/notation/write.lua) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers.add, paw.markers.list, paw.markers.remove | teal |
| [extensions/notation/lua/notation/write.lua](../../../../../../extensions/notation/lua/notation/write.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/notation/lua/notation/write.lua](../../../../../../extensions/notation/lua/notation/write.lua) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callbacks: paw.tempo.at, paw.tempo.remove, paw.tempo.set, paw.tempo.set_signature | teal |
| [extensions/notation/lua/notation/write.lua](../../../../../../extensions/notation/lua/notation/write.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.notify | teal |
| [extensions/notation/lua/notation/write.lua](../../../../../../extensions/notation/lua/notation/write.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.merge, paw.util.round | teal |
| [extensions/notation/manifest.lua](../../../../../../extensions/notation/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
