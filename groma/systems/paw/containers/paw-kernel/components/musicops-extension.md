---
type: C4 Component
title: Musical operators extension
status: stable
groma:
  id: musicops-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/musicops/init.lua
    - scanner: teal
      file: extensions/musicops/lua/musicops/init.lua
    - scanner: teal
      file: extensions/musicops/lua/musicops/keys.lua
    - scanner: teal
      file: extensions/musicops/lua/musicops/scale.lua
    - scanner: teal
      file: extensions/musicops/manifest.lua
      symbol: musicops
  group: Bundled extensions
  technology: Lua
description: Adds operators that humanize, strum, arpeggiate and fit notes to a scale.
---

Each operator works with the motions and text objects of the modal grammar, as one undo step.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/musicops/lua/musicops/init.lua](../../../../../../extensions/musicops/lua/musicops/init.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.pitch | teal |
| [extensions/musicops/lua/musicops/init.lua](../../../../../../extensions/musicops/lua/musicops/init.lua) | [runtime/lua/paw/notes.tl](../../../../../../runtime/lua/paw/notes.tl) | Invokes supplied callback: paw.notes.quantize | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: paw.api.musicops_originals | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands, paw.commands.alias, paw.commands.exec, paw.commands.get | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.clip | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callbacks: paw.edit.arrange, paw.edit.roll | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.key_name, paw.harmony.parse_key | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.group, paw.keymap.list, paw.keymap.operator, paw.keymap.parse, paw.keymap.set, paw.keymap.textobject | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callback: paw.markers.add | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/roll_clips.tl](../../../../../../runtime/lua/paw/roll_clips.tl) | Invokes supplied callbacks: paw.roll_clips, paw.roll_clips.parts | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/roll_draw.tl](../../../../../../runtime/lua/paw/roll_draw.tl) | Invokes supplied callback: paw.roll_draw.pitch | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.notify, paw.ui.page, paw.ui.views | teal |
| [extensions/musicops/lua/musicops/keys.lua](../../../../../../extensions/musicops/lua/musicops/keys.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/musicops/lua/musicops/scale.lua](../../../../../../extensions/musicops/lua/musicops/scale.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.emit | teal |
| [extensions/musicops/lua/musicops/scale.lua](../../../../../../extensions/musicops/lua/musicops/scale.lua) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.degree, paw.harmony.degree_pitch, paw.harmony.in_key, paw.harmony.key_name, paw.harmony.parse_key, paw.harmony.pitch_class, paw.harmony.project_key, paw.harmony.scale_names, paw.harmony.scales, paw.harmony.set_key, paw.harmony.snap, paw.harmony.step | teal |
| [extensions/musicops/manifest.lua](../../../../../../extensions/musicops/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
