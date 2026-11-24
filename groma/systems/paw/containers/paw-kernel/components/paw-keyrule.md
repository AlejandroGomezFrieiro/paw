---
type: C4 Component
title: Keyrule
status: stable
groma:
  id: paw-keyrule
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/keyrule.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/keyrule.tl](../../../../../../runtime/lua/paw/keyrule.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callbacks: paw.keymap.every, paw.keymap.groups, paw.keymap.parse | teal |
