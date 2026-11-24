---
type: C4 Component
title: Plot
status: stable
groma:
  id: plot
  parent: paw-kernel
  code:
    - scanner: teal
      file: runtime/lua/paw/plot.tl
---

## Derived relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [runtime/lua/paw/plot.tl](../../../../../../runtime/lua/paw/plot.tl) | [runtime/lua/paw/draw.tl](../../../../../../runtime/lua/paw/draw.tl) | Invokes supplied callbacks: paw.draw.bar_lines, paw.draw.curve, paw.draw.mix, paw.draw.waveform | teal |
| [runtime/lua/paw/plot.tl](../../../../../../runtime/lua/paw/plot.tl) | [runtime/lua/paw/theme.tl](../../../../../../runtime/lua/paw/theme.tl) | Invokes supplied callbacks: paw.theme.palette, require("paw.theme") | teal |
