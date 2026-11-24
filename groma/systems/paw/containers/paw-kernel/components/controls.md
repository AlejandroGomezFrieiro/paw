---
type: C4 Component
title: Controls
status: stable
groma:
  id: controls
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/controls.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/controls.lua](../../../../../../runtime/lua/paw/controls.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [runtime/lua/paw/controls.lua](../../../../../../runtime/lua/paw/controls.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/controls.lua](../../../../../../runtime/lua/paw/controls.lua) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callback: paw.api.tempo_signature | teal |
| [runtime/lua/paw/controls.lua](../../../../../../runtime/lua/paw/controls.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callbacks: paw.music.name, paw.music.pitch | teal |
| [runtime/lua/paw/controls.lua](../../../../../../runtime/lua/paw/controls.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, paw.objects.time | teal |
| [runtime/lua/paw/controls.lua](../../../../../../runtime/lua/paw/controls.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/controls.lua](../../../../../../runtime/lua/paw/controls.lua) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.keep | teal |
| [runtime/lua/paw/controls.lua](../../../../../../runtime/lua/paw/controls.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.round | teal |
