---
type: C4 Component
title: Subjects
status: stable
groma:
  id: subjects
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/lsp/subjects.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_list | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [crates/paw-core/src/api/devices.rs](../../../../../../crates/paw-core/src/api/devices.rs) | Invokes supplied callback: paw.api.device_get | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [crates/paw-core/src/api/engine.rs](../../../../../../crates/paw-core/src/api/engine.rs) | Invokes supplied callback: paw.api.engine_get | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.clip, paw.address.device, paw.address.parse, paw.address.project, paw.address.render, paw.address.renders, paw.address.track, require("paw.address") | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.track_id | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callback: paw.harmony.is_drums | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [runtime/lua/paw/lsp/document.tl](../../../../../../runtime/lua/paw/lsp/document.tl) | Invokes supplied callbacks: paw.lsp.document.build, paw.lsp.document.key_of, require("paw.lsp.document") | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [runtime/lua/paw/markers.tl](../../../../../../runtime/lua/paw/markers.tl) | Invokes supplied callbacks: paw.markers, paw.markers.list | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [runtime/lua/paw/roll_clips.tl](../../../../../../runtime/lua/paw/roll_clips.tl) | Invokes supplied callbacks: paw.roll_clips, paw.roll_clips.ids | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats, paw.seats.list, paw.seats.within | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [runtime/lua/paw/tempo.tl](../../../../../../runtime/lua/paw/tempo.tl) | Invokes supplied callbacks: paw.tempo.points, paw.tempo.signatures | teal |
| [runtime/lua/paw/lsp/subjects.tl](../../../../../../runtime/lua/paw/lsp/subjects.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.views | teal |
