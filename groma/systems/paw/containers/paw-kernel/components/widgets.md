---
type: C4 Component
title: Widgets
status: stable
groma:
  id: widgets
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/roles/widgets.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/roles/widgets.lua](../../../../../../runtime/lua/paw/roles/widgets.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.str_width | teal |
| [runtime/lua/paw/roles/widgets.lua](../../../../../../runtime/lua/paw/roles/widgets.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.g, paw.draw.pan, paw.draw.slider, paw.draw.vmeter | teal |
| [runtime/lua/paw/roles/widgets.lua](../../../../../../runtime/lua/paw/roles/widgets.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
