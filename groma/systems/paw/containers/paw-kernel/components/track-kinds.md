---
type: C4 Component
title: Track kinds
status: stable
groma:
  id: track-kinds
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/track_kinds.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.openers | teal |
| [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.add_track, paw.objects.clip, paw.objects.track | teal |
| [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callback: require("paw.registry") | teal |
| [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.layer | teal |
