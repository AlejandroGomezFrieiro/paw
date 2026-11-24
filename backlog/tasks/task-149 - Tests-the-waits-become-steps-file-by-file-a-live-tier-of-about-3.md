---
id: TASK-149
title: >-
  Tests: the waits become steps; the live tier, -j 4 by default, and the docs
  (last part)
status: Done
assignee: []
created_date: '2026-11-22T20:28:00Z'
updated_date: '2026-11-24T10:56:00Z'
labels:
  - tests
  - better-testing
  - agent:builder
milestone: m-12
dependencies:
  - TASK-149.1
  - TASK-149.3
  - TASK-149.4
  - TASK-148
  - TASK-145
  - TASK-330
priority: high
ordinal: 161000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Epic. Do not build this ticket: build its children.

Source: backlog/docs/designs/test-suite-review.md, finding T4, ticket P4, sections 3.3 and 7 (shards).

With the manual clock (TASK-146), the stepped backend (TASK-147) and the handshakes (TASK-148) in place, change the tests that the lint allow-list (tests/timing-allowed.txt) names. The steps { wait = N } of the tutor's lessons become { advance = N }. Delete the 7 local wait_for helpers. Mark the live tests with T.live or a file tests/live_<area>.lua (about 3 % of the suite, fewer than 60 tests; owner, 2026-11-22). Live tests check outcomes only. When all parts are done, make -j 4 the default of suite.sh (owner: shards only after this ticket).

Children (agents can do parts 1, 3 and 5 side by side; part 2 needs TASK-148, part 4 needs TASK-147):
- TASK-149.1: the guides and the tutor's lessons.
- TASK-149.2: plugins, offline renders and safety.
- TASK-149.3: core, input, flow, attr, scope, complete, stretch, doctor.
- TASK-149.4: the other files of tests/.
- TASK-149.5: the tests of the extensions.
- TASK-149.6: the live tier, -j 4 by default, the docs.

The Rust lines of tests/timing-allowed.txt (crates/*) are not in this ticket: the product part of the time lint is in TASK-146.

Read first: backlog/docs/designs/test-suite-review.md, sections 1 (the table of files), 3.1, 3.3, 4 (T4), 5. .claude/skills/lua-testing and prune-tests.

Overlaps: TASK-121 (shards, done).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The lint allow-list has no line for a stepped test
- [ ] #2 Fewer than 60 tests are live, and each checks outcomes only
- [ ] #3 suite.sh -j 4 --shuffle <seed> passes three times with three seeds
- [ ] #4 The full suite passes in a dev build and in a release build
- [ ] #5 -j 4 is the default of suite.sh, and the how-to page says so
- [ ] #6 Each part names the tests that it pruned and why
- [ ] #7 (TASK-149.6) Fewer than 60 tests are live, and each checks outcomes only
- [ ] #8 (TASK-149.6) suite.sh -j 4 --shuffle <seed> passes three times with three seeds
- [ ] #9 (TASK-149.6) The full suite passes in a dev build and in a release build
- [ ] #10 (TASK-149.6) -j 4 is the default of suite.sh; the how-to page and the skill lua-testing say so; Vale reports 0 alerts
- [ ] #11 M.registries in runtime/lua/paw/ext.lua is gone; the leak check of tests/suite.lua reads paw.registry.all() and still finds a leaked key, hook or timer (from TASK-208 AC 1)
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
Board review 2026-11-23: split into TASK-149.1 to TASK-149.6 (it was L). Set this epic to Done when all children are merged. The criteria below are the criteria of the whole; each child checks its own part.

Merged from TASK-149.6 (Tests to steps 6: the live tier, -j 4 by default, and the docs) by the PO on 2026-11-23.

Its description:
Last part of TASK-149. Read the description of TASK-149 first.

When parts 1 to 5 are merged: count the live tests (T.live or tests/live_<area>.lua; owner, 2026-11-22: about 3 % of the suite, fewer than 60). Each live test checks outcomes only. Make -j 4 the default of tests/tools/suite.sh (owner: shards only after the waits are steps). Change the how-to page on the tests and the skill lua-testing. Run the full suite in a dev build and in a release build, and three times with -j 4 --shuffle and three seeds.

Size: S.

PO 2026-11-23: Bundle: TASK-149.6 was the last part; this ticket is now that part. Build it when TASK-149.1, TASK-149.3, TASK-149.4, TASK-148 and TASK-145 are merged. Size S.

PO 2026-11-23 (after batch 18+19, c04f8ae9): TASK-145, 147, 148, 149.1, 149.3 and 149.4 are on main. This last part can start when TASK-330 (the 18 order problems of a shuffled run) is merged, because AC 3 and AC 8 need three shuffle seeds to pass. The three quarantined plugin tests (TASK-331) may stay quarantined for this ticket. New AC 11 from TASK-208. Size S to M.

From TASK-330: under load, 'lenses: a one-shot server checks each render' (waits 5000 ms of wall time) and 'two clicks are a double click only when the second comes within the double click time' failed once in a shuffled run. Check both for wall-time dependence.

Wave 23 (2026-11-24), base 9cecbfdc (batches 20-22 + W1).

W1 full suite (2026-11-24): 'two clicks are a double click only when the second comes within the double click time' failed under load (tuimouse.lua:284, got 6 want 0): fix it in this ticket.

Order issue (2026-11-24, suite only 'move'): 'recent: the newest project is first, and one that is opened again moves up' (tests/recent.lua:44) sees recent entries that an earlier test leaves; passes alone. Fix the isolation in this ticket.

On local main (6ab9c2ac, 2026-11-24, not pushed). The suite.sh fork bomb of the WIP (jobs=4 default, shards re-sharding) is fixed: a shard never shards (exit 2), -j 4 only for a full run. Also fixed: spawn makes the folder of its log (lenses failed under -j 2). Review: send-back fixed. Merge-check green: clippy 0, nextest 693/693, suite words all passed, peak 3034 tasks. Follow-up: M.log_path gives state/paw/paw (lsp/init.tl:1127).
<!-- SECTION:NOTES:END -->
