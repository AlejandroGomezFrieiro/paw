---
type: C4 Component
title: Buf
status: stable
groma:
  id: buf
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/buf.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/buf.tl](../../../../../../runtime/lua/paw/buf.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/buf.tl](../../../../../../runtime/lua/paw/buf.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.grid_keep, paw.api.grid_put | teal |
