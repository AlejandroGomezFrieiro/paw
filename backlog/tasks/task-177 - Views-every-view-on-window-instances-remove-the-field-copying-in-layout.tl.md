---
id: TASK-177
title: Editor subject by clip kind, and every view on window instances (B7)
status: To Do
assignee: []
created_date: '2026-11-22T23:12:00Z'
updated_date: '2026-11-24T14:18:00Z'
labels:
  - agent:builder
milestone: m-10
dependencies:
  - TASK-304
references:
  - architecture/decisions/0018-parts-and-typed-lanes.md
  - architecture/decisions/0022-modifier-stack-ux.md
  - architecture/decisions/0003-one-view-two-frontends.md
  - backlog/docs/designs/architecture-plan.md
priority: medium
ordinal: 189000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bundle B7 of backlog/docs/designs/architecture-plan.md (V2.9, V2.15; section 6.3 and m10-generalization-review.md 2.7 and 3). It keeps TASK-177 (window instances) and adds the editor subject.

The piano roll stops being the hub. paw.editor.define(clip_kind, view, impl) registers editors for a clip kind: several for each kind, one default (owner round 5.4). Ex ranges, the language servers, snippets, diagnostics, the quickfix list, locators and completion read the subject of the focused editor. Every view keeps window state on window instances (design backlog/docs/designs/window-instances.md; the spike TASK-130 is on main): the copy code in layout.tl goes. notation moves to Rust later (m-11): change only its window state.

No other bundle that edits layout.tl or the piano roll in its batch. Read first: the skill .claude/skills/architecture and the ADRs in the references. Size: L. One Opus agent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 paw.editor.define(clip_kind, view, impl) and paw.editor.current(clip_kind) give { owner, lane, clip, cursor, selection } (lane is nil until LA). Several editors for each clip kind, one default; the piano roll is the default editor of midi
- [ ] #2 No module outside the piano roll imports its private Roll type; views:get("pianoroll") appears only in an allow-list that tools/privatepath.lua checks (the suite runs it)
- [ ] #3 A second note editor registered in a test (a minimal view) gets Ex ranges and diagnostics with real keys
- [ ] #4 No view keeps window state by copying fields; the copy code in layout.tl is gone
- [ ] #5 Two windows of each view keep their own state, by a test with real keys for each view that has window state
- [ ] #6 Frame times stay within the spread of main's, measured in bench/
- [ ] #7 Docs: the extension skill and the API reference are true; Vale reports 0 alerts
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Board review 2026-11-23: still open. The spike (TASK-130) is on main (427c65d7): the piano roll uses window_instances. notation still calls paw.layout.window_keep (extensions/notation/init.lua:45). notation moves to Rust later (m-11): change only its window state, not its code. Size: M.

Lane heads (HD, TASK-323): the head key scope uses the key_scope of the editor subject; privatepath covers paw/heads/ (design: backlog/docs/designs/lane-heads.md)
<!-- SECTION:NOTES:END -->
