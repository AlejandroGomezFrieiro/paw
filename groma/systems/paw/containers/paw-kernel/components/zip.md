---
type: C4 Component
title: Zip
status: stable
groma:
  id: zip
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/zip.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/zip.tl](../../../../../../runtime/lua/paw/zip.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.crc32, paw.api.inflate | teal |
| [runtime/lua/paw/zip.tl](../../../../../../runtime/lua/paw/zip.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
| [runtime/lua/paw/zip.tl](../../../../../../runtime/lua/paw/zip.tl) | [runtime/lua/paw/bytes.tl](../../../../../../runtime/lua/paw/bytes.tl) | Invokes supplied callback: require("paw.bytes") | teal |
