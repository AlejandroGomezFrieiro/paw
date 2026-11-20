# paw

**A personal audio workstation that you control as Neovim and change in Lua.**

[![License: MIT OR Apache-2.0](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue)](#license)
![Linux](https://img.shields.io/badge/platform-Linux-informational)
![Built with Nix](https://img.shields.io/badge/built%20with-Nix-5277C3)

![The demo song plays. 3>ic moves the melody, . moves it again and u undoes it. :%s/e5/g5/g changes it, with a preview while it is typed](docs/images/tui-arrange.gif)

paw is a digital audio workstation for Linux. A small Rust kernel plays the
sound, keeps the project and hosts plugins. Each view, command and key that
you use is Lua, and your configuration can change it. To extend paw, use
[your `init.lua`](docs/how-to/configure-paw.md), [extensions](#extensions),
[devices written in Lua](docs/reference/lua-devices.md) and
[kinds of track](docs/reference/extensions.md#kinds-of-track). You can
package them for Nix or share them as a git repository.

The core of paw is a complete DAW. Extensions add the score, the drum grids
and the synthesized voices. To get a feature that is not there, write it in a
few lines of Lua or load an extension that adds it.

```lua
-- ~/.config/paw/init.lua: :reload applies it and the sound does not stop
paw.ui.hl("Playhead", { bg = "#f38ba8" })
paw.keymap.set("<leader>T", "track.add Strings device=synth", { desc = "A strings track" })
```

paw works in the [terminal](docs/reference/grammar.md). It is modal and you use it
from the keyboard. Where the terminal can show pictures (kitty graphics), paw
shows them. The same views also open in a [graphical window](crates/paw-gui/README.md)
for the mouse, from the same Lua. [Lua scripts](docs/reference/scripting.md), a
[socket](docs/reference/protocol.md) (`paw ctl`) and an [AI agent](#for-agents)
can also control paw.

> [!NOTE]
> paw is a **personal project and it is not complete**. One person made it
> for their own music. It runs on Linux (PipeWire, ALSA or JACK). It plays,
> edits, records and renders MIDI and audio through built-in devices and
> CLAP, LV2 and VST3 plugins. Most tests use stand-ins, not real hardware,
> and paw can change without notice. See
> [what paw does not do](docs/reference/limits.md).

[Try it](#try-it) · [Is paw for you?](#is-paw-for-you) ·
[What it does](#what-it-does) · [A tour](#a-tour) ·
[Extensions](#extensions) · [Documentation](#documentation)

## Try it

You need Linux and [Nix](https://nixos.org/download/) with flakes enabled
(`experimental-features = nix-command flakes` in `nix.conf`). The first run
builds paw from source. This takes several minutes.

1. Get the source and start paw with a demo song:

   ```sh
   git clone https://github.com/AlejandroGomezFrieiro/custom_daw paw && cd paw
   nix run . -- -e 'dofile("examples/demo-song.lua")'
   ```

   The arrange view shows the song, with one row for each track.
2. Press `Space`. The song plays and the playhead moves to the right.
3. Press `Space` again to stop the song.
4. Press `?`. A list shows each key of the current view.
5. Press `Esc` to close the list.
6. Type `:tutor` and press `Enter`. The first of seventeen short lessons starts.
7. Type `:q` and press `Enter` to quit.

`:help` opens the manual. `:checkhealth` shows what works on your computer.
`nix run . -- doctor` examines your sound devices, MIDI ports and plugins.
[How to install paw](docs/how-to/install-paw.md) and
[how to build it from the source](docs/how-to/build-paw-from-source.md) give
the steps. [The programs](docs/reference/programs.md) lists their options.

## Is paw for you?

paw is for people who like open programs that they can change. They use
Neovim or a window manager that tiles, and they keep their configuration in a
repository. They write ten lines of Lua before they wait for a feature.

| If you want | Look at |
| --- | --- |
| A modal DAW in the terminal for the keyboard, which you can script and change | **paw** |
| A mature DAW on each platform, with many settings | [REAPER](https://www.reaper.fm) |
| A mature open-source DAW to record and mix on Linux | [Ardour](https://ardour.org) |
| Sound design, modulation and performance | [Bitwig Studio](https://www.bitwig.com), [Ableton Live](https://www.ableton.com) |
| A tracker for composition from the keyboard | [Renoise](https://www.renoise.com) |
| Scores to print first, playback second | [MuseScore](https://musescore.org), [Dorico](https://www.steinberg.net/dorico/) |

paw is newer and smaller than all of them. Select it for the way it works,
not for the length of its list of features.

## What it does

- **Edit.** MIDI and audio clips, a piano roll, take lanes and comps,
  time stretch and pitch shift, looped clips and markers. A tempo map with
  changes of time signature, and an undo tree that keeps each branch. Each
  note can have an articulation (MIDI 2.0). paw sends it to each instrument
  as the keyswitches that the instrument needs.
- **Large projects.** `:narrow Strings` shows only one group in the views
  and freezes the other tracks to audio. You can freeze a track and render
  stems by group.
- **Record.** Audio and MIDI, with an input for each track that you can monitor.
  Loop recording into takes, punch in and out, and a count-in. Takes stay
  after a crash.
- **Mix.** Groups, sends, side-chains, instruments with several outputs,
  automation with the read, touch, latch and write modes, and controller learn.
- **Devices.** A synth, a drum kit, fifteen effects and meters, and a sample
  player for SFZ and Decent Sampler libraries. Devices written in Lua, and
  your CLAP, LV2 and VST3 plugins. Each plugin runs in a process of its own,
  so a crash stops only that plugin.
- **Files.** A project is a folder of text files that you can read: a file
  for each track and for each clip. paw renders to WAV
  and FLAC (MP3, Ogg and Opus through ffmpeg) in the background. It opens and
  exports MIDI files.
- **Find.** Pickers as in telescope and fzf-lua, with previews that you can
  hear. `:vimgrep` puts matches from the whole project in the quickfix list.
  Queries find items by structure (`:select clip[name~=pizz] > note[pitch>=C5]`).
- **Folders.** A file manager as in oil.nvim (`:e ~/samples`). Edit the lines
  to rename, move and place sounds. `:Pdiff` and the git drivers compare and
  merge projects.
- **Live and remote.** Scenes start clips on the bar ([the clip launcher](extensions/launcher/README.md)).
  A terminal or a graphical window can attach to paw on a different computer
  over TLS ([how to work from another computer](docs/how-to/work-from-another-computer.md)).

## A tour

The keys work as in Vim, but on a timeline and not on a text. paw has
counts, operators, motions, text objects, visual mode, registers, macros,
marks and `.`. One rule applies in each view: `h` `j` `k` `l` only move, `+` and `-`
change the value under the cursor, and `Esc` cancels.

![Notes drawn with i, typed on the home row with I, selected and transposed](docs/images/tui-pianoroll.gif)

The command line accepts Ex commands. A line is a bar, and a range can be a
range of tracks (`:5,8d`, `:t2,t4 mute`, `:%s/c4/d4/gc`). paw shows a
preview while you type:

![A substitution confirmed match by match, then tracks muted by a range](docs/images/tui-ex.gif)

The mixer, the device picker and the device panel are views like the other
views. A picker plays each item before you select it:

![The mixer while the song plays: a fader moves, a track is muted, and the picker adds a chorus](docs/images/tui-mixer.gif)

You can edit tracks, sends, devices and markers as text, as oil.nvim edits
folders. `:w` shows the plan and applies it as one undo step:

![The tracks as text: one renamed and turned down, then written](docs/images/tui-textbuf.gif)

<details>
<summary>More: find, files, large projects, record, help, configuration</summary>

![The clips picker shows the melody beside the list. Then the notes picker. Then :vimgrep puts four clips in the quickfix list, and ]q moves through them](docs/images/tui-pickers.gif)

![:e ~/music shows a folder of sounds as text. cw renames a file. A new name moves one into samples/, and dd deletes one. :w shows the plan](docs/images/tui-files.gif)

`zn` narrows the views to one group of tracks, `:t*` is the range of its
tracks, and `:freeze` renders the other group:

![The song has two groups. The views narrow to the rhythm section, and the other tracks play from files. Then the other group is rendered](docs/images/tui-narrow.gif)

![Loop recording into takes (a script plays the notes), and a comp of one take](docs/images/tui-takes.gif)

![The keys of a view, the leader's list, K on a clip, and :help](docs/images/tui-help.gif)

![init.lua edited beside paw: :reload changes the playhead and adds a key](docs/images/tui-config.gif)

</details>

[docs/reference/keys.md](docs/reference/keys.md) shows all the keys on one page.
You can make your own status line, as with lualine (`paw.statusline.setup`).

**The graphical window.** `paw-gui` shows the same views as panes for the
mouse. The terminal and the graphical window use the same Lua. See
[its page](crates/paw-gui/README.md).

## Extensions

An extension is a folder of Lua. It adds commands, keys, views, buffer
types, devices and kinds of track. It has a manifest, hooks into each edit,
save and undo, and its own `:checkhealth`. The extension owns all that it
adds, and `:ext.unload` removes all of it.

An extension can also include the native programs that it needs, and Nix
builds them. [utau](extensions/utau) has its own voice engine and
[sampler](extensions/sampler) has its own sample player. The core does not
know about them.

A view that an extension writes works in the terminal and in the graphical
window. See
[extensions](docs/reference/extensions.md) and the [API reference](docs/reference/api.md).
LuaLS completes `paw.*` from [runtime/types](runtime/types). With Claude Code,
the [`paw-extension` skill](.claude/skills/paw-extension/SKILL.md) gives the
instructions.

| Extension | Adds |
| --- | --- |
| [notation](extensions/notation) | a clip as a score or tablature, engraved, a view over its MIDI |
| [utau](extensions/utau) | vocal tracks that OpenUtau's voicebanks sing, with their own editor |
| [sampler](extensions/sampler) | paw's own sample player: SFZ and Decent Sampler, an articulation for each note |
| [articulations](extensions/articulations) | one file for each instrument: keyswitches, ranges, delays and an articulation for each note |
| [drums](extensions/drums) | drum tracks and a grid to program them |
| [pattern](extensions/pattern) | clips written as a line of text, as in TidalCycles |
| [musicops](extensions/musicops) | humanize, strum, arpeggiate and other note edits |
| [sections](extensions/sections) | intro, verse and chorus as named parts of the song |
| [templates](extensions/templates) | tracks and device chains saved under a name |
| [undotree](extensions/undotree) | the undo tree, to move through |
| [projdiff](extensions/projdiff) | the changes in a project, and a merge of two versions of it, also in git |
| [mixdiag](extensions/mixdiag) | measurements of the mix, and the problems in it |
| [plugstate](extensions/plugstate) | amp models, impulse responses and instrument files of plugins, chosen without their windows, and snapshots |
| [rpp](extensions/rpp) | open and write REAPER projects |
| [dawproject](extensions/dawproject) | open and write DAWproject files of Bitwig Studio, Studio One and Cubase |
| [vinput](extensions/vinput) | virtual inputs, for example a guitar converted to MIDI |
| [tutor](extensions/tutor) | the course, inside paw |
| [doctor](extensions/doctor) | checks of your sound card, MIDI devices and plugins |
| [launcher](extensions/launcher) | a clip launcher: slots of clips on each track, started and stopped while the song plays |
| [continue](extensions/continue) | suggestions in the piano roll for how a phrase continues |
| [luafx](extensions/luafx) | devices written in Lua, to use and to copy |
| [midilsp](extensions/midilsp) | MIDI LSP, a language server for music, as an entry of `paw.lsp` |
| [snippets](extensions/snippets) | a first set of snippets for `paw.snippet` |

The page of each extension shows it at work. Load extensions from `init.lua`
([config/init.lua](config/init.lua) loads a set of them, and a line loads
each other one), or build paw with
them in Nix: `paw.withExtensions (exts: [ exts.utau ])`.

## For agents

An AI agent with a shell controls paw as a script does. It uses
`paw ctl --json eval '<lua>'` on a paw that runs, or `paw -l script.lua`
headless (see [How to drive paw from an agent](docs/how-to/drive-paw-from-an-agent.md)).
A client without a shell uses the MCP server, `paw-mcp`. It gives tools that
return JSON, a `lua` tool for all other operations, and the manual and the
API reference as resources. Each batch of changes from an agent is one named
undo step. See [crates/paw-mcp](crates/paw-mcp/README.md).

## Documentation

[The manual](docs/README.md) has four kinds of page. In paw, `:help` shows
the same pages.

- Tutorials: [the course](docs/tutorials/course/README.md), seventeen short
  lessons. In paw, `:tutor` gives the same lessons.
- How-to guides: [install paw](docs/how-to/install-paw.md),
  [configure it](docs/how-to/configure-paw.md),
  [choose the audio devices](docs/how-to/choose-audio-devices.md) and
  [work from another computer](docs/how-to/work-from-another-computer.md).
- Reference: [all the keys](docs/reference/keys.md),
  [the keys of the terminal](docs/reference/grammar.md), [the options](docs/reference/options.md),
  [the graphical window](docs/reference/window.md),
  [the Lua API](docs/reference/api.md) and [the limits](docs/reference/limits.md).
  The manual has more reference pages.
- Explanation: [about the architecture](docs/explanation/about-the-architecture.md),
  [about the key rule](docs/explanation/about-the-key-rule.md).

The graphical window has [its own page](crates/paw-gui/README.md), and each
extension has a README.

## Inspiration

- [Neovim](https://neovim.io) and Vim: the modal grammar, Ex, the quickfix
  list, `:help`, and a small core with all else in Lua.
  [oil.nvim](https://github.com/stevearc/oil.nvim) for lists that you edit as text.
- [pi](https://pi.dev), the minimal agent for code: a small core that trusts
  you, and extensions that you own for all else.
- [REAPER](https://www.reaper.fm): a light DAW that you can script, and
  notation as a view over MIDI.
- The Vim modes for REAPER, which showed that key sequences can control a
  DAW: [reaper-keys](https://github.com/gwatcha/reaper-keys),
  [vimper](https://github.com/ggVGc/vimper),
  [reavim-ext](https://github.com/AntoineBalaine/reavim-ext) and
  [ReaLeader](https://github.com/SV3A/ReaLeader) (leader keys with a
  which-key list).
- [Ardour](https://ardour.org), [Bitwig Studio](https://www.bitwig.com) and
  [Renoise](https://www.renoise.com) for the DAW. [Dorico](https://www.steinberg.net/dorico/)
  and [MuseScore](https://musescore.org) for the score.
  [TidalCycles](https://tidalcycles.org) for patterns as text.

## Contribute

paw is a personal project for the taste of one person, and it changes at its
own speed. Send bug reports, questions and ideas as GitHub issues. Before a
pull request that is larger than a small fix, open an issue.
[The instructions for agents and contributors](AGENTS.md) give the rules for
code and for documentation.

The tests (`cargo test --release`, `tests/tools/suite.sh`) must pass, and
each new behavior must have a test. The tests use a null audio backend and a private X
display. They do not use your sound card or your screen. The pictures on this
page are recordings of paw, and [docs/images/make](docs/images/make) makes
them again.

## License

You can use paw under the [MIT](LICENSE-MIT) license or under the
[Apache-2.0](LICENSE-APACHE) license. Unless you state a different license,
each contribution that you send for inclusion has the same two licenses,
with no other terms or conditions.
