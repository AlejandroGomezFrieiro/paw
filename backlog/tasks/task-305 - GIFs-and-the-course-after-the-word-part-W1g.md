---
id: TASK-305
title: GIFs and the course after the word part (W1g)
status: To Do
assignee: []
created_date: '2026-11-23T16:01:00Z'
updated_date: '2026-11-24T14:21:00Z'
labels:
  - agent:worker
  - docs
  - gifs
  - bundle
milestone: m-17
dependencies:
  - TASK-304
references:
  - architecture/decisions/0030-the-user-word-part.md
priority: medium
ordinal: 368000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle W1g of the architecture plan, version 2 (backlog/docs/designs/architecture-plan.md V2.7 step 1). W1 renames track to part in the code and the docs. This bundle makes the pictures and the generated course agree.

Use the skill paw-gifs for each GIF. The course in docs/tutorials/course comes from the tutor's lessons: do not edit it by hand.

Size: S.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each GIF in docs/images whose scene or text shows track for the container is made again with the paw-gifs skill
- [ ] #2 The tutor's lessons say part; the course is made again from them; the tutor test passes
- [ ] #3 git grep of docs/, the lessons and the GIF scripts, with the allow-list of W1, finds no track for the container
- [ ] #4 Vale reports 0 alerts
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
From W1: stale GIFs and scripts: docs/images/make cast-basics, gui-mix, rig, stills, tui-arrange, tui-config, tui-ex, tui-narrow, tui-textbuf, tui-tour; extensions articulations, drums, notation tui-score, projdiff, sampler, sections, templates, utau (scene.lua, tui-utau). Plus every GIF or cast that shows the arrange view.
<!-- SECTION:NOTES:END -->
