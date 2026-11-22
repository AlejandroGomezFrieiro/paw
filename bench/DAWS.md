# paw against REAPER, Ardour and LMMS

This study measures the processor time that paw and three other DAWs use
while they play the same small song. The question was this: does paw,
with its terminal or its graphical window, use less of the processor
than REAPER? All the numbers come from runs on one machine on 2026-11-19.
[The engine results](RESULTS.md) compare paw's engine with Tracktion Engine.

## The short answer

In the terminal, paw uses less of the processor than REAPER, Ardour and
LMMS. Sometimes the graphical window of paw and REAPER draw through the
same display server, a Wayland compositor on the graphics card. Then the
graphical window is level with REAPER, or below it. Against REAPER on a plain X server in memory (Xvfb), the
graphical window uses more in the arrange view and the mixer.

The values are the percent of one processor core that the program and its
display server use together, while the song plays in a loop. Each value is
the median of the runs, with the smallest and the largest value in
brackets.

**1500x960:**

| View | paw, terminal only | paw in xterm | paw window, GPU | paw window, software | REAPER, Xvfb | REAPER, Weston | Ardour | LMMS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Arrange | 8.6 (8.3 to 10.7) | 8.3 (7.9 to 11.6) | 12.4 (10.8 to 13.9) | 13.8 (12.5 to 15.1) | 12.0 (12.0 to 12.0) | 15.2 (15.1 to 15.3) | 11.6 (11.4 to 12.3) | 27.9 (27.7 to 28.8) |
| Mixer | 8.5 (7.7 to 9.9) | 8.7 (8.6 to 10.8) | 15.6 (13.0 to 18.1) | 15.2 (15.1 to 15.2) | 12.4 (12.2 to 12.6) | 16.2 (16.2 to 16.2) | 9.6 (9.4 to 11.1) | 31.6 (30.6 to 32.5) |
| Piano roll | not measured | not measured | 10.7 (10.2 to 11.2) | 11.1 (10.4 to 11.8) | 14.1 (13.0 to 15.3) | 17.6 (17.1 to 18.0) | not measured | not measured |

**2560x1440** (the graphical window and REAPER only):

| View | paw window, GPU | paw window, software | REAPER, Xvfb | REAPER, Weston |
| --- | ---: | ---: | ---: | ---: |
| Arrange | 15.1 (12.5 to 17.7) | 15.6 (15.5 to 15.7) | 12.6 (12.6 to 12.7) | 14.8 (14.7 to 14.8) |
| Mixer | 15.8 (15.7 to 16.0) | 17.6 (17.3 to 17.9) | 12.8 (11.4 to 14.1) | 15.8 (15.0 to 16.7) |
| Piano roll | 13.4 (12.9 to 13.9) | 12.8 (12.0 to 13.5) | 14.2 (13.2 to 15.2) | 17.2 (16.4 to 18.1) |

The resident memory for the arrange view at 1500x960, in MB:

- paw in the terminal: 38, and with xterm: 53
- the graphical window with its kernel: 172 on the GPU, 204 in software
- REAPER: 131, Ardour: 280, LMMS: 306

Where the numbers come from (sets of `results/daws-2026-11-19.jsonl`):

- paw in the terminal and Ardour: set `fece459`, three rounds.
- LMMS: set `start`, three rounds. LMMS has no part of paw in it, so the
  later builds of paw do not change its value.
- The graphical window and REAPER: set `window2-sweep`, two rounds, with
  the build of WINDOW2 (merged as 68226cbc). REAPER on Xvfb in set
  `fece459` gave 11.6 in the arrange view and 17.2 (11.6 to 17.5) in the
  mixer, at a load average of 18.5.
- paw in the terminal was not measured in the piano roll after the
  terminal changes (FRAMES). Before them, it used 13.7 (12.9 to 15.0).

**The values come from runs under external load.** Other people and
programs used the machine at the same time. Each table gives the load
average of its runs in the results file.

## The machine and the method

- **The machine.** AMD Ryzen AI 9 HX 370 (12 cores, 24 threads), 32 GB,
  NixOS, Linux 7.3.1 with the real-time kernel. Each run used cores 16 to
  23 (`taskset -c 16-23`) for the program and its display server.
- **The programs.** paw at the commits that each table names, built with
  `cargo build --release`. REAPER 7.84, Ardour 9.8, LMMS 1.2.2 (a build
  of 2026-04-21), Weston 15.0.1, all from Nix.
- **The song.** paw's demo song (`examples/demo-song.lua`): four tracks
  (drums, bass, keys, lead), a delay on the keys, a reverb that the other
  tracks send to, 8 bars at 108 BPM in a loop. The other DAWs get the same
  notes from paw's MIDI export (`daws/demo.mid`, `daws/song.json`). Each
  DAW plays them with its own synthesizers and effects:
  - REAPER: ReaSynth on each track, ReaDelay on the keys, ReaVerbate on a
    reverb track.
  - Ardour: ACE Reasonable Synth, ACE Delay on the keys, ACE Reverb on a
    bus.
  - LMMS: TripleOscillator on each track, its Delay on the keys, ReverbSC
    on the master.

  So the study compares whole programs, not engines. The synthesizers do
  different work for each note.
- **No audio device.** paw runs with `--audio null`. REAPER, Ardour and
  LMMS use their null audio devices.
- **The display.** Each run has a private display of its own:
  - "Xvfb" is an X server in memory. A program on Xvfb draws with the
    processor, and the server does almost no work.
  - "Weston" is a headless Weston compositor on the graphics card. paw's
    window draws on it with the GPU. REAPER is an X11 program, so it
    draws through XWayland on Weston.
  - "software" is paw's window with `--renderer software` (llvmpipe, 4
    threads) on Xvfb.
  - "paw, terminal only" is paw in a pseudo-terminal (`script`), 187x56
    cells, with no terminal emulator. "paw in xterm" adds xterm (DejaVu
    Sans Mono 10) on Xvfb.
- **What "total" counts.** The total is the sum of three parts:
  - the program: paw (or `paw-gui` and its kernel, `paw`), and for REAPER,
    Ardour and LMMS every process of their process tree
  - the terminal emulator, if there is one
  - the display server: Xvfb, Weston, or Weston and XWayland together.
- **A run.** The program starts and plays. After it settles (8 s for paw,
  12 to 30 s for the other DAWs), the harness reads the processor time of
  each process from `/proc` over 15 or 20 s.
- **Turns.** A round runs each setup once, and the order of the setups
  turns by one place each round. A comparison of two builds of paw runs
  them in interleaved pairs: base, new, base, new.
- **The lock.** Each run held a shared lock, so that no other measurement
  ran at the same time on the machine.
- **Safety.** The other DAWs ran in bubblewrap, with a new home folder and
  configuration folder, no network and no access to the home folder.
  REAPER always ran with `-cfgfile` and its own `reaper.ini`. paw ran with
  `--clean --no-plugins` and its own `XDG_*` folders.

The machine was shared, so the load average went from 0.3 to 65 during
these runs. A difference smaller than the spread of the two values is "no
measurable difference" in this study. Some counters do not change with the
load, and the results file keeps them next to the processor times:

- the frames a second
- the part of the window that paw draws again
- the bytes that paw writes to the terminal.

## How paw got there

### The start (0694042)

Set `start`, three rounds, 20 s each, load average 0.3 to 2.3:

| View | paw, terminal only | paw in xterm | paw window, GPU | paw window, software | REAPER, Xvfb | Ardour | LMMS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Arrange | 17.5 (17.1 to 18.2) | 19.4 (18.3 to 19.7) | 21.8 (21.2 to 23.2) | 57.0 (56.7 to 57.3) | 12.6 (12.5 to 12.8) | 15.0 (11.5 to 17.5) | 27.9 (27.7 to 28.8) |
| Mixer | 20.6 (18.1 to 21.6) | 22.6 (19.2 to 22.8) | 26.2 (23.9 to 27.9) | 59.5 (59.3 to 60.4) | 13.5 (13.2 to 14.1) | 10.5 (8.8 to 13.0) | 31.6 (30.6 to 32.5) |

Set `modes` has three more rounds of the same build. In them, the kernel
alone used 12.6 to 12.8 % in the graphical window. paw drew 30 whole
frames a second in the terminal and in the window.

### The terminal draws only what moves, and devices sleep (fece459)

Two changes merged at the same time, so these runs measure them together:

- **FRAMES** (merged as 546eae76). While the song plays, the terminal
  draws again only its live parts: the playhead, the meters, the status
  line and the tab line. paw sends a frame only when a cell changes. The
  window gets the scene and the state at its own pace.
- **ENGINE** (merged as 78054873). Devices sleep through silence, the
  worker threads run only when a block needs them, and the reverb and the
  LFOs do less work. [The engine results](RESULTS.md) have its numbers: `paw --headless` with
  the demo song went from 6.1 to 3.4 % while it plays, and from 5.7 to 1.1
  % while it is stopped.

Set `fece459` (the build after both merges), three rounds, 20 s each,
load average 3.5 to 65:

| View | Setup | Before (`start`) | After (`fece459`) |
| --- | --- | ---: | ---: |
| Arrange | paw, terminal only | 17.5 (17.1 to 18.2) | 8.6 (8.3 to 10.7) |
| Arrange | paw in xterm | 19.4 (18.3 to 19.7) | 8.3 (7.9 to 11.6) |
| Arrange | paw window, GPU | 21.8 (21.2 to 23.2) | 13.2 (12.3 to 13.6) |
| Arrange | paw window, software | 57.0 (56.7 to 57.3) | 44.4 (44.0 to 61.5) |
| Mixer | paw, terminal only | 20.6 (18.1 to 21.6) | 8.5 (7.7 to 9.9) |
| Mixer | paw in xterm | 22.6 (19.2 to 22.8) | 8.7 (8.6 to 10.8) |
| Mixer | paw window, GPU | 26.2 (23.9 to 27.9) | 14.8 (14.2 to 16.0) |
| Mixer | paw window, software | 59.5 (59.3 to 60.4) | 48.2 (45.2 to 58.5) |

In the same rounds, REAPER on Xvfb used 11.6 (11.1 to 12.9) in the
arrange view. In the mixer it used 17.2 (11.6 to 17.5). Ardour used 11.6 (11.4 to 12.3)
and 9.6 (9.4 to 11.1). The load average in these rounds was higher than in
`start`.

The kernel of the graphical window went from 12.7 to 5.9 % in the arrange
view. The terminal now gets about 59 small updates a second in place of 30
whole frames. In the arrange view it gets 10,500 bytes a second in place of
8,090. The cost of the window's own drawing did not change: in software it
was still about 39 % of a core.

### The window draws again only what changed (WINDOW, dd657dc4)

WINDOW put a loop of paw's own in place of eframe's. The window draws again
only the 32-pixel squares that changed, and shows nothing new when nothing
changed. The still parts of a scene are painted once. In software on X11,
it copies only the changed parts to the screen.

Set `window`: five interleaved pairs, 15 s each, at 1500x960. The base is
`paw-gui` of `main` before WINDOW, with the same kernel. The load average
was 1.8 to 16.5.

| View | Setup | Before | After | Part of the window drawn a frame, after |
| --- | --- | ---: | ---: | ---: |
| Arrange | paw window, software | 44.3 (43.2 to 47.8) | 15.1 (13.6 to 16.5) | 4.1 % |
| Mixer | paw window, software | 52.2 (49.4 to 53.2) | 18.7 (16.6 to 20.5) | 5.0 % |
| Piano roll | paw window, software | 47.9 (46.0 to 49.1) | 11.8 (9.8 to 12.6) | 0.9 % |
| Arrange | paw window, GPU | 14.0 (13.2 to 14.2) | 14.0 (12.0 to 14.9) | 4.1 % |
| Mixer | paw window, GPU | 15.5 (14.7 to 18.9) | 14.1 (13.0 to 16.1) | 5.1 % |
| Piano roll | paw window, GPU | 18.2 (16.2 to 20.5) | 17.3 (13.0 to 18.3) | 0.9 % |

Before WINDOW, the window drew all of itself for each frame. On the GPU,
the change gave no measurable difference.

### Frames without egui's pass, and scene keys (WINDOW2, 68226cbc)

- **Frames from the live values** (69c663b3). When only the live values
  change (the playhead, the meters), the window draws the frame from them
  and does not run egui's pass. With the base, the window ran 30 passes a
  second on the GPU. With WINDOW2, it ran 1.1 to 1.7 passes a second.
- **Scene keys** (e17277f1). A view can give a `scene_key`. While the key
  stays the same, the kernel does not make and send the scene again. The
  notation view and the session view use it, so they no longer send a
  scene at each tick.

Set `window2`: five interleaved pairs, 15 s each, at 1500x960. The base is
`main` after WINDOW. The load average was 3.1 to 27.6.

| View | Setup | Before | After |
| --- | --- | ---: | ---: |
| Arrange | paw window, GPU | 12.6 (11.3 to 19.3) | 11.3 (11.1 to 17.8) |
| Mixer | paw window, GPU | 12.9 (12.2 to 13.3) | 10.7 (10.3 to 12.1) |
| Piano roll | paw window, GPU | 12.6 (11.7 to 15.4) | 10.3 (9.5 to 12.5) |
| Session | paw window, GPU | 16.1 (14.8 to 17.4) | 12.3 (10.7 to 17.4) |
| Notation | paw window, GPU | 18.8 (18.5 to 23.5) | 12.5 (11.4 to 15.3) |
| Arrange | paw window, software | 12.8 (11.9 to 17.6) | 11.9 (11.2 to 13.4) |

The mixer and the notation view have a measurable difference. In the other
rows, the ranges overlap. In the notation view, the kernel went from 10.3
to 7.0 % and the window from 7.5 to 3.8 %.

Set `window-sweep` (the WINDOW branch before its merge, three rounds) and
set `window2-sweep` (the WINDOW2 build, two rounds) compare the window with
REAPER at both sizes. The first table of this page comes from
`window2-sweep`.

## Where paw is still behind

- **The arrange view and the mixer against REAPER on Xvfb.** In the
  graphical window, paw uses 12 to 18 % where REAPER uses 12 to 13 %. On
  Xvfb, REAPER draws in software into the server's memory, and the server
  uses less than 1 %. On Weston, REAPER pays for XWayland too (4 to 5 %),
  and paw is level with it or below it.
- **The kernel's tick.** In the graphical window, about half of the total
  is the kernel: 5.1 to 5.7 % in set `window2`. The engine alone uses
  about 3.4 % (`paw --headless`, in [the engine results](RESULTS.md)). The rest is the work of
  the kernel for each frame: the views in Lua, the live values and the
  scene. In the terminal, the kernel is the whole of paw's 8 to 9 %.
- **The mixer's meters.** The meters change at each frame, so the mixer
  draws more of the window than the arrange view does: 5.0 % against 4.1 %
  of the window at 1500x960. In the graphical window, the mixer costs 0.7
  to 3.2 % more than the arrange view. In the terminal, the two cost the
  same.
- **Large screens.** At 2560x1440 the graphical window uses 15 to 18 % in
  the arrange view and the mixer, against 12.6 and 12.8 % for REAPER on
  Xvfb.

What the study does not compare:

- plugins: each DAW used its own built-in synthesizers and effects, and
  no third-party plugin
- recording, a real audio device, and the latency of the audio
- larger projects: the song has four tracks and a reverb
- the time on the graphics card: the study counts processor time only
- the frame rate of REAPER, Ardour and LMMS, which the harness does not
  read. paw's graphical window draws at 30 frames a second on the GPU and
  15 in software (`paw.opt.window_fps`).

## How to do the measurement again

The harness is in [daws/](daws). Its scripts name every option in their
first lines.

- `daws/paw.sh` measures one run of paw in a mode and a view.
- `daws/daw.sh` measures one run of REAPER, Ardour or LMMS.
- `daws/rounds.sh` runs interleaved rounds of setups and views.
- `daws/pairs.sh` runs interleaved pairs of two builds of paw.
- `daws/table.py` makes the tables, and the JSON lines of a results file.

The dev shell has Xvfb, xdotool and ImageMagick. The scripts also need
bubblewrap, `script` and `flock`, xterm or WezTerm for those modes, and
Weston and XWayland for the GPU modes. REAPER is not free software, so the
harness has no default for it. Give the path of its binary in `REAPER`.
Give `ARDOUR`, `LMMS`, `WESTON` and `XWAYLAND` if they are not on the
`PATH`.

```sh
nix develop -c cargo build --release
export REAPER=/path/to/reaper LOCK=/tmp/measure.lock
nix develop -c bench/daws/rounds.sh cmp 3 20 \
  paw:tui-pty paw:tui-xterm paw:gui-sw paw:gui-gpu reaper reaper-weston ardour lmms
SIZES="1500x960 2560x1440" VIEWS="arrange mixer roll" \
  nix develop -c bench/daws/rounds.sh big 2 15 paw:gui-sw paw:gui-gpu reaper reaper-weston
BASEBIN=/path/to/base/target/release NEWBIN=target/release \
  nix develop -c bench/daws/pairs.sh pr paw:gui-gpu mixer 5 15
python3 bench/daws/table.py show /tmp/paw-bench/daws/results --split
python3 bench/daws/table.py collect /tmp/paw-bench/daws/results cmp > runs.jsonl
```

The results and the scratch folders go to `$BENCH_TMP/daws` (default
`/tmp/paw-bench/daws`). Use `CORES` to pin to other cores. Each run takes
the settle time and the measured time. A round of the first command takes
about 5 minutes for each view.

To make all the tables of this page from the results file:

```sh
python3 bench/daws/table.py show bench/results/daws-2026-11-19.jsonl --split
```

The file has seven sets: `start`, `modes`, `fece459`, `window`,
`window-sweep`, `window2` and `window2-sweep`. The runs of the sets had
other scripts in a session folder, with the same method. The scripts in
`daws/` join them. The raw folders of the runs (screenshots, terminal
output, sandboxes) were session results and are not kept.
