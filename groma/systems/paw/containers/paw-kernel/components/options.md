---
type: C4 Component
title: Options
status: stable
groma:
  id: options
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/options.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callback: paw.api.env | teal |
| [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, require("paw.events") | teal |
