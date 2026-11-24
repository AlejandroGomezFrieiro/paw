---
type: C4 Component
title: MIDI LSP extension
status: stable
groma:
  id: midilsp-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/midilsp/init.lua
    - scanner: teal
      file: extensions/midilsp/lua/midilsp/adapter.lua
    - scanner: teal
      file: extensions/midilsp/lua/midilsp/checks.lua
    - scanner: teal
      file: extensions/midilsp/lua/midilsp/init.lua
    - scanner: teal
      file: extensions/midilsp/manifest.lua
      symbol: midilsp
  group: Bundled extensions
  technology: Lua
description: Adds MIDI LSP, a language server for music, to paw.lsp.
---

Tells paw where the MIDI LSP server is and how to start it, and keeps its preset and rules with the project. The results (voice-leading diagnostics with fixes, the chords it hears, suggestions) go through the generic parts of the core: paw.diagnostic, paw.harmony and paw.complete.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/midilsp/init.lua](../../../../../../extensions/midilsp/init.lua) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [extensions/midilsp/init.lua](../../../../../../extensions/midilsp/init.lua) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.set | teal |
| [extensions/midilsp/init.lua](../../../../../../extensions/midilsp/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [extensions/midilsp/init.lua](../../../../../../extensions/midilsp/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.notify, paw.ui.page | teal |
| [extensions/midilsp/lua/midilsp/adapter.lua](../../../../../../extensions/midilsp/lua/midilsp/adapter.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_notes | teal |
| [extensions/midilsp/lua/midilsp/adapter.lua](../../../../../../extensions/midilsp/lua/midilsp/adapter.lua) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.clip, paw.address.find_note, paw.address.note, paw.address.parse, paw.address.resolve | teal |
| [extensions/midilsp/lua/midilsp/adapter.lua](../../../../../../extensions/midilsp/lua/midilsp/adapter.lua) | [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | Invokes supplied callbacks: paw.lsp.adapter, paw.lsp.has | teal |
| [extensions/midilsp/lua/midilsp/adapter.lua](../../../../../../extensions/midilsp/lua/midilsp/adapter.lua) | [runtime/lua/paw/lsp/rpc.tl](../../../../../../runtime/lua/paw/lsp/rpc.tl) | Invokes supplied callback: require("paw.lsp.rpc") | teal |
| [extensions/midilsp/lua/midilsp/adapter.lua](../../../../../../extensions/midilsp/lua/midilsp/adapter.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.merge | teal |
| [extensions/midilsp/lua/midilsp/checks.lua](../../../../../../extensions/midilsp/lua/midilsp/checks.lua) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callback: paw.api.engine_get | teal |
| [extensions/midilsp/lua/midilsp/checks.lua](../../../../../../extensions/midilsp/lua/midilsp/checks.lua) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.fs_exists, paw.api.which | teal |
| [extensions/midilsp/lua/midilsp/checks.lua](../../../../../../extensions/midilsp/lua/midilsp/checks.lua) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [extensions/midilsp/lua/midilsp/checks.lua](../../../../../../extensions/midilsp/lua/midilsp/checks.lua) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.device, paw.address.track | teal |
| [extensions/midilsp/lua/midilsp/checks.lua](../../../../../../extensions/midilsp/lua/midilsp/checks.lua) | [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | Invokes supplied callback: paw.bytes.base64 | teal |
| [extensions/midilsp/lua/midilsp/checks.lua](../../../../../../extensions/midilsp/lua/midilsp/checks.lua) | [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | Invokes supplied callbacks: paw.lsp.config, paw.lsp.enable | teal |
| [extensions/midilsp/lua/midilsp/checks.lua](../../../../../../extensions/midilsp/lua/midilsp/checks.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [extensions/midilsp/lua/midilsp/init.lua](../../../../../../extensions/midilsp/lua/midilsp/init.lua) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callback: paw.api.clip_get | teal |
| [extensions/midilsp/lua/midilsp/init.lua](../../../../../../extensions/midilsp/lua/midilsp/init.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callbacks: paw.api.project_get, paw.api.project_set | teal |
| [extensions/midilsp/lua/midilsp/init.lua](../../../../../../extensions/midilsp/lua/midilsp/init.lua) | [runtime/lua/paw/diagnostic.tl](../../../../../../runtime/lua/paw/diagnostic.tl) | Invokes supplied callbacks: paw.diagnostic.apply, paw.diagnostic.format, paw.diagnostic.get, paw.diagnostic.severity, paw.diagnostic.show | teal |
| [extensions/midilsp/lua/midilsp/init.lua](../../../../../../extensions/midilsp/lua/midilsp/init.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [extensions/midilsp/lua/midilsp/init.lua](../../../../../../extensions/midilsp/lua/midilsp/init.lua) | [runtime/lua/paw/lsp/init.tl](../../../../../../runtime/lua/paw/lsp/init.tl) | Invokes supplied callbacks: paw.lsp.clients, paw.lsp.config, paw.lsp.enable, paw.lsp.info_lines, paw.lsp.notify | teal |
| [extensions/midilsp/lua/midilsp/init.lua](../../../../../../extensions/midilsp/lua/midilsp/init.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/midilsp/lua/midilsp/init.lua](../../../../../../extensions/midilsp/lua/midilsp/init.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [extensions/midilsp/lua/midilsp/init.lua](../../../../../../extensions/midilsp/lua/midilsp/init.lua) | [runtime/lua/paw/pick.tl](../../../../../../runtime/lua/paw/pick.tl) | Invokes supplied callback: paw.pick | teal |
| [extensions/midilsp/lua/midilsp/init.lua](../../../../../../extensions/midilsp/lua/midilsp/init.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/midilsp/lua/midilsp/init.lua](../../../../../../extensions/midilsp/lua/midilsp/init.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.fit | teal |
| [extensions/midilsp/manifest.lua](../../../../../../extensions/midilsp/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
