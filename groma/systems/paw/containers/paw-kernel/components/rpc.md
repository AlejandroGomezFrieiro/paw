---
type: C4 Component
title: Rpc
status: stable
groma:
  id: rpc
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/lsp/rpc.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/lsp/rpc.tl](../../../../../../runtime/lua/paw/lsp/rpc.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callback: paw.api.json_decode | teal |
| [runtime/lua/paw/lsp/rpc.tl](../../../../../../runtime/lua/paw/lsp/rpc.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
