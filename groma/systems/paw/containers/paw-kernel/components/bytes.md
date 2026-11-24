---
type: C4 Component
title: Bytes
status: stable
groma:
  id: bytes
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/bytes.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.base64_decode, paw.api.base64_encode | teal |
| [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
