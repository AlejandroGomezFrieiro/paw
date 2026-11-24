---
type: C4 Component
title: Tutor extension
status: stable
groma:
  id: tutor-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/tutor/init.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/docs.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/init.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/devices.lua
      symbol: selected
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/extensions.lua
      symbol: loaded
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/finding.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/first_steps.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/grammar.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/grammar_notes.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/init.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/loops.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/making.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/mixing.lua
      symbol: near
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/moving.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/pianoroll.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/ranges.lua
      symbol: track
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/recording.lua
      symbol: play_three_notes
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/registers.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/saving.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/visual.lua
      symbol: track
    - scanner: teal
      file: extensions/tutor/lua/tutor/lessons/your_own.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/look.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/panel.lua
    - scanner: teal
      file: extensions/tutor/lua/tutor/store.lua
    - scanner: teal
      file: extensions/tutor/manifest.lua
      symbol: tutor
  group: Bundled extensions
  technology: Lua
description: Teaches a first-time user in a course inside paw.
---

Runs the lessons of the course in the program. The lessons are also the source of the course pages in docs/tutorials/course.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/tutor/init.lua](../../../../../../extensions/tutor/init.lua) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callbacks: paw.ext.load, paw.ext.loaded | teal |
| [extensions/tutor/init.lua](../../../../../../extensions/tutor/init.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.every | teal |
| [extensions/tutor/init.lua](../../../../../../extensions/tutor/init.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.group | teal |
| [extensions/tutor/init.lua](../../../../../../extensions/tutor/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/tutor/lua/tutor/init.lua](../../../../../../extensions/tutor/lua/tutor/init.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: paw.api.tutor | teal |
| [extensions/tutor/lua/tutor/init.lua](../../../../../../extensions/tutor/lua/tutor/init.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/tutor/lua/tutor/init.lua](../../../../../../extensions/tutor/lua/tutor/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [extensions/tutor/lua/tutor/init.lua](../../../../../../extensions/tutor/lua/tutor/init.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.get | teal |
| [extensions/tutor/lua/tutor/init.lua](../../../../../../extensions/tutor/lua/tutor/init.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.index, paw.cursor.set_beat, paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/init.lua](../../../../../../extensions/tutor/lua/tutor/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/tutor/lua/tutor/init.lua](../../../../../../extensions/tutor/lua/tutor/init.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.flush, paw.try | teal |
| [extensions/tutor/lua/tutor/init.lua](../../../../../../extensions/tutor/lua/tutor/init.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.set_mode | teal |
| [extensions/tutor/lua/tutor/init.lua](../../../../../../extensions/tutor/lua/tutor/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.project, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/init.lua](../../../../../../extensions/tutor/lua/tutor/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [extensions/tutor/lua/tutor/init.lua](../../../../../../extensions/tutor/lua/tutor/init.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/tutor/lua/tutor/init.lua](../../../../../../extensions/tutor/lua/tutor/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.float, paw.ui.focus, paw.ui.hide, paw.ui.messages, paw.ui.notify, paw.ui.page, paw.ui.views | teal |
| [extensions/tutor/lua/tutor/lessons/devices.lua](../../../../../../extensions/tutor/lua/tutor/lessons/devices.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/devices.lua](../../../../../../extensions/tutor/lua/tutor/lessons/devices.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/devices.lua](../../../../../../extensions/tutor/lua/tutor/lessons/devices.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.views | teal |
| [extensions/tutor/lua/tutor/lessons/extensions.lua](../../../../../../extensions/tutor/lua/tutor/lessons/extensions.lua) | [extensions/sections/lua/sections/init.lua](../../../../../../extensions/sections/lua/sections/init.lua) | Invokes supplied callback: require("sections") | teal |
| [extensions/tutor/lua/tutor/lessons/extensions.lua](../../../../../../extensions/tutor/lua/tutor/lessons/extensions.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/extensions.lua](../../../../../../extensions/tutor/lua/tutor/lessons/extensions.lua) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callback: paw.ext.loaded | teal |
| [extensions/tutor/lua/tutor/lessons/extensions.lua](../../../../../../extensions/tutor/lua/tutor/lessons/extensions.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track, paw.objects.tracks, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/finding.lua](../../../../../../extensions/tutor/lua/tutor/lessons/finding.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/finding.lua](../../../../../../extensions/tutor/lua/tutor/lessons/finding.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.hints, paw.keymap.pending | teal |
| [extensions/tutor/lua/tutor/lessons/finding.lua](../../../../../../extensions/tutor/lua/tutor/lessons/finding.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/finding.lua](../../../../../../extensions/tutor/lua/tutor/lessons/finding.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick.state | teal |
| [extensions/tutor/lua/tutor/lessons/first_steps.lua](../../../../../../extensions/tutor/lua/tutor/lessons/first_steps.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.project, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/grammar_notes.lua](../../../../../../extensions/tutor/lua/tutor/lessons/grammar_notes.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/grammar_notes.lua](../../../../../../extensions/tutor/lua/tutor/lessons/grammar_notes.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.mode | teal |
| [extensions/tutor/lua/tutor/lessons/grammar_notes.lua](../../../../../../extensions/tutor/lua/tutor/lessons/grammar_notes.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track | teal |
| [extensions/tutor/lua/tutor/lessons/grammar_notes.lua](../../../../../../extensions/tutor/lua/tutor/lessons/grammar_notes.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.views | teal |
| [extensions/tutor/lua/tutor/lessons/grammar.lua](../../../../../../extensions/tutor/lua/tutor/lessons/grammar.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/grammar.lua](../../../../../../extensions/tutor/lua/tutor/lessons/grammar.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track, paw.objects.tracks, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/loops.lua](../../../../../../extensions/tutor/lua/tutor/lessons/loops.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/loops.lua](../../../../../../extensions/tutor/lua/tutor/lessons/loops.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.marks | teal |
| [extensions/tutor/lua/tutor/lessons/loops.lua](../../../../../../extensions/tutor/lua/tutor/lessons/loops.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/making.lua](../../../../../../extensions/tutor/lua/tutor/lessons/making.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.tracks, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/mixing.lua](../../../../../../extensions/tutor/lua/tutor/lessons/mixing.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/tutor/lua/tutor/lessons/mixing.lua](../../../../../../extensions/tutor/lua/tutor/lessons/mixing.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/mixing.lua](../../../../../../extensions/tutor/lua/tutor/lessons/mixing.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/moving.lua](../../../../../../extensions/tutor/lua/tutor/lessons/moving.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/moving.lua](../../../../../../extensions/tutor/lua/tutor/lessons/moving.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.mode | teal |
| [extensions/tutor/lua/tutor/lessons/moving.lua](../../../../../../extensions/tutor/lua/tutor/lessons/moving.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track | teal |
| [extensions/tutor/lua/tutor/lessons/moving.lua](../../../../../../extensions/tutor/lua/tutor/lessons/moving.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.views | teal |
| [extensions/tutor/lua/tutor/lessons/pianoroll.lua](../../../../../../extensions/tutor/lua/tutor/lessons/pianoroll.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/pianoroll.lua](../../../../../../extensions/tutor/lua/tutor/lessons/pianoroll.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.mode | teal |
| [extensions/tutor/lua/tutor/lessons/pianoroll.lua](../../../../../../extensions/tutor/lua/tutor/lessons/pianoroll.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track | teal |
| [extensions/tutor/lua/tutor/lessons/pianoroll.lua](../../../../../../extensions/tutor/lua/tutor/lessons/pianoroll.lua) | [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | Invokes supplied callbacks: paw.roll_draw.stepping, paw.roll_draw.text | teal |
| [extensions/tutor/lua/tutor/lessons/pianoroll.lua](../../../../../../extensions/tutor/lua/tutor/lessons/pianoroll.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.views | teal |
| [extensions/tutor/lua/tutor/lessons/ranges.lua](../../../../../../extensions/tutor/lua/tutor/lessons/ranges.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/ranges.lua](../../../../../../extensions/tutor/lua/tutor/lessons/ranges.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/recording.lua](../../../../../../extensions/tutor/lua/tutor/lessons/recording.lua) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callback: paw.api.engine_restart | teal |
| [extensions/tutor/lua/tutor/lessons/recording.lua](../../../../../../extensions/tutor/lua/tutor/lessons/recording.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.sleep | teal |
| [extensions/tutor/lua/tutor/lessons/recording.lua](../../../../../../extensions/tutor/lua/tutor/lessons/recording.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/recording.lua](../../../../../../extensions/tutor/lua/tutor/lessons/recording.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.midi.note_off, paw.objects.midi.note_on, paw.objects.track, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/registers.lua](../../../../../../extensions/tutor/lua/tutor/lessons/registers.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/registers.lua](../../../../../../extensions/tutor/lua/tutor/lessons/registers.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.getreg, paw.keymap.recording, paw.keymap.registers | teal |
| [extensions/tutor/lua/tutor/lessons/registers.lua](../../../../../../extensions/tutor/lua/tutor/lessons/registers.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/saving.lua](../../../../../../extensions/tutor/lua/tutor/lessons/saving.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/saving.lua](../../../../../../extensions/tutor/lua/tutor/lessons/saving.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.project, paw.objects.track | teal |
| [extensions/tutor/lua/tutor/lessons/saving.lua](../../../../../../extensions/tutor/lua/tutor/lessons/saving.lua) | [runtime/lua/paw/views/files.lua](../../../../../../runtime/lua/paw/views/files.lua) | Invokes supplied callback: paw.views.files.here | teal |
| [extensions/tutor/lua/tutor/lessons/visual.lua](../../../../../../extensions/tutor/lua/tutor/lessons/visual.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/visual.lua](../../../../../../extensions/tutor/lua/tutor/lessons/visual.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.getreg, paw.keymap.mode, paw.keymap.selection | teal |
| [extensions/tutor/lua/tutor/lessons/visual.lua](../../../../../../extensions/tutor/lua/tutor/lessons/visual.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track, paw.objects.tracks, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/your_own.lua](../../../../../../extensions/tutor/lua/tutor/lessons/your_own.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.set_track | teal |
| [extensions/tutor/lua/tutor/lessons/your_own.lua](../../../../../../extensions/tutor/lua/tutor/lessons/your_own.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.track, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/lessons/your_own.lua](../../../../../../extensions/tutor/lua/tutor/lessons/your_own.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/tutor/lua/tutor/look.lua](../../../../../../extensions/tutor/lua/tutor/look.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [extensions/tutor/lua/tutor/look.lua](../../../../../../extensions/tutor/lua/tutor/look.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track | teal |
| [extensions/tutor/lua/tutor/look.lua](../../../../../../extensions/tutor/lua/tutor/look.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.getreg, paw.keymap.mode | teal |
| [extensions/tutor/lua/tutor/look.lua](../../../../../../extensions/tutor/lua/tutor/look.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.pitch | teal |
| [extensions/tutor/lua/tutor/look.lua](../../../../../../extensions/tutor/lua/tutor/look.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.track, paw.objects.transport | teal |
| [extensions/tutor/lua/tutor/look.lua](../../../../../../extensions/tutor/lua/tutor/look.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.float, paw.ui.focused, paw.ui.messages, paw.ui.views, paw.ui.visible | teal |
| [extensions/tutor/lua/tutor/panel.lua](../../../../../../extensions/tutor/lua/tutor/panel.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.str_width | teal |
| [extensions/tutor/lua/tutor/panel.lua](../../../../../../extensions/tutor/lua/tutor/panel.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.box, paw.ui.dock, paw.ui.hide, paw.ui.hl, paw.ui.show, paw.ui.view, paw.ui.visible | teal |
| [extensions/tutor/lua/tutor/store.lua](../../../../../../extensions/tutor/lua/tutor/store.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.fs_exists | teal |
| [extensions/tutor/lua/tutor/store.lua](../../../../../../extensions/tutor/lua/tutor/store.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/tutor/manifest.lua](../../../../../../extensions/tutor/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
