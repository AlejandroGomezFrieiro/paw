---
type: C4 Component
title: Cursor
status: stable
groma:
  id: defaults-cursor
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/cursor.lua
      symbol: clip_edges
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/cursor.lua](../../../../../../runtime/lua/paw/defaults/cursor.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [runtime/lua/paw/defaults/cursor.lua](../../../../../../runtime/lua/paw/defaults/cursor.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callbacks: paw.cursor.beat, paw.cursor.move_track, paw.cursor.set_beat, paw.cursor.set_track, paw.cursor.snap, paw.cursor.track | teal |
| [runtime/lua/paw/defaults/cursor.lua](../../../../../../runtime/lua/paw/defaults/cursor.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.time, paw.objects.transport | teal |
| [runtime/lua/paw/defaults/cursor.lua](../../../../../../runtime/lua/paw/defaults/cursor.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/defaults/cursor.lua](../../../../../../runtime/lua/paw/defaults/cursor.lua) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope.song_bar, paw.scope.tracks | teal |
| [runtime/lua/paw/defaults/cursor.lua](../../../../../../runtime/lua/paw/defaults/cursor.lua) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callback: paw.tempo.is_bar_line | teal |
| [runtime/lua/paw/defaults/cursor.lua](../../../../../../runtime/lua/paw/defaults/cursor.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
