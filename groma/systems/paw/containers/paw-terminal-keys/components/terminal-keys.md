---
type: C4 Component
title: Terminal keys
status: stable
groma:
  id: terminal-keys
  parent: paw-terminal-keys
  code:
    - scanner: rust
      file: fuzz/fuzz_targets/terminal_keys.rs
      symbol: step
---
