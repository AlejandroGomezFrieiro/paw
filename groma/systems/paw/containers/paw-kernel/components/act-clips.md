---
type: C4 Component
title: Clips
status: stable
groma:
  id: act-clips
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/frontend/act/clips.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/frontend/act/clips.tl](../../../../../../runtime/lua/paw/frontend/act/clips.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_add, paw.api.clip_controls, paw.api.clip_get, paw.api.clip_list, paw.api.clip_notes, paw.api.clip_set, paw.api.clip_set_controls, paw.api.clip_set_notes | teal |
| [runtime/lua/paw/frontend/act/clips.tl](../../../../../../runtime/lua/paw/frontend/act/clips.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/frontend/act/clips.tl](../../../../../../runtime/lua/paw/frontend/act/clips.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/frontend/act/clips.tl](../../../../../../runtime/lua/paw/frontend/act/clips.tl) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/frontend/act/clips.tl](../../../../../../runtime/lua/paw/frontend/act/clips.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.exec, require("paw.commands") | teal |
| [runtime/lua/paw/frontend/act/clips.tl](../../../../../../runtime/lua/paw/frontend/act/clips.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.event, paw.events.on, require("paw.events") | teal |
| [runtime/lua/paw/frontend/act/clips.tl](../../../../../../runtime/lua/paw/frontend/act/clips.tl) | [runtime/lua/paw/frontend/core.tl](../../../../../../runtime/lua/paw/frontend/core.tl) | Invokes supplied callbacks: paw.frontend.core.act, paw.frontend.core.chosen_clips, paw.frontend.core.openers, paw.frontend.core.refresh, require("paw.frontend.core") | teal |
| [runtime/lua/paw/frontend/act/clips.tl](../../../../../../runtime/lua/paw/frontend/act/clips.tl) | [runtime/lua/paw/frontend/host.tl](../../../../../../runtime/lua/paw/frontend/host.tl) | Invokes supplied callbacks: paw.frontend.host.Region, paw.frontend.host.paw, paw.frontend.host.roll, require("paw.frontend.host") | teal |
| [runtime/lua/paw/frontend/act/clips.tl](../../../../../../runtime/lua/paw/frontend/act/clips.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/frontend/act/clips.tl](../../../../../../runtime/lua/paw/frontend/act/clips.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.keep, require("paw.seats") | teal |
| [runtime/lua/paw/frontend/act/clips.tl](../../../../../../runtime/lua/paw/frontend/act/clips.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.round, require("paw.util") | teal |
