---
id: TASK-333
title: Esc stops a recording and keeps the take
status: Done
assignee: []
created_date: '2026-11-23T20:21:00Z'
updated_date: '2026-11-24T03:24:00Z'
labels:
  - ux
milestone: m-15
dependencies: []
priority: high
ordinal: 402000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-23: 'ESC might be actually a nice way to escape Recording mode instead of leader+space. Been instinctively going there.' Design (orchestrator): Escape keeps its chain (keymap.tl ~1552, 1855): it first cancels the innermost thing (a popover, a pending operator, visual mode, a selection). When nothing else is left to cancel and paw records, Escape stops the recording as R does: the take is kept, the transport stops, one undo step, the message names the take. During a count-in, Escape cancels the take (nothing is recorded). Escape never stops plain playback. Like leaving insert mode in Vim: the text stays.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Real keys: R, then Esc: the take is kept, the transport stops, the message names the take, u removes it in one step
- [ ] #2 Real keys: R, v (a selection), Esc: the selection goes and the recording goes on; a second Esc stops it
- [ ] #3 Esc during the count-in records nothing; Esc while playing (not recording) does not stop the song
- [ ] #4 The key rule page, the keys reference, the record how-to and the tutor's recording lesson say it
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
Branch worktree-agent-a914b2c82be059014, commit 5742f538 (base c04f8ae9). escape_hint(how?) now sends the escape event, so every view that maps Esc (piano roll, drum grid, vinput, utau, doctor, notation) also ends a recording; the transport's escape listener calls the take off in the count-in, else transport.stop() (take kept, record mode ends, message 'recording stopped: take N kept (u removes it)'); plain playback untouched. Test tests/record_mix.lua 'Esc ends a take and keeps it in each view where one records, after what it cancels first' (arrange, piano roll, mixer); count-in check in guides_record.lua. Docs: key-rule, keys, recording, events, three record how-tos, notation reference, tutor lesson 12 (course regenerated). Esc stops the song as well as the take (R leaves it playing). Joins the next batch.

PO 2026-11-24: built, waits to merge (batch 21 or 22); status In Progress until it is on main.

On local main in batches 21+22 (4300ace4, 2026-11-24, not pushed). Full suite passed after two fixes (cab47711 a plugin is not work in flight; 4300ace4 the pick test waits for the walk); nix flake check passed.
<!-- SECTION:NOTES:END -->
