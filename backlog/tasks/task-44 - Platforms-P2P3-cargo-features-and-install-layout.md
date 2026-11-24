---
id: TASK-44
title: 'Platforms P2+P3: cargo features and install layout'
status: To Do
assignee: []
created_date: '2026-11-21T19:52:00Z'
updated_date: '2026-11-23T16:16:00Z'
labels:
  - platforms
milestone: m-1
dependencies: []
priority: medium
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
P2: pipewire and lv2 as cargo features, Linux-only deps under target cfg, guard paw-gui's prctl (client.rs:261). P3: find share/paw relative to the binary (one root-finding function) so bundled extensions load without the Nix wrapper. Size S each. Design: backlog/docs/designs/platforms.md.
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Architecture review 2026-11-22 (backlog/docs/designs/architecture-review.md): TASK-99 adds the paw-core feature 'native' (rpc, tls, io, bake::helper, encode, files_watch), which belongs with these cargo features. TASK-98 adds [workspace.lints] and rust-version to the same manifests.
<!-- SECTION:NOTES:END -->
