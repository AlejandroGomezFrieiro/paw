---
type: C4 Component
title: Util
status: stable
groma:
  id: util
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/util.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.str_width | teal |
| [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw, paw.draw.g | teal |
