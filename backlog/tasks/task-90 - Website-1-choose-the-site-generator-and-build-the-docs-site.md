---
id: TASK-90
title: 'Website 1: choose the site generator and build the docs site'
status: Done
assignee: []
created_date: '2026-11-22T10:12:00Z'
updated_date: '2026-11-22T11:08:00Z'
labels:
  - docs
  - website
milestone: m-9
dependencies: []
priority: high
ordinal: 93000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build a static site from docs/ (and the extension READMEs) without changing the Markdown sources: evaluate mdBook, MkDocs Material, Zola and Astro Starlight for search, navigation from docs/README.md, code highlighting, dark mode, GIFs, relative links and anchors as GitHub renders them, build in Nix (a flake output, no network at build time), speed. Pick one with reasons; a nix build .#website output; local preview command. No publishing yet.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a4db4872f71dc9608, commit 75be6857. mdBook chosen: nix build .#website (2 s, 264 pages, 4762 links, 0 broken, no network); MkDocs Material 15.6 s and depends on MkDocs 2.0 breakage; Zola/Starlight judged, not built. Preview: nix develop -c tools/website/build.sh /tmp/paw-site serve. Pages: docs/explanation/about-the-website.md, docs/how-to/preview-the-manual-as-a-website.md. Not published.
<!-- SECTION:NOTES:END -->
