---
type: C4 Component
title: Freeze
status: stable
groma:
  id: freeze
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/freeze.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.media_dir | teal |
| [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list, paw.api.track_set | teal |
| [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_checkpoint | teal |
| [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | [runtime/lua/paw/bake_state.tl](../../../../../../runtime/lua/paw/bake_state.tl) | Invokes supplied callbacks: paw.bake_state.describe, paw.bake_state.make, require("paw.bake_state") | teal |
| [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track_id | teal |
| [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | Invokes supplied callbacks: paw.derived.node, require("paw.derived") | teal |
| [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.on | teal |
| [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | [runtime/lua/paw/render.tl](../../../../../../runtime/lua/paw/render.tl) | Invokes supplied callback: paw.render | teal |
| [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callback: paw.scope.tracks | teal |
| [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.input, paw.ui.notify | teal |
