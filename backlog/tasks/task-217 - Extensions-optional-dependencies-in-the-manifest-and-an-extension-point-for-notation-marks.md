---
id: TASK-217
title: >-
  Extensions: optional dependencies in the manifest, and an extension point for
  notation marks
status: Done
assignee: []
created_date: '2026-11-23T06:42:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - extensions
  - manifest
milestone: m-5
dependencies: []
priority: medium
ordinal: 245000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-209: no manifest declares a dependency on another extension, but articulations requires notation.marks (notation.lua:8, with a defer and event loop in init.lua:18), tutor requires sections (lessons/extensions.lua:71), interop pcall-requires sections (init.tl:168), musicops adds keys to the utau view (keys.lua:17, 399, 620). Add requires/optional fields to the manifest that ext.lua checks and orders by, and a public extension point in notation for marks so articulations does not reach into its modules.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A manifest can name the extensions that it requires and the extensions that it can use; ext.lua loads them first, and gives a clear message when a required one is missing
- [x] #2 The manifests of articulations, tutor, interop and musicops name their dependencies, and articulations no longer polls package.loaded for notation.marks
- [x] #3 notation has a public extension point for marks, and articulations uses it; a test loads articulations without notation and it works with no marks
- [x] #4 docs/reference/extensions.md (the manifest fields) and the paw-extension skill say it; Vale reports 0 alerts
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a81a022a6819e41e4 (eff0f276). Manifests take optional = {name = version}: in the same batch the optional one loads first. A missing optional is no error, and a wrong version warns. A missing required one says where to put it. articulations (notation), interop (sections), musicops (utau) and tutor (musicops, sections, undotree) name theirs. The marks extension point is the core registry paw.query.marks plus the event notation.marked. Articulations no longer polls package.loaded. Tests: extensions_api optional order, and articulations without notation. Docs: reference/extensions.md, how-to/load-an-extension.md, the paw-extension skill. Vale 0.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main (eff0f276). Manifests take requires and optional; ext.lua orders and gives a clear message for a missing required one; articulations, interop, musicops and tutor name theirs; paw.query.marks and the event notation.marked are the marks extension point; tests for the order and for articulations without notation; docs and the extension skill changed.
<!-- SECTION:FINAL_SUMMARY:END -->
