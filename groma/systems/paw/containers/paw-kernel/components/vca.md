---
type: C4 Component
title: Vca
status: stable
groma:
  id: vca
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/vca.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/vca.tl](../../../../../../runtime/lua/paw/vca.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/vca.tl](../../../../../../runtime/lua/paw/vca.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_list, paw.api.track_remove, paw.api.track_set | teal |
| [runtime/lua/paw/vca.tl](../../../../../../runtime/lua/paw/vca.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/vca.tl](../../../../../../runtime/lua/paw/vca.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.track_removed, require("paw.events.kernel") | teal |
| [runtime/lua/paw/vca.tl](../../../../../../runtime/lua/paw/vca.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.add_track | teal |
