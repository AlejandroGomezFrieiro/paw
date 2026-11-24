---
id: TASK-37
title: 'Platforms 0: audit what ties paw to Nix and Linux'
status: Done
assignee: []
created_date: '2026-11-21T19:33:00Z'
updated_date: '2026-11-23T06:20:00Z'
labels:
  - platforms
milestone: m-1
dependencies: []
priority: medium
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
List every dependency on Nix (flake-only build steps, the dev shell's tools, plugin paths, the utau engine and sampler packaging, tests) and on Linux (ALSA sequencer, rustix/poll, fork for plugin helpers, X11/Wayland, XDG paths, /proc, signals, Unix sockets for paw ctl/attach). Output: a design doc backlog/docs/designs/platforms.md with a per-platform plan and the order.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit done (2026-11-21): backlog/docs/designs/platforms.md. Plain cargo build works outside Nix with: C compiler+make (LuaJIT vendored), pkg-config, ALSA + PipeWire headers, libclang (bindgen for cpal's pipewire feature), lilv; tested on a scratch target, binary runs --audio null. Nix-only today: install layout (PAW_HOME wrapper; bundled extensions found only from the source tree), native extension parts (sampler, utau .NET, ara), test plugins/tools, all install docs; no CI besides nix flake check. Deep Linux ties: plugin sandbox (memfd+futex+fd passing+PDEATHSIG, also carries Lua devices), ALSA seq MIDI (UMP), X11 plugin editor windows, Unix sockets as the only local IPC; the rest has standard crates (notify, interprocess, sysinfo, directories, rfd, fontdb, crossterm). Plan: 20 ordered parts P1-P20 (seams first, then Linux archive+CI, macOS, Windows), risks, 10 owner questions with recommended answers. Proposed new tickets (not created): P1 seams, P7 Lua portability, P10 MIDI trait, P11 plugin windows/bundles, P13 Windows IPC.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Audit done: backlog/docs/designs/platforms.md. Plain cargo build works with build-essential pkg-config libasound2-dev libpipewire-0.3-dev libclang-dev liblilv-dev; parts P1-P20 ordered; 10 owner questions with recommendations.
<!-- SECTION:FINAL_SUMMARY:END -->
