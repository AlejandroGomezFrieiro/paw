---
type: C4 Component
title: Tempolane
status: stable
groma:
  id: tempolane
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/tempolane.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.state_get, paw.api.state_set | teal |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.nest_get, paw.api.nest_set | teal |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callbacks: paw.api.tempo_points, paw.api.tempo_set_points | teal |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.beat | teal |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, require("paw.events") | teal |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callback: paw.tempo.place | teal |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [runtime/lua/paw/tempolane.tl](../../../../../../runtime/lua/paw/tempolane.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, require("paw.util") | teal |
