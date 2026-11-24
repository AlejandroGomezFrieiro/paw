---
id: TASK-365
title: 'rust-skills: compare with the community Rust Design Patterns book'
status: Done
assignee: []
created_date: '2026-11-24T13:35:00Z'
updated_date: '2026-11-24T14:33:00Z'
labels:
  - tooling
  - skills
  - agent:worker
milestone: m-7
dependencies: []
priority: low
ordinal: 434000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-24: improve our Rust skills with https://rust-unofficial.github.io/patterns/ (idioms, design patterns, anti-patterns, functional usage). Do NOT start before the next push of main to origin (owner).
Steps: 1. Read the book; for each idiom, pattern and anti-pattern, find whether .claude/skills/rust-skills (rules/*.md, paw-crates.md) or CODING_STANDARDS.md already covers it. 2. Add a rule only for what paw lacks and would use (audio-thread rules win over a book pattern that allocates or locks); cite the book page; MPL-2.0 text is not copied, rules are written in our words. 3. Where a pattern is mechanical, propose a clippy lint or an ast-grep rule (tools/ast-grep/rules) instead of a prose rule. 4. Report a table: book item, covered or added or skipped, why. .claude/skills edits need the owner's fast-forward of main.
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
Orchestrator 2026-11-24: merged in 06af8a85 (merge tree, on 5a80ef26); review MERGE; checks in the merge tree: clippy -D warnings clean, rustlint clean, nextest 727 passed, apidoc, hygiene, tl check, lints, mcpscore 163, render gate 7 bit-identical; Lua part arrange passed; mixdiag fails as on main (TASK-371). Done after the owner's fast-forward (touches .claude/skills).
<!-- SECTION:NOTES:END -->
