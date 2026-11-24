---
type: C4 Component
title: Slices
status: stable
groma:
  id: slices
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/slices.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/slices.tl](../../../../../../runtime/lua/paw/slices.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/slices.tl](../../../../../../runtime/lua/paw/slices.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.real_ms | teal |
| [runtime/lua/paw/slices.tl](../../../../../../runtime/lua/paw/slices.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.cancel, paw.defer, paw.try | teal |
| [runtime/lua/paw/slices.tl](../../../../../../runtime/lua/paw/slices.tl) | [runtime/lua/paw/limit.tl](../../../../../../runtime/lua/paw/limit.tl) | Invokes supplied callback: require("paw.limit") | teal |
