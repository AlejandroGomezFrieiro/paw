---
id: TASK-87
title: 'Vale: every rule is an error or off, by kind of file'
status: Done
assignee: []
created_date: '2026-11-22T09:25:00Z'
updated_date: '2026-11-22T09:45:00Z'
labels:
  - docs
  - vale
  - quality
milestone: m-6
dependencies: []
priority: high
ordinal: 87000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-22: fix the setup instead of ignoring Vale output. No warnings level: each rule is an error or switched off. Rule sets by path: external (README, docs/, extension and crate READMEs) = Plain + AiTells + alex + Vale spelling (+ the STE rules that agree with plain writing), as errors; generated pages (docs/reference/api.md, docs/tutorials/course/*) = spelling only, prose rules run on their sources (doc comments, tutor lessons) via a check in tools/apidoc.lua or the tutor's make-docs; internal (AGENTS.md, .claude/**, bench/*.md except RESULTS.md) = STE as errors; bench/RESULTS.md excluded (dated log). Readability grade levels off for external pages (they leak today and conflict with plain writing). Vocabulary exceptions for real technical terms (e.g. alex flags 'hang' for a plugin hang). Fix every current alert (24 warnings: Readability on 5 pages, STE.Paragraphs on api.md and curve-editor.md, STE.Ing on AGENTS.md and bench/README.md, alex 'hang'). Then the docs check fails on any alert. Update AGENTS.md and the diataxis-docs skill's Vale section.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a7b99f7efff2fed11. .vale.ini sections by kind, all rules error/off, docs check fails on any alert, 0 alerts.
<!-- SECTION:NOTES:END -->
