---
id: TASK-347
title: 'Flavours of paw: self-contained configs plus extensions'
status: To Do
assignee: []
created_date: '2026-11-24T07:54:00Z'
updated_date: '2026-11-24T11:10:00Z'
labels:
  - idea
  - ux
dependencies: []
priority: low
ordinal: 416000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner idea (2026-11-24). The repo gives 'flavours' of paw: each is a self-contained config plus a set of extensions that gives one behaviour, for example a music DAW with the good standards of other DAWs (keys, views, defaults). A flavour can also be only an example. A user starts paw with one flavour, or copies it as the start of a config. Open points: where they live (examples/ or flavours/), how to start one (an option such as --flavour, or an XDG config folder), how a flavour composes with the user config, tests that each flavour opens and plays, and docs (how-to per flavour). Not high priority: design only when the core work of the current milestones ends.
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
From modalkit (2026-11-24): a flavour can carry a whole key environment, as modalkit's env::vim, env::emacs, env::kak and env::mixed presets do. A 'kak' flavour (select first, then act) may suit music editing: select notes, see them, then transpose. Flavours are binding sets over paw.keymap, swappable at runtime, not a second engine.
<!-- SECTION:NOTES:END -->
