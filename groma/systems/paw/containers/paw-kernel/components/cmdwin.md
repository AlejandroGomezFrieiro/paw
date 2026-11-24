---
type: C4 Component
title: Cmdwin
status: stable
groma:
  id: cmdwin
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/cmdwin.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/cmdwin.tl](../../../../../../runtime/lua/paw/cmdwin.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/cmdwin.tl](../../../../../../runtime/lua/paw/cmdwin.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.ui_redraw | teal |
| [runtime/lua/paw/cmdwin.tl](../../../../../../runtime/lua/paw/cmdwin.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.normal | teal |
| [runtime/lua/paw/cmdwin.tl](../../../../../../runtime/lua/paw/cmdwin.tl) | [runtime/lua/paw/layout.tl](../../../../../../runtime/lua/paw/layout.tl) | Invokes supplied callbacks: paw.layout.buf_create, paw.layout.close, paw.layout.current, paw.layout.enter, paw.layout.get, paw.layout.move_to_edge, paw.layout.split | teal |
| [runtime/lua/paw/cmdwin.tl](../../../../../../runtime/lua/paw/cmdwin.tl) | [runtime/lua/paw/textbuf.tl](../../../../../../runtime/lua/paw/textbuf.tl) | Invokes supplied callbacks: paw.textbuf.here, paw.textbuf.kind, paw.textbuf.reload | teal |
| [runtime/lua/paw/cmdwin.tl](../../../../../../runtime/lua/paw/cmdwin.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
