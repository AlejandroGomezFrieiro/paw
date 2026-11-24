---
type: C4 Component
title: Startuptime
status: stable
groma:
  id: paw-startuptime
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/startuptime.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/startuptime.tl](../../../../../../runtime/lua/paw/startuptime.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/startuptime.tl](../../../../../../runtime/lua/paw/startuptime.tl) | [crates/paw-core/src/api/system.rs](../../../../../../crates/paw-core/src/api/system.rs) | Invokes supplied callbacks: paw.api.startup_enter, paw.api.startup_leave | teal |
