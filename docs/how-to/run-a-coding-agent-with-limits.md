# How to run a coding agent with limits

<!-- tags: agent claude-code pi -->

The guide shows you how to start Claude Code on a checkout of paw, so
that the processes it starts can't use up the processes, the memory or the
processor of the machine, and can't write outside the checkout and the
caches of the build. It assumes Nix with flakes, a Linux desktop with a
systemd user session, and the `claude` command on your `PATH`.

## Start the agent

1. In the checkout, run `nix run .#agent`. To give arguments to Claude
   Code, put them after `--`, for example `nix run .#agent -- --resume`.
2. Work with Claude Code as usual.

The command starts the `claude` of your `PATH`, so your own wrapper,
plugins and settings stay in use. It starts `claude` in a systemd scope in
`paw-agents.slice`, with these limits:

| Limit | Value | Variable to change it |
| --- | --- | --- |
| `TasksMax` (processes and threads) | 20000 | `PAW_AGENT_TASKS_MAX` |
| `MemoryHigh` (the kernel slows the scope down above it) | 18G | `PAW_AGENT_MEMORY_HIGH` |
| `MemoryMax` (the kernel stops a process above it) | 22G | `PAW_AGENT_MEMORY_MAX` |
| `MemorySwapMax` | 8G | `PAW_AGENT_MEMORY_SWAP_MAX` |
| `CPUWeight` (the default of other programs is 100) | 50 | `PAW_AGENT_CPU_WEIGHT` |

The values suit a machine with 30 GB of memory and 24 processor cores. On
a smaller machine, set lower values, for example
`PAW_AGENT_MEMORY_HIGH=8G PAW_AGENT_MEMORY_MAX=10G nix run .#agent`.

A command that forks without end, such as a fork bomb, gets an error from
the kernel when the scope reaches `TasksMax`, and the rest of the desktop
keeps working. An agent that runs `nix run .#agent` again stays in the
scope that it is in. If the machine has no systemd user manager, the
command says so and starts `claude` with no limits.

To see the limits of a running agent, run
`systemctl --user list-units 'paw-agent-*'` to find the name of its scope,
and then `systemctl --user show -p TasksMax -p MemoryMax paw-agent-<number>.scope`.

## Limit all the agents together

Each agent gets its own scope, and the limits of a scope hold for that
agent only. Two agents can use twice the memory of one, so the machine
can still run out of memory when several agents work at the same time.
To limit them together, give the slice a user unit:

1. Write the file `~/.config/systemd/user/paw-agents.slice`:

   ```ini
   [Unit]
   Description=Coding agents of paw

   [Slice]
   TasksMax=30000
   MemoryHigh=20G
   MemoryMax=24G
   MemorySwapMax=8G
   CPUWeight=50
   ```

2. Run `systemctl --user daemon-reload`.

If you use home-manager, define the same slice with
`systemd.user.slices.paw-agents` in place of the file. Without the unit,
`nix run .#agent` says that the slice has no `MemoryMax`, and only the
limits of each scope hold.

## Know what the sandbox allows

The project settings in `.claude/settings.json` turn on the sandbox of
Claude Code for each command that the agent runs. The settings apply to
every session of Claude Code in the checkout, whether or not you start it
with `nix run .#agent`.

- A command can write in the checkout, in the temporary folder of Claude
  Code (`/tmp/claude-` and your user id), in `~/.cargo`, in
  `~/.cache/sccache`, in `~/.cache/nix`, in `~/.groma` and in
  `/tmp/paw-suite-locks`. A hook of the settings makes
  `/tmp/paw-suite-locks` when a session starts, and `tests/tools/suite.sh`
  keeps the slots of the machine there.
- A command can't read `~/.config/paw`, `~/.local/state/paw`,
  `~/.cache/paw`, `~/.local/share/OpenUtau`, `~/.config/REAPER`, `~/.wine`,
  `~/.local/share/wineprefixes`, `~/.ssh` and `~/.gnupg`. In the sandbox,
  each of these folders is an empty folder in memory. A command can write a
  file there without an error, but the file is gone when the command ends,
  and the real folder doesn't change.
- A command can't read `~/.config/gh`, `~/.claude.json` and
  `~/.claude/.credentials.json`, which hold sign-in tokens.
- A command can reach crates.io, GitHub, the Nix cache and the Nix flake
  registry, and the Rust documentation sites, and no other host.
- A command can open Unix sockets, because the tests start paw with a
  control socket, and `nix` talks to the Nix daemon through one. On Linux,
  the sandbox allows all Unix sockets or none. So the settings hide the
  folders where the sockets of your desktop are: `/run/user` (the session
  bus, PipeWire and a paw that you have open), `/run/dbus` and
  `/tmp/.X11-unix` (your X display). The Nix daemon builds and downloads
  in a sandbox of its own, so `nix develop`, `nix build` and
  `nix flake check` work in the sandbox.
- The tests of `extensions/interop` that open a project in REAPER start
  REAPER in a sandbox of their own, which can't start inside the sandbox of
  Claude Code. The suite skips them there, and says why.

The commands of git that reach a remote over SSH, `git push`, `git fetch`,
`git pull` and `git ls-remote`, run outside the sandbox, because they need
the keys in `~/.ssh`.

A command that the sandbox refuses fails with an error such as
`Read-only file system`, and the agent can't run it outside the sandbox. If
the work needs another folder or host, add it to `.claude/settings.json`
in a commit of its own, so that each agent gets the same rules.

## Know what pi does

pi in this checkout uses the rules of `AGENTS.md` and the skills of
`.claude/skills` (`.pi/settings.json`). The extension
`.pi/extensions/paw.ts` runs the same hooks as Claude Code:
`tools/guard-hook.py` refuses a command that `AGENTS.md` forbids, and
`tools/vale-hook.sh` runs Vale on each Markdown file that an edit or a
write changes.

pi has no sandbox. The limits of `nix run .#agent` apply to Claude Code
only, and a command of pi can read and write each file of your account.
Run pi in a container when the work needs that limit.
