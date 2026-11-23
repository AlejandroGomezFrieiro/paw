#!/usr/bin/env python3
"""Record a terminal session of paw as an asciicast (version 2).

    cast.py NAME OUT.cast < STEPS

The website plays the file with its player (tools/website/paw-cast.js),
and the reader can pause it and copy the keys of each step. A scene
script (cast-*.sh) gives the steps on standard input, one on each line:

    caption TEXT     a new step: a marker with TEXT in the file
    keys KEYS        type KEYS (Vim notation, as paw-pod.js reads it)
    pause SECONDS    wait, and record what paw draws

paw runs in a pseudo-terminal of 100 by 30 cells, with --clean,
--no-plugins and --audio null, in a scratch home, as rig.sh runs it. The
Lua in SETUP runs at the start. PAW_BIN is the folder of the paw program
(target/release when it is not set). The time before paw draws its first
screen is not in the file.
"""

import codecs
import fcntl
import json
import os
import pty
import re
import select
import shutil
import signal
import struct
import sys
import tempfile
import termios
import time

COLS, ROWS = 100, 30
KEY_DELAY = 0.18
ESC_DELAY = 0.08

# Keys in Vim notation, as bytes for the terminal (paw-pod.js has the same table).
NAMED = {
    "esc": "\x1b", "cr": "\r", "enter": "\r", "return": "\r", "space": " ",
    "leader": " ", "tab": "\t", "bs": "\x7f", "del": "\x1b[3~", "lt": "<",
    "bar": "|", "bslash": "\\", "up": "\x1b[A", "down": "\x1b[B",
    "right": "\x1b[C", "left": "\x1b[D", "home": "\x1b[H", "end": "\x1b[F",
    "pageup": "\x1b[5~", "pagedown": "\x1b[6~",
}


def parse_keys(keys):
    """Split keys in Vim notation into the bytes of each key."""
    out, i = [], 0
    while i < len(keys):
        m = re.match(r"<([^<>]+)>", keys[i:]) if keys[i] == "<" else None
        if m:
            name = m.group(1).lower()
            ctrl = re.fullmatch(r"c-(.)", name)
            alt = re.fullmatch(r"[am]-(.+)", m.group(1))
            if name in NAMED:
                out.append(NAMED[name])
            elif ctrl:
                out.append(chr(ord(ctrl.group(1).upper()) & 0x1F))
            elif alt:
                out.append("\x1b" + NAMED.get(alt.group(1).lower(), alt.group(1)))
            else:
                sys.exit(f"cast.py: unknown key <{m.group(1)}>")
            i += len(m.group(0))
        else:
            out.append(keys[i])
            i += 1
    return out


class Session:
    """paw in a pseudo-terminal, and the events of the cast."""

    def __init__(self, paw, setup, home):
        pid, fd = pty.fork()
        if pid == 0:
            env = {
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "TERM": "xterm-256color",
                "COLORTERM": "truecolor",
                "HOME": home,
                "XDG_CONFIG_HOME": f"{home}/config",
                "XDG_DATA_HOME": f"{home}/data",
                "XDG_STATE_HOME": f"{home}/state",
                "XDG_CACHE_HOME": f"{home}/cache",
                "XDG_RUNTIME_DIR": f"{home}/run",
                "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent/bus",
            }
            args = [paw, "--clean", "--no-plugins", "--audio", "null", "-e", setup]
            os.execve(paw, args, env)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        self.pid, self.fd = pid, fd
        self.decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
        self.events = []
        self.start = None
        self.seen = ""

    def now(self):
        return 0.0 if self.start is None else time.monotonic() - self.start

    def read(self, seconds):
        """Record what paw writes for SECONDS."""
        until = time.monotonic() + seconds
        while (left := until - time.monotonic()) > 0:
            ready, _, _ = select.select([self.fd], [], [], left)
            if not ready:
                continue
            try:
                data = os.read(self.fd, 65536)
            except OSError:
                return
            text = self.decoder.decode(data)
            if text:
                self.events.append([round(self.now(), 3), "o", text])
                if self.start is None:
                    self.seen = (self.seen + text)[-4096:]

    def wait_ready(self, timeout=30):
        """Wait until paw draws its status line, then until it is quiet."""
        until = time.monotonic() + timeout
        while "NORMAL" not in self.seen:
            if time.monotonic() > until:
                sys.exit("cast.py: paw did not draw its first screen")
            self.read(0.1)
        self.read(1.0)
        # The startup's events are the first frame, at time 0.
        self.start = time.monotonic()

    def type(self, keys):
        for key in parse_keys(keys):
            self.events.append([round(self.now(), 3), "i", key])
            os.write(self.fd, key.encode())
            self.read(ESC_DELAY if key == "\x1b" else KEY_DELAY)

    def mark(self, caption):
        self.events.append([round(self.now(), 3), "m", caption])

    def stop(self):
        try:
            os.kill(self.pid, signal.SIGTERM)
            os.waitpid(self.pid, 0)
        except OSError:
            pass
        os.close(self.fd)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    name, out = sys.argv[1], sys.argv[2]
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    paw = os.path.join(os.environ.get("PAW_BIN") or os.path.join(root, "target", "release"), "paw")
    steps = [line.rstrip("\n").split(" ", 1) for line in sys.stdin if line.strip() and not line.startswith("#")]
    home = tempfile.mkdtemp(prefix="paw-cast-")
    os.chdir(root)
    session = Session(paw, os.environ.get("SETUP", "dofile('examples/demo-song.lua')"), home)
    try:
        session.wait_ready()
        for verb, arg in steps:
            if verb == "caption":
                session.mark(arg)
            elif verb == "keys":
                session.type(arg)
            elif verb == "pause":
                session.read(float(arg))
            else:
                sys.exit(f"cast.py: unknown step {verb}")
    finally:
        session.stop()
        shutil.rmtree(home, ignore_errors=True)
    header = {"version": 2, "width": COLS, "height": ROWS, "title": name, "env": {"TERM": "xterm-256color"}}
    with open(out, "w", encoding="utf-8") as f:
        f.write(json.dumps(header) + "\n")
        for event in session.events:
            f.write(json.dumps(event, ensure_ascii=False) + "\n")
    print(f"wrote {out}: {len(session.events)} events, {session.now():.1f} s")


if __name__ == "__main__":
    main()
