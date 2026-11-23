#!/usr/bin/env python3
"""Two builds of paw in one scenario, in turns: A B A B ..., and the median,
smallest and largest value of each measure for each build.

    bench/profile/compare.py <paw A> <paw B> <pairs> <scenario> [drive.py options]

Run it under bench/profile/run.sh's lock and cores, or as run.sh does:
    flock <lock> taskset -c 16-23 bench/profile/compare.py ...

The measures: for startup the time to the first frame; for keys the
kernel's processor time and the time to the first frame of each key; for
idle, play and record the processor share of the kernel thread and its
instructions (perf stat, when --perf is given); for repeat the kernel's
processor time per round, the time from each key to its first frame, and
(with --budget) the callbacks over the budget: the slow-key warnings.
"""
import json
import os
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))


def measures(rec):
    out = {}
    s = rec.get("scenario")
    if s == "startup":
        out[f"first frame ms ({rec['what']})"] = rec["first_frame_ms"]
    elif s == "keys" and "key" in rec:
        out[f"{rec['key']}: kernel ms"] = rec.get("kernel_cpu_ms")
        out[f"{rec['key']}: first frame ms"] = rec.get("first_frame_ms")
    elif s in ("idle", "idle-armed", "play", "record"):
        out["kernel cpu %"] = rec["cpu_percent"].get("kernel", 0)
        out["frames/s"] = rec["frames_per_s"]
        kernel = rec.get("perfstat", {}).get("kernel", {})
        if "instructions:u" in kernel:
            out["kernel Ginstructions/s"] = kernel["instructions:u"] / 1e9 / rec["seconds"]
    elif s == "repeat":
        out["kernel ms per round"] = rec["kernel_cpu_ms_per_round"]
        if "slow" in rec:
            out["callbacks over the budget"] = sum(times for _, times, _ in rec["slow"])
        for k, v in rec.items():
            if k.startswith("first_frame_ms "):
                out[k[len("first_frame_ms "):] + ": first frame ms (median of the rounds)"] = v[0]
    return out


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    a, b, pairs, rest = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4:]
    results = {"A": {}, "B": {}}
    for i in range(pairs):
        for name, binary in (("A", a), ("B", b)):
            run = subprocess.run([sys.executable, os.path.join(here, "drive.py")] + rest +
                                 ["--paw", binary, "--label", f"compare-{name}"],
                                 capture_output=True, text=True)
            for line in run.stdout.splitlines():
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                for k, v in measures(rec).items():
                    if v is not None:
                        results[name].setdefault(k, []).append(v)
            if run.returncode != 0:
                print(run.stderr[-2000:], file=sys.stderr)
    print(f"A = {a}\nB = {b}\n{pairs} pairs, load {open('/proc/loadavg').read().split()[0]} at the end")
    for k in results["A"]:
        row = [k]
        for name in ("A", "B"):
            vals = sorted(results[name].get(k, []))
            if vals:
                row.append(f"{vals[len(vals) // 2]:.2f} ({vals[0]:.2f} to {vals[-1]:.2f})")
            else:
                row.append("-")
        print(" | ".join(row))


main()
