---
id: TASK-161
title: 'Tests read nothing of the machine: audit and mock'
status: Done
assignee: []
created_date: '2026-11-22T20:36:00Z'
updated_date: '2026-11-23T01:26:00Z'
labels: []
milestone: m-12
dependencies: []
priority: high
ordinal: 173000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner, 2026-11-22: "Tests should be fully self-contained, and not depend on my specific computer/directories. Mock whatever is needed instead of using my real home." Main (5d520705) seals each run: tests/tools/env.sh and sealed::seal give a scratch HOME, empty plugin folders, a scratch WINEPREFIX, and tests/suite.lua refuses to run outside it. A run with the real HOME had scanned ~/.vst3, where a yabridge bridge starts wine in the owner's prefix. This ticket finds and removes what is left: tests that read the user name or the passwd home (tests/guides_howto.lua near line 409, extensions/plugstate/tests.lua near line 236), system fonts, /run/current-system or /etc/profiles plugin folders, the network, the real XDG_RUNTIME_DIR, and tools that start paw outside env.sh (tests/tools/*.sh, bench/, tools/). Mock with the stub CLAP plugin, a fake behind a trait, or a scratch folder.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A search of tests/, extensions/*/tests*.lua, crates/*/tests and tests/tools lists each read of the machine, and each one is removed or mocked
- [ ] #2 With HOME, USER and every plugin path variable set to values that do not exist, the full suite and the Rust tests give the same result
- [ ] #3 A lint in the suite fails on a new os.getenv("HOME"), os.getenv("USER") or absolute /home path in a test file
- [ ] #4 rust-testing and lua-testing skills name the rule and the helpers
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built on branch worktree-agent-a93ee565e941bba88: 86caf3da (env.sh and sealed::seal give XDG, runtime folder, USER/LOGNAME paw-test, GIT_CONFIG_NOSYSTEM, VST3_PRESET_PATH, no bus; seal fills only unset vars; bench run/stress/abuse source env.sh; T.home; passwd/USER reads removed from guides_howto, plugstate tests, tests_tone3000; paw.health.cjk_font seam; plugstate.share_dirs skips Nix profiles when CLAP_PATH is set), e1171546 (skills, AGENTS.md, run-the-tests), 9959c2a3 (machine patterns in tools/testlint.lua, no allow-list). Merged main and the TASK-143 branch (cb03f205) to build on its lint; removed the stale guides_mix paw.wait( line of tests/timing-allowed.txt. Rust tests to run: cargo test -p paw-tui --test join --test remote --test safety --test suite; -p paw-mcp --test protocol; -p paw-core upload. Window reads (paused): paw-gui theme.rs find_cjk via fontconfig, window.rs needs Xvfb/openbox/xdotool/ImageMagick/tesseract. Left for TASK-162: paw-plugins usual_dirs, libs.rs, presets.rs, window.rs Xauthority, plugstate share_dirs/binary_of, paw-core session/folder.rs and paw-tui ~ read HOME in library code.
<!-- SECTION:NOTES:END -->
