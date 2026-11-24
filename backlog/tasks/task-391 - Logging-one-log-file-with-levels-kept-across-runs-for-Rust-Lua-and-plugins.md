---
id: TASK-391
title: 'Logging: one log file with levels, kept across runs, for Rust, Lua and plugins'
status: Done
assignee: []
created_date: '2026-11-24T18:05:00Z'
updated_date: '2026-11-24T20:34:00Z'
labels:
  - agent:builder
dependencies:
  - TASK-384
priority: high
ordinal: 460000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner, 2026-11-24: set up logging and tracing so paw keeps a record of issues. Today there are three places that do not meet: the messages list (paw.notify, last 500, in memory), the kernel log ring (paw.api.log, last 1000 lines, in memory, no command shows it) and stderr.log (Rust eprintln!, plugins, libraries; emptied at each start, ADR 0042). No logging crate is used; nothing survives a crash.

Design to propose (a short ADR, because it adds a crate, a file, an option and a command):
- The tracing crate in the Rust crates, one subscriber in the program that writes paw.log in the state folder (XDG_STATE_HOME/paw) with time, level and target; the previous runs kept (paw.log.1 .. paw.log.N) and a size cap.
- A panic writes its message and backtrace to the log before the terminal is restored.
- paw.notify and paw.api.log write to the same log (target lua); the output of plugin hosts and stderr.log lines go in with target plugin / stderr (or stderr.log is folded in: say which).
- The audio thread never logs: no allocation, no lock. It keeps counters (as lua.drops, xruns) that the kernel thread logs.
- paw.opt.loglevel, per target (for example {default = 'info', plugin = 'debug'}), and an environment variable for the start (PAW_LOG).
- :log opens the log in a view (current run; :log! the previous run). :messages stays as it is.
- The eprintln! calls outside tests move to tracing macros.
Add tracing and tracing-subscriber (and tracing-appender if used) to .claude/skills/rust-skills/paw-crates.md with the reason.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A proposed ADR in the report (scratchpad pending-arch) for the owner; the code follows it
- [ ] #2 paw.log in the state folder gets Rust, Lua (paw.notify, paw.api.log) and plugin lines with time, level and target; the previous runs are kept, with a size cap; tests in a sealed home
- [ ] #3 A panic leaves its message and backtrace in the log, and the terminal shows it after it is restored; a test
- [ ] #4 No logging on the audio thread: a test or a check (the no-allocation check) guards it
- [ ] #5 paw.opt.loglevel per target and PAW_LOG change what is written; a test
- [ ] #6 :log opens the log of this run, :log! the previous run; a test with real keys
- [ ] #7 No eprintln! outside tests and benches in the crates (a check in tools/ or clippy's print_stderr lint)
- [ ] #8 Docs: state-files.md, a how-to (find out what went wrong: the log, :log, loglevel), cmdline.md, options; Vale 0
- [ ] #9 Defaults as the note of 2026-11-24 says: info to the file, a debug flight recorder written on a panic, an error or :log dump, the trail of user actions, the start header, rate-limited audio counters, repeated lines folded, 5 runs of 10 MB; a test for the flight recorder on a panic and on an error
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
Owner, 2026-11-24: the default log level must be enough to trace crashes and bugs. Defaults to build (the ADR proposes them, the owner accepts):
- The file gets info and above for every target by default.
- A flight recorder: debug and above for every target in an in-memory ring (about the last 2000 events, no file write). paw writes the ring to the log on a panic, a crash signal (with TASK-389), an error-level event, and on :log dump. So a crash log has the detail before it, with no cost in a normal run.
- The trail at info: each user action as one line (the command or key map name and its undo step label), so a log shows what led to a bug. Not each motion key.
- A header at each start: paw version and commit, OS, terminal, audio backend, sample rate and block size, the extensions and plugins loaded, and the options that differ from their default.
- The audio thread's counters (xruns, dropped events, late plugin blocks) at warn when they change, at most one line per second per counter.
- The same line repeated: one line with a count.
- Keep 5 runs, 10 MB each at most.
- No secrets in the log: no environment dump, paths under the home folder written as ~.

Owner, 2026-11-24: ADR 0043 accepted, with a lock so that a second session at the same time writes its own file (paw.2.log) and never rotates a live session's log. loglevel stays text in the RUST_LOG syntax, the same for the option and PAW_LOG. Work: 4e4462db on worktree-agent-a498b74dcaa5c1ddc. Follow-up: flake.nix sets PAW_COMMIT so the start header names the commit.

STATE 2026-11-24 (session paused): branch worktree-agent-a498b74dcaa5c1ddc, head 4e4462db. ADR 0043 accepted (architecture/decisions/0043-one-log.md; update it with the lock when the builder's draft lands). OPEN: the builder adds the session lock (flock on paw.log.lock; a second session writes paw.2.log, never rotates a live log; stderr.log fold per session), loads teal/lua-testing/rust-testing and fixes what they find, and runs tests/clock.lua 30x under -j4 (one failure seen: timers_due 1, want 0). NEXT: opus review (contract: tracing crate, paw.api.log level, :log, loglevel, PAW_LOG, audio counters, panic hook), merge check, then the OWNER fast-forwards because the branch changes .claude/skills/rust-skills/paw-crates.md: git merge --ff-only <sha> in the main checkout. Then architecture: 06-runtime, 08-concepts, 10-quality items; decisions/README.md and 09-decisions.md rows for 0043.

Builder done: head 1c751ad0 (session lock: flock on paw.log.lock, a second session takes slot paw.2.log / stderr.2.log, up to 9; two tests; ADR 0043 text in architecture/decisions with the lock). Skills loaded, nothing to change. NEXT: opus review, merge check, owner ff (branch changes .claude/skills/rust-skills/paw-crates.md).

Opus review of 1c751ad0: merge after fixes. Hard: (1) main.rs:819-820 an ending error prints twice (tracing echo + say); (2) main.rs:547-560 + logging/mod.rs:376-380 panic hook deadlock if a panic happens while the Book mutex is held (files() relocks). Soft: :log dump test; PAW_LOG errors silent in clients and paw-mcp; TERM missing in header; no upper bound after the cap; debug paw.api.log fills the log_get ring; audio_counters duplicates COUNTERS; fold header names stderr.log for every slot; output_log with no slot empties a live slot-1 file. Sent to the builder. Note: the workspace print_stderr lint fails clippy for paw-gui (paused, flake skips it): owner to decide.

Builder done: head 89e4ceb1, all review fixes (print once, panic hook try_lock, :log dump test, PAW_LOG errors in clients, TERM, 2x cap bound, debug out of the ring, slot file names, no-slot append). NEXT: merge 89e4ceb1 (not 1c751ad0) in the merge tree, merge check, owner ff.

On main in merge 6b64a180 (2026-11-24), set Done by tools/board-sync.sh.
<!-- SECTION:NOTES:END -->
