---
type: C4 Component
title: ARA extension
status: stable
groma:
  id: ara-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/ara/init.lua
    - scanner: teal
      file: extensions/ara/lua/ara/init.lua
    - scanner: teal
      file: extensions/ara/manifest.lua
      symbol: ara
  group: Bundled extensions
  technology: Lua
description: Hosts ARA plugins on audio tracks.
---

An ARA plugin (for example Melodyne) reads a whole audio clip, not only the block that plays now. The extension connects such a plugin to the clips of an audio track and keeps the ARA data beside the state of the device. It has a native part in native/, which Nix builds.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_editor | teal |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.log | teal |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_label | teal |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track_id | teal |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | Invokes supplied callback: paw.health.register | teal |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: paw.defer | teal |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.set | teal |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.add_track | teal |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [runtime/lua/paw/plugins.lua](../../../../../../runtime/lua/paw/plugins.lua) | Invokes supplied callback: paw.plugins.attached | teal |
| [extensions/ara/init.lua](../../../../../../extensions/ara/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/ara/lua/ara/init.lua](../../../../../../extensions/ara/lua/ara/init.lua) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_add, paw.api.device_call, paw.api.device_find, paw.api.device_find_all | teal |
| [extensions/ara/lua/ara/init.lua](../../../../../../extensions/ara/lua/ara/init.lua) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.json_decode | teal |
| [extensions/ara/lua/ara/init.lua](../../../../../../extensions/ara/lua/ara/init.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/ara/lua/ara/init.lua](../../../../../../extensions/ara/lua/ara/init.lua) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callback: paw.api.undo_discard | teal |
| [extensions/ara/lua/ara/init.lua](../../../../../../extensions/ara/lua/ara/init.lua) | [runtime/lua/paw/ext.lua](../../../../../../runtime/lua/paw/ext.lua) | Invokes supplied callback: paw.ext.loaded | teal |
| [extensions/ara/lua/ara/init.lua](../../../../../../extensions/ara/lua/ara/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/ara/lua/ara/init.lua](../../../../../../extensions/ara/lua/ara/init.lua) | [runtime/lua/paw/plugins.lua](../../../../../../runtime/lua/paw/plugins.lua) | Invokes supplied callbacks: paw.plugins.attach, paw.plugins.attached | teal |
| [extensions/ara/lua/ara/init.lua](../../../../../../extensions/ara/lua/ara/init.lua) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callback: paw.tempo.seconds_to_beats | teal |
| [extensions/ara/manifest.lua](../../../../../../extensions/ara/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
