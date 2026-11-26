#!/usr/bin/env python3
"""A hook of Claude Code (.claude/settings.json, PreToolUse on Bash) and of
pi (.pi/extensions/paw.ts, before a command of the tool `bash`).

It refuses the commands that the rules of AGENTS.md forbid, before they run.
Each one once cost a run of hours or put the machine under a load that it
could not carry. The refusal goes back to the agent (exit 2) with the rule
and what to run instead. It reads each command of the line (split at ;, &&,
||, | and new lines), after `nix develop -c`, `timeout N`, `env` and
assignments, so a text that only names a command (an echo, a heredoc of a
brief) passes.
"""
import json
import os
import re
import shlex
import shutil
import sys

RULES = [
    (lambda w: w[:2] == ["cargo", "test"] and "--workspace" in w,
     "`cargo test --workspace` builds a debug paw and starts the whole Lua suite. "
     "Test one crate: `cargo nextest run -p <crate>`. The full suite is the orchestrator's, before a push."),
    (lambda w: w[:1] == ["cargo"] and builds_gui(w),
     "The window (crates/paw-gui) is paused: do not build, check or test it (AGENTS.md)."),
    (lambda w: bool(w) and w[0].endswith("tests/tools/loaded.sh"),
     "tests/tools/loaded.sh puts a heavy load on the machine: only the owner starts it."),
    (lambda w: bool(w) and w[0].endswith("tests/tools/e2e.sh"),
     "The end-to-end tests are for CI and the release check: only the owner, or the agent that builds them, runs them."),
    (lambda w: w[:2] == ["cargo", "fmt"] and "--check" not in w,
     "`cargo fmt` rewrites files, and paw is not rustfmt-clean: it once rewrote 158 files of one crate. "
     "Keep the style of the file by hand; `cargo fmt --check -p <crate>` only reads."),
    (lambda w: w[:1] == ["cargo"] and builds_release(w),
     "Release builds are for CI and for bench/. The tests and the GIFs use the dev build, "
     "which tests/tools/env.sh builds when it is missing."),
    (lambda w: bool(w) and w[0] != "cargo" and w[0].endswith("/cargo") and not w[0].endswith("tools/bin/cargo"),
     "Run cargo by its name. The dev shell's cargo (tools/bin/cargo) waits for a slot of the machine's queue."),
    (lambda w: w[:1] == ["cargo"] and not queued_cargo(),
     "This shell has no cargo queue: start the agent in the dev shell again (direnv reload, or nix develop), "
     "or run tools/bin/cargo."),
    (lambda w: w[:1] == ["heavy"] and any(x in ("--", "--slots", "--pool", "--dir") for x in w) and "--status" not in w,
     "The cargo queue sets the slots of heavy. Run cargo, and tools/queue.sh to see the queue."),
    (lambda w: w[:3] == ["backlog", "task", "edit"] and any(x in ("-l", "--label") or x.startswith("--label=") for x in w),
     "`backlog task edit -l` replaces every label of the ticket. "
     "Use `--add-label <label>` or `--remove-label <label>`."),
]

def builds_gui(words):
    """Whether a cargo command names paw-gui as its package (not with --exclude)."""
    for flag, value in zip(words, words[1:] + [""]):
        if flag in ("-p", "--package") and value == "paw-gui":
            return True
        if flag == "--manifest-path" and "paw-gui" in value:
            return True
        if flag in ("-ppaw-gui", "--package=paw-gui") or flag.startswith("--manifest-path=") and "paw-gui" in flag:
            return True
    return False


RELEASE_PROFILES = {"release", "profiling", "dist", "bench"}


def builds_release(words):
    """Whether a cargo command builds with a release profile."""
    for i, word in enumerate(words):
        if word in ("--release", "-r"):
            return True
        if word == "--profile" and i + 1 < len(words) and words[i + 1] in RELEASE_PROFILES:
            return True
        if word.startswith("--profile=") and word.split("=", 1)[1] in RELEASE_PROFILES:
            return True
    return False


def queued_cargo():
    """Whether `cargo` on PATH is the dev shell's cargo of tools/bin."""
    found = shutil.which("cargo") or ""
    return found.endswith("tools/bin/cargo")


QUEUE_ESCAPE = re.compile(r"(^|[\s;&|(])(export\s+)?(HEAVY_\w+|CI|PAW_CARGO\w*|CARGO_BUILD_JOBS)=")


PREFIXES = {"env", "nice", "time", "command", "exec"}


def words_of(segment):
    try:
        words = shlex.split(segment, comments=True)
    except ValueError:
        return []
    while words:
        head = words[0]
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", head) or head in PREFIXES:
            words = words[1:]
        elif head == "timeout" and len(words) > 1:
            words = words[2:]
        elif head == "nix" and words[1:3] == ["develop", "-c"]:
            words = words[3:]
        elif head in ("sh", "bash") and words[1:2] and not words[1].startswith("-"):
            words = words[1:]
        else:
            break
    return words


def main():
    data = json.load(sys.stdin)
    command = (data.get("tool_input") or {}).get("command") or ""
    # A heredoc body is text, not commands: drop it.
    command = re.sub(r"<<-?\s*'?\"?(\w+)'?\"?.*?\n.*?\n\1\s*(\n|$)", "\n", command, flags=re.S)
    if QUEUE_ESCAPE.search(command):
        print("Refused by the project hook (tools/guard-hook.py): the variables of the cargo queue "
              "(HEAVY_*, CI, PAW_CARGO*, CARGO_BUILD_JOBS) are set by tools/bin/cargo, not by a command.", file=sys.stderr)
        sys.exit(2)
    for segment in re.split(r"\|\||&&|[;|\n&()]", command):
        words = words_of(segment.strip())
        for refused, why in RULES:
            if refused(words):
                print(f"Refused by the project hook (tools/guard-hook.py): {why}", file=sys.stderr)
                sys.exit(2)
    sys.exit(0)


if __name__ == "__main__":
    main()
