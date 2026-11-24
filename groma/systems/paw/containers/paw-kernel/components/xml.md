---
type: C4 Component
title: Xml
status: stable
groma:
  id: xml
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/xml.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/xml.tl](../../../../../../runtime/lua/paw/xml.tl) | [crates/paw-core/src/api/formats.rs](../../../../../../crates/paw-core/src/api/formats.rs) | Invokes supplied callbacks: paw.api.xml_decode, paw.api.xml_encode | teal |
| [runtime/lua/paw/xml.tl](../../../../../../runtime/lua/paw/xml.tl) | [crates/paw-core/src/api/mod.rs](../../../../../../crates/paw-core/src/api/mod.rs) | Invokes supplied callback: require("paw.api") | teal |
