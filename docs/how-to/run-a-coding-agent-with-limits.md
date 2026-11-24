# How to run a coding agent with limits

<!-- tags: agent claude-code -->

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

## Know what the sandbox allows

The project settings in `.claude/settings.json` turn on the sandbox of
Claude Code for each command that the agent runs. The settings apply
whether or not you start the agent with `nix run .#agent`.

- A command can write in the checkout, in the temporary folder of Claude
  Code, in `~/.cargo`, in `~/.cache/sccache` and in `/tmp/paw-suite-locks`,
  where `tests/tools/suite.sh` keeps the slots of the machine.
- A command can't read or write `~/.config/paw`, `~/.local/share/OpenUtau`,
  `~/.config/REAPER`, `~/.wine`, `~/.local/share/wineprefixes`, `~/.ssh`
  and `~/.gnupg`. In the sandbox, each of these folders is empty, and a
  file written there is gone when the command ends.
- A command can reach crates.io, GitHub, the Nix cache and the Rust
  documentation sites, and no other host.
- A command can open Unix sockets, because the tests start paw with a
  control socket.

Some commands run outside the sandbox:

- `nix build` and `nix flake check`, because they talk to the Nix daemon,
  and the daemon builds in a sandbox of its own.
- `git push`, because it needs the keys in `~/.ssh`.

A command that the sandbox refuses fails with an error such as
`Read-only file system`, and the agent can't run it outside the sandbox. If
the work needs another folder or host, add it to `.claude/settings.json`
in a commit of its own, so that each agent gets the same rules.
