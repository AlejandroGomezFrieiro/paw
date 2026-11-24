---
type: C4 Component
title: Plugin host server
status: stable
groma:
  id: plugin-host-server
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-plugins/src/sandbox/serve.rs
  group: Plugin hosting
  technology: Rust
description: 'The helper process''s side: hosts one plugin or Lua device and serves blocks and control requests.'
---

Runs when the `paw` binary is started again as a plugin host. Loads the plugin through its format host and processes each block the kernel hands it through shared memory.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-plugins/src/sandbox/serve.rs](../../../../../../crates/paw-plugins/src/sandbox/serve.rs) | [crates/paw-plugins/src/clap.rs](../../../../../../crates/paw-plugins/src/clap.rs) | Hosts CLAP plugins | Rust call |
| [crates/paw-plugins/src/sandbox/serve.rs](../../../../../../crates/paw-plugins/src/sandbox/serve.rs) | [crates/paw-plugins/src/vst3.rs](../../../../../../crates/paw-plugins/src/vst3.rs) | Hosts VST3 plugins | Rust call |
| [crates/paw-plugins/src/sandbox/serve.rs](../../../../../../crates/paw-plugins/src/sandbox/serve.rs) | [crates/paw-plugins/src/lv2/mod.rs](../../../../../../crates/paw-plugins/src/lv2/mod.rs) | Hosts LV2 plugins | Rust call |
