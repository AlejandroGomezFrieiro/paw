---
id: TASK-363
title: 'GIF rig without X: headless Wayland, nix run .#gifs, and a check mode'
status: Done
assignee: []
created_date: '2026-11-24T13:03:00Z'
updated_date: '2026-11-24T14:21:00Z'
labels:
  - docs
  - tooling
  - agent:builder
milestone: m-9
dependencies: []
priority: high
ordinal: 432000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The GIF rig (docs/images/make) needs Xvfb, openbox and xdotool. The Claude Code sandbox hides /tmp/.X11-unix and Xvfb needs a lock file in /tmp (-nolock is root only), so no agent can make a GIF. Spike 2026-11-24 in the sandbox: sway with WLR_BACKENDS=headless WLR_RENDERER=pixman and XDG_RUNTIME_DIR under $TMPDIR starts, and grim takes a screenshot (Xwayland fails, not needed).
Goal: one standard command that works the same in the sandbox, in the owner's terminal and in CI.
1. rig.sh: replace Xvfb/openbox/xdotool/x11grab with headless sway (private XDG_RUNTIME_DIR in $TMPDIR, an output of the terminal size), a terminal (Ghostty first, as the owner asked; WezTerm with front_end Software as the fallback; record which one works and why), wtype for the keys, wf-recorder (or grim frames) for the video. Keep the scene API (rig_start, term_start, rec_start, cap, key, keys, typ, pause, rec_stop) so tui-*.sh scenes do not change. gif.py stays.
2. Fail loudly (absorbs TASK-361): no compositor socket, no terminal window, no recording, or no GIF written -> exit non-zero with the reason. Exit 0 only when every asked GIF exists and passes the budget.
3. A flake app: nix run .#gifs -- <scene...> (all tools pinned in the flake, PAW_BIN honored, NOCOPY honored). make.sh becomes a thin wrapper or goes.
4. A check mode: nix run .#gifs -- --check [scene...] replays each scene with no recording and fails when a key errors or paw reports an error; cheap enough to add to nix flake check (add it if it stays under about a minute, else say why not).
5. Keep pictures (kitty graphics) working if the terminal supports it.
6. Update the paw-gifs skill and docs (how-to/reference that names make.sh) in the same work.
Fallback if no terminal runs headless: cast.py + agg (nixpkgs#asciinema-agg 1.9.0), with the caption and key bar from gif.py; report the loss of pictures.
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Each acceptance criterion is met, and the notes give its evidence
- [x] #2 Tests: each change of behavior has a test (real keys for a UX change); tests are sealed and do not depend on time; prune-tests is applied
- [x] #3 Checks pass: clippy 0 warnings, tlcheck, luacheck, fmtcheck, testlint, layers, apidoc check, Vale 0 alerts on changed Markdown
- [x] #4 Docs: each page the change made untrue is fixed; the notes give the stale-docs search; generated files are generated, not edited
- [x] #5 Architecture: a contract change is in the architecture documentation; a design change has a proposed ADR
- [x] #6 Report: it starts with Changes for the orchestrator (file, place, exact edit), then commits, evidence, tests to run after the build, before and after screens for a UX change, owner questions
- [x] #7 Hygiene: no ticket ids or backlog paths in tracked files; commit trailer; no process left running; paw-gui not touched
- [x] #8 Orchestrator: merged on main; affected tests and the full suite pass; the changes for the orchestrator are applied
<!-- DOD:END -->
