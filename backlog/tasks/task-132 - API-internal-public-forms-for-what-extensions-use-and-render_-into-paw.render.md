---
id: TASK-132
title: >-
  API: @internal, public forms for what extensions use, and render_* into
  paw.render
status: To Do
assignee: []
created_date: '2026-11-22T19:00:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:worker
milestone: m-10
dependencies: []
priority: medium
ordinal: 144000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add the doc tag `@internal`, honored by `tools/apidoc.lua`. Tag the internal modules. Give public forms to the command-line history and to the key grabber and message sink (a stack with an owner). Fold the top-level `render_*` names into `paw.render`. Write down whether `paw.api` is public for extensions.

Read first: backlog/docs/designs/architecture-review-lua.md, the finding L8 and its proposal P10.

Overlaps: TASK-105, TASK-103.
Dependencies: none; before TASK-105.

Owner decisions (2026-11-22): the review's recommendations are accepted. notation and utau are not ported to Teal: they move to Rust as native extensions later (a separate ticket).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 api.md lists no internal module
- [ ] #2 no bundled extension requires a module that is internal
- [ ] #3 an unload gives back a grabber or a sink that the extension took
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
Board review 2026-11-23: still open (apidoc.lua has no @internal; init.lua still sets paw.render_* aliases at lines 370-371). TASK-105 (m-6) waits for it. Size: M.

From TASK-209: also make a public palette for paw.theme (used by articulations roll.lua:13, sections ui.lua:376, utau editor.lua:18 and strips.lua:18) and a public form for the paw.state.last_cmdline write (articulations commands.lua:510, notation popover.lua:146; read by defaults/keys.lua:95 for @:). Internal modules used by extensions: paw.mouse_menus (launcher), paw.views.curve, paw.views.cmdline, paw.lsp.rpc (midilsp).

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): Do not fold render_* into paw.render: architecture-plan.md V2.9 reserves paw.render(what, opts) for render with provenance (bundle RD, ADR 0025). Choose another name for the old render_* helpers. This ticket is part of LOCK (with TASK-105, 206, 220, 221).
<!-- SECTION:NOTES:END -->
