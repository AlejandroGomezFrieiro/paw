---
type: C4 Component
title: Notes
status: stable
groma:
  id: notes
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/roles/notes.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/roles/notes.lua](../../../../../../runtime/lua/paw/roles/notes.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.g, paw.draw.piano_key | teal |
| [runtime/lua/paw/roles/notes.lua](../../../../../../runtime/lua/paw/roles/notes.lua) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callback: paw.options.opt | teal |
| [runtime/lua/paw/roles/notes.lua](../../../../../../runtime/lua/paw/roles/notes.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callbacks: paw.util.clamp, paw.util.fit | teal |
