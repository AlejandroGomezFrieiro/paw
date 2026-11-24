#!/usr/bin/env bash
# Starts Claude Code (the `claude` on PATH) in a systemd scope with hard
# limits on tasks, memory and CPU. A command that runs away (a fork bomb, a
# build that uses all the memory) then stops at the limit of the scope, and
# the desktop stays usable. `nix run .#agent -- <arguments of claude>`.
#
# The limits suit a machine of 30 GB and 24 cores. To change one, set the
# variable of the same name, for example PAW_AGENT_MEMORY_MAX=12G.
set -euo pipefail

slice=paw-agents.slice
tasks_max=${PAW_AGENT_TASKS_MAX:-20000}
memory_high=${PAW_AGENT_MEMORY_HIGH:-18G}
memory_max=${PAW_AGENT_MEMORY_MAX:-22G}
memory_swap_max=${PAW_AGENT_MEMORY_SWAP_MAX:-8G}
# Below the default weight of 100: the desktop gets the CPU first.
cpu_weight=${PAW_AGENT_CPU_WEIGHT:-50}

# A claude started from an agent already has the limits of its scope.
if grep -q "/$slice/" /proc/self/cgroup; then
  echo "agent: already in $slice, claude starts in the same scope" >&2
  exec claude "$@"
fi

if ! command -v systemd-run > /dev/null || ! systemctl --user show-environment > /dev/null 2>&1; then
  echo "agent: no systemd user manager, claude starts with no limits on tasks, memory and CPU" >&2
  exec claude "$@"
fi

# The limits above hold for each scope. Only a user unit of the slice
# limits all the agents together (docs/how-to/run-a-coding-agent-with-limits.md).
if [ "$(systemctl --user show -p MemoryMax --value "$slice")" = infinity ]; then
  echo "agent: $slice has no MemoryMax, so the agents together have no limit; see docs/how-to/run-a-coding-agent-with-limits.md" >&2
fi

exec systemd-run --user --scope --quiet --collect \
  --slice="$slice" --unit="paw-agent-$$" \
  --property=TasksMax="$tasks_max" \
  --property=MemoryHigh="$memory_high" \
  --property=MemoryMax="$memory_max" \
  --property=MemorySwapMax="$memory_swap_max" \
  --property=CPUWeight="$cpu_weight" \
  -- claude "$@"
