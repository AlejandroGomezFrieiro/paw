---
id: TASK-284
title: >-
  Devices graph: racks and templates (save, load, picker with preview, keys to
  fill, copy or linked, bundled metal templates) (G5, G12)
status: To Do
assignee: []
created_date: '2026-11-23T11:58:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-16
dependencies:
  - TASK-281
  - TASK-282
  - TASK-298
  - TASK-312
references:
  - architecture/decisions/0021-one-template-store.md
  - architecture/decisions/0031-templates-shape-content-linked.md
  - backlog/docs/designs/architecture-plan.md
documentation:
  - backlog/docs/designs/devices-graph.md
priority: medium
ordinal: 346000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The same chain goes on many tracks (four DI guitars, a vocal double), and a new user needs good starting chains. Templates are chain files (racks/*.chain) in three places: bundled, user and project. Design section 9.5. The bundled templates come from the skill mixing-mastering, references/metal.md, and use built-in devices only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 :rack.save and :rack.load through the store (templates/rack/<name>.chain); the project layer wins a name clash, then the user, an extension, the bundle
- [ ] #2 The picker of a lists devices, presets and templates, with a preview of the outline, macros, keys to fill, latency and CPU
- [ ] #3 On load, a template fills its keys from the part names, shows the guesses, and an empty key is a diagnostic
- [ ] #4 A load is a copy; Ctrl-l or :rack.link makes a linked rack; :rack.update, :rack.reset, :rack.unlink, :chain.copy and :chain.link work, each one undo step
- [ ] #5 Part templates keep the part graph and the inserts of each strip
- [ ] #6 Bundled templates Parallel crush, Metal guitar bus, Drum bus smash, Scream vocal and Bass split, each with a checks block that passes
<!-- AC:END -->

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
PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): G5. A rack is a template of kind rack in templates/rack/ (ADR 0021, 0031). Unblocked by: B8 (TASK-298) and MX.
<!-- SECTION:NOTES:END -->
