# The graphical window
<!-- tags: window gui paw-gui -->

`paw-gui` is the graphical frontend of paw, and it shows the kernel's views
for the mouse, which are the transport, the tracks, the clips on a
timeline, the devices of the selected track, the mixer and the piano roll. The window page
describes its command line, its parts and what each gesture does. For the
reasons behind its design, see [About scenes](../explanation/about-scenes.md).
For the Lua functions behind it, see [The graphical window in
Lua](window-lua.md).

## Command line

```sh
paw-gui [kernel options] [project]
paw-gui --socket <path>
paw-gui --connect <host:port> --token-file <path>
```

| Option | Value | Effect |
| --- | --- | --- |
| kernel options, project | | Starts a kernel (`paw --headless`) with these options, and stops it when the window closes. |
| `--socket` | path | Attaches to a kernel that runs on this machine, on its Unix socket. |
| `--connect` | host:port | Attaches to a kernel on another machine, over TCP and TLS. The kernel must run with `--listen-tcp`. |
| `--token` | token | The token for `--connect`. |
| `--token-file` | path | The file that holds the token for `--connect`. |
| `PAW_TOKEN` | token | The environment variable that holds the token, when the two options above are absent. |
| `--accept-certificate` | | Accepts the certificate that the kernel shows, even when a different one is remembered for its address. |
| `--no-tls` | | Connects without TLS, to a kernel started with `--no-tls`. |
| `--listen-audio` | | Plays the kernel's sound on this machine (about 1 Mbit/s). The engine menu has the same switch. |
| `--renderer` | `gpu` (default) or `software` | `gpu` draws with OpenGL on the system's driver. `software` asks Mesa for llvmpipe, which draws on the processor. |
| `PAW_GUI_RENDERER` | `gpu` or `software` | The environment variable for the renderer, when `--renderer` is absent. |
| `PAW_GUI_STATS` | any value | Each 10 seconds, the window writes to its log the passes of its layout, the frames that it made without a pass, the frames that it showed, the pixels that it drew in each frame, the textures that it sent to OpenGL, and the age of the buffers that the driver gave. |
| `-h`, `--help` | | Shows the options. |

The token, the certificates and the TLS rules are in [The control
protocol](protocol.md#connections).

## The kernel and the window

The window keeps no project state. The kernel sends the state when it
changes (`frontend.watch`, at most 30 times a second), and each gesture and
each key returns to the kernel as a call to `paw.frontend.act` or as a key,
so the window, a terminal and a script can control the same project at
the same time.

A window that started its kernel shares the kernel's seat. A window
attached with `--socket` or `--connect` has a seat of its own: its own
cursor, selection and mode. See [Seats](protocol.md#seats).

The menus of the window are the kernel's menus (`paw.frontend.menu`, in
`runtime/lua/paw/window_menus.tl`), and the window shows them and tells the
kernel which entry the user selected.

## What the window keeps

The window keeps its layout in `window.json`, in the state directory of the
kernel's machine (`~/.local/state/paw/window.json`). It writes the file
when a value is stable for one second and when it closes, using
`paw.frontend.layout_get()` and `paw.frontend.layout_set(table)`, so a
window attached to a kernel that runs already also finds the file.

| Field | Value |
| --- | --- |
| `width`, `height` | The size of the window. |
| `x`, `y` | The position of the window on the screen, on X11 only. |

The zoom and the height of the tracks are the kernel's options
(`paw.opt.zoom`, `paw.opt.track_height`), the same as in the terminal.
What the panes show is the kernel's layout, which the project keeps (see
[Layouts](windows.md#layouts)) and not `window.json`.

On Wayland, the compositor decides the position of a window, so the
window keeps no position there. If no screen shows a saved position, the
window opens at the top left of the main screen.

## Graphics

The window is written with [egui](https://github.com/emilk/egui). It draws
with OpenGL through egui's glow renderer, on the system's driver, which is the
driver of the graphics card or Mesa's llvmpipe on the processor. On NixOS,
`hardware.graphics.enable` supplies the driver. If OpenGL cannot start,
the window shows one line that says so and stops.

At start, the window writes the name of the OpenGL renderer to its log
(`paw-gui: OpenGL renderer: ...`) and tells it to the kernel
(`paw.frontend.window_renderer`). If the renderer draws on the processor
(`llvmpipe`, `softpipe` or `swrast`), the kernel shows one warning that
gives the likely cause and what to do. `:checkhealth window` shows the
renderer and the advice for all the usual causes, which are in the table below.

| Cause | What to do |
| --- | --- |
| `PAW_GUI_RENDERER=software` or `--renderer software` | Remove the variable and the option. |
| `LIBGL_ALWAYS_SOFTWARE` is set | Remove the variable. |
| The system has no OpenGL driver for the graphics card | On NixOS, set `hardware.graphics.enable = true`. On other systems, install the Mesa drivers. |
| The X server gives no DRI3 (SSH with X forwarding, VNC, Xvfb) | Start the window on the screen of the computer. |
| The computer has no graphics card (no render node in `/dev/dri`) | The window can draw only on the processor. |

The window draws a frame only when something changes, so at rest it draws
nothing. While the song plays, it draws the playhead, the clock and the
meters at most `paw.opt.window_fps` times a second, and the value `"auto"`
(the default) is 30 on a graphics card and 15 on the processor, where
each frame costs much more. A key, the pointer and an edit show in the
next frame all the same. The window tells the kernel this rate, and the
kernel sends the values that move at the same rate and not faster.

The window also draws a frame again only where it changed
(`paw.opt.window_cache`) by dividing the window into squares of 32 by 32
pixels, where a square whose shapes are the same as in the last frame keeps its
pixels. While the song plays, only the squares of the playhead, the clock,
the meters and the live values change, which is a few percent of the window, and a
frame that changes no square is not drawn and not shown. The window draws
each changed square from all the shapes in it, so the pixels are the same
as when it draws the full window. With EGL, the window also tells the
display server or the compositor which parts changed, so they copy only
those parts. With the software renderer on X11, the window uses GLX and
copies only the changed parts to the window
(`GLX_MESA_copy_sub_buffer`), and once a second it copies all of the window,
so a part that an X server without a compositor lost returns. With
`paw.opt.window_cache = false`, the window draws each frame in full, and a
view in a window of its own always draws in full.

While the song plays, often only the live values change, and then the window
makes a frame without a pass of its layout, keeping the shapes of the
last pass and painting again only the parts that the live values move, which are the
playhead, the meters, the clock and the load of the engine. A key, the
pointer, a new scene or a change of mode starts a full pass, so a click
always finds what the window shows. A full pass also runs after 30 such
frames, and when a character of these parts shows for the first
time at its place.

A view that the kernel paints as a picture (notation) keeps the page of
the picture as one image. The window makes again only the small images
of the parts that move over the page, such as the playhead.

The piano roll and the timeline get
only the notes, lines and points near the visible area, so a clip of
thousands of notes opens and scrolls as fast as a short clip.

Measured with the demo song in a 1500x960 window on llvmpipe, without a
graphics card, with `LP_NUM_THREADS=4`. Other programs used the computer
at the same time, so the values are not exact:

| State | Load of the window, without the kernel |
| --- | --- |
| At rest | 0% of a core |
| While the song plays, the arrange view | about 10% of a core |
| While the song plays, the mixer | about 11% of a core |
| While the song plays, the piano roll | about 5% of a core |
| While the song plays, notation | about 14% of a core |

The kernel uses about 5% to 9% more. While the song plays, the window
draws about 4% of its pixels in each frame. Before the window drew only
the changed parts, the arrange view used about 37% of a core.

llvmpipe uses as many threads as the processor has free, so the load
that you measure changes with what else runs. To compare two windows, set
`LP_NUM_THREADS=4` for both.

On a graphics card, the card fills the pixels.

## Colors and fonts

The surfaces are neutral grays, and a color marks a state, as in the table below.

| Color | Meaning |
| --- | --- |
| Blue | The selection, the edit cursor, a switch that is on |
| Amber | The playhead, the loop |
| Green | Playback |
| Red | Record, an armed track |
| Orange | Mute |
| Yellow | Solo |
| The track's color | The track's stripe, its clips, its notes and its name plate in the mixer, and nothing else |

| Text | Font |
| --- | --- |
| Words | Inter, in the program |
| Numbers that change (the clock, levels, values) | JetBrains Mono, in the program |
| Japanese, Chinese and Korean (a lyric such as さくら) | The system's font for them, found through fontconfig (Noto Sans CJK, Source Han Sans and more) |
| Kana, when the system has no such font | Noto Sans CJK JP, cut to the kana (60 KB, in the program). Kanji and hangul then show as boxes. |
| Icons | Phosphor |

The fonts in the program are in `crates/paw-gui/fonts`, with their
licenses, which are the SIL Open Font License and MIT for Phosphor, so the window
looks the same on all machines.

## Parts of the window

From top to bottom, the window has the following parts.

- the transport bar
- a row of tabs, when there is more than one tab
- the main area, with one pane for each window of the current tab
- the status line.

A pane of the arrange view shows the ruler, the track headers and the
timeline, as the arrange view of the terminal does, drawn from its scene and
laid out in cells of the window's monospace font. The ruler is its first
row, a track is three to four rows tall, and the zoom is columns a beat.
The window paints the following parts as widgets, where they fall between cells.

- the clips
- the ground of each row, with its bar lines
- the curves of the automation and the tempo
- the levels and the switches of the headers
- the playhead.

The live values move the playhead and the levels with no new scene, and the
status line tells what the pointer does at its position.

## Transport bar

| Part | Gesture and effect |
| --- | --- |
| Buttons | Return to the start, stop, play or pause, record, loop, metronome. |
| Tempo | Drag it, or turn the wheel over it, to change the tempo. Double-click it to type a tempo. |
| Project name | Click it to open the file menu. A dot beside the name tells that there are changes that are not saved. |
| Mixer, Automation, Piano roll | Show or hide these views. |
| More | Lists all the other views of the kernel, also the views of extensions. Each one opens in a pane: where it docks, else split from the pane that has the keyboard. A view with a painted twin (`painted = "name"` on its table, as the undo tree and the mix report have) is offered as the twin. |
| Engine indicator (`pipewire · UR22mkII · 48 kHz`) | Click it to open the engine menu. |

## File menu

| Entry | Effect |
| --- | --- |
| New project, Open… | Make or open a project. If there are changes that are not saved, the window asks first. |
| Open recent | A submenu of the recent projects. "Clear the list" is at its end. |
| Recover unsaved work… | Runs `:recover`. |
| Save, Save as… | Save the project. |
| Import… | Imports a sound file or a MIDI file. |
| Render… | Opens the render dialog. |
| Sound files | "Find missing files…" (`:media.relink`) and "Copy into the project's folder" (`:media.collect`). |
| Markers and regions…, MIDI controllers… | Run `:marker.list` and `:learn.list`. |
| Quit | Closes the window. If there are changes that are not saved, the window asks first. |

The question about changes that are not saved has three answers, which are to save the
changes, to not save them, or to stay. For a project that has no file yet,
the window then asks where to save it, and a click on the close button of the
window asks the same question. In Lua, the question is
`paw.frontend.act.leave(how, "open:" .. path)`.

Open… with a `.mid` file opens it as a new project. Import, and the import
entry of the timeline menu, put its tracks below the track of the cursor,
starting at the cursor, and the tempo map does not change. See
[MIDI](midi.md#midi-files) for what paw makes of a MIDI file.

The render dialog has the fields below.

| Field | Values |
| --- | --- |
| File | The path of the rendered file. The `…` button opens a file dialog. |
| Range | The song, the loop, the selection or a region. |
| Format | WAV, FLAC. With ffmpeg installed, also MP3, Ogg and Opus. These have a quality (Low, Medium, High or Best) in place of the sample size and the dither. |
| Sample size, tail, normalize, dither, mono, a file for each track | As `:render` takes them. |
| Tags | Title, artist, album, track, year, genre, comment and cover. The project keeps them. |

The render runs in the background, and the status line shows its progress and
a Cancel button.

## File dialogs

When the window started its kernel, the two use the same disk, and then Open…,
Save as…, Import and the `…` button of the render dialog show the desktop's
file dialog. The window asks for the dialog through the XDG desktop portal
(`org.freedesktop.portal.FileChooser` over D-Bus) and links no toolkit.

- The dialog offers projects, MIDI files, sound files and all files.
- It starts in the directory of the last file selected, or beside the
  project if there is none, and the list picker of the kernel starts there too.
- The window continues to work while the dialog is open.

The window uses the kernel's list picker in the following conditions.

- there is no portal (no session bus, a bare window manager)
- `paw.opt.native_dialogs` is `false`
- the window is attached with `--socket` or `--connect`.

An attached window still shows the desktop's dialog for Import, and it then
sends the selected sound file to the kernel.

## Engine menu

The engine menu starts with the sample rate, the block size and the
latencies, and it lists the output devices, the input devices and the block
sizes. On an attached window, "Hear it on this machine" plays the kernel's
sound on this machine, as `--listen-audio` does, and the sound comes 0.25
seconds late or more.

## Ruler

| Gesture | Effect |
| --- | --- |
| Click | Puts the edit cursor and the playhead there. |
| Drag | Loops the dragged range. |
| Drag an edge of the loop | Changes the loop. |
| Double-click | Starts or stops the loop. |
| Drag an end of the punch range | Moves it. Hold `Shift` to move off the grid. |
| Drag a tempo flag (`96`) or a signature flag (`6/8`) | Moves the change. |
| Double-click a flag | Opens a prompt for a new value. |
| Right-click a flag | Removes the change. |

The ruler numbers the bars by the tempo map. The punch range is the line
under the band of the loop, red when punch is on and gray when it is off, and the
timeline menu sets the punch range from the selection or from the loop and
starts and stops punch.

## Tempo lane

The tempo lane is a row under the ruler that shows the tempo map as a
curve, where a change that holds is level and a ramp slopes. The timeline menu, `zT`
and `:tempo.lane` show and hide it, and its corner shows its range of tempos.

| Gesture | Effect |
| --- | --- |
| Click | Adds a tempo change at the tempo of the height clicked. |
| Hold and drag | Draws a curve of ramps. |
| Drag a change | Moves it in time and in tempo. The first change moves only in tempo. |
| Double-click a change | Makes it a ramp, or makes a ramp hold. |
| Right-click a change | Removes it. |

## Bands under the ruler

Under the markers, each extension that adds a band
(`paw.frontend.bands`) has a row, in the terminal too, for example the
findings of the mix. A click on an entry does what the entry is for, and the
status line says what the click does. The sections of the song are on the
ruler's second row, and a click on one goes to its start.

## Timeline

| Gesture | Effect |
| --- | --- |
| Click on empty space | Puts the edit cursor there and clears the selection of clips. |
| Double-click on empty space | Makes an empty MIDI clip, one bar long. |
| Drag across empty lanes | Selects a range of time on those tracks. Then `Delete` deletes it. A right-click on it opens a menu to delete, copy, loop or mute it. |
| Right-drag | Draws a box. The clips that it touches become selected. With `Shift`, they are added. With `Ctrl`, each one changes state. |
| Hold the middle button | Moves the view. |
| Right-click | Opens a menu on release, if the pointer did not move: a new clip, paste, a new track. |
| Drag a clip onto another pane | The view of the pane takes the clip if it takes clips: a slot of the session view of the clip launcher copies it. |

## Clips

| Gesture | Effect |
| --- | --- |
| Click | Selects the clip. |
| `Ctrl` and click | Adds the clip to the selection, or removes it. |
| `Shift` and click | Selects the clips between this clip and the last clip selected. On one track, by time. Across tracks, the rectangle. |
| Drag a selected clip | Moves all selected clips. They keep their positions to each other, also across tracks. They move in whole steps of the grid, so a clip off the grid keeps its distance to the grid. |
| `Ctrl` and drag | Drops copies. |
| `Shift` and drag | Moves off the grid. |
| Drag an edge | Trims the clip, and the same edge of each selected clip. The start moves without a change to what plays: an audio clip starts later in its file, a MIDI clip hides the notes before its new start. When you drag the edge out again, the notes show again. |
| `Alt` and drag an edge | Slips the contents inside the clip. |
| `Alt`, `Shift` and drag the right edge of an audio clip | Stretches its sound to end there. See [Stretched and repeating clips](stretch.md). |
| Drag the end of a looped clip | Makes it longer, and the loop repeats. |
| Double-click | Opens the notes of the clip. A selection of several clips opens all of them, with the clicked one active. A clip of a kind of track with an `editor` opens in that editor. |
| Right-click | A menu: rename, split at the pointer or at the edit cursor, glue the selected clips, repeat, mute, stretch, shift, loop, delete, and the entries of extensions. |

On an audio clip:

| Gesture | Effect |
| --- | --- |
| Drag a top corner | Changes the fade in or the fade out. The fade shows on the clip. |
| Drag the top line | Changes the gain of the clip. Hold `Shift` for small steps. The height of the waveform follows the gain. |
| Double-click the top row | Puts a warp marker there: a yellow line down the clip, with a handle at the top. |
| Drag the handle of a warp marker | Moves it on the grid, and stretches the sound on each side. Hold `Shift` to move off the grid. |
| Right-click the handle of a warp marker | Removes it. |

Each gesture is one undo step. Two or more selected clips are the
selection of visual mode, so `d`, `x`, `y`, `>`, `gc`, `J` (glue) and the
other operators act on them, `S` splits them at the cursor, and `Esc` clears
the selection. One clip selected with a click is the clip under the cursor.

## Track headers

A track header is the terminal's header, with a stripe in the color of
the track down its left, and it shows the following, line by line.

- the number and the name of the track, the letter of its automation mode
  (`A`, `T`, `L`, `W`) and the switches `M`, `S`, `R` and the loudspeaker
  (`I` in the terminal, monitor). A switch that is on has its color.
- the input button (the microphone, `in` in the terminal), the level of
  the track with the place of its fader on it and its clip light, and the
  volume in dB
- a knob for the pan, the devices of the track and the track it plays into
- the sends, and the input with the level that arrives there.

A shorter row shows less, and the shortest row shows only the first line. The
master is the last header, with its level on both sides.

The level is green to −18 dB, then yellow-green, yellow,
orange, and red from 0 dB, and a thin line holds the peak for a short time.
The clip light comes on when a level reaches 0 dB, and it stays on until you
click the volume in dB.

| Gesture | Effect |
| --- | --- |
| Click | Selects the track. |
| Double-click | Opens a prompt for a new name. |
| Drag up or down | Moves the track. Drop it among the tracks of a group, or under its header, to put it in the group. Drop it outside the group to remove it from the group. |
| Click `M`, `S`, `R` or `I` | Changes the switch. |
| Press `M`, `S` or `R` and move across other tracks | Sets the switch of each track as the first one was set. |
| Drag the level sideways | Changes the volume, one dB a cell. Hold `Shift` for small steps. |
| Double-click the level | Sets the volume to 0 dB. |
| Drag the pan sideways | Changes the pan. A double-click sets the center. |
| Click the microphone | Opens a menu of the audio inputs, MIDI ports and MIDI channels of the track. |
| Click the volume in dB | Puts out the clip light. |
| Drag the bottom edge (in the terminal, `Alt` and a drag on the header) | Changes the height of the track, in lines. The track keeps its height. |
| Double-click the bottom edge | Gives the track the height of the other tracks. |
| Right-click | A menu on release: color, duplicate, bounce to audio, a new track below, delete, the input, the groups, the VCAs, the take lanes, the automation, the templates, and the entries of extensions. |

The menu of a track has three entries for groups. They are `New group
with this track…`, `Move into a group…` and `Take out of its group`
(`Dissolve the group` on a group). The members of
a group show under it, one step in and in its color, and their sound goes
through the group. The triangle beside the name of the group hides and
shows the members.

## Routing

Under the devices of the selected track, in the device panel:

| Part | Effect |
| --- | --- |
| Output | Selects the track that this track plays into. |
| + Send | Adds a send to another track. |
| Level of a send | Drag it to change the level. |
| `pre` | Takes the send before the fader. |
| Cross | Removes the send. |

## Templates

With the templates extension:

| Menu | Entry | Effect |
| --- | --- | --- |
| A track's menu | Save as a template… | Saves the track. On a group, saves the whole group. |
| A track's menu | Save its devices as a chain… | Saves the chain of devices. |
| `Track`, and the timeline menu | From a template… | Makes a track from a template. |
| A track's menu | Add devices from a template… | Puts a saved chain on the track. |

## Record

| Part | Effect |
| --- | --- |
| Record button | Starts a take on the armed tracks. With no track armed, it arms the selected track and tells so. A second click, or stop, ends the take. |
| `R` on a track | Arms the track. |
| The microphone on a track, or Input on its menu | A menu of the audio inputs, MIDI ports and MIDI channels of the track. The input (for example `UR22mkII · 1/2`) shows on the last line of the header, with the level that arrives there, armed or not. |
| The loudspeaker on a track | Starts and stops input monitoring. |

A track without an audio input records MIDI. The take shows in red on
each armed track and grows longer while it records, and with punch on, it
records only in the punch range. With a count-in, the clock shows `count 4`, `count 3` and
so on, and the button blinks on the beats until the take starts. The
timeline menu starts and stops the count-in, and a pre-roll of two bars
before a punch.

## Take lanes

A track's menu, a clip's Takes menu or `zt` shows the takes of a track as
lanes under its clips.

| Gesture | Effect |
| --- | --- |
| Drag across lane k | Take k plays over that range, on the grid. Hold `Shift` to move off the grid. The clips are cut at its ends. Adjacent pieces of the same take join again. It is one undo step. |
| Click on lane k | Gives the piece under the pointer take k. |
| Right-click | Hides the lanes. |

The mouse of the terminal does the same (see [The mouse](mouse.md)).

## Automation

Automation on the transport bar shows the lanes of the selected track as
rows under its clips, or hides them (`:lane.rows`). The track with the
cursor shows its volume curve over its empty lane.

| Gesture | Effect |
| --- | --- |
| Click | Adds a point. |
| Hold and drag | Draws a curve. |
| Drag a point | Moves it. |
| Right-click a point | Removes it. |
| Right-click elsewhere | A menu to clear the lane or to stop it. |
| Curve button beside a parameter of a device | Gives the parameter a lane and shows the lanes of the track as rows. |
| Right-click the name of a parameter | A menu to automate it (a lane with a point at its value, at the cursor), or to edit its curve in the curve editor. The curve editor opens in a pane split from the pane that has the keyboard. |

A track's menu has Automation ▸ Show or hide the lanes as rows, as the
button does. Each lane of the track is then a row under its clips, always
ready for points, with the gestures above. The clips above stay editable.
A track with no lane gets a lane for its fader. The same menu sets the
automation mode of the track, which the letter on the header shows.

## Session view

The clip launcher extension adds the session view (More ▸ Session). The
window draws it from its scene, with the gestures of the terminal. See
[its README](../../extensions/launcher/README.md).

## Mixer

The mixer is the terminal's mixer, laid out in cells of the window's
monospace font. Each track has a strip, the VCAs follow the tracks, and the
master is the last strip, and a strip shows the following.

- the name of the track on a plate in its color
- the track it plays into
- its first four devices and its sends, when the mixer is tall enough
- the meters and the clip light, beside a fader with its scale
- the peak, the level and the pan
- the switches `M`, `S`, `R` and `I`.

The window paints the faders, the switches, the meters, the peaks and the
clip lights as widgets (the roles of [About
scenes](../explanation/about-scenes.md)). A fader cap can be at any point
along its travel. The live values move the meters, the peaks and the clip
lights 30 times a second, with no new scene, and the pointer uses the hit
regions of the terminal, in fractions of a cell, so a fader moves smoothly.

| Gesture | Effect |
| --- | --- |
| Drag a fader up or down | Changes the level. Hold `Shift` for small steps. |
| Drag the level sideways | Changes the level. |
| Click or drag along the pan | Changes the pan. |
| Double-click a fader or a pan | Sets 0 dB or the center. |
| Wheel | Moves the fader. With `Shift`, scrolls the strips. |
| Click a device | Shows it in the device panel. |
| Click the output | Opens a menu of outputs. |
| Drag a send | Changes its level. |
| Click `M`, `S`, `R` or `I` | Changes the switch. |
| Click the peak or the clip light | Clears the clip light. |
| Right-click a strip | Opens the menu of the track. |

The menus of a strip and of a track header have entries for VCAs. They
make a VCA with the track, put the track under a VCA, or remove it from
its VCA.

When the mixer has the keyboard, its strip shows the row of its cursor, as
in the terminal.

## Device panel

The device panel is the kernel's device panel, drawn from the same scene
as in the terminal, and the window paints its parts as widgets. The heading of
a device is a band with a power button, a parameter is a slider with its
value, and the buttons have icons.

The pointer uses the hit regions and gestures of the
terminal, in fractions of a cell. [The device panel](device-panel.md#the-pointer)
lists the gestures.

| Gesture | Effect |
| --- | --- |
| `+ add a device` | Opens the picker of devices. Type part of a name, then `Enter`. `Ctrl-f` in the picker makes a device a favorite. |
| Drag a slider | Changes the parameter. |
| `Ctrl` and the wheel over a slider | Changes it in small steps. |
| Double-click a slider | Sets it to its default. |
| Power button | Disables or enables the device. |
| Arrows, cross | Move the device along the chain, remove it. |
| Window button | Opens the plugin's own editor. |

A parameter that a lane moves has an amber slider, and the slider moves with
the lane while the song plays, with no new scene from the kernel.

## Piano roll

The piano roll is the kernel's piano roll, drawn from the same scene as in
the terminal, and its grid is a plane of beats and pitches. The window paints
the notes where they are, between cells, in the colors of their tracks.
The pointer uses the hit regions and gestures of the terminal's mouse, in
fractions of a cell. The mouse works as in REAPER's MIDI editor.

Notes:

| Gesture | Effect |
| --- | --- |
| Drag on empty grid | Draws a note from where the press starts to where the drag stops. |
| Click on empty grid | Draws a note of the note length on the tools row. To draw or stretch a note sets that length. |
| `Shift` while you draw, move or stretch | Moves off the grid. |
| Click a note | Selects it. |
| `Shift` or `Ctrl` and click a note | Adds it to the selection, or removes it. |
| Drag a note | Moves it and the other selected notes. With `Ctrl`, drops copies. A copy of the note follows the pointer. |
| Drag an end of a note | Changes the start or the end of all selected notes. |
| Right-drag, or `Ctrl` and drag | Selects the notes that the box touches. With `Shift`, adds them. With `Ctrl`, each one changes state. |
| Right-click a note | Removes it. |
| Right-click empty grid | A menu: select all, clear the selection, delete, quantize, snap. |
| Double-click a note | Removes it. |
| `Alt` and drag | Erases each note that the pointer crosses. |

While you drag, the status line shows the name, the position and the
length of the note.

The keyboard and the view:

| Gesture | Effect |
| --- | --- |
| Click or drag on the keyboard | Plays the key under the pointer. |
| Right-drag on the keyboard | Selects the notes in that range of pitches. |
| Wheel | Scrolls the pitches. With `Shift`, scrolls in time. |
| `Ctrl` and wheel | Zooms in time at the pointer. |
| Middle button | Moves the view. |
| Scroll bar at the right of the grid | Scrolls the pitches, in a wide roll. |
| Click on the ruler | Moves the playhead. |

| Key | Effect |
| --- | --- |
| `Ctrl-a` (in the window), `gA` | Selects all notes. |
| `x`, `Delete` | Remove the selected notes. |
| `Esc` | Clears the selection. |

The strip under the roll shows the velocities. Its name at its left (Vel ▾)
selects what it shows: velocities, or a controller (pitch wheel,
modulation, expression, pedal).

| Gesture | Effect |
| --- | --- |
| Drag across the velocity bars | Sets the velocities. If notes are selected, only theirs. |
| Hold and drag on a controller | Draws moves. |
| Right-drag on a controller | Draws a straight line of moves. |
| Click the head of a move | Selects it. With `Ctrl`, adds it or removes it. |
| `Ctrl` and drag | Selects the moves in a box. |
| Drag a selected head | Moves the selected moves. |
| `Delete` | Removes the selected moves. |
| Right-click | A menu: select all, clear the selection, delete, clear. |

The tools are at the right of the title row of the roll. A roll can be
narrower than 140 columns and 20 rows tall or more, and then the tools are on
a row of their own under the title, in the terminal too. Before them, the row shows
the selection, or what insert mode draws. The tools are, in order, as follows.

| Tool | Effect |
| --- | --- |
| grid | A menu of grid sizes. |
| note length | A menu of note lengths. |
| snap | Starts or stops the snap to the grid. |
| quantize | Quantizes the selected notes, or all notes (`:notes.quantize`). |
| step | Step input (`I`): notes played on a MIDI keyboard go in at the cursor. A click starts or stops it. |
| list | The event list: each note and move of the clip as a row to change in place. See [The event list](midi.md#the-event-list). |
| Suggest, and other switches of modules | Start and stop the suggestions of a completion source. |
| tracks | `:roll.tracks`: each track near the roll, to show or hide its notes, and its clips, to edit them together. |
| zoom | A menu of zooms. |
| Window | Moves the roll into a window of its own. |
| x | Closes the roll. |

Above the ruler, a row shows the names of the chords that sound over all
pitched tracks (`paw.opt.chords` sets names, Roman numerals, both, or off). See
[Harmony](harmony.md). The ruler counts bars
and beats, a dot on the keyboard shows the keys that sound at the cursor,
and the title shows the name of the chord.

Notes of the other clips of the track, and of other pitched tracks, show
behind as dashed lines in their colors. The layers that extensions add
show as in the terminal, and they include the articulations, the notes of a
snippet, the ghosts of a suggestion and its badge, and the outline of the
notation.

Several clips:

| Gesture | Effect |
| --- | --- |
| Click a note of another track | Makes its clip the active clip. New notes go there. |
| `Ctrl` and click a note of another track | Adds its clip to the edited clips, or removes it. |
| Double-click one of several selected clips in the timeline | Opens all of them, that one active. |

With several clips edited, each clip's notes have the color of its track.
A click, a box, a drag, `Delete`, the velocity strip and the keys reach the
notes of all of them, each note stays in its clip, and each edit is one undo
step.

Suggestions, with a completion source loaded (see
[Harmony](harmony.md)):

| Key | Effect |
| --- | --- |
| Suggest on the tools row | Suggestions come by themselves after a pause. |
| `Ctrl-Space` | Asks for a suggestion. |
| `Tab` | Accepts the suggestion. A click on the badge does the same. |
| `Alt-1` … `Alt-9` | Shows another suggestion. |
| `Esc` | Dismisses the suggestion. |

## Wheel and zoom

| Gesture | Effect |
| --- | --- |
| Wheel | Scrolls. |
| `Shift` and wheel | Scrolls sideways. |
| `Ctrl` and wheel | Zooms in time at the pointer, in the timeline and in the piano roll. Over the track headers, it makes all tracks taller or shorter. |
| `Alt` and wheel | Makes the tracks taller or shorter. |
| `Ctrl -`, `Ctrl +` | Zoom in time the view that has the keyboard (`:zoom by=…`, as `zo` and `zi`). |
| `Ctrl 0` | Shows the whole song (`:zoom fit`). |
| `Ctrl ↑`, `Ctrl ↓` | Change the height of the tracks, from one line to twelve. |

In the timeline, the wheel scrolls a track, or a bar with `Shift`. After a
zoom, the window draws the waveforms again at their new width.

## Sound files and MIDI files

| Gesture | Effect |
| --- | --- |
| `Track` → "From a sound file…", or "Import a sound or MIDI file…" in the timeline menu | Opens a list of files. Type to make the list shorter. `Enter` opens a directory. A wav, aiff, flac, mp3 or ogg file goes on a new track at the cursor. |
| `:import path` | Does the same. |
| `paw-gui take.mp3` | Starts a project with the file. |

## Drops

On X11, you can drag files from a file manager into the window:

| File | Result |
| --- | --- |
| A sound file | A new track for each file, with the clip at the edit cursor. |
| A MIDI file | Its tracks, as `:import` puts them. |
| A project (a project folder, its `project.toml`, or a `.json` file) | Opens it, after the question about changes that are not saved. |
| Other files | The status line tells that it did not take them. |

The window does not know the position of the pointer at a drop, because
winit 0.30 does not tell it, and with this version of winit, Wayland sends no
drops. A window can be attached to a kernel that it did not start, and then
it first sends the sound files and MIDI files to the kernel, into the
media folder of its project. It sends no other files.

## Pages over the window

A picker (commands, files, devices) shows over the window.

| Gesture | Effect |
| --- | --- |
| Click a row | Selects it. |
| Double-click a row, or `Enter` | Accepts the row. |
| Wheel | Scrolls. |
| Click outside the page | Closes it. |
| "Open in a window" at its top right | Moves the page into a window of its own, in its colors. |

## Keys

All keys go to the key mappings of the kernel, so the window has the
modes, operators, registers and macros of the terminal. The status line
shows the following.

- the mode, and the view that has the keys (`NORMAL·mixer`)
- the prompt, messages and keys typed so far
- the important keys of the view that has the keyboard (the key bar of the terminal, `paw.opt.keybar`)
- the count of the quickfix list (`qf E1 W2`), in the color of the worst entry.

While you type a command, a list above the status line shows what the
command can become, with a description of each, and `Tab` and `Shift-Tab` move
through it. `Up` and `Down` move through the history. A message stays until
the next key, a change of mode, or the end of `paw.opt.message_time`.

The window shows the selection, the two cursors, the list of the keys that
can come next, and help and other pages over the window, and a page such as
the list of commands is as wide as the window. `Ctrl-z`, `Ctrl-y`, `Ctrl-s`
and `Delete` do what they do in the terminal. When the piano roll or the
mixer opens, it gets the keyboard.

`:help` opens the manual in a pane, split as in the terminal. `Ctrl-w f` or
`:textbuf.window` moves it into a window of its own. The keys are the keys
of help in [Help](help.md).

## Panes and tabs

The window shows the tabs and windows of the kernel, as the terminal does
(see [Windows, buffers and tabs](windows.md)).
Each window of the current tab is a pane of the main area, laid out by
the same rules, where a size in cells is that number of cells of the monospace
font, in pixels. A pane is never smaller than the window's own drawing of
its view needs.

| View | How the window draws it |
| --- | --- |
| The arrange view, the mixer, the piano roll, the device panel, the drum grid | From the scene. The window paints the roles (clips, curves, faders, meters, switches, buttons, sliders, notes) as widgets. |
| A view that paints (the notation, the vocal editor, the undo tree) | From the scene, as a picture. |
| Any other buffer (a curve `paw://lane/3`, the quickfix list, a text buffer `paw://tracks`, an empty window) | From the scene, cell by cell in the monospace font, as the terminal draws it. |

A pane drawn from its scene has the window's own title. Its buttons move
the pane into a window of its own, or close it. The title row of the
terminal is hidden under it. What a view draws over a role (the
articulation of a note, the cursor, the selection) shows over it, as in
the terminal. A menu that the view opens (a right-click) shows as a menu
of the window. An idle pane does no work.

The keys and commands below do in the window what they do in the terminal.

`:vs paw://lane/3`, `Enter` on a lane row, `:copen`, `:sp quickfix`,
`:e paw://tracks`, `Ctrl-w` and its keys, `:q`, `:only`, `:tabnew mixer`,
`gt`, `:layout edit`.

| Gesture | Effect |
| --- | --- |
| Press in a pane | Gives the pane the keyboard. A ring in the color of the selection shows that pane, when there is more than one pane. |
| Drag a border between panes | Shares the space. The panes keep a size of whole cells, as `Ctrl-w +` does. The kernel moves the border with the code that moves it in the terminal (`paw.layout.drag_border`). |
| Click a tab | Goes to the tab. The row of tabs shows when there is more than one tab, as the tab line of the terminal does. |
| The close button of a tab, or a middle click on a tab | Closes the tab, as `:tabclose` does. The last tab stays. |
| Drag a tab along the row | Moves the tab there, as `:tabmove` does. A line shows where it goes. |
| `+` after the last tab | Opens a new tab with the start page, as `:tabnew` does. |
| The close button of a pane | Closes its window, as `Ctrl-w c` does. The last window of a tab stays. |

Two panes of one view (two piano rolls, two mixers, two device panels)
are two scenes. Each has the state of its window: its clip, cursor and
scroll. A view moved into a window of its own keeps the state of the pane
that it left, and then has its own, while the other panes of the view stay.
When it returns to the main window, the pane shows what the window showed.

Each attached window has its own tabs and windows. When a window shows its
main area for the first time, the kernel shows the device panel if
the tab has its closed place, as the default start layout has. A start layout of the
configuration (`paw.ui.start_layout`) shows as it is.

A window narrowed to a group (`:narrow Strings`, `znag`, see
[Scopes](narrowing.md))
gives the name of the group to its tab in the row of tabs. Its pane shows
only the tracks of the group, because the timeline, the mixer and the device panel take
their rows from `paw.groups.rows()`.

## Views in windows of their own

A view can move into a window of its own:

- `:view.window undotree`, which without a name moves the focused view, or the page over the other views.
- `Ctrl-w f` in a curve and in a text buffer.
- The button on the title of a pane drawn from its scene.
- "Open in a window" on a page over the window.

The window opens over the center of the main window and shows the view
under a title with a Dock button. Its status line shows the mode, then a
prompt, a message, or the keys of the view. A view in a pane leaves the
pane while it is in a window, and the window has the keyboard while it is in
front.

| Action | Result |
| --- | --- |
| The close button, the Dock button, or `Ctrl-w d` (`:view.dock`) | The view returns to the main window as a pane: where it was, else where it docks, else split from the window that has the keyboard. That pane gets the keyboard. |
| `:q`, or the view's own `q` | Closes the view. The keyboard returns to the main window, to the pane that had it. |
| `Esc` | Stays in the view. |
| A key typed in the main window | The keyboard returns to the main window. |

The kernel draws the view at the size of the window, in cells of
JetBrains Mono, with the theme's colors in 24 bits. The
size of a cell comes from the font, so box-drawing characters join.

Keys go to the view's mappings with the view focused. A prompt that the view
opens shows there. The pointer goes to the view's `on_mouse` in cells,
as from a terminal: down, up, drag, scroll. The kernel draws the view again
only when a redraw is necessary and the view changed, at most 30 times a
second.

The font has no braille, so the window draws each braille character
(U+2800 to U+28FF) as small squares, in two columns and four rows of dots.
The font also has no sextants (U+1FB00 to U+1FB3B, the default for curves), so
the window draws each one as up to six rectangles, each a half cell
by a third. `paw.opt.curve_glyphs` selects the characters, and
`paw.opt.braille` off draws lines.

A terminal attached to the same kernel does not change, because the view is drawn
on a grid of its own (`paw.api.ui_view_snapshot`).

## Status line

The status line of the window is its own. It shows the mode, the prompt,
messages and keys. `paw.statusline.setup` (see
[The status line](status-line.md)) sets
`modal.statusline` in `frontend.state`, but only the terminal draws it, and the window does not.
The extra sections of the tab line, and
`tabline.always`, are also for the terminal only.
