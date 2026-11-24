---
id: TASK-121
title: Tests that fail only when run with a filter (order-dependent)
status: Done
assignee: []
created_date: '2026-11-22T18:00:00Z'
updated_date: '2026-11-22T21:52:00Z'
labels:
  - tests
milestone: m-3
dependencies: []
priority: medium
ordinal: 133000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several agents saw tests fail under 'suite.sh only <words>' that pass alone and in the full suite: the utau vocal editor ('a double click on empty space selects the phrase there', 'plays notes as they are placed'), tests/ui.lua 'tracks fit their height', tests/scope.lua 'narrowing to a group', and the tutor lesson 4 step 14. One known cause: tuimouse puts back its options only in its last test. Make each test file restore what it changes (options, layout, tabs), so any filter gives the same result as the full suite.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each named test passes under its file's 'only' filter and under 'only' filters that run it after other files
- [ ] #2 The full suite still passes
- [ ] #3 The leak check runs after each test file, and its allow-list exists with a count
- [ ] #4 suite.sh -j 2 gives the same result as suite.sh (at most -j 4; one process is the default)
- [ ] #5 The how-to page on the tests says how to use -j and what the leak check says
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan, from the Lua review (L1/P1, owner accepted 2026-11-22): see the design architecture-review-lua.md L1.

Built on branch worktree-agent-a4cb58c8859bb90a5 (head 3f008db9, main merged at 79282208). Not Done: the orchestrator merges.
- paw.option.snapshot() / restore(s) (options.tl, API doc regenerated).
- Runner (tests/suite.lua): options go back to the start of the run after EACH test (not in T.fresh: tests that set an option and then call fresh() mid-test keep it). T.fresh also leaves insert/visual/pending keys, closes floats, widens scopes. T.start() = fresh + <Esc><Esc>. T.screen(w, h). T.write_wav and T.samples moved from tests/core.lua into the runner (devices, media, safety, tempo, projdiff used them through core.lua: order dependence).
- Leak check after each part (a file of tests/, or all test files of one extension: tests_tone3000_auth uses T.t3k from tests_tone3000). It unloads extensions the tests loaded, removes hooks/timers/keys that test code made, and fails "<part> leaves no state behind" for a hook/timer/key of test code, or an extension it cannot unload. Checked only when every test of the part ran. tests/leaks-allowed.txt: count 0; a stale line fails the run.
- suite.sh -j N (1..4, default 1): N shards of whole parts, each with its own scratch/XDG/HOME (env.sh through PAW_TEST_SCRATCH); outputs joined in suite.out.
- Leaks found and fixed: tests/automation.lua and tests/model.lua hooks (paw.off in T.after); tuimouse mixer size in T.after (its last test "leave the options as they found them" removed); vinput tests set vinput_file each load.
- Product bugs found by the reset: :bnext crashed on the view of an unloaded extension (buffers_list skips it); mixdiag's band under the ruler stayed after unload (new registry "bands" in paw.ext.registries); the pointer's zoom-to-fit stayed armed for the next clip opened by keys (pianoroll open() clears it, frontend sets it after opening); the device panel kept its row in another project with the same track id (reset on project.loaded). Each has a test.
- Tests: vocal_window() paints before its first click (T7); roll_scene resets the step; guides_mix timed() waits for pending keys, not 150 ms.
- Docs: how-to run-the-tests (-j, leak check), reference/extensions (bands), reference/source-tree, skills paw-extension and lua-testing.
Runs (shared bin + dev-runtime, under external load): suite.sh 1 process (before the last fixes) 7 failed; suite.sh -j 2 (later code) 5 failed. Common to both: apidoc x2 and "search: ... Lua API" = artefacts of PAW_RUNTIME dev-runtime (no doc comments), not of this branch. Rest fixed after: teal shadowing, templates guide, utau curves, check the mix, make music 3.
Left (T7): MIDI test ports, engine backend, window history, kernel id counter are not in the fingerprint.

Fix after the merge with TASK-123 (commit on branch, see git log): 'guide: check the mix' failed in the full plugins run. Cause: paw.lsp.config was not an ext registry. mixdiag runs an in-process language server; after the runner unloaded mixdiag, the client stayed live with the old lens module, and the reloaded mixdiag published to a new lens module that had no ctx, so no diagnostics and ]d did not move. Fix: registry 'lsp' in paw.ext.registries; unloading stops and forgets the server. Test in tests/extensions_api.lua (fails on the old code). Checked with the merge tree binary: suite.sh plugins 'mix' 49 ok (old code: 1 failed, the same failure).

Merged to main (batch 2, 2026-11-22): dev build, full suite with plugins passed in one process; nextest paw-core/paw-scene/paw-tui passed. -j 2 order failures moved to TASK-144.
<!-- SECTION:NOTES:END -->
