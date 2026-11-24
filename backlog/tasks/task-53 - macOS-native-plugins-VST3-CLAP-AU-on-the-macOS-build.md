---
id: TASK-53
title: macOS native plugins (VST3, CLAP, AU) on the macOS build
status: To Do
assignee: []
created_date: '2026-11-21T20:47:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - platforms
  - macos
  - plugins
milestone: m-1
dependencies:
  - TASK-47
priority: low
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On macOS paw runs natively, so macOS plugins load in paw's own helper processes: bundle layouts (.vst3, .clap, .component), entry points, Cocoa editor windows, code-signing and library-validation rules for loading third-party plugins (hardened runtime entitlement). Audio Units: decide (owner-question in TASK-49 recommended not in m-1). Builds on TASK-47 (plugin bundle loaders and editor windows).
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
