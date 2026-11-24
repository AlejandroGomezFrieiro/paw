---
id: TASK-91
title: 'Website 2: landing page'
status: Done
assignee: []
created_date: '2026-11-22T10:12:00Z'
updated_date: '2026-11-22T11:55:00Z'
labels:
  - docs
  - website
milestone: m-9
dependencies: []
priority: high
ordinal: 94000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A landing page for paw in plain writing: what paw is (one sentence), who it is for, a short GIF or live demo, the main ideas (modal keys, terminal first, Lua/Teal extensions, MIDI as the truth, non-destructive media), install (Nix now, standalone later), links to Make music and the docs, and a 'Try it in your browser' slot (Website 4). Reuses README facts; Vale external rules apply.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The landing page is the first page of the built site and opens with one sentence that says what paw is, and a sentence on who it is for
- [ ] #2 The page shows a demo GIF, and has a section for each main idea (modal keys, terminal first, Lua and Teal extensions, MIDI as the truth, files that paw never deletes), and each fact is in README.md or docs/
- [ ] #3 The page has an install section (Nix), links to Make music and the manual, and a marked, empty slot titled Try it in your browser for TASK-108 and TASK-107
- [ ] #4 The page reads well in light and dark themes and at phone width, with no JavaScript framework
- [ ] #5 nix build .#website passes with 0 broken links, Vale reports 0 alerts on the new Markdown, and About the website says how the landing page is built
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-a7fca4a97b0b86615. Landing page tools/website/landing.md (staged over README.md only), landing.css, book.toml additional-css, build.sh, about-the-website.md. nix build .#website passes, 0 broken links. Slot: div#try-in-browser.
<!-- SECTION:NOTES:END -->
