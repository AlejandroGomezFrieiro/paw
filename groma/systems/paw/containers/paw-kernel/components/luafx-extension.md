---
type: C4 Component
title: Lua devices extension
status: stable
groma:
  id: luafx-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/luafx/devices/chords.lua
      symbol: process
    - scanner: teal
      file: extensions/luafx/devices/drive.lua
    - scanner: teal
      file: extensions/luafx/devices/gain_pan.lua
    - scanner: teal
      file: extensions/luafx/devices/sine.lua
      symbol: process
    - scanner: teal
      file: extensions/luafx/manifest.lua
      symbol: luafx
  group: Bundled extensions
  technology: Lua
description: Supplies devices written in Lua.
---

Has no init file. The loader adds its devices/ folder to paw.luadev, and the device picker then shows the devices beside the built-in devices. The devices are also examples to start new devices from.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/luafx/devices/chords.lua](../../../../../../extensions/luafx/devices/chords.lua) | [runtime/lua/paw/dsp.lua](../../../../../../runtime/lua/paw/dsp.lua) | Invokes supplied callbacks: paw.dsp.NOTE_OFF, paw.dsp.NOTE_ON, paw.dsp.device, require("paw.dsp") | teal |
| [extensions/luafx/devices/drive.lua](../../../../../../extensions/luafx/devices/drive.lua) | [runtime/lua/paw/dsp.lua](../../../../../../runtime/lua/paw/dsp.lua) | Invokes supplied callbacks: paw.dsp.biquad, paw.dsp.device, paw.dsp.gain, paw.dsp.saturate, require("paw.dsp") | teal |
| [extensions/luafx/devices/gain_pan.lua](../../../../../../extensions/luafx/devices/gain_pan.lua) | [runtime/lua/paw/dsp.lua](../../../../../../runtime/lua/paw/dsp.lua) | Invokes supplied callbacks: paw.dsp.device, paw.dsp.gain, paw.dsp.smoother, require("paw.dsp") | teal |
| [extensions/luafx/devices/sine.lua](../../../../../../extensions/luafx/devices/sine.lua) | [runtime/lua/paw/dsp.lua](../../../../../../runtime/lua/paw/dsp.lua) | Invokes supplied callbacks: paw.dsp.ALL_NOTES_OFF, paw.dsp.NOTE_OFF, paw.dsp.NOTE_ON, paw.dsp.device, paw.dsp.gain, paw.dsp.mtof, require("paw.dsp") | teal |
| [extensions/luafx/manifest.lua](../../../../../../extensions/luafx/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
