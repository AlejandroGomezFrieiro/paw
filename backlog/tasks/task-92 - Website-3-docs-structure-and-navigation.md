---
id: TASK-92
title: 'Website 3: docs structure and navigation'
status: Done
assignee: []
created_date: '2026-11-22T10:12:00Z'
updated_date: '2026-11-22T12:10:00Z'
labels:
  - docs
  - website
milestone: m-9
dependencies: []
priority: medium
ordinal: 95000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Sidebar and sections from docs/README.md (Start here, tutorials, how-to, reference, explanation, extensions), search, 'edit this page' links, previous/next in tutorials, the extension READMEs and doc/ pages as their own section, api.md as API reference; a link checker for the built site in nix flake check; the same structure as :help.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every page of the built site has an edit link to its file on GitHub (the landing page links tools/website/landing.md)
- [ ] #2 Every chapter shows previous and next links, and the tutorials follow each other in the order of docs/README.md
- [ ] #3 The sidebar parts are Tutorials, How-to guides, Reference, API reference (api.md alone), Explanation and Extensions, in the order of :help
- [ ] #4 Each extension is a chapter of Extensions, and its doc/ pages are nested under it
- [ ] #5 nix flake check builds the website, so a broken link or anchor fails it
- [ ] #6 The docs name the structure, Vale reports 0 alerts, nix build .#website passes, and a screenshot shows the sidebar, search and edit link
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-ae6808e5433fa4ec0. Added edit links (book.toml, build.sh), API reference part (summary.lua), website in flake checks, docs updated. Search, prev/next, extensions part existed or are native to mdBook.
<!-- SECTION:NOTES:END -->
