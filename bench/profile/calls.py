#!/usr/bin/env python3
"""Count the calls of `paw.api` functions, and where they come from, while
paw plays (or stays idle) in the profile's pseudo-terminal: which Rust
entry points the Lua runtime calls per frame, and from which lines.

    bench/profile/calls.py [--secs N] [--still] [--top N] [drive.py options]
    bench/profile/calls.py --press j,k [--times N] [--top N] [drive.py options]

Each `paw.api` function is wrapped for the measurement; the wrapper's own
cost makes the run slower, so it counts, it does not time.
"""
import os
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import drive  # noqa: E402

WRAP = r"""
local api = paw.api
_G.__paw_calls = { n = {}, from = {} }
local calls = _G.__paw_calls
_G.__paw_api_saved = {}
for name, fn in pairs(api) do
  if type(fn) == 'function' then
    _G.__paw_api_saved[name] = fn
    api[name] = function(...)
      calls.n[name] = (calls.n[name] or 0) + 1
      local info = debug.getinfo(2, 'Sl')
      local where = info and (info.short_src .. ':' .. (info.currentline or 0)) or '?'
      local key = name .. ' <- ' .. where
      calls.from[key] = (calls.from[key] or 0) + 1
      return fn(...)
    end
  end
end
"""

UNWRAP = r"""
for name, fn in pairs(_G.__paw_api_saved) do paw.api[name] = fn end
local out = {}
for k, v in pairs(_G.__paw_calls.from) do out[#out + 1] = v .. '\t' .. k end
return table.concat(out, '\n')
"""


def main():
    argv = sys.argv[1:]
    secs, still, top, keys, times = 10.0, False, 40, None, 10
    rest = []
    i = 0
    while i < len(argv):
        if argv[i] == "--secs":
            secs = float(argv[i + 1]); i += 1
        elif argv[i] == "--still":
            still = True
        elif argv[i] == "--press":
            keys = argv[i + 1]; i += 1
        elif argv[i] == "--times":
            times = int(argv[i + 1]); i += 1
        elif argv[i] == "--top":
            top = int(argv[i + 1]); i += 1
        else:
            rest.append(argv[i])
        i += 1
    opts = drive.parse(["calls"] + rest)
    project = None if opts.empty else (opts.project or os.path.join(opts.out, "project"))
    paw, _ = drive.start(opts, project)
    paw.screen.wait_quiet(500, 30)
    if not still and not keys:
        paw.eval("paw.api.transport_set('loop_enabled', true); paw.api.transport_play()")
        time.sleep(1)
    frames0 = paw.screen.count()
    paw.eval(WRAP)
    if keys:
        seq = [k.encode().decode("unicode_escape").encode("latin-1") for k in keys.split(",")]
        for _ in range(times):
            for k in seq:
                n = paw.screen.count()
                paw.key(k)
                paw.screen.wait_frames(n + 1, 10)
                paw.screen.wait_quiet(100, 10)
    else:
        time.sleep(secs)
    text = paw.eval(UNWRAP) or ""
    frames = paw.screen.count() - frames0
    paw.quit()
    rows = []
    for line in text.splitlines():
        n, _, key = line.partition("\t")
        rows.append((int(n), key))
    rows.sort(reverse=True)
    print(f"{frames} frames in {secs} s; calls per frame:")
    for n, key in rows[:top]:
        print(f"  {n / max(frames, 1):8.2f}  {key}")


main()
