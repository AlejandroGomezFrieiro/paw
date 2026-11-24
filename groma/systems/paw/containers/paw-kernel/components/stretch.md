---
type: C4 Component
title: Stretch
status: stable
groma:
  id: stretch
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/stretch.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/stretch.lua](../../../../../../runtime/lua/paw/stretch.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_controls, paw.api.clip_get, paw.api.clip_notes, paw.api.clip_set, paw.api.clip_set_controls, paw.api.clip_set_notes, paw.api.clip_warp_add, paw.api.clip_warp_move, paw.api.clip_warp_remove | teal |
| [runtime/lua/paw/stretch.lua](../../../../../../runtime/lua/paw/stretch.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/stretch.lua](../../../../../../runtime/lua/paw/stretch.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/stretch.lua](../../../../../../runtime/lua/paw/stretch.lua) | [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | Invokes supplied callback: paw.takes.shift | teal |
| [runtime/lua/paw/stretch.lua](../../../../../../runtime/lua/paw/stretch.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
