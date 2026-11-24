---
type: C4 Component
title: Ruler example extension
status: stable
groma:
  id: rulerplus-extension
  parent: paw-kernel
  code:
    - scanner: teal
      file: extensions/rulerplus/init.tl
    - scanner: teal
      file: extensions/rulerplus/manifest.lua
      symbol: rulerplus
  group: Bundled extensions
  technology: Teal
description: Shows how to change the bar labels of the ruler.
---

An example for configuration authors. Through paw.ruler.add, it adds phrase marks, the key, the chords and signed relative bars to the bar labels of the ruler.

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [extensions/rulerplus/init.tl](../../../../../../extensions/rulerplus/init.tl) | [crates/paw-core/src/api/screen.rs](../../../../../../crates/paw-core/src/api/screen.rs) | Invokes supplied callback: paw.api.str_width | teal |
| [extensions/rulerplus/init.tl](../../../../../../extensions/rulerplus/init.tl) | [runtime/lua/paw/commands.tl](../../../../../../runtime/lua/paw/commands.tl) | Invokes supplied callback: paw.commands | teal |
| [extensions/rulerplus/init.tl](../../../../../../extensions/rulerplus/init.tl) | [runtime/lua/paw/contracts.tl](../../../../../../runtime/lua/paw/contracts.tl) | Invokes supplied callbacks: paw.contracts.ColumnCells, paw.contracts.Piece | teal |
| [extensions/rulerplus/init.tl](../../../../../../extensions/rulerplus/init.tl) | [runtime/lua/paw/cursor.tl](../../../../../../runtime/lua/paw/cursor.tl) | Invokes supplied callback: paw.cursor.beat | teal |
| [extensions/rulerplus/init.tl](../../../../../../extensions/rulerplus/init.tl) | [runtime/lua/paw/harmony.tl](../../../../../../runtime/lua/paw/harmony.tl) | Invokes supplied callbacks: paw.harmony.at, paw.harmony.key, paw.harmony.label, paw.harmony.pc_name | teal |
| [extensions/rulerplus/init.tl](../../../../../../extensions/rulerplus/init.tl) | [runtime/lua/paw/keymap.tl](../../../../../../runtime/lua/paw/keymap.tl) | Invokes supplied callback: paw.keymap.set | teal |
| [extensions/rulerplus/init.tl](../../../../../../extensions/rulerplus/init.tl) | [runtime/lua/paw/objects.tl](../../../../../../runtime/lua/paw/objects.tl) | Invokes supplied callback: paw.objects.time | teal |
| [extensions/rulerplus/init.tl](../../../../../../extensions/rulerplus/init.tl) | [runtime/lua/paw/options.tl](../../../../../../runtime/lua/paw/options.tl) | Invokes supplied callbacks: paw.options.define, paw.options.opt | teal |
| [extensions/rulerplus/init.tl](../../../../../../extensions/rulerplus/init.tl) | [runtime/lua/paw/ruler.tl](../../../../../../runtime/lua/paw/ruler.tl) | Invokes supplied callbacks: paw.ruler.add, paw.ruler.labels, paw.ruler.set | teal |
| [extensions/rulerplus/init.tl](../../../../../../extensions/rulerplus/init.tl) | [runtime/lua/paw/ui.tl](../../../../../../runtime/lua/paw/ui.tl) | Invokes supplied callback: paw.ui.notify | teal |
| [extensions/rulerplus/init.tl](../../../../../../extensions/rulerplus/init.tl) | [runtime/lua/paw/util.tl](../../../../../../runtime/lua/paw/util.tl) | Invokes supplied callback: paw.util.fit | teal |
| [extensions/rulerplus/manifest.lua](../../../../../../extensions/rulerplus/manifest.lua) | [runtime/lua/paw/init.lua](../../../../../../runtime/lua/paw/init.lua) | Invokes supplied callback: requires paw ^1.0 | teal |
