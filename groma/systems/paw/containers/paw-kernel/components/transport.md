---
type: C4 Component
title: Transport
status: stable
groma:
  id: transport
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/transport.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callback: paw.api.engine_follow | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callbacks: paw.api.transport_get, paw.api.transport_set | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_current, paw.api.undo_join, paw.api.undo_limits | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.track_id | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/defaults/common.lua](../../../../../../runtime/lua/paw/defaults/common.lua) | Invokes supplied callback: require("paw.defaults.common") | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/edit.tl](../../../../../../runtime/lua/paw/edit.tl) | Invokes supplied callback: paw.edit.arrange | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.mode, paw.keymap.selection, paw.keymap.set_mode | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.time, paw.objects.transport | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | Invokes supplied callback: paw.ruler.loop_text | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.current | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | Invokes supplied callbacks: paw.takes.count, paw.takes.record_over | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callback: paw.tempo.commands | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | Invokes supplied callback: paw.tempolane.commands | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.notify, paw.ui.views | teal |
| [runtime/lua/paw/defaults/transport.lua](../../../../../../runtime/lua/paw/defaults/transport.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
