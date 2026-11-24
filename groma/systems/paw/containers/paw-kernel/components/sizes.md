---
type: C4 Component
title: Sizes
status: stable
groma:
  id: sizes
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/defaults/sizes.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/defaults/sizes.lua](../../../../../../runtime/lua/paw/defaults/sizes.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/defaults/sizes.lua](../../../../../../runtime/lua/paw/defaults/sizes.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.alternate, paw.layout.equalize, paw.layout.focusable_windows, paw.layout.maximize, paw.layout.resize | teal |
| [runtime/lua/paw/defaults/sizes.lua](../../../../../../runtime/lua/paw/defaults/sizes.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [runtime/lua/paw/defaults/sizes.lua](../../../../../../runtime/lua/paw/defaults/sizes.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.arrange, paw.ui.focused, paw.ui.layout, paw.ui.notify, paw.ui.views | teal |
| [runtime/lua/paw/defaults/sizes.lua](../../../../../../runtime/lua/paw/defaults/sizes.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
