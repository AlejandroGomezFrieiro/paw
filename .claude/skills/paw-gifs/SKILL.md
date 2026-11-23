---
name: paw-gifs
description: Make, make again or review a GIF of paw with the rig in docs/images/make. Use it when a task adds or changes a scene script (tui-*.sh). Use it when a change alters a view, key or message that a GIF shows. Use it for a demo, a screen recording or a picture of paw.
---

# GIFs of paw

The GIFs show paw to a new user. Each GIF is a script that drives the
real program, so a person or an agent can make each GIF again after a
change. The rig is in `docs/images/make`. It is better for paw than a
terminal recorder such as VHS. It uses a real terminal and needs no
browser. It also adds a caption and a bar of the keys.

The rules adapt the demo-gif skill of Conor Bronsdon
(github.com/conorbronsdon/demo-gif-skill, MIT license) to the rig of paw.

## When to make or make again a GIF

Make a GIF in these conditions:

- A new feature is in the README of paw or of an extension.
- A long scene shows too many features. Split it into GIFs of one feature.

Make a GIF again in these conditions:

- A change alters a view, a key, a caption or a message that a GIF shows.
  To find the scenes, search `docs/images/make` and
  `extensions/*/images/make` for the key or the command.
- The work on the ruler, the scopes and the clip edges of the arrange view
  lands. Then, make `tui-tour` and the other scenes of the arrange view
  again.

Do not make a GIF again only for a smaller file.

## The rig

| File | What it does |
| --- | --- |
| `make.sh` | Runs a set or one scene. It starts a Nix shell with WezTerm, ffmpeg, gifsicle and xdotool. |
| `rig.sh` | The functions of a scene: a private X display, the terminal, the recorder, the keys, the captions. |
| `gif.py` | Cuts the recorded file, adds the caption and the key bar, and makes the GIF. |
| `wezterm.lua` | The font and the colors of the terminal. |
| `tui-*.sh` | One scene for each GIF. |

```sh
# Into target/test-scratch/media, to examine:
NOCOPY=1 docs/images/make/make.sh tui-tour
# Into docs/images, to commit:
docs/images/make/make.sh tui-tour
```

The rig uses a private display (`:177`), a scratch home and `--audio null`.
Never use the display, the audio devices, the configuration or the home
folder of the owner.

`PAW_BIN` is the folder of the `paw` binary. Without it, the rig uses
`target/release`. An agent does not build: it sets `PAW_BIN` to the
shared binary of the session.

The scenes `gui-*.sh` need `paw-gui`. The graphical window is paused, so do
not make them.

## Recorded sessions

A recorded session is an asciicast (version 2) that the website plays with
`tools/website/paw-cast.js`. The reader can pause it and copy the keys of
each step. A cast scene is `cast-*.sh` in `docs/images/make`. It gives
steps to `cast.py` on standard input:

| Step | What it does |
| --- | --- |
| `caption TEXT` | Starts a step. The player shows TEXT and lists the keys of the step. |
| `keys KEYS` | Types KEYS in Vim notation, for example `4G5|<CR>`. |
| `pause SECONDS` | Records the screen for SECONDS. |

`cast.py` runs paw in a pseudo-terminal of 100 by 30 cells, with
`--clean`, `--no-plugins`, `--audio null` and a scratch home. It needs no
display. `make.sh cast-basics` writes `docs/images/cast-basics.cast`.
The rules for captions and for the loop apply to a cast too. To read the
screens of a cast as text, give the cast to the `Screen` class of
`paw-cast.js` in Node.

## Kinds of GIF

| Kind | Length | Where it goes |
| --- | --- | --- |
| The tour, `tui-tour.gif` | 60 to 75 s | At the top of `README.md` and of the first page of the website (`tools/website/landing.md`). |
| A GIF of one feature | 10 to 25 s | The section "A tour" of `README.md`, or its list in `<details>`. |
| A GIF of an extension | 10 to 25 s | The README of the extension, from `extensions/<name>/images/make`. |

A page of `docs/` shows a GIF only in a tutorial or a contents page. The
skill in [diataxis-docs](../diataxis-docs/SKILL.md) gives the rule.

## The structure of a scene

1. Write a comment at the top. It tells what the scene shows.
2. Source the rig, and set `SETUP` to the Lua that makes the start state.
3. Call `rig_start` and `term_start`.
4. Do the steps that the user must not see before `rec_start`.
5. Call `rec_start name`. The name is the name of the GIF.
6. Write one chapter for each feature. A chapter is a `cap` and its keys.
7. Call `rec_stop`. The last caption ends the GIF.

```sh
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO paw.cursor.set_track(paw.tracks()[1]) paw.flush()"
rig_start
term_start
rec_start tui-name
cap "Move: j k over tracks, w b e over clips"
pause 2.0; keys 0.35 j j w w e b; pause 0.8
rec_stop
```

`key` presses keys, `keys p ...` presses keys with a pause of `p` after
each, and `typ` types text at `TYPE_DELAY` ms for each character. The
comment at the top of `rig.sh` lists the other functions.

## Time of each step

| Item | Value |
| --- | --- |
| The first frame | 2 s on the start state, before the first key |
| A key in a series of motions | 0.25 to 0.4 s |
| A character of typed text | 70 to 150 ms (`TYPE_DELAY`) |
| Before `Enter` on a command line | 0.4 to 0.5 s |
| A result | 1 to 2 s, and 2 to 4 s for a screen with much text |
| A chapter | 3 to 8 s |
| The frame rate | 10 frames each second (`FPS` in `gif.py`) |

The key bar shows the keys of one group. A pause of more than 1.3 s, a new
caption, `Enter` or `Esc` starts a new group.

## Captions

- Write one caption for each chapter. It names the keys and the result:
  "Find: / jumps to a clip by name".
- Write the keys as the user types them: `Space fc`, `Ctrl-a`, `zw`, `5|`.
- Write not more than 72 characters. The caption and the key bar share a
  line of 1120 pixels.
- A caption is external text. Use the skill `plain-writing`.

## The key bar

`gif.py` writes each key as Vim writes it, for example `<C-a>` and `<CR>`.
If a key shows its X name in the bar, add the name to `NAMES` in `gif.py`.

## The loop rule

A GIF plays again from its start, so the last frame must show the
start state.

- Undo all the edits with one count, for example `7u`.
- Put the cursor and the playhead back, for example `gs gg 0`.
- Keep a count of the edits in the scene (`CHANGES` in `tui-tour.sh`). A
  count that is too large undoes the song of `SETUP`.
- Stop the song before the end, and close each panel and each window that
  the scene opened.

## The size budget

| Item | Value |
| --- | --- |
| Width | 1120 pixels (the terminal 1120 × 700 and the bar of 40 pixels) |
| Colors | 128, from the palette of ffmpeg (`COLORS` in `gif.py`) |
| Optimization | `gifsicle -O3 --lossy=30` (`LOSSY` in `gif.py`) |
| Largest file | 8 MB (`BUDGET` in `gif.py`) |

`gif.py` prints the size and the length of each GIF. It stops with an
error above the budget. A GIF of one feature is usually less than 1 MB,
and the tour is about 1.2 MB. The demo-gif skill gives 64 colors for a
terminal, but the colors of the clips of paw need 128.

## Alt text

- Tell what occurs on the screen, in order, in full sentences.
- Name a key only when the GIF is about that key.
- Change the alt text in each place that shows the GIF when the scene
  changes. Search `README.md`, `docs/` and `tools/website/` for the file
  name.

## Check a GIF

1. Before you write the scene, try the keys in a run without a display.
   Feed them with `paw.keymap.feed`, and read the screen with
   `paw.api.ui_frame_snapshot`. Use `tests/tools/run.sh --headless -l`.
2. Make the GIF with `NOCOPY=1`.
3. Extract some frames:
   `ffmpeg -ss 30 -i tui-tour.gif -frames:v 1 f30.png`. Read each frame.
   The time of `-ss` in a GIF is not exact. `gifsicle --info` gives the
   delay of each frame.
4. Make sure that each chapter shows the result that its caption names.
5. Make sure that the last frame and the first frame show the same state.
6. Make sure that the size and the length that `gif.py` prints obey the
   budget.
7. Make the GIF into its folder. Commit the GIF and its scene together.

## Write a scene that a change of the screen does not break

The screens of paw change often. Use these rules in each scene:

- Go to a track with its number (`4G`), and to a bar with `5|`.
- Find a clip by its name with `/`, not with a count of motions.
- Write a comment for each number that depends on the rows of that time,
  for example the track numbers and `CHANGES`.
- After a change of a view, make the GIF again and read its frames.
