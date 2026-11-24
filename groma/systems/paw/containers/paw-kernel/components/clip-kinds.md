---
type: C4 Component
title: Clip kinds
status: stable
groma:
  id: clip-kinds
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/clip_kinds.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/clip_kinds.tl](../../../../../../runtime/lua/paw/clip_kinds.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_add, paw.api.clip_custom, paw.api.clip_get, paw.api.clip_kind_define, paw.api.clip_kind_remove, paw.api.clip_list, paw.api.clip_set_custom, paw.api.cue_list | teal |
| [runtime/lua/paw/clip_kinds.tl](../../../../../../runtime/lua/paw/clip_kinds.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/clip_kinds.tl](../../../../../../runtime/lua/paw/clip_kinds.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callback: paw.api.track_list | teal |
| [runtime/lua/paw/clip_kinds.tl](../../../../../../runtime/lua/paw/clip_kinds.tl) | [crates/paw-core/src/api/undo.rs](../../../../../../crates/paw-core/src/api/undo.rs) | Invokes supplied callbacks: paw.api.undo_label, paw.api.undo_pending, paw.api.undo_reset | teal |
| [runtime/lua/paw/clip_kinds.tl](../../../../../../runtime/lua/paw/clip_kinds.tl) | [crates/paw-core/src/tempo_api.rs](../../../../../../crates/paw-core/src/tempo_api.rs) | Invokes supplied callback: paw.api.tempo_seconds | teal |
| [runtime/lua/paw/clip_kinds.tl](../../../../../../runtime/lua/paw/clip_kinds.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/clip_kinds.tl](../../../../../../runtime/lua/paw/clip_kinds.tl) | [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | Invokes supplied callbacks: paw.events.kernel.project_loaded, require("paw.events.kernel") | teal |
| [runtime/lua/paw/clip_kinds.tl](../../../../../../runtime/lua/paw/clip_kinds.tl) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callbacks: paw.limit.within, require("paw.limit") | teal |
| [runtime/lua/paw/clip_kinds.tl](../../../../../../runtime/lua/paw/clip_kinds.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.clip, require("paw.objects") | teal |
| [runtime/lua/paw/clip_kinds.tl](../../../../../../runtime/lua/paw/clip_kinds.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, require("paw.options") | teal |
| [runtime/lua/paw/clip_kinds.tl](../../../../../../runtime/lua/paw/clip_kinds.tl) | [runtime/lua/paw/registry.tl](../../../../../../runtime/lua/paw/registry.tl) | Invokes supplied callbacks: paw.registry.new, require("paw.registry") | teal |
