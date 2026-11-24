---
id: TASK-384
title: 'Bug: plugin and audio library output prints over the terminal screen'
status: In Progress
assignee: []
created_date: '2026-11-24T17:34:00Z'
updated_date: '2026-11-24T17:35:00Z'
labels:
  - bug
  - ux
  - tui
  - agent:builder
milestone: m-15
dependencies: []
priority: high
ordinal: 453000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Screenshot (names redacted): backlog/assets/tui-stray-output.png

With a project that has plugins on its parts, lines such as 'using block size: 1024' and 'buffersize changed to 128' print straight onto the terminal, on top of the arrange view, the status line and the message line. paw does not draw them, and they stay until the next full redraw. The terminal UI must stay correct whatever a plugin or a library writes.

Causes found so far:
1. The sandboxed plugin host inherits paw's stdout and stderr (crates/paw-plugins/src/sandbox/factory.rs: only stdin is set to null), so everything a plugin prints reaches the terminal.
2. Libraries that run inside paw itself (the audio backend client, a plugin hosted in-process where there is no sandbox) write to paw's own fd 1 and fd 2, which are the terminal.

Direction (the builder decides the details):
- Give every child process of paw (plugin host, scan, helpers) pipes for stdout and stderr, and send the text to a log (and to :messages at debug level), never to the terminal.
- In the TUI, keep a private file descriptor for the terminal and point fd 1 and fd 2 of the process at a log file at start, so no library can write onto the screen; put them back on exit and on a crash, so a panic message still reaches the user.
- A full redraw key (Ctrl-l, as in Vim) and a full redraw after a resume (SIGCONT) or a resize.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A test starts paw with a sandboxed plugin (or a stand-in host) that writes to stdout and stderr, and the terminal screen (T.render or the golden screen) shows none of that text
- [ ] #2 A test calls a library write to fd 2 inside paw (for example io.stderr from a Lua device or an FFI write) and the screen stays correct; the text is in the log
- [ ] #3 A panic still prints its message on the terminal after paw restores it
- [ ] #4 Ctrl-l redraws the whole screen; a test with real keys
- [ ] #5 docs: the troubleshooting guide says where plugin output goes and how to read it
- [ ] #6 Audit (owner, 2026-11-24: a more stable terminal UI): list each other way the screen can go out of step with paw's frame (wide and combining characters, emoji, tabs and control characters in names, resize during a draw, a slow or stalled terminal, SIGCONT, alternate screen and mouse modes after a crash, terminals without synchronized output), each with how to reproduce it and a proposed fix, as Changes for the orchestrator; fix in this ticket only what is small and certain
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
Started 2026-11-24: branch tui-output, base 427be393.
<!-- SECTION:NOTES:END -->
