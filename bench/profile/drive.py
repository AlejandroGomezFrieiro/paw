#!/usr/bin/env python3
"""Drive paw in a private pseudo-terminal and measure it: the scenarios of
bench/profile.md.

    bench/profile/drive.py <scenario> [options]

Scenarios: startup, idle, idle-armed, keys, play, record, long, and repeat
(the keys of --keys, --times times, under the probes: to profile one key).

paw runs with --clean --no-plugins --audio null, its XDG_* folders and HOME
in a scratch folder, and a control socket of its own. The driver plays the
terminal: it answers the terminal probe, writes the keys and reads what paw
draws. A frame is what paw sends between the start and the end of a
synchronized update (modes 2026 h and l).

What it measures:
  - processor time of each thread of paw, from /proc/<pid>/task/<tid>/schedstat
    (nanoseconds on the processor; independent of the clock's tick);
  - frames, and bytes written to the terminal, per frame and per second;
  - resident memory (VmRSS, VmHWM) and the Lua heap (collectgarbage);
  - per key: the time from the key to the end of the first frame after it
    and to the last frame before the screen is quiet, the bytes of those
    frames, and the processor time of the kernel thread.

Each scenario prints one JSON line per measurement to stdout and appends it
to <out>/results.jsonl.

Options (all optional):
  --paw PATH       the binary (default target/release/paw, or
                   target/profiling/paw when it is newer)
  --out DIR        where results and scratch go (default
                   $BENCH_TMP/profile, BENCH_TMP default /tmp/paw-bench)
  --project DIR    the project to open (default: made by project.lua in
                   <out>/project, 64 tracks, 2 000 clips, 50 000 notes)
  --empty          open no project
  --size COLSxROWS the terminal (default 187x56)
  --secs N         the length of idle, play, record (default 60) and long
                   (default 600)
  --wrap CMD       run paw under this command, split on spaces (heaptrack,
                   valgrind); the measured process is still paw itself
  --perf SECS      while playing or idle, also `perf stat` the process for
                   SECS seconds (instructions per thread)
  --record SECS    while playing or idle, also `perf record` it (dwarf call
                   graphs) for SECS seconds and write a flamegraph SVG
  --luaprof        while playing or idle, also run LuaJIT's profiler in the
                   kernel and write a flamegraph of the Lua functions
  --label TEXT     a label for the results and file names
  --reps N         repetitions of startup and of each moving key (default 5)
  --keys K1,K2     repeat: the keys, comma-separated, with Python escapes
  --times N        repeat: how many rounds (default 20); it also gives the
                   time from each key to its first frame (median, min, max)
  --setup LUA      Lua run in the kernel after the start, before measuring
  --budget MS      paw.opt.budget_ms (default 5, 0 is off): each callback
                   that takes longer is named once; keys lists them with
                   the key that ran them ("slow": name, times, last ms),
                   repeat at the end
"""

import json
import os
import pty
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import fcntl
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

SYNC_START = b"\x1b[?2026h"
SYNC_END = b"\x1b[?2026l"


def now_ms():
    return time.monotonic_ns() / 1e6


class Screen:
    """What paw writes to its terminal, read on a thread: frames and bytes."""

    def __init__(self, fd):
        self.fd = fd
        self.lock = threading.Condition()
        self.total = 0
        # (time the frame ended in ms, bytes from its start to its end)
        self.frames = []
        self.frame_bytes = 0
        self.in_frame = False
        self.last_byte = now_ms()
        self.tail = b""
        self.answered = 0
        self.closed = False
        self.keep = bytearray()
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        while True:
            try:
                chunk = os.read(self.fd, 1 << 16)
            except OSError:
                chunk = b""
            t = now_ms()
            with self.lock:
                if not chunk:
                    self.closed = True
                    self.lock.notify_all()
                    return
                self.total += len(chunk)
                self.last_byte = t
                if len(self.keep) < 1 << 20:
                    self.keep += chunk
                # The terminal probe ends with DA1 (ESC [ c); answer it so
                # that paw does not wait a second and a half for it.
                buf = self.tail + chunk
                if b"\x1b[c" in buf and self.answered < 1:
                    self.answered += 1
                    os.write(self.fd, b"\x1b[?62;22c")
                # Frames: count the bytes between the markers.
                pos = 0
                start_at = len(self.tail)
                while True:
                    i_s = buf.find(SYNC_START, pos)
                    i_e = buf.find(SYNC_END, pos)
                    if i_s < 0 and i_e < 0:
                        break
                    if i_e < 0 or (0 <= i_s < i_e):
                        if i_s + len(SYNC_START) > start_at:
                            self.in_frame = True
                            self.frame_bytes = 0
                        pos = i_s + len(SYNC_START)
                    else:
                        if i_e + len(SYNC_END) > start_at and self.in_frame:
                            self.frame_bytes += max(0, i_e - max(pos, start_at))
                            self.frames.append((t, self.frame_bytes))
                            self.in_frame = False
                            self.frame_bytes = 0
                        pos = i_e + len(SYNC_END)
                if self.in_frame:
                    self.frame_bytes += len(buf) - max(pos, start_at)
                self.tail = buf[-8:]
                self.lock.notify_all()

    def count(self):
        with self.lock:
            return len(self.frames)

    def wait_frames(self, n, timeout):
        """Wait until there are at least n frames; True if there are."""
        end = time.monotonic() + timeout
        with self.lock:
            while len(self.frames) < n and not self.closed:
                left = end - time.monotonic()
                if left <= 0:
                    return False
                self.lock.wait(left)
            return len(self.frames) >= n

    def wait_quiet(self, quiet_ms, timeout):
        """Wait until nothing was written for quiet_ms."""
        end = now_ms() + timeout * 1000
        while now_ms() < end:
            with self.lock:
                idle = now_ms() - self.last_byte
            if idle >= quiet_ms:
                return True
            time.sleep(min(quiet_ms - idle, 50) / 1000)
        return False


class Paw:
    def __init__(self, opts, project, extra_args=(), env_extra=None):
        self.opts = opts
        self.run = tempfile.mkdtemp(prefix="paw-prof.", dir="/tmp")
        os.chmod(self.run, 0o700)
        self.sock_path = os.path.join(self.run, "s")
        xdg = os.path.join(opts.out, "xdg", opts.label)
        shutil.rmtree(xdg, ignore_errors=True)
        for d in ("state", "cache", "config", "data"):
            os.makedirs(os.path.join(xdg, d))
        env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "TERM": "xterm-256color",
            "HOME": xdg,
            "XDG_STATE_HOME": xdg + "/state",
            "XDG_CACHE_HOME": xdg + "/cache",
            "XDG_CONFIG_HOME": xdg + "/config",
            "XDG_DATA_HOME": xdg + "/data",
            "XDG_RUNTIME_DIR": self.run,
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent/bus",
            "LANG": "C.UTF-8",
        }
        # PAW_RUNTIME: the Lua of a checkout (tools/dev-runtime.sh); LD_PRELOAD:
        # another allocator, for example.
        for k in ("LD_LIBRARY_PATH", "LUA_PATH", "LUA_CPATH", "PAW_RUNTIME", "LD_PRELOAD"):
            if k in os.environ:
                env[k] = os.environ[k]
        env.update(env_extra or {})
        argv = opts.wrap + [opts.paw, "--clean", "--no-plugins", "--audio", "null", "--listen", self.sock_path]
        argv += list(extra_args)
        if project:
            argv.append(project)
        cols, rows = opts.cols, opts.rows
        self.t0 = now_ms()
        pid, fd = pty.fork()
        if pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, cols * 8, rows * 16))
            # "Here" for the file picker: the project folder.
            os.chdir(project or opts.out)
            os.execvpe(argv[0], argv, env)
        self.child = pid
        self.fd = fd
        self.screen = Screen(fd)
        self.sock = None
        self.ids = 0
        self.pid = None

    # --- the control socket ---
    def connect(self, timeout=60):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if os.path.exists(self.sock_path):
                try:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.connect(self.sock_path)
                    self.sock = s
                    self.rfile = s.makefile("rb")
                    self.call("hello", {})
                    self.pid = int(self.eval("local f = io.open('/proc/self/stat'); local s = f:read('*a'); f:close(); return s:match('^%d+')"))
                    return
                except OSError:
                    pass
            time.sleep(0.02)
        raise RuntimeError("paw's control socket did not open")

    def call(self, method, params):
        self.ids += 1
        mine = self.ids
        self.sock.sendall((json.dumps({"id": mine, "method": method, "params": params}) + "\n").encode())
        while True:
            line = self.rfile.readline()
            if not line:
                raise RuntimeError("paw closed the socket")
            msg = json.loads(line)
            if msg.get("id") == mine:
                if "error" in msg:
                    raise RuntimeError(msg["error"])
                return msg.get("result")

    def eval(self, code, *args):
        return self.call("eval", [code] + list(args))

    # --- the process ---
    def threads(self):
        """{tid: (name, ns on the processor)} of paw's threads."""
        out = {}
        base = f"/proc/{self.pid}/task"
        try:
            tids = os.listdir(base)
        except OSError:
            return out
        for tid in tids:
            try:
                with open(f"{base}/{tid}/comm") as f:
                    name = f.read().strip()
                with open(f"{base}/{tid}/schedstat") as f:
                    ns = int(f.read().split()[0])
                # The main thread is the kernel; others of one name apart.
                if int(tid) == self.pid:
                    name = "kernel"
                elif name == "paw":
                    name = f"paw:{tid}"
                out[int(tid)] = (name, ns)
            except OSError:
                pass
        return out

    def kernel_ns(self):
        try:
            with open(f"/proc/{self.pid}/task/{self.pid}/schedstat") as f:
                return int(f.read().split()[0])
        except OSError:
            return 0

    def memory(self):
        out = {}
        try:
            with open(f"/proc/{self.pid}/status") as f:
                for line in f:
                    k, _, v = line.partition(":")
                    if k in ("VmRSS", "VmHWM", "RssAnon"):
                        out[k] = int(v.split()[0])
        except OSError:
            pass
        return out

    def lua_kb(self):
        return self.eval("return collectgarbage('count')")

    def key(self, data):
        os.write(self.fd, data)

    def quit(self, timeout=20):
        try:
            if self.sock:
                self.sock.sendall(b'{"id": null, "method": "eval", "params": ["paw.api.quit(0)"]}\n')
        except OSError:
            pass
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            done, _ = os.waitpid(self.child, os.WNOHANG)
            if done:
                break
            time.sleep(0.05)
        else:
            try:
                os.kill(self.child, signal.SIGKILL)
                os.waitpid(self.child, 0)
            except OSError:
                pass
        shutil.rmtree(self.run, ignore_errors=True)


def per_thread(before, after, secs):
    """Processor % of one core per thread name over secs, from two threads()."""
    sums = {}
    for tid, (name, ns) in after.items():
        start = before.get(tid, (name, 0))[1]
        sums[name] = sums.get(name, 0) + (ns - start)
    return {name: round(ns / 1e9 / secs * 100, 2) for name, ns in sorted(sums.items(), key=lambda kv: -kv[1]) if ns > 0}


def emit(opts, record):
    record.setdefault("label", opts.label)
    record["load1"] = float(open("/proc/loadavg").read().split()[0])
    line = json.dumps(record)
    print(line, flush=True)
    with open(os.path.join(opts.out, "results.jsonl"), "a") as f:
        f.write(line + "\n")


# --- LuaJIT's profiler, run in the kernel through the socket ---
LUAPROF_START = r"""
local prof = require('jit.profile')
local folded = {}
_G.__paw_profile = folded
prof.start('fi1', function(th, samples, vmstate)
  local stack = prof.dumpstack(th, 'pF;', -48)
  stack = stack:gsub(';$', ''):gsub('%[builtin#(%d+)%]', 'builtin#%1')
  local key = stack .. ';[' .. vmstate .. ']'
  folded[key] = (folded[key] or 0) + samples
end)
"""

LUAPROF_STOP = r"""
require('jit.profile').stop()
local out = {}
for k, v in pairs(_G.__paw_profile or {}) do out[#out + 1] = k .. ' ' .. v end
_G.__paw_profile = nil
return table.concat(out, '\n')
"""


def flamegraph(folded_path, svg_path, title):
    tool = shutil.which("inferno-flamegraph")
    if not tool:
        return
    with open(folded_path) as src, open(svg_path, "w") as dst:
        subprocess.run([tool, "--title", title, "--width", "1600"], stdin=src, stdout=dst)


class Probes:
    """perf stat, perf record and LuaJIT's profiler around a stretch of work."""

    def __init__(self, opts, paw, what, secs):
        self.opts, self.paw, self.tag = opts, paw, f"{opts.label}-{what}"
        self.procs = []
        if opts.luaprof:
            paw.eval(LUAPROF_START)
        if opts.perf:
            self.procs.append(subprocess.Popen(
                ["perf", "stat", "-x", ",", "--per-thread", "-e",
                 "instructions:u,cycles:u,task-clock,context-switches,page-faults",
                 "-p", str(paw.pid), "-o", self.path("perfstat"), "--", "sleep", str(min(opts.perf, secs))]))
        if opts.record:
            self.procs.append(subprocess.Popen(
                ["perf", "record", "-q", "-e", "cycles:u", "-F", "499", "--call-graph", "dwarf,16384", "--user-callchains",
                 "-p", str(paw.pid), "-o", self.path("perf.data"), "--", "sleep", str(min(opts.record, secs))],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        self.before, self.frames0, self.bytes0 = paw.threads(), paw.screen.count(), paw.screen.total
        self.t0 = time.monotonic()

    def path(self, ext):
        return os.path.join(self.opts.out, f"{self.tag}.{ext}")

    def stop(self):
        opts, paw = self.opts, self.paw
        after, frames1, bytes1 = paw.threads(), paw.screen.count(), paw.screen.total
        elapsed = time.monotonic() - self.t0
        for p in self.procs:
            try:
                p.wait(timeout=300)
            except subprocess.TimeoutExpired:
                p.kill()
        with paw.screen.lock:
            sizes = sorted(b for (t, b) in paw.screen.frames[self.frames0:frames1])
        result = {
            "seconds": round(elapsed, 2),
            "cpu_percent": per_thread(self.before, after, elapsed),
            "frames": frames1 - self.frames0,
            "frames_per_s": round((frames1 - self.frames0) / elapsed, 2),
            "bytes_per_s": round((bytes1 - self.bytes0) / elapsed),
            "bytes_per_frame_p50": sizes[len(sizes) // 2] if sizes else 0,
            "bytes_per_frame_max": sizes[-1] if sizes else 0,
        }
        if opts.luaprof:
            folded = paw.eval(LUAPROF_STOP) or ""
            with open(self.path("lua.folded"), "w") as f:
                f.write(folded + "\n")
            flamegraph(self.path("lua.folded"), self.path("lua.svg"), f"paw kernel, Lua functions: {self.tag}")
            result["lua_folded"] = self.path("lua.folded")
        if opts.record and os.path.exists(self.path("perf.data")) and shutil.which("inferno-collapse-perf"):
            with open(self.path("perf.folded"), "w") as out:
                script = subprocess.Popen(["perf", "script", "-i", self.path("perf.data")],
                                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                subprocess.run(["inferno-collapse-perf", "--all"], stdin=script.stdout, stdout=out)
                script.wait()
            flamegraph(self.path("perf.folded"), self.path("perf.svg"), f"paw, perf: {self.tag}")
            result["perf_folded"] = self.path("perf.folded")
        if opts.perf:
            result["perfstat"] = parse_perfstat(self.path("perfstat"), paw.pid)
        return result


def with_probes(opts, paw, secs, what):
    """Measure paw for secs seconds; perf and the Lua profiler as asked."""
    probes = Probes(opts, paw, what, secs)
    time.sleep(secs)
    return probes.stop()


def parse_perfstat(path, pid=None):
    """{thread: {event: value}} from perf stat -x , --per-thread; the
    thread `pid` is named kernel, the other threads named paw keep their
    number."""
    out = {}
    try:
        lines = open(path).read().splitlines()
    except OSError:
        return out
    for line in lines:
        parts = line.split(",")
        if len(parts) < 4 or line.startswith("#"):
            continue
        thread, value, event = parts[0], parts[1], parts[3]
        try:
            v = float(value)
        except ValueError:
            continue
        if v == 0:
            continue
        name, _, tid = thread.rpartition("-")
        if pid is not None and tid == str(pid):
            name = "kernel"
        elif name == "paw":
            name = thread
        d = out.setdefault(name, {})
        d[event] = d.get(event, 0) + v
    return out


def start(opts, project, extra=(), env_extra=None):
    paw = Paw(opts, project, extra, env_extra)
    if not paw.screen.wait_frames(1, 120):
        tail = bytes(paw.screen.keep[-2000:]).decode("utf-8", "replace")
        paw.quit(2)
        raise RuntimeError("no first frame; the terminal shows:\n" + tail)
    first = paw.screen.frames[0][0] - paw.t0
    paw.connect()
    if opts.budget:
        paw.eval("paw.opt.budget_ms = ...", opts.budget)
    if opts.setup:
        paw.eval(opts.setup)
        paw.screen.wait_quiet(300, 30)
    return paw, first


# --- the keys ---
ESC = b"\x1b"
KEYS = [
    # (name, bytes, setup)  setup: Lua run before (not measured)
    ("j", b"j", None), ("k", b"k", None), ("w", b"w", None), ("b", b"b", None),
    ("l", b"l", None), ("h", b"h", None),
    ("G", b"G", None), ("gg", b"gg", None),
    ("C-d", b"\x04", None), ("C-u", b"\x15", None),
    ("zoom in +", b"+", None), ("zoom out -", b"-", None),
    ("x", b"x", None), ("u", b"u", None),
    ("dd", b"dd", None), ("u", b"u", None),
    ("open piano roll (CR)", b"\r", None), ("j in roll", b"j", None), ("l in roll", b"l", None),
    ("close (Esc :q)", ESC + b":q\r", None),
    ("mixer <leader>mm", b" mm", None), ("j in mixer", b"j", None), ("mixer off", b" mm", None),
    ("picker <leader>ff", b" ff", None), ("type in picker", b"tra", None), ("picker Esc", ESC, None),
    ("picker <leader>fg", b" fg", None), ("picker Esc", ESC, None),
    (":help CR", b":help\r", None), ("C-d in help", b"\x04", None), ("help :q", b":q\r", None),
]


SLOW_LUA = r"""
local out = {}
for _, s in ipairs(paw.limit.slow) do
  out[#out + 1] = string.format("%s\t%d\t%.1f", s.name, s.times, s.last)
end
return table.concat(out, "\n")
"""


def slow_counts(paw):
    """Each callback over the budget so far (paw.limit.slow):
    {name: [times, last ms]}."""
    out = {}
    for line in (paw.eval(SLOW_LUA) or "").split("\n"):
        if line:
            name, times, last = line.rsplit("\t", 2)
            out[name] = [int(times), float(last)]
    return out


def slow_since(paw, before):
    """The callbacks over the budget since `before` (slow_counts):
    [[name, times, last ms], ...]."""
    now = slow_counts(paw)
    return [[name, t - before.get(name, [0])[0], ms] for name, (t, ms) in now.items() if t > before.get(name, [0])[0]]


def measure_key(paw, name, data, quiet_ms=250):
    frames0 = paw.screen.count()
    k0 = paw.kernel_ns()
    t0 = now_ms()
    paw.key(data)
    got = paw.screen.wait_frames(frames0 + 1, 10)
    paw.screen.wait_quiet(quiet_ms, 10)
    k1 = paw.kernel_ns()
    with paw.screen.lock:
        new = paw.screen.frames[frames0:]
    rec = {"key": name, "frames": len(new),
           "kernel_cpu_ms": round((k1 - k0) / 1e6, 2)}
    if got and new:
        rec["first_frame_ms"] = round(new[0][0] - t0, 2)
        rec["last_frame_ms"] = round(new[-1][0] - t0, 2)
        rec["first_frame_bytes"] = new[0][1]
        rec["bytes"] = sum(b for (_, b) in new)
    return rec


def scenario_keys(opts, project):
    paw, first = start(opts, project)
    paw.screen.wait_quiet(500, 30)
    # The cursor on the second track, at the start.
    results = []
    reps = opts.reps
    named = slow_counts(paw)
    emit(opts, {"scenario": "keys", "slow_at_start": slow_since(paw, {})})
    for name, data, _ in KEYS:
        recs = [measure_key(paw, name, data)]
        # Moves are repeated: a key that changes the project is not.
        if name in ("j", "k", "w", "b", "l", "h", "C-d", "C-u", "j in roll", "l in roll", "j in mixer"):
            for _ in range(reps - 1):
                recs.append(measure_key(paw, name, data))
        rec = recs[0]
        if len(recs) > 1:
            for f in ("first_frame_ms", "kernel_cpu_ms", "bytes"):
                vals = sorted(r.get(f, 0) for r in recs)
                rec[f] = vals[len(vals) // 2]
                rec[f + "_min"] = vals[0]
                rec[f + "_max"] = vals[-1]
            rec["reps"] = len(recs)
        # The callbacks of this key (and of the timers after it) over the budget.
        slow = slow_since(paw, named)
        named = slow_counts(paw)
        if slow:
            rec["slow"] = slow
        rec["scenario"] = "keys"
        emit(opts, rec)
        results.append(rec)
    emit(opts, {"scenario": "keys", "memory_kb": paw.memory(), "lua_kb": round(paw.lua_kb())})
    paw.quit()


def scenario_startup(opts, project):
    # Empty, then the large project.
    for proj, what in ((None, "empty"), (project, "large project")):
        times = []
        for _ in range(opts.reps):
            paw, first = start(opts, proj)
            paw.screen.wait_quiet(300, 30)
            mem, lua = paw.memory(), paw.lua_kb()
            times.append(first)
            paw.quit()
        times.sort()
        emit(opts, {"scenario": "startup", "what": what, "first_frame_ms": round(times[len(times) // 2], 1),
                    "min_ms": round(times[0], 1), "max_ms": round(times[-1], 1), "reps": len(times),
                    "memory_kb": mem, "lua_kb": round(lua)})


def scenario_idle(opts, project, armed=False):
    paw, first = start(opts, project)
    if armed:
        # A track armed on the null backend's test input: meters move with it.
        paw.eval("paw.api.engine_restart({ backend = 'null', test_input = { frequency = 440, level = -12, channels = 2 } })")
        paw.eval("local id = paw.api.track_list()[1]; paw.api.track_set(id, { input = '1', armed = true })")
    paw.screen.wait_quiet(2000, 10)
    mem0 = paw.memory()
    res = with_probes(opts, paw, opts.secs, "idle-armed" if armed else "idle")
    res.update({"scenario": "idle-armed" if armed else "idle", "memory_kb_before": mem0, "memory_kb": paw.memory(),
                "lua_kb": round(paw.lua_kb())})
    emit(opts, res)
    paw.quit()


def scenario_play(opts, project, record=False):
    paw, first = start(opts, project)
    paw.screen.wait_quiet(500, 30)
    what = "record" if record else "play"
    if record:
        paw.eval("paw.api.engine_restart({ backend = 'null', test_input = { frequency = 440, level = -12, channels = 2 } })")
        paw.eval("local id = paw.api.track_add({ name = 'Take' }); paw.api.track_set(id, { input = '1', armed = true }); paw.flush()")
        paw.eval("paw.api.transport_set('loop_enabled', false)")
        paw.eval("paw.commands.exec('transport.record')")
    else:
        paw.eval("paw.api.transport_set('loop_enabled', true); paw.api.transport_play()")
    time.sleep(2)
    mem0, lua0 = paw.memory(), paw.lua_kb()
    frames0 = paw.eval("return paw.api.ui_frames()")
    res = with_probes(opts, paw, opts.secs, what)
    frames1 = paw.eval("return paw.api.ui_frames()")
    res.update({"scenario": what, "memory_kb_before": mem0, "memory_kb": paw.memory(), "lua_kb_before": round(lua0),
                "lua_kb": round(paw.lua_kb()),
                "kernel_frames": {k: frames1[k] - frames0[k] for k in frames1},
                "playing": paw.eval("return paw.api.transport_get().playing"),
                "recording": paw.eval("return paw.api.transport_get().recording")})
    emit(opts, res)
    paw.eval("paw.api.transport_stop()")
    paw.quit()


LONG_KEYS = [b"j", b"j", b"w", b"w", b"x", b"u", b"k", b"b", b"\r", b"j", b"l", ESC + b":q\r",
             b" mm", b"j", b" mm", b"dd", b"u", b"+", b"-", b" ", b" "]


def scenario_long(opts, project):
    paw, first = start(opts, project)
    paw.screen.wait_quiet(500, 30)
    t_end = time.monotonic() + opts.secs
    rounds = 0
    samples = []
    t_start = time.monotonic()
    before = paw.threads()
    while time.monotonic() < t_end:
        for k in LONG_KEYS:
            paw.key(k)
            time.sleep(0.15)
        # Play for a moment every round.
        paw.eval("paw.api.transport_play()")
        time.sleep(1.5)
        paw.eval("paw.api.transport_stop()")
        rounds += 1
        if rounds % 5 == 1:
            mem = paw.memory()
            samples.append({"t": round(time.monotonic() - t_start), "rss_kb": mem.get("VmRSS"),
                            "lua_kb": round(paw.lua_kb())})
            print(json.dumps(samples[-1]), file=sys.stderr, flush=True)
    after = paw.threads()
    # The heap after a full collection: what is really kept.
    paw.eval("collectgarbage(); collectgarbage()")
    mem = paw.memory()
    emit(opts, {"scenario": "long", "rounds": rounds, "samples": samples,
                "cpu_percent": per_thread(before, after, time.monotonic() - t_start),
                "memory_kb": mem, "lua_kb_after_collect": round(paw.lua_kb()),
                "undo_bytes": paw.eval("return paw.api.undo_tree().bytes")})
    paw.quit()


def scenario_repeat(opts, project):
    """The keys of --keys (Python escapes: \\x1b is Esc), --times times, each
    waited for until the screen is quiet, under the probes."""
    paw, first = start(opts, project)
    paw.screen.wait_quiet(500, 30)
    keys = [k.encode().decode("unicode_escape").encode("latin-1") for k in opts.keys.split(",")]
    probes = Probes(opts, paw, "repeat", 3600)
    k0 = paw.kernel_ns()
    t0 = time.monotonic()
    first = {name: [] for name in opts.keys.split(",")}
    for _ in range(opts.times):
        for name, k in zip(opts.keys.split(","), keys):
            n = paw.screen.count()
            t = now_ms()
            paw.key(k)
            if paw.screen.wait_frames(n + 1, 10):
                with paw.screen.lock:
                    first[name].append(paw.screen.frames[n][0] - t)
            paw.screen.wait_quiet(100, 10)
    res = probes.stop()
    if opts.budget:
        res["slow"] = slow_since(paw, {})
    res.update({"scenario": "repeat", "keys": opts.keys, "times": opts.times,
                "kernel_cpu_ms_per_round": round((paw.kernel_ns() - k0) / 1e6 / opts.times, 2),
                "wall_s": round(time.monotonic() - t0, 2)})
    # The time from each key to its first frame: median, smallest, largest.
    for name, vals in first.items():
        if vals:
            vals.sort()
            res["first_frame_ms " + name] = [round(vals[len(vals) // 2], 1), round(vals[0], 1), round(vals[-1], 1)]
    emit(opts, res)
    paw.quit()


class Opts:
    pass


def parse(argv):
    o = Opts()
    o.scenario = argv[0] if argv else "keys"
    o.paw = None
    o.out = os.path.join(os.environ.get("BENCH_TMP", "/tmp/paw-bench"), "profile")
    o.project = None
    o.empty = False
    o.cols, o.rows = 187, 56
    o.secs = None
    o.wrap = []
    o.perf = 0
    o.record = 0
    o.luaprof = False
    o.label = None
    o.reps = 5
    o.keys = "j,k"
    o.times = 20
    o.setup = None
    o.budget = 5
    i = 1
    while i < len(argv):
        a = argv[i]
        v = argv[i + 1] if i + 1 < len(argv) else None
        if a == "--paw": o.paw = v; i += 1
        elif a == "--out": o.out = v; i += 1
        elif a == "--project": o.project = v; i += 1
        elif a == "--empty": o.empty = True
        elif a == "--size": o.cols, o.rows = (int(x) for x in v.split("x")); i += 1
        elif a == "--secs": o.secs = float(v); i += 1
        elif a == "--wrap": o.wrap = v.split(); i += 1
        elif a == "--perf": o.perf = float(v); i += 1
        elif a == "--record": o.record = float(v); i += 1
        elif a == "--luaprof": o.luaprof = True
        elif a == "--label": o.label = v; i += 1
        elif a == "--reps": o.reps = int(v); i += 1
        elif a == "--keys": o.keys = v; i += 1
        elif a == "--times": o.times = int(v); i += 1
        elif a == "--setup": o.setup = v; i += 1
        elif a == "--budget": o.budget = float(v); i += 1
        else:
            sys.exit(f"unknown option {a}\n{__doc__}")
        i += 1
    if o.paw is None:
        rel = os.path.join(REPO, "target/release/paw")
        prof = os.path.join(REPO, "target/profiling/paw")
        cands = [p for p in (prof, rel) if os.path.exists(p)]
        if not cands:
            sys.exit("build paw first: cargo build --release (or --profile profiling)")
        o.paw = max(cands, key=os.path.getmtime)
    o.paw = os.path.abspath(o.paw)
    if o.secs is None:
        o.secs = 600 if o.scenario == "long" else 60
    o.label = o.label or o.scenario
    os.makedirs(o.out, exist_ok=True)
    return o


def main():
    opts = parse(sys.argv[1:])
    project = None
    if not opts.empty:
        project = opts.project or os.path.join(opts.out, "project")
        if not os.path.exists(os.path.join(project, "project.toml")):
            env = dict(os.environ, XDG_CONFIG_HOME=opts.out + "/gen", XDG_DATA_HOME=opts.out + "/gen",
                       XDG_STATE_HOME=opts.out + "/gen", XDG_CACHE_HOME=opts.out + "/gen")
            subprocess.run([opts.paw, "--clean", "--no-plugins", "-l", os.path.join(HERE, "project.lua"), project],
                           env=env, check=True)
    s = opts.scenario
    if s == "keys":
        scenario_keys(opts, project)
    elif s == "startup":
        scenario_startup(opts, project)
    elif s == "idle":
        scenario_idle(opts, project)
    elif s == "idle-armed":
        scenario_idle(opts, project, armed=True)
    elif s == "play":
        scenario_play(opts, project)
    elif s == "record":
        scenario_play(opts, project, record=True)
    elif s == "long":
        scenario_long(opts, project)
    elif s == "repeat":
        scenario_repeat(opts, project)
    else:
        sys.exit(f"unknown scenario {s}\n{__doc__}")


if __name__ == "__main__":
    main()
