---
type: C4 Component
title: Annotation
status: stable
groma:
  id: annotation
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/annotation.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/annotation.lua](../../../../../../runtime/lua/paw/annotation.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callbacks: paw.api.str_width, paw.api.ui_redraw | teal |
| [runtime/lua/paw/annotation.lua](../../../../../../runtime/lua/paw/annotation.lua) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.device, paw.address.track, paw.address.within | teal |
| [runtime/lua/paw/annotation.lua](../../../../../../runtime/lua/paw/annotation.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.on | teal |
| [runtime/lua/paw/annotation.lua](../../../../../../runtime/lua/paw/annotation.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.layer, paw.ui.views | teal |
| [runtime/lua/paw/annotation.lua](../../../../../../runtime/lua/paw/annotation.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.fit | teal |
