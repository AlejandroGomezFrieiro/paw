---
type: C4 Component
title: Notes
status: stable
groma:
  id: act-notes
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/frontend/act/notes.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/frontend/act/notes.tl](../../../../../../runtime/lua/paw/frontend/act/notes.tl) | [crates/paw-core/src/api/clips.rs](../../../../../../crates/paw-core/src/api/clips.rs) | Invokes supplied callbacks: paw.api.clip_get, paw.api.clip_notes | teal |
| [runtime/lua/paw/frontend/act/notes.tl](../../../../../../runtime/lua/paw/frontend/act/notes.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/frontend/act/notes.tl](../../../../../../runtime/lua/paw/frontend/act/notes.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/frontend/act/notes.tl](../../../../../../runtime/lua/paw/frontend/act/notes.tl) | [runtime/lua/paw/frontend/core.tl](../../../../../../runtime/lua/paw/frontend/core.tl) | Invokes supplied callbacks: paw.frontend.core.act, paw.frontend.core.chosen_notes, require("paw.frontend.core") | teal |
| [runtime/lua/paw/frontend/act/notes.tl](../../../../../../runtime/lua/paw/frontend/act/notes.tl) | [runtime/lua/paw/frontend/host.tl](../../../../../../runtime/lua/paw/frontend/host.tl) | Invokes supplied callbacks: paw.frontend.host.Point, paw.frontend.host.paw, paw.frontend.host.roll, require("paw.frontend.host") | teal |
| [runtime/lua/paw/frontend/act/notes.tl](../../../../../../runtime/lua/paw/frontend/act/notes.tl) | [runtime/lua/paw/notes.tl](../../../../../../runtime/lua/paw/notes.tl) | Invokes supplied callbacks: paw.notes.quantize, require("paw.notes") | teal |
| [runtime/lua/paw/frontend/act/notes.tl](../../../../../../runtime/lua/paw/frontend/act/notes.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.opt, require("paw.options") | teal |
| [runtime/lua/paw/frontend/act/notes.tl](../../../../../../runtime/lua/paw/frontend/act/notes.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callbacks: paw.seats.keep, require("paw.seats") | teal |
| [runtime/lua/paw/frontend/act/notes.tl](../../../../../../runtime/lua/paw/frontend/act/notes.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, require("paw.util") | teal |
