---
id: TASK-396
title: The skill paw-extension has 25 Vale errors
status: To Do
assignee: []
created_date: '2026-11-24T20:50:00Z'
labels:
  - docs
  - skills
  - agent:worker
dependencies: []
priority: low
ordinal: 465000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
tools/vale.sh .claude/skills/paw-extension/SKILL.md reports 25 errors (14 on main before the A2 merge): dashes, file paths, -ing words, phrasal verbs, spelling. The merge check only runs Vale on files that a branch changes, so the errors stay until a branch touches the file. The owner edits .claude/skills (agents cannot write it): an agent writes the corrected text as a patch, and the owner applies it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 tools/vale.sh .claude/skills/paw-extension/SKILL.md reports 0 errors
- [ ] #2 tools/vale.sh over all of .claude/skills reports 0 errors, or each file left has a ticket
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
