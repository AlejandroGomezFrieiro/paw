---
type: C4 Component
title: Complete
status: stable
groma:
  id: complete
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/complete.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_notes | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.log | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callbacks: paw.api.note_off, paw.api.note_on, paw.api.transport_get | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.g, paw.draw.track_colour | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.clip_changed, paw.events.kernel.clip_removed, paw.events.kernel.project_loaded, require("paw.events.kernel") | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony, paw.harmony.key | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.defer | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.pending, paw.keymap.selection | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callbacks: paw.limit.named, require("paw.limit") | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.name, require("paw.music") | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.changed, paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.keep, require("paw.seats") | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callbacks: paw.theme.palette, require("paw.theme") | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.float, paw.ui.focused, paw.ui.hl, paw.ui.keybar, paw.ui.notify, paw.ui.poke, paw.ui.views | teal |
| [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, require("paw.util") | teal |
