---
type: C4 Component
title: Kernel
status: stable
groma:
  id: kernel
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/events/kernel.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/events/kernel.tl](../../../../../../runtime/lua/paw/events/kernel.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.event, require("paw.events") | teal |
