---
id: TASK-112
title: Bring your own devices in the browser (design)
status: To Do
assignee: []
created_date: '2026-11-22T11:00:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - web
  - plugins
  - design
milestone: m-0
dependencies: []
priority: low
ordinal: 115000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-22: let browser users use custom devices, maybe ones they already own. Design and compare: (1) hardware they own: Web MIDI controllers and synths, audio input (getUserMedia); (2) plugins they own (VST3/CLAP/AU are native and cannot load in a page): a companion native helper on their machine (paw's plugin helper as a small local app) that the page reaches over localhost (WebSocket/WebTransport), with latency, jitter and security (pairing, origin checks) measured in a spike; (3) web-native devices: WebAssembly devices (TASK-1) and WebCLAP (prior art: openDAW), Lua devices; (4) licences and copy protection of commercial plugins. Recommend an order; owner approves before building.
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
