#!/usr/bin/env python3
"""The functions that cost the most in a folded stack file (from
drive.py --luaprof or --record): self and inclusive share of the samples.

    bench/profile/top.py <file.folded> [n] [--thread NAME] [--under FRAME]

--thread keeps the stacks of one thread (perf folded stacks start with the
thread's name); --under keeps the stacks that pass through a frame that
contains FRAME, so that the inclusive table shows what that frame calls.
"""
import sys


def main():
    args = sys.argv[1:]
    thread = under = None
    if "--thread" in args:
        i = args.index("--thread")
        thread = args[i + 1]
        del args[i:i + 2]
    if "--under" in args:
        i = args.index("--under")
        under = args[i + 1]
        del args[i:i + 2]
    path = args[0]
    n = int(args[1]) if len(args) > 1 else 25
    selfs, incl, total = {}, {}, 0
    for line in open(path):
        line = line.rstrip("\n")
        if not line:
            continue
        stack, _, count = line.rpartition(" ")
        try:
            count = int(count)
        except ValueError:
            continue
        frames = stack.split(";")
        if thread and not frames[0].startswith(thread):
            continue
        if under:
            hit = [i for i, f in enumerate(frames) if under in f]
            if not hit:
                continue
            frames = frames[hit[0]:]
        total += count
        # The Lua profiler ends each stack with the VM state: [I] [N] [C] [G] [J].
        leaf = frames[-1]
        if leaf.startswith("[") and len(frames) > 1:
            leaf = frames[-2] + " " + leaf
        selfs[leaf] = selfs.get(leaf, 0) + count
        for f in set(frames):
            incl[f] = incl.get(f, 0) + count
    print(f"{total} samples")
    print("self:")
    for f, c in sorted(selfs.items(), key=lambda kv: -kv[1])[:n]:
        print(f"  {100 * c / total:5.1f}%  {f}")
    print("inclusive:")
    for f, c in sorted(incl.items(), key=lambda kv: -kv[1])[:n]:
        print(f"  {100 * c / total:5.1f}%  {f}")


main()
