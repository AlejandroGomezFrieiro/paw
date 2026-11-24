---
type: C4 Component
title: Ext
status: stable
groma:
  id: ext
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/ext.lua
---

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/articulations/init.lua](../../../../../../extensions/articulations/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/columnplus/init.tl](../../../../../../extensions/columnplus/init.tl) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/continue/init.lua](../../../../../../extensions/continue/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/doctor/init.lua](../../../../../../extensions/doctor/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/drums/init.lua](../../../../../../extensions/drums/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/interop/init.tl](../../../../../../extensions/interop/init.tl) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/launcher/init.lua](../../../../../../extensions/launcher/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/luafx/manifest.lua](../../../../../../extensions/luafx/manifest.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/midilsp/init.lua](../../../../../../extensions/midilsp/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/mixdiag/init.lua](../../../../../../extensions/mixdiag/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/musicops/init.lua](../../../../../../extensions/musicops/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/notation/init.lua](../../../../../../extensions/notation/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/pattern/init.lua](../../../../../../extensions/pattern/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/plugstate/init.tl](../../../../../../extensions/plugstate/init.tl) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/projdiff/init.lua](../../../../../../extensions/projdiff/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/rulerplus/init.tl](../../../../../../extensions/rulerplus/init.tl) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/sampler/init.lua](../../../../../../extensions/sampler/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/sections/init.lua](../../../../../../extensions/sections/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/snippets/manifest.lua](../../../../../../extensions/snippets/manifest.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/templates/init.lua](../../../../../../extensions/templates/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/tutor/init.lua](../../../../../../extensions/tutor/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/undotree/init.lua](../../../../../../extensions/undotree/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/utau/init.lua](../../../../../../extensions/utau/init.lua) | Loads the extension at startup | Lua: manifest and init |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [extensions/vinput/init.lua](../../../../../../extensions/vinput/init.lua) | Loads the extension at startup | Lua: manifest and init |

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: paw.api.version | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.build, paw.api.read_dir, paw.api.startup_enter, paw.api.startup_leave | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address, paw.address.schemes | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/complete.tl](../../../../../../runtime/lua/paw/complete.tl) | Invokes supplied callbacks: paw.complete, paw.complete.sources | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.off, require("paw.events") | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/formats.tl](../../../../../../runtime/lua/paw/formats.tl) | Invokes supplied callbacks: paw.formats, paw.formats.register, paw.formats.registry, paw.formats.unregister | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | Invokes supplied callbacks: paw.health, paw.health.checks | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.timers | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.each, paw.keymap.groups, paw.keymap.put | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/lang.tl](../../../../../../runtime/lua/paw/lang.tl) | Invokes supplied callbacks: paw.lang, paw.lang.compilers, paw.lang.find, paw.lang.loadfile, paw.lang.of, paw.lang.searchpath | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/learn.lua](../../../../../../runtime/lua/paw/learn.lua) | Invokes supplied callbacks: paw.learn, paw.learn.triggers | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callback: paw.limit.untrusted | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | Invokes supplied callbacks: paw.lsp, paw.lsp.configs, paw.lsp.enable | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/luadev.lua](../../../../../../runtime/lua/paw/luadev.lua) | Invokes supplied callbacks: paw.luadev, paw.luadev.add_dir, paw.luadev.dirs, paw.luadev.kinds_in, paw.luadev.remove_dir | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.definitions, paw.options.undefine | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/plugins.lua](../../../../../../runtime/lua/paw/plugins.lua) | Invokes supplied callbacks: paw.plugins, paw.plugins.dirs, paw.plugins.remove_dir | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.all, require("paw.registry") | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/snippet.tl](../../../../../../runtime/lua/paw/snippet.tl) | Invokes supplied callback: paw.snippet.load_dir | teal |
| [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.keybar, paw.ui.layer, paw.ui.layers, paw.ui.notify | teal |
