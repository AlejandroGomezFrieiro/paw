---
type: C4 Component
title: Status
status: stable
groma:
  id: status
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/status.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/status.lua](../../../../../../runtime/lua/paw/views/status.lua) | [runtime/lua/paw/statusline.tl](../../../../../../runtime/lua/paw/statusline.tl) | Invokes supplied callbacks: paw.statusline.draw, paw.statusline.grid_text, paw.statusline.segments, paw.statusline.stamp | teal |
| [runtime/lua/paw/views/status.lua](../../../../../../runtime/lua/paw/views/status.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.view | teal |
