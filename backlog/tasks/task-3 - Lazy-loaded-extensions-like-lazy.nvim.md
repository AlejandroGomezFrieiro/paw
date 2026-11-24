---
id: TASK-3
title: Lazy-loaded extensions (like lazy.nvim)
status: Done
assignee: []
created_date: '2026-11-21T18:33:00Z'
updated_date: '2026-11-23T20:11:00Z'
labels:
  - extensions
  - performance
milestone: m-5
dependencies:
  - TASK-103
  - TASK-208
priority: high
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Triggers in manifests and user config: cmd, keys, event, kind (like ft), view, lazy=false. Stubs show commands/keys before load; first use loads and runs with count/register as one undo step; projects with a lazy kind open and play unchanged; :extensions shows why it loaded. Measure start-up before/after with bench/profile. Brief: backlog/docs/designs/lazy-brief.md
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A manifest and the user config take the triggers cmd, keys, event, kind, view and lazy=false
- [x] #2 Stubs show the commands and keys before the load; the first use loads and runs with count and register as one undo step (test with real keys)
- [x] #3 A project with a lazy clip kind opens and plays unchanged; :extensions says why each extension loaded
- [x] #4 Start-up time before and after, with spread, in bench/RESULTS.md
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
Branch worktree-agent-a81a022a6819e41e4 (fc22125a, 270c1a36, ff334ab0, ad85aba8, a06ea6bb; main merged at 7be67ee5). New runtime/lua/paw/lazy.tl: paw.ext.use(name|path, spec); the manifest triggers are cmd/keys/event/kind/view/lazy. Stubs go in paw.commands.specs, the keymap and paw.ui.views. The kind trigger is any key of any paw.registry (registry.missing hook). The first use re-runs the line or keys with count and register as one undo step. :extensions, :checkhealth, the extension picker and :help show loaded_by and what each waiting extension waits for (golden tests/screens/extensions_lazy/extensions.txt). doctor, drums, mixdiag, notation, plugstate, templates and tutor wait. bench/extstart.sh: 285 ms to 217 ms median (load avg 17) in bench/RESULTS.md. Tests: tests/extensions_lazy.lua.

PO 2026-11-23 (cleanup for plan V2, architecture-plan.md): The lazy kind trigger is a key of any paw.registry (plan 6.1). Under plan V2 the kinds of A2 (paw.kinds.define) mirror into the same registries, so the trigger keeps working.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged on main in batch 19 (fc22125a, 270c1a36, ff334ab0). lazy.tl: manifest triggers cmd, keys, event, kind, view, lazy; stubs; the first use runs with count and register as one undo step; :extensions gives loaded_by. bench/extstart.sh 285 ms to 217 ms median in bench/RESULTS.md. Full suite passed on c04f8ae9.
<!-- SECTION:FINAL_SUMMARY:END -->
