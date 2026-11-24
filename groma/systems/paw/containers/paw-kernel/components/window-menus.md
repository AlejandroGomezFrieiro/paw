---
type: C4 Component
title: Window menus
status: stable
groma:
  id: window-menus
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/window_menus.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/window_menus.tl](../../../../../../runtime/lua/paw/window_menus.tl) | [runtime/lua/paw/menu.tl](../../../../../../runtime/lua/paw/menu.tl) | Invokes supplied callback: require("paw.menu") | teal |
| [runtime/lua/paw/window_menus.tl](../../../../../../runtime/lua/paw/window_menus.tl) | [runtime/lua/paw/mouse_menus.tl](../../../../../../runtime/lua/paw/mouse_menus.tl) | Invokes supplied callbacks: paw.mouse_menus.MenuArg, require("paw.mouse_menus") | teal |
