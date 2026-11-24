---
id: TASK-73
title: 'Prose: plain-writing for external docs, STE for internal (setup + README)'
status: Done
assignee: []
created_date: '2026-11-22T07:59:00Z'
updated_date: '2026-11-22T08:37:00Z'
labels:
  - docs
  - prose
milestone: m-6
dependencies: []
priority: high
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-22: external documents use the plain-writing skill (github.com/docwriter-org/plain-writing-skill, MIT); internal technical text (tickets, designs, AGENTS.md, .claude/skills, bench/, code comments, commit messages, chat) keeps Simplified Technical English. Phase A: vendor the skill in .claude/skills/plain-writing (with its MIT licence and source), a Vale style 'Plain' for its checkable rules, .vale.ini per-path sections (external: README.md, docs/**, extensions/*/README.md and doc/**, crates/*/README.md; internal: AGENTS.md, .claude/**, bench/**), AGENTS.md documentation standards and the diataxis-docs skill updated, then README.md rewritten. Phase B (TASK after this): the rest of the docs.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Phase A done on branch worktree-agent-acc66b85b1e330fd8 (51ae7658..41b54b72, 7 commits): vendored .claude/skills/plain-writing (SKILL.md, LICENSE, SOURCE, PAW.md); Vale style Plain (10 rules, warning); .vale.ini: [*.md] = external set (Vale, Plain, write-good, alex, AiTells + STE.Spelling/Glossary/PassiveBy/Paragraphs), a section for AGENTS.md, bench/*.md, .claude/** = the STE set as before; AGENTS.md, diataxis-docs, paw-extension skills updated; tools/vale.sh makes absolute paths relative (the hook gave absolute paths, so per-path sections did not apply); README.md rewritten, 0 errors 0 warnings. Checks: full Vale 0 errors, nix docs check passes, suite only guide help passes. Phase B: 305 Plain warnings (252 Plain.Demonstrative), then raise Plain to error.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Merged: skill vendored (.claude/skills/plain-writing + PAW.md), Plain Vale style, per-path .vale.ini ([*.md] = Plain; AGENTS.md, bench, .claude = STE), AGENTS.md + diataxis-docs updated, README rewritten.
<!-- SECTION:FINAL_SUMMARY:END -->
