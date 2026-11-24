---
type: C4 Component
title: Device pictures
status: stable
groma:
  id: device-pictures
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/views/device_pictures.lua
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/views/device_pictures.lua](../../../../../../runtime/lua/paw/views/device_pictures.lua) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.curve, paw.draw.g | teal |
| [runtime/lua/paw/views/device_pictures.lua](../../../../../../runtime/lua/paw/views/device_pictures.lua) | [runtime/lua/paw/params.lua](../../../../../../runtime/lua/paw/params.lua) | Invokes supplied callback: paw.params.read | teal |
| [runtime/lua/paw/views/device_pictures.lua](../../../../../../runtime/lua/paw/views/device_pictures.lua) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.clamp | teal |
