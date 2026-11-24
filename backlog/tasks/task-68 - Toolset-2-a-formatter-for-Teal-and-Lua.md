---
id: TASK-68
title: 'Toolset 2: a formatter for Teal and Lua'
status: Done
assignee: []
created_date: '2026-11-22T05:45:00Z'
updated_date: '2026-11-22T07:34:00Z'
labels:
  - teal
  - lua
  - tooling
  - format
milestone: m-8
dependencies: []
priority: medium
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
cerulean for .tl, StyLua for .lua (or one tool for both if one fits): a config that matches paw's current style as closely as possible; a format check in nix flake check. Reformatting the whole tree is a big diff: owner approves first; one commit, nothing else in it.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Settings + counting check merged; no reformat: StyLua would change 468/515 Lua files (+38k/-15k), cerulean 90/93 Teal files (+25k/-13k) and fails on 3; both break aligned comments and one-line ifs/functions. Owner question: reformat or not (recommended: no; maybe format new files only).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Tree formatted (4247de7b + fixed-point pass); strict format check; limit.tl, pick.tl, ui.tl excluded (cerulean output invalid).
<!-- SECTION:FINAL_SUMMARY:END -->
