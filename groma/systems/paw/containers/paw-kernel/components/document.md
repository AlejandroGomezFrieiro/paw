---
type: C4 Component
title: Document
status: stable
groma:
  id: document
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/lsp/document.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/lsp/document.tl](../../../../../../runtime/lua/paw/lsp/document.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_controls, paw.api.clip_get, paw.api.clip_notes | teal |
| [runtime/lua/paw/lsp/document.tl](../../../../../../runtime/lua/paw/lsp/document.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/lsp/document.tl](../../../../../../runtime/lua/paw/lsp/document.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/lsp/document.tl](../../../../../../runtime/lua/paw/lsp/document.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_get | teal |
| [runtime/lua/paw/lsp/document.tl](../../../../../../runtime/lua/paw/lsp/document.tl) | [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | Invokes supplied callbacks: paw.derived.node, require("paw.derived") | teal |
| [runtime/lua/paw/lsp/document.tl](../../../../../../runtime/lua/paw/lsp/document.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/lsp/document.tl](../../../../../../runtime/lua/paw/lsp/document.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.project_loaded, require("paw.events.kernel") | teal |
| [runtime/lua/paw/lsp/document.tl](../../../../../../runtime/lua/paw/lsp/document.tl) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.is_drums, paw.harmony.key | teal |
| [runtime/lua/paw/lsp/document.tl](../../../../../../runtime/lua/paw/lsp/document.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [runtime/lua/paw/lsp/document.tl](../../../../../../runtime/lua/paw/lsp/document.tl) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callbacks: paw.tempo.at, paw.tempo.points, paw.tempo.signature_at, paw.tempo.signatures | teal |
