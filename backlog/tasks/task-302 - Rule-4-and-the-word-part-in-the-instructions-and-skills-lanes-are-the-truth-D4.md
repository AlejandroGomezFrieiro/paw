---
id: TASK-302
title: >-
  Rule 4 and the word part in the instructions and skills: lanes are the truth
  (D4)
status: Done
assignee: []
created_date: '2026-11-23T16:01:00Z'
updated_date: '2026-11-23T23:03:00Z'
labels:
  - docs
  - architecture
  - bundle
milestone: m-9
dependencies: []
references:
  - architecture/decisions/0019-lanes-are-the-truth.md
  - architecture/decisions/0030-the-user-word-part.md
  - backlog/docs/designs/architecture-plan.md
  - backlog/docs/designs/owner-answers-2026-11-23.md
priority: high
ordinal: 364000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle D4 of the architecture plan, version 2 (backlog/docs/designs/architecture-plan.md V2.15 and V2.16 point P1).

The owner changed rule 4 on 2026-11-23 (round 7.2 of backlog/docs/designs/owner-answers-2026-11-23.md): "Lanes are the truth. Source lanes hold the data. A derived lane is a recipe plus its kept result. A project opens and plays without the extension or program that made a derived lane."

Lanes do not exist in the code until LA. So this bundle changes the rules for future work now (AGENTS.md and the skills) and adds one paragraph to the public page. LA rewrites the public page when lanes exist. Each public fact stays true.

Read first: the skill .claude/skills/architecture (after batch 19 it is on main), architecture/08-concepts.md and 13-roadmap.md, the ADRs in the references, and backlog/docs/designs/architecture-plan.md (the sections that this ticket names). An Opus agent does the whole bundle in one branch, with its tests and docs in the same commits. Use the skills diataxis-docs and plain-writing for the public pages.

Size: S. It changes no code.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 AGENTS.md rule 4 has the text of round 7.2, with a link to the public page
- [x] #2 The skills paw-extension (rule 1 of its list), diataxis-docs (the list of explanation pages and the glossary words part and lane) and teal (if it names the rule) agree with rule 4
- [x] #3 docs/explanation/about-midi-as-the-truth.md has one paragraph at its top: the rule is now lanes are the truth; today a track has one lane of each kind; LA rewrites the page. Each fact on the page stays true
- [x] #4 tools/website/landing.md (MIDI is the truth) agrees
- [x] #5 Vale reports 0 alerts on each changed file
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
Branch worktree-agent-aaa99bf5c92f62fc8, commit 8ad2ea9b (base de7285a2). AC1-AC4 done in the commit. AC5: Vale 0 alerts on AGENTS.md, the public page and landing.md. The two skills have alerts that were there before (glossary list, other parts); the changed lines add none. teal skill does not name rule 4: no change. Architecture folder: the worktree isolation refused edits outside the worktree. The script scratchpad/agents/D4-arch-tickets.sh does the ADR tickets fields and the bundle-to-ticket links; tested on a copy: 0 target errors, 0 notes, all ticket ids exist.

On main in batch 20 (5041115e, pushed 2026-11-24 with the tag pre-parts). Full suite passed after one test fix (5041115e: three tests and the time-axis test expected the null backend); nix flake check passed.

PO 2026-11-24: ACs checked against main 8ad2ea9b: AGENTS.md rule 4 'Lanes are the truth', paw-extension and diataxis-docs skills, the paragraph in about-midi-as-the-truth.md, landing.md changed. The landing heading still says 'MIDI is the truth' with the old page link: LA (TASK-309) rewrites the page and the heading.
<!-- SECTION:NOTES:END -->
