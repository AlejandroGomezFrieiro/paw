---
type: C4 Component
title: Sections extension
status: stable
groma:
  id: sections-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/sections/init.lua
    - scanner: teal
      file: extensions/sections/lua/sections/arrange.lua
    - scanner: teal
      file: extensions/sections/lua/sections/init.lua
    - scanner: teal
      file: extensions/sections/lua/sections/ui.lua
    - scanner: teal
      file: extensions/sections/lua/sections/view.lua
    - scanner: teal
      file: extensions/sections/manifest.lua
      symbol: sections
  group: Bundled extensions
  technology: Lua
description: Names the sections of the song and arranges by section.
---

A section has a name and a start, and continues to the next section. Sections are text objects and motions, so the usual operators work on a whole section. Each edit applies to every track and is one undo step.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/sections/lua/sections/arrange.lua](../../../../../../extensions/sections/lua/sections/arrange.lua) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callbacks: paw.api.lane_list, paw.api.lane_points, paw.api.lane_set_points | teal |
| [extensions/sections/lua/sections/arrange.lua](../../../../../../extensions/sections/lua/sections/arrange.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_list, paw.api.clip_notes, paw.api.clip_remove, paw.api.clip_set, paw.api.clip_set_notes | teal |
| [extensions/sections/lua/sections/arrange.lua](../../../../../../extensions/sections/lua/sections/arrange.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [extensions/sections/lua/sections/arrange.lua](../../../../../../extensions/sections/lua/sections/arrange.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [extensions/sections/lua/sections/arrange.lua](../../../../../../extensions/sections/lua/sections/arrange.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.restore_clip, paw.objects.time | teal |
| [extensions/sections/lua/sections/arrange.lua](../../../../../../extensions/sections/lua/sections/arrange.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/sections/lua/sections/init.lua](../../../../../../extensions/sections/lua/sections/init.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_set | teal |
| [extensions/sections/lua/sections/init.lua](../../../../../../extensions/sections/lua/sections/init.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [extensions/sections/lua/sections/init.lua](../../../../../../extensions/sections/lua/sections/init.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.beat | teal |
| [extensions/sections/lua/sections/init.lua](../../../../../../extensions/sections/lua/sections/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on | teal |
| [extensions/sections/lua/sections/init.lua](../../../../../../extensions/sections/lua/sections/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.project, paw.objects.time | teal |
| [extensions/sections/lua/sections/ui.lua](../../../../../../extensions/sections/lua/sections/ui.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [extensions/sections/lua/sections/ui.lua](../../../../../../extensions/sections/lua/sections/ui.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [extensions/sections/lua/sections/ui.lua](../../../../../../extensions/sections/lua/sections/ui.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [extensions/sections/lua/sections/ui.lua](../../../../../../extensions/sections/lua/sections/ui.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.set_beat | teal |
| [extensions/sections/lua/sections/ui.lua](../../../../../../extensions/sections/lua/sections/ui.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/sections/lua/sections/ui.lua](../../../../../../extensions/sections/lua/sections/ui.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.getreg, paw.keymap.group, paw.keymap.push_jump, paw.keymap.set, paw.keymap.setreg, paw.keymap.textobject | teal |
| [extensions/sections/lua/sections/ui.lua](../../../../../../extensions/sections/lua/sections/ui.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.project, paw.objects.time | teal |
| [extensions/sections/lua/sections/ui.lua](../../../../../../extensions/sections/lua/sections/ui.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/sections/lua/sections/ui.lua](../../../../../../extensions/sections/lua/sections/ui.lua) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callback: paw.tempo.is_bar_line | teal |
| [extensions/sections/lua/sections/ui.lua](../../../../../../extensions/sections/lua/sections/ui.lua) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callbacks: paw.theme.palette, require("paw.theme") | teal |
| [extensions/sections/lua/sections/ui.lua](../../../../../../extensions/sections/lua/sections/ui.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focus, paw.ui.focused, paw.ui.hl, paw.ui.input, paw.ui.notify, paw.ui.views | teal |
| [extensions/sections/lua/sections/ui.lua](../../../../../../extensions/sections/lua/sections/ui.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/sections/lua/sections/view.lua](../../../../../../extensions/sections/lua/sections/view.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [extensions/sections/lua/sections/view.lua](../../../../../../extensions/sections/lua/sections/view.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [extensions/sections/lua/sections/view.lua](../../../../../../extensions/sections/lua/sections/view.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.close, paw.ui.float, paw.ui.open, paw.ui.view | teal |
| [extensions/sections/lua/sections/view.lua](../../../../../../extensions/sections/lua/sections/view.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
| [extensions/sections/manifest.lua](../../../../../../extensions/sections/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
