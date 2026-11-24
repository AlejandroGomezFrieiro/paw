---
type: C4 Component
title: Window
status: stable
groma:
  id: window
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/frontend/act/window.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/frontend/act/window.tl](../../../../../../runtime/lua/paw/frontend/act/window.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/frontend/act/window.tl](../../../../../../runtime/lua/paw/frontend/act/window.tl) | [crates/paw-core/src/api/timers.rs](../../../../../../crates/paw-core/src/api/timers.rs) | Invokes supplied callback: paw.api.quit | teal |
| [runtime/lua/paw/frontend/act/window.tl](../../../../../../runtime/lua/paw/frontend/act/window.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callbacks: paw.commands.exec, paw.commands.run, require("paw.commands") | teal |
| [runtime/lua/paw/frontend/act/window.tl](../../../../../../runtime/lua/paw/frontend/act/window.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.emit, paw.events.event, require("paw.events") | teal |
| [runtime/lua/paw/frontend/act/window.tl](../../../../../../runtime/lua/paw/frontend/act/window.tl) | [runtime/lua/paw/frontend/core.tl](../../../../../../runtime/lua/paw/frontend/core.tl) | Invokes supplied callbacks: paw.frontend.core.act, paw.frontend.core.bands, paw.frontend.core.menus, paw.frontend.core.save_as, require("paw.frontend.core") | teal |
| [runtime/lua/paw/frontend/act/window.tl](../../../../../../runtime/lua/paw/frontend/act/window.tl) | [runtime/lua/paw/frontend/host.tl](../../../../../../runtime/lua/paw/frontend/host.tl) | Invokes supplied callbacks: paw.frontend.host.paw, require("paw.frontend.host") | teal |
| [runtime/lua/paw/frontend/act/window.tl](../../../../../../runtime/lua/paw/frontend/act/window.tl) | [runtime/lua/paw/frontend/state.tl](../../../../../../runtime/lua/paw/frontend/state.tl) | Invokes supplied callback: require("paw.frontend.state") | teal |
| [runtime/lua/paw/frontend/act/window.tl](../../../../../../runtime/lua/paw/frontend/act/window.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.expand_path, require("paw.util") | teal |
