---
type: C4 Component
title: Plugin state extension
status: stable
groma:
  id: plugstate-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/plugstate/init.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/adapters.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/bytes.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/commands.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/frameworks.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/init.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/jsonspan.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/juce.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/juceplugins.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/jucestate.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/jucexml.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/soundshed.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/tone3000_api.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/tone3000_auth.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/tone3000_search.tl
    - scanner: teal
      file: extensions/plugstate/lua/plugstate/tone3000.tl
    - scanner: teal
      file: extensions/plugstate/manifest.lua
      symbol: plugstate
  group: Bundled extensions
  technology: Teal
description: Loads the models, impulse responses and instruments of a plugin without its window.
---

Many plugins keep part of their sound outside their parameters, for example an amp model or a cabinet impulse response. The extension sets that part with keys and commands, steps through a folder of files, and keeps snapshots of the plugin state. It knows the state formats of some plugin frameworks.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/plugstate/init.tl](../../../../../../extensions/plugstate/init.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [extensions/plugstate/init.tl](../../../../../../extensions/plugstate/init.tl) | [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | Invokes supplied callback: paw.health.register | teal |
| [extensions/plugstate/lua/plugstate/adapters.tl](../../../../../../extensions/plugstate/lua/plugstate/adapters.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_call, paw.api.device_state | teal |
| [extensions/plugstate/lua/plugstate/adapters.tl](../../../../../../extensions/plugstate/lua/plugstate/adapters.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_decode, paw.api.json_encode | teal |
| [extensions/plugstate/lua/plugstate/adapters.tl](../../../../../../extensions/plugstate/lua/plugstate/adapters.tl) | [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | Invokes supplied callbacks: paw.bytes.base64, paw.bytes.le32, paw.bytes.u32, paw.bytes.unbase64, paw.bytes.vst3_join, paw.bytes.vst3_split | teal |
| [extensions/plugstate/lua/plugstate/commands.tl](../../../../../../extensions/plugstate/lua/plugstate/commands.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [extensions/plugstate/lua/plugstate/commands.tl](../../../../../../extensions/plugstate/lua/plugstate/commands.tl) | [runtime/lua/paw/audition.tl](../../../../../../runtime/lua/paw/audition.tl) | Invokes supplied callbacks: paw.audition.through, paw.audition.try | teal |
| [extensions/plugstate/lua/plugstate/commands.tl](../../../../../../extensions/plugstate/lua/plugstate/commands.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.set | teal |
| [extensions/plugstate/lua/plugstate/commands.tl](../../../../../../extensions/plugstate/lua/plugstate/commands.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/plugstate/lua/plugstate/commands.tl](../../../../../../extensions/plugstate/lua/plugstate/commands.tl) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/plugstate/lua/plugstate/commands.tl](../../../../../../extensions/plugstate/lua/plugstate/commands.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/plugstate/lua/plugstate/frameworks.tl](../../../../../../extensions/plugstate/lua/plugstate/frameworks.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_state, paw.api.plugins_dirs | teal |
| [extensions/plugstate/lua/plugstate/frameworks.tl](../../../../../../extensions/plugstate/lua/plugstate/frameworks.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.json_encode | teal |
| [extensions/plugstate/lua/plugstate/frameworks.tl](../../../../../../extensions/plugstate/lua/plugstate/frameworks.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [extensions/plugstate/lua/plugstate/frameworks.tl](../../../../../../extensions/plugstate/lua/plugstate/frameworks.tl) | [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | Invokes supplied callbacks: paw.bytes.base64, paw.bytes.le32, paw.bytes.u32, paw.bytes.unbase64, paw.bytes.vst3_join, paw.bytes.vst3_split | teal |
| [extensions/plugstate/lua/plugstate/init.tl](../../../../../../extensions/plugstate/lua/plugstate/init.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_load, paw.api.device_set, paw.api.device_state, paw.api.plugins_dirs | teal |
| [extensions/plugstate/lua/plugstate/init.tl](../../../../../../extensions/plugstate/lua/plugstate/init.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [extensions/plugstate/lua/plugstate/init.tl](../../../../../../extensions/plugstate/lua/plugstate/init.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/plugstate/lua/plugstate/init.tl](../../../../../../extensions/plugstate/lua/plugstate/init.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track_id | teal |
| [extensions/plugstate/lua/plugstate/init.tl](../../../../../../extensions/plugstate/lua/plugstate/init.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event | teal |
| [extensions/plugstate/lua/plugstate/init.tl](../../../../../../extensions/plugstate/lua/plugstate/init.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.device | teal |
| [extensions/plugstate/lua/plugstate/init.tl](../../../../../../extensions/plugstate/lua/plugstate/init.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/plugstate/lua/plugstate/init.tl](../../../../../../extensions/plugstate/lua/plugstate/init.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.views | teal |
| [extensions/plugstate/lua/plugstate/jsonspan.tl](../../../../../../extensions/plugstate/lua/plugstate/jsonspan.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_decode, paw.api.json_encode | teal |
| [extensions/plugstate/lua/plugstate/juce.tl](../../../../../../extensions/plugstate/lua/plugstate/juce.tl) | [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | Invokes supplied callbacks: paw.bytes.base64, paw.bytes.unbase64, paw.bytes.vst3_join, paw.bytes.vst3_split | teal |
| [extensions/plugstate/lua/plugstate/juceplugins.tl](../../../../../../extensions/plugstate/lua/plugstate/juceplugins.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_load, paw.api.device_state | teal |
| [extensions/plugstate/lua/plugstate/juceplugins.tl](../../../../../../extensions/plugstate/lua/plugstate/juceplugins.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/plugstate/lua/plugstate/juceplugins.tl](../../../../../../extensions/plugstate/lua/plugstate/juceplugins.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track_id | teal |
| [extensions/plugstate/lua/plugstate/juceplugins.tl](../../../../../../extensions/plugstate/lua/plugstate/juceplugins.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/plugstate/lua/plugstate/jucestate.tl](../../../../../../extensions/plugstate/lua/plugstate/jucestate.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.deflate, paw.api.inflate, paw.api.json_decode, paw.api.json_encode | teal |
| [extensions/plugstate/lua/plugstate/jucestate.tl](../../../../../../extensions/plugstate/lua/plugstate/jucestate.tl) | [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | Invokes supplied callbacks: paw.bytes.base64, paw.bytes.le32, paw.bytes.u32, paw.bytes.unbase64, paw.bytes.vst3_join, paw.bytes.vst3_split | teal |
| [extensions/plugstate/lua/plugstate/jucexml.tl](../../../../../../extensions/plugstate/lua/plugstate/jucexml.tl) | [runtime/lua/paw/xml.tl](../../../../../../runtime/lua/paw/xml.tl) | Invokes supplied callbacks: paw.xml.decode, paw.xml.encode | teal |
| [extensions/plugstate/lua/plugstate/soundshed.tl](../../../../../../extensions/plugstate/lua/plugstate/soundshed.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_state | teal |
| [extensions/plugstate/lua/plugstate/soundshed.tl](../../../../../../extensions/plugstate/lua/plugstate/soundshed.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_decode, paw.api.json_encode | teal |
| [extensions/plugstate/lua/plugstate/soundshed.tl](../../../../../../extensions/plugstate/lua/plugstate/soundshed.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.read_dir | teal |
| [extensions/plugstate/lua/plugstate/soundshed.tl](../../../../../../extensions/plugstate/lua/plugstate/soundshed.tl) | [crates/paw-core/src/fs_api.rs](../../../../../../crates/paw-core/src/fs_api.rs) | Invokes supplied callback: paw.api.fs_mkdir | teal |
| [extensions/plugstate/lua/plugstate/soundshed.tl](../../../../../../extensions/plugstate/lua/plugstate/soundshed.tl) | [runtime/lua/paw/zip.tl](../../../../../../runtime/lua/paw/zip.tl) | Invokes supplied callback: paw.zip.read | teal |
| [extensions/plugstate/lua/plugstate/tone3000_api.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_api.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.json_decode | teal |
| [extensions/plugstate/lua/plugstate/tone3000_api.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_api.tl) | [crates/paw-core/src/api/processes.rs](../../../../../../crates/paw-core/src/api/processes.rs) | Invokes supplied callbacks: paw.api.proc_close_input, paw.api.proc_kill, paw.api.proc_spawn, paw.api.proc_status, paw.api.proc_write | teal |
| [extensions/plugstate/lua/plugstate/tone3000_api.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_api.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [extensions/plugstate/lua/plugstate/tone3000_api.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_api.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.every | teal |
| [extensions/plugstate/lua/plugstate/tone3000_api.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_api.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/plugstate/lua/plugstate/tone3000_api.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_api.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/plugstate/lua/plugstate/tone3000_auth.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_auth.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_decode, paw.api.json_encode | teal |
| [extensions/plugstate/lua/plugstate/tone3000_auth.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_auth.tl) | [crates/paw-core/src/api/processes.rs](../../../../../../crates/paw-core/src/api/processes.rs) | Invokes supplied callbacks: paw.api.proc_close_input, paw.api.proc_kill, paw.api.proc_read, paw.api.proc_spawn, paw.api.proc_status, paw.api.proc_write | teal |
| [extensions/plugstate/lua/plugstate/tone3000_auth.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_auth.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [extensions/plugstate/lua/plugstate/tone3000_auth.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_auth.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [extensions/plugstate/lua/plugstate/tone3000_auth.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_auth.tl) | [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | Invokes supplied callback: paw.health.executable | teal |
| [extensions/plugstate/lua/plugstate/tone3000_auth.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_auth.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.every | teal |
| [extensions/plugstate/lua/plugstate/tone3000_auth.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_auth.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.define | teal |
| [extensions/plugstate/lua/plugstate/tone3000_auth.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_auth.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.notify, paw.ui.page | teal |
| [extensions/plugstate/lua/plugstate/tone3000_search.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_search.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callbacks: paw.api.device_get, paw.api.device_set | teal |
| [extensions/plugstate/lua/plugstate/tone3000_search.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_search.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands, paw.commands.exec | teal |
| [extensions/plugstate/lua/plugstate/tone3000_search.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_search.tl) | [runtime/lua/paw/health.lua](../../../../../../runtime/lua/paw/health.lua) | Invokes supplied callback: paw.health.register | teal |
| [extensions/plugstate/lua/plugstate/tone3000_search.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_search.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.set | teal |
| [extensions/plugstate/lua/plugstate/tone3000_search.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_search.tl) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/plugstate/lua/plugstate/tone3000_search.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000_search.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/plugstate/lua/plugstate/tone3000.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_state | teal |
| [extensions/plugstate/lua/plugstate/tone3000.tl](../../../../../../extensions/plugstate/lua/plugstate/tone3000.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.json_decode, paw.api.json_encode | teal |
| [extensions/plugstate/manifest.lua](../../../../../../extensions/plugstate/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
