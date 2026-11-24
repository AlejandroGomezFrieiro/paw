---
type: C4 Component
title: Roll context
status: stable
groma:
  id: roll-context
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/roll_context.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/roll_context.tl](../../../../../../runtime/lua/paw/roll_context.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_list, paw.api.clip_notes | teal |
| [runtime/lua/paw/roll_context.tl](../../../../../../runtime/lua/paw/roll_context.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/roll_context.tl](../../../../../../runtime/lua/paw/roll_context.tl) | [crates/paw-core/src/api/tracks.rs](../../../../../../crates/paw-core/src/api/tracks.rs) | Invokes supplied callbacks: paw.api.track_get, paw.api.track_list | teal |
| [runtime/lua/paw/roll_context.tl](../../../../../../runtime/lua/paw/roll_context.tl) | [runtime/lua/paw/derived.tl](../../../../../../runtime/lua/paw/derived.tl) | Invokes supplied callbacks: paw.derived.node, require("paw.derived") | teal |
| [runtime/lua/paw/roll_context.tl](../../../../../../runtime/lua/paw/roll_context.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
