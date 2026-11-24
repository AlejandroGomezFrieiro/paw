---
type: C4 Component
title: Command line
status: stable
groma:
  id: command-line
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-tui/src/args.rs
    - scanner: rust
      file: crates/paw-tui/src/main.rs
    - scanner: teal
      file: crates/paw-tui/src/main.rs
  group: Terminal frontend
  technology: Rust, clap
description: 'Entry point of the `paw` binary: chooses between kernel with terminal, headless kernel, helper and client modes.'
---

Parses the command line (clap) and starts the right thing: the kernel with the terminal UI, a headless kernel with a control socket, a script run, `paw ctl` and `attach` against a running instance, or the plugin-host and plugin-scan helper modes. It registers the plugin formats and the Lua-device helper with the kernel.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-tui/src/main.rs](../../../../../../crates/paw-tui/src/main.rs) | [crates/paw-core/src/kernel.rs](../../../../../../crates/paw-core/src/kernel.rs) | Starts the kernel | Rust call |
| [crates/paw-tui/src/main.rs](../../../../../../crates/paw-tui/src/main.rs) | [crates/paw-plugins/src/sandbox/serve.rs](../../../../../../crates/paw-plugins/src/sandbox/serve.rs) | Runs as plugin host | Helper mode of the same binary |
| [crates/paw-tui/src/main.rs](../../../../../../crates/paw-tui/src/main.rs) | [crates/paw-plugins/src/lib.rs](../../../../../../crates/paw-plugins/src/lib.rs) | Registers plugin formats | Rust call |
| [crates/paw-tui/src/main.rs](../../../../../../crates/paw-tui/src/main.rs) | [crates/paw-proto/src/lib.rs](../../../../../../crates/paw-proto/src/lib.rs) | Calls running instances | Rust call |
| [crates/paw-tui/src/main.rs](../../../../../../crates/paw-tui/src/main.rs) | [crates/paw-luadev/src/lib.rs](../../../../../../crates/paw-luadev/src/lib.rs) | Serves Lua devices | Helper mode of the same binary |
