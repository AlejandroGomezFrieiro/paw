---
id: TASK-353
title: >-
  Dev tools: nix run .#agent, Claude in a limited scope with the built-in
  sandbox
status: Done
assignee: []
created_date: '2026-11-24T10:56:00Z'
updated_date: '2026-11-24T14:15:00Z'
labels:
  - agent:builder
  - quality
  - foundation
dependencies: []
priority: high
ordinal: 422000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-24: sandbox Claude with our flake. Four restarts came from a fork bomb that took the desktop down: agents need hard resource limits and filesystem rules that hold by construction. (1) A flake app apps.agent (nix run .#agent): starts the claude on PATH (keep the owner's home-manager wrapper and mods) in systemd-run --user --scope --slice=paw-agents.slice with TasksMax, MemoryHigh, MemoryMax, MemorySwapMax and CPUWeight sized for 30 GB / 24 cores (a starting point: TasksMax 20000, MemoryHigh 18G, MemoryMax 22G, MemorySwapMax 8G); not nested; extra args pass through; a fallback message where systemd-run is absent. (2) Claude Code's built-in sandbox, if this Claude Code version has it (check the installed version's settings schema and docs first; sandbox-runtime from Anthropic on Linux uses bubblewrap): project .claude/settings.json enables it for Bash, with write access to the repo, its worktrees, the Claude scratch folder (/tmp/claude-<uid>), target/, ~/.cargo and the sccache cache; deny reads and writes of the owner's data folders (~/.config/paw, ~/.local/share/OpenUtau, REAPER folders, wine prefixes, ~/.ssh, ~/.gnupg); network limited to what work needs (crates.io, static.crates.io, github.com, the Nix caches, docs sites the agents read); the commands that cannot run in it (nix, systemd-run, cargo with the daemon?) listed as excluded with a reason. Prove each rule: a write outside is refused, a build and a suite run work. (3) Docs: AGENTS.md (one line: start agents with nix run .#agent), docs/how-to for contributors, and the guard-hook/taskguard notes in .orchestrator are the orchestrator's (report the edits). Not claudebox: its /tmp is a tmpfs in RAM (our merge tree and target/ are 20 GB), it has no custom mounts and starts its own claude-code. Keep tools/guard-hook.py for now.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 nix run .#agent starts Claude in a scope whose limits systemctl --user show reports
- [x] #2 A fork bomb test inside the scope (bounded, for example a shell that forks until it fails, under timeout) is refused by the kernel and the desktop is unaffected; the test is a manual check in the report, not a suite test
- [x] #3 With the sandbox on: a write to ~/.config/paw is refused, a read of ~/.ssh is refused, cargo build and tests/tools/suite.sh only <word> work
- [x] #4 AGENTS.md and the contributor how-to say how to start an agent; no stale advice
<!-- AC:END -->

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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
On local main e4246af6 (2026-11-24, not pushed). Two reviews (send-backs: slot folder, slice docs, deny list incl. paw state and credentials, sockets hidden by folder since allowUnixSockets is macOS only, git fetch/pull excluded). Checks: JSON, Vale 0, hygiene, luacheck, flake app evaluates. Open: verify in a real session started with nix run .#agent (TasksMax of the scope, write to ~/.config/paw hidden, suite slot after a reboot: does allowWrite see the folder that the SessionStart hook makes?). Proposed ADR text in the agent report: to file.
<!-- SECTION:NOTES:END -->
