---
type: C4 Component
title: Seats
status: stable
groma:
  id: seats
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/seats.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | [crates/paw-core/src/api/processes.rs](../../../../../../crates/paw-core/src/api/processes.rs) | Invokes supplied callback: paw.api.ui_seat | teal |
| [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_attached | teal |
| [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.emit | teal |
| [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: require("paw.util") | teal |
