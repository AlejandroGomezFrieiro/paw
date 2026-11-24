---
id: TASK-298
title: >-
  Templates in the core: one Template trait for every kind of object, and the
  templates extension moves into paw
status: To Do
assignee: []
created_date: '2026-11-23T13:39:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-10
dependencies:
  - TASK-279
  - TASK-310
  - TASK-311
references:
  - architecture/decisions/0020-template-contract-as-teal-record.md
  - architecture/decisions/0021-one-template-store.md
  - architecture/decisions/0031-templates-shape-content-linked.md
  - backlog/docs/designs/architecture-plan.md
documentation:
  - backlog/docs/designs/devices-graph.md
priority: high
ordinal: 360000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-23: as part of the devices graph, make a generic template trait in the core and move the templates extension into paw, so that other objects can use it. Today extensions/templates saves a track, a group or a device chain under a name (\Ts, \Tl). The export presets of TASK-222.5 also layer project, init.lua and built-in sources: the same idea. Design first in the ticket notes (short): the Rust trait (kind, capture to data, make from data at a place as one undo step, a version for its format) and its Lua face (paw.template.register for extensions); one store with sources bundled, user (XDG data) and project, the project winning a name clash, then the user; copy or linked instances with overrides (linked racks of the graph use it); keys to fill on load (the design's track-name guesses); a picker with a preview; the kinds at the start: track, group, device chain, rack (with TASK-279), export preset (move 222.5's presets onto it), and an extension's own kind. The chain language's .chain files (TASK-281) are the format of chain and rack templates.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A Teal contract TemplateKind in contracts.tl and paw.templates.define; template kinds are entries of Kinds<TemplateFamily, TemplateMeta> in Rust (no Rust trait until two Rust kinds exist); a test registers a kind from Lua
- [ ] #2 The kinds project, part, lane, rack, stack and export; a template keeps the shape by default and the content with a flag (ADR 0031); :template lists the templates with their layer (the store of B3: templates/<kind>/ in the project, the user data folder, an extension and the runtime)
- [ ] #3 Part templates (the old track and group templates) and rack templates (the old device chain templates) work, with the keys of extensions/templates moved to core keys that keep the key rule; the extension is removed, and its docs, README, tutor and GIF change in the same commit
- [ ] #4 Export presets are templates of kind export (no second layering code)
- [ ] #5 Insert copies by default; insert linked keeps a link with overrides for each instance; a linked definition is copied into the project; :template.update and unlink; one undo step each
- [ ] #6 Rack templates and linked racks of the devices graph use it; TASK-284 builds on it
- [ ] #7 A project that uses a template opens and plays without the template present
- [ ] #8 An extension defines a kind with its own format: capture and make functions, its own file form, a version and a migrate function; the store keeps the files as the kind writes them and never parses them
- [ ] #9 An extension can generate templates for a context; they show in the store and the picker with their source, and can be saved as user templates
- [ ] #10 A template of a kind whose extension is not loaded is listed with that extension's name and is not made; loading the extension makes it usable; it is never deleted or rewritten
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
Owner 2026-11-23: extensions must be able to define their own template serialization and deserialization, so that they can generate custom templates.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): B8. Not as a Rust trait: the contract is a Teal record with a Rust list of kinds (ADR 0020). The kinds are project, part, lane, rack, stack and export (ADR 0031); track, group and device chain templates become part and rack templates. The store is bundle B3. Unblocked by: B3 and B4.

PO 2026-11-23 (plan V2 bundles): Bundle B8 (architecture-plan.md V2.15). The criteria follow ADR 0020 and 0031; the store is B3 (TASK-310), the linked definitions use Defs of B4 (TASK-311).
<!-- SECTION:NOTES:END -->
