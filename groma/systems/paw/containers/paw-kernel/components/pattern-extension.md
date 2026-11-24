---
type: C4 Component
title: Pattern extension
status: stable
groma:
  id: pattern-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/pattern/init.lua
    - scanner: teal
      file: extensions/pattern/lua/pattern/commands.lua
    - scanner: teal
      file: extensions/pattern/lua/pattern/core.lua
    - scanner: teal
      file: extensions/pattern/lua/pattern/eval.lua
    - scanner: teal
      file: extensions/pattern/lua/pattern/init.lua
    - scanner: teal
      file: extensions/pattern/lua/pattern/names.lua
      symbol: note
    - scanner: teal
      file: extensions/pattern/lua/pattern/parse.lua
    - scanner: teal
      file: extensions/pattern/manifest.lua
      symbol: pattern
  group: Bundled extensions
  technology: Lua
description: Turns a line of text into the notes of a MIDI clip, as in TidalCycles.
---

The text uses the mini-notation of TidalCycles. The user can change the text while the song plays, and the extension writes the notes of the MIDI clip from it.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/pattern/init.lua](../../../../../../extensions/pattern/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/pattern/init.lua](../../../../../../extensions/pattern/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/pattern/lua/pattern/commands.lua](../../../../../../extensions/pattern/lua/pattern/commands.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [extensions/pattern/lua/pattern/commands.lua](../../../../../../extensions/pattern/lua/pattern/commands.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.clip, paw.cursor.set_beat, paw.cursor.track | teal |
| [extensions/pattern/lua/pattern/commands.lua](../../../../../../extensions/pattern/lua/pattern/commands.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.group | teal |
| [extensions/pattern/lua/pattern/commands.lua](../../../../../../extensions/pattern/lua/pattern/commands.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/pattern/lua/pattern/commands.lua](../../../../../../extensions/pattern/lua/pattern/commands.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/pattern/lua/pattern/commands.lua](../../../../../../extensions/pattern/lua/pattern/commands.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.input, paw.ui.notify | teal |
| [extensions/pattern/lua/pattern/commands.lua](../../../../../../extensions/pattern/lua/pattern/commands.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/pattern/lua/pattern/init.lua](../../../../../../extensions/pattern/lua/pattern/init.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list, paw.api.clip_notes, paw.api.clip_set | teal |
| [extensions/pattern/lua/pattern/init.lua](../../../../../../extensions/pattern/lua/pattern/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [extensions/pattern/lua/pattern/init.lua](../../../../../../extensions/pattern/lua/pattern/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [extensions/pattern/lua/pattern/init.lua](../../../../../../extensions/pattern/lua/pattern/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/pattern/lua/pattern/init.lua](../../../../../../extensions/pattern/lua/pattern/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/pattern/lua/pattern/names.lua](../../../../../../extensions/pattern/lua/pattern/names.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.scales | teal |
| [extensions/pattern/manifest.lua](../../../../../../extensions/pattern/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
