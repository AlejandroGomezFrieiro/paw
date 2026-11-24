---
type: C4 Component
title: Sampler extension
status: stable
groma:
  id: sampler-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/sampler/init.lua
    - scanner: teal
      file: extensions/sampler/lua/sampler/commands.lua
    - scanner: teal
      file: extensions/sampler/lua/sampler/init.lua
    - scanner: teal
      file: extensions/sampler/manifest.lua
      symbol: sampler
  group: Bundled extensions
  technology: Lua
description: Adds the paw sample player for SFZ and Decent Sampler instruments.
---

The player is a CLAP plugin (dev.paw.sampler), the paw-sampler container, which the extension builds from its own Rust source. The Lua part finds instruments and puts the player on tracks. Each note can choose its articulation through its MIDI 2.0 attribute.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/sampler/init.lua](../../../../../../extensions/sampler/init.lua) | [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | Invokes supplied callback: paw.health.register | teal |
| [extensions/sampler/init.lua](../../../../../../extensions/sampler/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/sampler/init.lua](../../../../../../extensions/sampler/init.lua) | [runtime/lua/paw/plugins.lua](../../../../../../runtime/lua/paw/plugins.lua) | Invokes supplied callbacks: paw.plugins, paw.plugins.add_dir | teal |
| [extensions/sampler/lua/sampler/commands.lua](../../../../../../extensions/sampler/lua/sampler/commands.lua) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callbacks: paw.audition.phrase, paw.audition.try | teal |
| [extensions/sampler/lua/sampler/commands.lua](../../../../../../extensions/sampler/lua/sampler/commands.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands.run | teal |
| [extensions/sampler/lua/sampler/commands.lua](../../../../../../extensions/sampler/lua/sampler/commands.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track_id | teal |
| [extensions/sampler/lua/sampler/commands.lua](../../../../../../extensions/sampler/lua/sampler/commands.lua) | [runtime/lua/paw/frontend.tl](../../../../../../runtime/lua/paw/frontend.tl) | Invokes supplied callback: paw.frontend.menus | teal |
| [extensions/sampler/lua/sampler/commands.lua](../../../../../../extensions/sampler/lua/sampler/commands.lua) | [runtime/lua/paw/music.tl](../../../../../../runtime/lua/paw/music.tl) | Invokes supplied callback: paw.music.name | teal |
| [extensions/sampler/lua/sampler/commands.lua](../../../../../../extensions/sampler/lua/sampler/commands.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/sampler/lua/sampler/commands.lua](../../../../../../extensions/sampler/lua/sampler/commands.lua) | [runtime/lua/paw/track_kinds.lua](../../../../../../runtime/lua/paw/track_kinds.lua) | Invokes supplied callback: paw.track_kinds.define | teal |
| [extensions/sampler/lua/sampler/commands.lua](../../../../../../extensions/sampler/lua/sampler/commands.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/sampler/lua/sampler/init.lua](../../../../../../extensions/sampler/lua/sampler/init.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_call, paw.api.device_find, paw.api.device_get, paw.api.device_load | teal |
| [extensions/sampler/lua/sampler/init.lua](../../../../../../extensions/sampler/lua/sampler/init.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: paw.api.decode | teal |
| [extensions/sampler/lua/sampler/init.lua](../../../../../../extensions/sampler/lua/sampler/init.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [extensions/sampler/lua/sampler/init.lua](../../../../../../extensions/sampler/lua/sampler/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/sampler/lua/sampler/init.lua](../../../../../../extensions/sampler/lua/sampler/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.emit | teal |
| [extensions/sampler/lua/sampler/init.lua](../../../../../../extensions/sampler/lua/sampler/init.lua) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callback: paw.ext.loaded | teal |
| [extensions/sampler/lua/sampler/init.lua](../../../../../../extensions/sampler/lua/sampler/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/sampler/manifest.lua](../../../../../../extensions/sampler/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
