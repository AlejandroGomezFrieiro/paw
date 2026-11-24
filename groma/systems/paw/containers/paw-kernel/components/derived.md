---
type: C4 Component
title: Derived
status: stable
groma:
  id: derived
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/derived.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.ui_redraw, paw.api.view_ranges, paw.api.view_ranges_set | teal |
| [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.real_ms | teal |
| [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.changed, paw.events.kernel.clip_added, paw.events.kernel.clip_changed, paw.events.kernel.clip_removed, paw.events.kernel.device_added, paw.events.kernel.device_changed, paw.events.kernel.device_removed, paw.events.kernel.project_changed, paw.events.kernel.project_loaded, paw.events.kernel.track_added, paw.events.kernel.track_changed, paw.events.kernel.track_moved, paw.events.kernel.track_removed, require("paw.events.kernel") | teal |
| [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.changed, require("paw.options") | teal |
| [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | [runtime/lua/paw/slices.tl](../../../../../../runtime/lua/paw/slices.tl) | Invokes supplied callbacks: paw.slices.job, paw.slices.run, paw.slices.stop, require("paw.slices") | teal |
