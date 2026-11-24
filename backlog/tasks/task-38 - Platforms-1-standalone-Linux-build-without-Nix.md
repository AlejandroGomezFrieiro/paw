---
id: TASK-38
title: 'Platforms 1: standalone Linux build without Nix'
status: To Do
assignee: []
created_date: '2026-11-21T19:33:00Z'
updated_date: '2026-11-23T16:15:00Z'
labels:
  - platforms
  - linux
  - packaging
milestone: m-1
dependencies:
  - TASK-44
priority: medium
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
cargo build --release works on a stock distro with documented system packages (ALSA, LuaJIT or vendored, fonts); the Lua runtime is embedded as today. Release archives (tar.gz with the binary, runtime, bundled extensions), install docs, and a CI job on a plain Ubuntu image. Then AppImage and/or Flatpak, and an AUR/deb recipe if cheap.
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
