---
type: C4 Component
title: Start
status: stable
groma:
  id: start
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/start.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/start.lua](../../../../../../runtime/lua/paw/views/start.lua) | [crates/paw-core/src/api/project.rs](../../../../../../crates/paw-core/src/api/project.rs) | Invokes supplied callback: paw.api.project_get | teal |
| [runtime/lua/paw/views/start.lua](../../../../../../runtime/lua/paw/views/start.lua) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/views/start.lua](../../../../../../runtime/lua/paw/views/start.lua) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.now | teal |
| [runtime/lua/paw/views/start.lua](../../../../../../runtime/lua/paw/views/start.lua) | [crates/paw-core/src/api/transport.rs](../../../../../../crates/paw-core/src/api/transport.rs) | Invokes supplied callback: paw.api.transport_get | teal |
| [runtime/lua/paw/views/start.lua](../../../../../../runtime/lua/paw/views/start.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callback: paw.draw.g | teal |
| [runtime/lua/paw/views/start.lua](../../../../../../runtime/lua/paw/views/start.lua) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callback: paw.events.on | teal |
| [runtime/lua/paw/views/start.lua](../../../../../../runtime/lua/paw/views/start.lua) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.buffers, paw.layout.buftype | teal |
| [runtime/lua/paw/views/start.lua](../../../../../../runtime/lua/paw/views/start.lua) | [runtime/lua/paw/mouse.tl](../../../../../../runtime/lua/paw/mouse.tl) | Invokes supplied callback: paw.mouse.wheel | teal |
| [runtime/lua/paw/views/start.lua](../../../../../../runtime/lua/paw/views/start.lua) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callbacks: paw.objects.project, paw.objects.time | teal |
| [runtime/lua/paw/views/start.lua](../../../../../../runtime/lua/paw/views/start.lua) | [runtime/lua/paw/recent.lua](../../../../../../runtime/lua/paw/recent.lua) | Invokes supplied callbacks: paw.recent, paw.recent.list, paw.recent.open | teal |
| [runtime/lua/paw/views/start.lua](../../../../../../runtime/lua/paw/views/start.lua) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.keybar, paw.ui.notify, paw.ui.titlebar | teal |
| [runtime/lua/paw/views/start.lua](../../../../../../runtime/lua/paw/views/start.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
