---
type: C4 Component
title: Registers
status: stable
groma:
  id: registers
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/keymap/registers.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/keymap/registers.tl](../../../../../../runtime/lua/paw/keymap/registers.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/keymap/registers.tl](../../../../../../runtime/lua/paw/keymap/registers.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/keymap/registers.tl](../../../../../../runtime/lua/paw/keymap/registers.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.keep | teal |
| [runtime/lua/paw/keymap/registers.tl](../../../../../../runtime/lua/paw/keymap/registers.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
