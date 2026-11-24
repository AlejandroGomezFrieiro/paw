---
type: C4 Component
title: Core
status: stable
groma:
  id: core
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/frontend/core.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/frontend/core.tl](../../../../../../runtime/lua/paw/frontend/core.tl) | [runtime/lua/paw/events.tl](../../../../../../runtime/lua/paw/events.tl) | Invokes supplied callbacks: paw.events.event, paw.events.on, require("paw.events") | teal |
