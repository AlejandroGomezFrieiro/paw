---
id: TASK-74
title: 'Prose: rewrite the docs with plain-writing (phase B)'
status: Done
assignee: []
created_date: '2026-11-22T07:59:00Z'
updated_date: '2026-11-22T09:06:00Z'
labels:
  - docs
  - prose
milestone: m-6
dependencies: []
priority: high
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After phase A and after the running agents merge (they edit reference pages): rewrite docs/ (tutorials, how-to, reference, explanation), extension READMEs and doc/ pages, crate READMEs and the tutor lessons (regenerate the course) with the plain-writing skill, keeping every fact and the Diátaxis structure; guide tests keep passing; generated pages come from their sources (api.md from doc comments: decide whether doc comments are external; the reference API is read by extension authors, so yes). Split by area across agents. Then raise the Plain Vale rules from warning to error.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Phase B finished on branch worktree-agent-a0a4a71cfbecff8ea: fixed all Plain warnings on external pages (Demonstrative, MiddleDot via code spans in doc comments, CountOpener, NegParallel, Puffery, Overused), alex.Ablist (LAME in code span, mixdiag disabled, bench dummy), regenerated api.md and types; the course had no Plain hits so docs.lua unchanged. All 10 Plain rules are level error. Vale: 0 errors, 0 Plain, 24 warnings left (STE.Ing internal files, STE.Paragraphs on 3 external pages).
<!-- SECTION:NOTES:END -->
