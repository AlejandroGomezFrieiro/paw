---
id: TASK-89
title: 'Vale: check .claude skills (internal, STE)'
status: To Do
assignee: []
created_date: '2026-11-22T09:40:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:worker
milestone: m-9
dependencies: []
priority: low
ordinal: 89000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
tools/vale.sh and the Vale hook skip .claude/**, so the skills (internal text, STE) are not checked; the diataxis-docs SKILL.md already has STE alerts (-ing forms, a dash). Add .claude/skills/**.md (not vendored third-party skills like plain-writing/SKILL.md, which stay as upstream) to the checked set and fix the alerts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 tools/vale.sh with no arguments checks .claude/skills/**/*.md except vendored skills
- [ ] #2 The Vale hook checks them too; Vale reports 0 alerts on them
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
2026-11-22: the YAML front matter of the teal and paw-extension skills is fixed on main (quoted descriptions). Vale can read them now and reports 52 STE errors in their text (internal style); fix them when .claude/ joins the default Vale run.

Board review 2026-11-23: half done. .vale.ini has the internal section for .claude/**/*.md (line 146), but tools/vale.sh with no arguments still leaves out .claude/skills, and the hook too. Both criteria are open.
<!-- SECTION:NOTES:END -->
