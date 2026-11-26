# The machine's queue for cargo, sourced by tools/bin/cargo and tools/queue.sh.
# The folder is fixed, not $TMPDIR, so that every sandbox shares it.
PAW_CARGO_LOCKS=${PAW_CARGO_LOCKS:-/tmp/paw-suite-locks}
PAW_CARGO_SLOTS=${PAW_CARGO_SLOTS:-3}
paw_cores=$(nproc 2> /dev/null || echo 4)
PAW_CARGO_JOBS=$((paw_cores / PAW_CARGO_SLOTS))
[ "$PAW_CARGO_JOBS" -ge 1 ] || PAW_CARGO_JOBS=1
PAW_HEAVY=${PAW_HEAVY:-heavy}
