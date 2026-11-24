---
id: TASK-251
title: Check paw with a screen reader, and list what to change
status: To Do
assignee: []
created_date: '2026-11-23T07:16:00Z'
updated_date: '2026-11-23T16:18:00Z'
labels:
  - parity
  - size-S
  - docs
  - ux
milestone: m-14
dependencies: []
documentation:
  - backlog/docs/designs/daw-feature-comparison.md
priority: low
ordinal: 315000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**User need.** A blind or low-vision musician uses paw with a screen reader. A terminal program can be a good fit for screen readers (Orca with a terminal, or a braille display), but only if what it draws reads well.

**Other DAWs.** REAPER with OSARA is the reference for accessible DAWs. The design doc says "Screen reader: unknown" and proposes a check (section 4.1, other gaps).

**paw now (checked 2026-11-23).** No page says what works. docs/reference/lua-views.md says that a role has a `label` "for a screen reader", so some thought exists. The message line says what each action did (rule 6), which helps.

**What to build.** An assessment, not a feature:
- Run paw (through tests/tools/run.sh, never on the owner display) with a screen reader that reads a terminal, and write what reads well and what does not: the message line, the command line, the pickers, the arrange view, the piano roll.
- A list of the smallest changes with the most effect (for example an option that announces the cursor target in the message line, or a plain text mode of a view), each as a proposed ticket.
- A short explanation page or a section in docs if the result is good enough to tell users.

**Core or extension.** Docs and tests first. Each change that follows decides core or extension in its own ticket.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A report in backlog/docs/ says what reads well and what does not, view by view, with the setup used
- [ ] #2 The proposed changes are tickets with acceptance criteria
- [ ] #3 If a test is added, it checks the text of the message line for an action with real keys, and reads nothing of the machine
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
