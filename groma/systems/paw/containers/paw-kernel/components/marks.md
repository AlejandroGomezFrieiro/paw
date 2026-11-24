---
type: C4 Component
title: Marks
status: stable
groma:
  id: marks
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/keymap/marks.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/keymap/marks.tl](../../../../../../runtime/lua/paw/keymap/marks.tl) | [runtime/lua/paw/scope.tl](../../../../../../runtime/lua/paw/scope.tl) | Invokes supplied callbacks: paw.scope, paw.scope.current, paw.scope.restore | teal |
| [runtime/lua/paw/keymap/marks.tl](../../../../../../runtime/lua/paw/keymap/marks.tl) | [runtime/lua/paw/seats.tl](../../../../../../runtime/lua/paw/seats.tl) | Invokes supplied callback: paw.seats.keep | teal |
| [runtime/lua/paw/keymap/marks.tl](../../../../../../runtime/lua/paw/keymap/marks.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callbacks: paw.ui.focused, paw.ui.notify, paw.ui.views | teal |
| [runtime/lua/paw/keymap/marks.tl](../../../../../../runtime/lua/paw/keymap/marks.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
