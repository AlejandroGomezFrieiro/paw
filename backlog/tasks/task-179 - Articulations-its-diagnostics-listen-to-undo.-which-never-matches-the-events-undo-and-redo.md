---
id: TASK-179
title: >-
  Articulations: its diagnostics listen to undo.*, which never matches the
  events undo and redo
status: Done
assignee: []
created_date: '2026-11-22T23:58:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels: []
milestone: m-4
dependencies: []
priority: medium
ordinal: 191000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by TASK-129 (2026-11-23). extensions/articulations' diagnostics subscribe to the pattern undo.*; the events are named undo and redo, so the handler never runs after an undo. Also consider whether paw.on should warn for a pattern that matches no declared event (TASK-129 checks only plain names).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After u and <C-r>, the articulation diagnostics are up to date, by a test with real keys
- [ ] #2 Decide and note: warn or not for a pattern that matches no declared name
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch worktree-agent-af471b53e308d9496, commit 3cd24c85, on top of TASK-129 (worktree-agent-a94cd7158c7eda819, merged in).
#1: undo and redo send the changes that they put back as clip.* and track.* events with restored = true, so the diagnostics already followed u and <C-r>; the subscription undo.* was dead. Removed it (no handler for undo/redo, which would only schedule the same check twice), with a comment why. New test 'articulations: the diagnostics follow u and <C-r>' (real keys). Mutation: without clip.*/track.* it fails at u.
#2 decision: warn. Reason: the same mistake as a misspelled name (a handler that never runs), found here by hand; the check is cheap (at startup and at each later paw.on); and it uses TASK-129's log line and :checkhealth events. Rule = what paw.emit matches: '*' always; 'family.*' needs one declared event whose family (the name before its last dot) is 'family'; any other text must be a declared name (so 'undo*' warns). One function family_of now holds the family rule for emit, listened and the check. Test: tests/health.lua checks that undo.* is logged once and listed, and track.* and * are not. With all bundled extensions loaded, paw.events.undeclared() is empty.
Docs: events.md, how-to/write-an-extension-in-teal.md, api.md (apidoc).
<!-- SECTION:NOTES:END -->
