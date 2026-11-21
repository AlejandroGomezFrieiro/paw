#!/usr/bin/env python3
"""Run a Lua script in paw without a terminal, with scratch XDG_* folders
and HOME, as the other profile scripts do.

    bench/profile/headless.py <script.lua> [args...]

PAW (default: the newer of target/profiling/paw and target/release/paw)
and BENCH_TMP (default /tmp/paw-bench) can be set. WRAP is a command put
before paw (split on spaces), for heaptrack or perf.
"""
import os
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(os.path.dirname(here))
paw = os.environ.get("PAW")
if not paw:
    cands = [p for p in (os.path.join(repo, "target/profiling/paw"), os.path.join(repo, "target/release/paw")) if os.path.exists(p)]
    paw = max(cands, key=os.path.getmtime)
scratch = os.path.join(os.environ.get("BENCH_TMP", "/tmp/paw-bench"), "profile", "headless")
for d in ("config", "data", "state", "cache"):
    os.makedirs(os.path.join(scratch, d), exist_ok=True)
env = dict(os.environ, HOME=scratch, XDG_CONFIG_HOME=scratch + "/config", XDG_DATA_HOME=scratch + "/data",
           XDG_STATE_HOME=scratch + "/state", XDG_CACHE_HOME=scratch + "/cache",
           DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent/bus")
wrap = os.environ.get("WRAP", "").split()
sys.exit(subprocess.run(wrap + [paw, "--clean", "--no-plugins", "-l"] + sys.argv[1:], env=env).returncode)
