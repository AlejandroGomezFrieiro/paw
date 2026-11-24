---
type: C4 Component
title: Draw
status: stable
groma:
  id: draw
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/draw.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.str_width | teal |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_meter | teal |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.transport_play, require("paw.events.kernel") | teal |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [runtime/lua/paw/groups.tl](../../../../../../runtime/lua/paw/groups.tl) | Invokes supplied callbacks: paw.groups, paw.groups.of | teal |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.is_black, paw.music.name | teal |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callbacks: paw.theme.hues, paw.theme.palette, require("paw.theme") | teal |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.hl | teal |
| [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
