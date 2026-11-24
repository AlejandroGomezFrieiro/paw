---
type: C4 Component
title: Lua devices
status: stable
groma:
  id: lua-devices
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-luadev/src/lib.rs
    - scanner: rust
      file: crates/paw-luadev/src/device.rs
  group: Plugin hosting
  technology: Rust, LuaJIT
description: Runs devices written in Lua (`lua:<name>`, JSFX-like) in a LuaJIT state of their own inside a helper process.
---

A script has parameters and a `process` function made with `paw.dsp`. LuaJIT allocates, so it never runs on the engine's audio thread; also finds the folders the scripts live in.
