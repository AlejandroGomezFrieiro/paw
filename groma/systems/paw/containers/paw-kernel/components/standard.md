---
type: C4 Component
title: Standard
status: stable
groma:
  id: standard
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/lsp/standard.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/lsp/standard.tl](../../../../../../runtime/lua/paw/lsp/standard.tl) | [runtime/lua/paw/address.tl](../../../../../../runtime/lua/paw/address.tl) | Invokes supplied callbacks: paw.address.clip, require("paw.address") | teal |
| [runtime/lua/paw/lsp/standard.tl](../../../../../../runtime/lua/paw/lsp/standard.tl) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callbacks: paw.PawCapabilities, paw.PawOffer, paw.PawPlace | teal |
| [runtime/lua/paw/lsp/standard.tl](../../../../../../runtime/lua/paw/lsp/standard.tl) | [runtime/lua/paw/lsp/rpc.tl](../../../../../../runtime/lua/paw/lsp/rpc.tl) | Invokes supplied callbacks: paw.lsp.rpc.Id, paw.lsp.rpc.encode, paw.lsp.rpc.object, require("paw.lsp.rpc") | teal |
