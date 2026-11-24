---
type: C4 Component
title: Insert
status: stable
groma:
  id: insert
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/insert.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [crates/paw-core/src/api/automation.rs](../../../../../../crates/paw-core/src/api/automation.rs) | Invokes supplied callback: paw.api.lane_set_points | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callback: paw.api.tempo_bar_length | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/clip_kinds.tl](../../../../../../runtime/lua/paw/clip_kinds.tl) | Invokes supplied callbacks: paw.clip_kinds.add, paw.clip_kinds.spec | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.completers, paw.commands.run, require("paw.commands") | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.lane_id, paw.cursor.set_beat, paw.cursor.track_id, require("paw.cursor") | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callback: paw.ext.caller | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers.add, paw.markers.default_name, paw.markers.list, paw.markers.regions, paw.markers.remove | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.lane, paw.objects.time, paw.objects.track, require("paw.objects") | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.changed, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | Invokes supplied callback: paw.track_kinds | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.input, paw.ui.notify, paw.ui.views | teal |
| [runtime/lua/paw/insert.tl](../../../../../../runtime/lua/paw/insert.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.by_order, require("paw.util") | teal |
