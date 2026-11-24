---
type: C4 Component
title: Track column example extension
status: stable
groma:
  id: columnplus-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/columnplus/init.tl
    - scanner: teal
      file: extensions/columnplus/manifest.lua
      symbol: columnplus
  group: Bundled extensions
  technology: Teal
description: Shows how to change the track column.
---

An example for configuration authors. Through paw.trackcolumn.add, it adds a color strip, clip counts, signs for takes and frozen tracks and other fold signs to the track column.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_list | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands, paw.commands.run | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [runtime/lua/paw/contracts.tl](../../../../../../runtime/lua/paw/contracts.tl) | Invokes supplied callback: paw.contracts.ColumnCells | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.set_track | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.track_hue | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.changed, require("paw.events.kernel") | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [runtime/lua/paw/freeze.lua](../../../../../../runtime/lua/paw/freeze.lua) | Invokes supplied callback: paw.freeze.state | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.set | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.changed, paw.options.define, paw.options.opt | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [runtime/lua/paw/takes.tl](../../../../../../runtime/lua/paw/takes.tl) | Invokes supplied callback: paw.takes.count | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [runtime/lua/paw/trackcolumn.tl](../../../../../../runtime/lua/paw/trackcolumn.tl) | Invokes supplied callbacks: paw.trackcolumn.add, paw.trackcolumn.components, paw.trackcolumn.set, paw.trackcolumn.shows, paw.trackcolumn.sign | teal |
| [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/columnplus/manifest.lua](../../../../../../extensions/columnplus/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
