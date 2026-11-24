---
type: C4 Container
title: paw-sampler (sample player plugin)
status: stable
groma:
  id: sampler-plugin
  parent: paw
  technology: Rust, CLAP (cdylib)
description: 'The sample player: a CLAP plugin (`dev.paw.sampler`) that plays SFZ and Decent Sampler instruments, plus a command-line tool.'
---

Native part of the `sampler` extension, built by Nix from `extensions/sampler/native`. paw loads it like any CLAP plugin, in a helper process. Each note can choose its articulation through its MIDI 2.0 attribute (M2-123 orchestral articulation profile). The `paw-sampler` binary describes, renders and benchmarks instruments from the command line.
