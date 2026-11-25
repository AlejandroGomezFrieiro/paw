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

## Check GitHub access

The dev shell includes `gh`. In the terminal that will open the pull
request, run:

```sh
nix develop -c gh auth status --hostname github.com
nix develop -c gh repo view AlejandroGomezFrieiro/paw \
  --json nameWithOwner,viewerPermission
```

If GitHub CLI asks you to sign in, run
`nix develop -c gh auth login --hostname github.com --git-protocol https --web`.
If GitHub refuses a push that changes a workflow, run
`nix develop -c gh auth refresh --hostname github.com --scopes workflow`
and approve the request in your browser.

A session in a sandbox may not see the login from your terminal. Run
`gh` from the signed-in terminal in that case. Keep tokens out of the
checkout and out of the agent's chat.

## Set up `pi`

Start `pi` in the checkout and approve project trust after you review the
configuration. Pi reads `AGENTS.md`, loads the skills in `.claude/skills`,
and installs the packages in `.pi/settings.json`. The package list covers
the agent team, pi-lens, MCP, the browser, terminal output, and cache statistics.
The Teal server is in `.pi-lens.json`. Automatic format and fixes are off.

To add the Matt Pocock skills, clone them into your Pi skill folder:

```sh
git clone --depth 1 https://github.com/mattpocock/skills.git \
  ~/.pi/agent/skills/mattpocock-skills
```

Use `git pull` in that clone to update the skills. Start a new session after
installation. Use `/skill:retro` to start a retrospective. Agents can load
skills by name with the `Skill` tool. The paw reviewer uses `code-review`.

## Assign a ticket in `pi`

Start the `Agent` call's `description` with `TASK-<id>:` and add a short
summary. Use the full ID for a child ticket, such as `TASK-<parent>.<child>:`.
Use the ticket's `agent:` label to select the builder or worker, and use a
separate call for each assignment. Pi reads the title from Backlog and shows
the assignment in `/agents`. The footer shows up to three active agents and
a count of the rest. Use `/agents` for the full list.

## Check `pi` after a change

Run `node tools/pi-smoke.mjs` after Pi has installed the project packages.
The check needs Node.js 24 and Pi on `PATH`. It uses a scratch checkout and a
local HTTP server. It needs no provider credentials and makes no paid requests.
The pre-commit hook runs it when you stage a Pi configuration or test change.

The project sets GPT-6.2 Sol at `medium` in `.pi/settings.json` and the paw
agent files in `.pi/agents/`. The project hook sends that model only to the
OpenAI provider on OpenRouter. If that provider is down, a request fails
instead of switching providers. Use `/cache-optimizer stats` to inspect
cache use. A cache hit alone does not prove which provider served a request.

Pi uses the shell and Vale hooks from Claude Code. Its comment hook flags
possible narration for review. It does not remove comments.
Pi has no sandbox. The limits of `nix run .#agent` apply to Claude Code
only, and a command of Pi can read and write each file of your account.
Run Pi in a container when the work needs that limit.
