---
id: TASK-52
title: 'Windows plugin bridge: native Windows plugins from paw in WSL, without wine'
status: To Do
assignee: []
created_date: '2026-11-21T20:47:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - platforms
  - windows
  - plugins
milestone: m-1
dependencies: []
priority: low
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
paw runs in WSL2 (Linux), Windows VST3/CLAP plugins are Windows .dll files. Design and build a bridge: a small native Windows helper (.exe, built for x86_64-pc-windows-msvc/gnu) that WSL starts through interop, loads the plugin, and talks to paw's existing plugin-helper protocol across the WSL2 VM boundary (no memfd/futex shared memory across it: localhost TCP, AF_VSOCK/hvsocket, or a shared file mapping; measure latency and jitter per block). Decide where audio runs: in WSL (WSLg PulseAudio, high latency) or with the Windows helper owning WASAPI output and the engine feeding it. Plugin editor windows: native Win32 windows from the helper. Scan Windows plugin folders (C:\Program Files\Common Files\VST3, CLAP) from WSL via /mnt/c. Prior art: yabridge (wine, which the owner rules out), audiogridder-style network hosting. Output: a design in backlog/docs/designs/, a spike with numbers, then the build.
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Each acceptance criterion is met, and the notes give its evidence
- [ ] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [ ] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [ ] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [ ] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [ ] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [ ] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [ ] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->
