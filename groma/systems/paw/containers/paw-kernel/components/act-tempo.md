---
type: C4 Component
title: Tempo
status: stable
groma:
  id: act-tempo
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/frontend/act/tempo.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/frontend/act/tempo.tl](../../../../../../runtime/lua/paw/frontend/act/tempo.tl) | [runtime/lua/paw/frontend/core.tl](../../../../../../runtime/lua/paw/frontend/core.tl) | Invokes supplied callback: require("paw.frontend.core") | teal |
| [runtime/lua/paw/frontend/act/tempo.tl](../../../../../../runtime/lua/paw/frontend/act/tempo.tl) | [runtime/lua/paw/frontend/host.tl](../../../../../../runtime/lua/paw/frontend/host.tl) | Invokes supplied callbacks: paw.frontend.host.Point, paw.frontend.host.paw, require("paw.frontend.host") | teal |
