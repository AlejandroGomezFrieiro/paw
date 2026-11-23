#!/usr/bin/env python3
"""gif.py name: $WORK/name.mkv -> $WORK/name.gif.

The recording is cut to the scene (name.lead says where it starts in the
recording, the last caption where it ends), and a bar is put under it: the
caption on the left (name.caps), and on the right a key-cast, the keys the
scene typed as Vim writes them (name.keys, both written by rig.sh)."""
import os
import subprocess
import sys

WORK = os.environ["WORK"]
NAME = sys.argv[1]
FPS = 10
BAR = 40
# The size budget of the skill in .claude/skills/paw-gifs: the colors of
# the palette (ffmpeg makes it, so gifsicle needs no --colors), gifsicle's
# lossy pass, and the largest GIF that the README takes.
LOSSY, COLORS = 30, 128
BUDGET = 8 * 1024 * 1024
BG, INK, KEYBG, KEYINK = "0x11111b", "0xcdd6f4", "0x313244", "0xf9e2af"
KEYSIZE = 18
# The key-cast is FiraCode, whose every glyph is 0.6 of the size wide.
ADVANCE = 0.6 * KEYSIZE


def font(name):
    return subprocess.run(["fc-match", "-f", "%{file}", name], capture_output=True, text=True).stdout


SANS, MONO = font("DejaVu Sans"), font("FiraCode Nerd Font")

NAMES = {
    "Return": "<CR>", "braceright": "}", "braceleft": "{", "Escape": "<Esc>", "space": "<Space>", "Tab": "<Tab>", "BackSpace": "<BS>",
    "comma": ",", "colon": ":", "plus": "+", "minus": "-", "dollar": "$", "slash": "/",
    "backslash": "\\", "less": "<", "greater": ">", "at": "@", "period": ".", "question": "?",
    "bracketright": "]", "bracketleft": "[", "apostrophe": "'", "parenleft": "(",
    "parenright": ")", "asciitilde": "~", "ampersand": "&", "asterisk": "*", "underscore": "_", "numbersign": "#", "equal": "=",
    "Up": "<Up>", "Down": "<Down>", "Left": "<Left>", "Right": "<Right>",
}


def vim(key):
    """An xdotool key name as Vim writes it: ctrl+w is <C-w>."""
    *mods, base = key.split("+")
    base = NAMES.get(base, base)
    if not mods:
        return base
    prefix = "".join({"ctrl": "C-", "alt": "M-", "shift": "S-"}[m] for m in mods)
    return "<" + prefix + base.strip("<>") + ">"


def rows(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [line.rstrip("\n").split("\t") for line in f if line.strip()]


lead = float(open(f"{WORK}/{NAME}.lead").read()) if os.path.exists(f"{WORK}/{NAME}.lead") else 0.0
caps = [(float(t), c) for t, c in rows(f"{WORK}/{NAME}.caps")]
end = caps[-1][0] if caps else None

# Each key pressed, and each character typed, at the time it was.
events = []
for t, kind, text in rows(f"{WORK}/{NAME}.keys"):
    t = float(t)
    if kind == "key":
        events.append((t, vim(text)))
    else:
        delay = float(kind.split()[1]) / 1000
        for i, ch in enumerate(text):
            events.append((t + i * delay, ch))

# Keys typed close together are shown together; a pause, Enter or Esc
# starts again. Each state of the line lasts until the next key, and the
# last one a little longer.
segments, line, last = [], "", None
for i, (t, k) in enumerate(events):
    new_caption = last is not None and any(last < c <= t for c, _ in caps)
    if last is None or new_caption or t - last > 1.3 or line.endswith("<CR>") or line.endswith("<Esc>"):
        line = ""
    line += k
    nxt = events[i + 1][0] if i + 1 < len(events) else None
    stop = t + 1.8 if nxt is None else min(nxt, t + 1.8) if nxt - t > 1.3 else nxt
    if end is not None:
        stop = min(stop, end)
    shown = line if len(line) <= 34 else "…" + line[-33:]
    segments.append((t, stop, shown))
    last = t

os.makedirs(f"{WORK}/caps", exist_ok=True)


def textfile(i, kind, text):
    path = f"{WORK}/caps/{NAME}-{kind}{i}.txt"
    with open(path, "w") as f:
        f.write(text)
    return path


filters = [f"fps={FPS}", f"pad=iw:ih+{BAR}:0:0:color={BG}"]
for i, ((t, c), (t2, _)) in enumerate(zip(caps, caps[1:])):
    if c:
        filters.append(
            f"drawtext=fontfile={SANS}:textfile={textfile(i, 'c', c)}:expansion=none:fontcolor={INK}:"
            f"fontsize=17:x=16:y=h-{BAR}+(({BAR}-th)/2):y_align=font:enable='between(t,{t:.2f},{t2:.2f})'")
for i, (t, t2, k) in enumerate(segments):
    w = int(len(k) * ADVANCE + 22)
    filters.append(
        f"drawtext=fontfile={MONO}:textfile={textfile(i, 'k', k)}:expansion=none:fontcolor={KEYINK}:"
        f"fontsize={KEYSIZE}:box=1:boxcolor={KEYBG}:boxw={w}:boxh=28:text_align=C+M:"
        f"x=w-{w}-10:y=h-{BAR}+6:enable='between(t,{t:.2f},{t2:.2f})'")
graph = (",".join(filters)
         + f",split[a][b];[a]palettegen=max_colors={COLORS}:stats_mode=diff[p];"
         + "[b][p]paletteuse=dither=none:diff_mode=rectangle")
script = f"{WORK}/caps/{NAME}.filter"
with open(script, "w") as f:
    f.write(graph)
cut = ["-ss", f"{lead:.2f}"] + (["-t", f"{end:.2f}"] if end else [])
out = f"{WORK}/{NAME}.gif"
subprocess.run(["ffmpeg", "-loglevel", "error", "-y"] + cut + ["-i", f"{WORK}/{NAME}.mkv",
               "-filter_complex_script", script, out], check=True)
subprocess.run(["gifsicle", "-O3", f"--lossy={LOSSY}", out, "-o", out], check=True)
size = os.path.getsize(out)
print(f"{NAME}.gif: {size / 1024 / 1024:.1f} MB, {end or 0:.0f} s")
if size > BUDGET:
    sys.exit(f"{NAME}.gif is larger than {BUDGET // 1024 // 1024} MB: make the scene shorter or split it")
