# paw

<p class="landing-tagline">A modal, keyboard-first and fully customizable digital audio workstation for Linux, inspired by Neovim.</p>

<div class="landing-actions">

[Make your first song](docs/tutorials/make-music/README.md)
[Read the manual](docs/README.md)
[Source on GitHub](https://github.com/AlejandroGomezFrieiro/custom_daw)

</div>

![The demo song plays. 3>ic moves the melody, . moves it again and u undoes it. :%s/e5/g5/g changes it, with a preview while it is typed](docs/images/tui-arrange.gif)

## Who paw is for

paw is for musicians who keep their tools in a configuration that they
write. You record, edit, mix and render songs in the terminal, with
motions, operators, counts, `.` and Ex commands, as you do in Vim. paw is
a personal project that one person made for their own music, and it is
newer and smaller than other DAWs, so [what paw does not do](docs/reference/limits.md)
lists its limits.

## The main ideas

### Modal keys

The keys work as in Vim, but on a timeline instead of on text. In each
view, `h` `j` `k` `l` only move, `+` and `-` change the value under the
cursor, and `Esc` cancels. On the command line, a range can be a range of
tracks (`:5,8d`, `:t2,t4 mute`), and paw shows a preview while you type.
[All the keys](docs/reference/keys.md) are on one page, and
[About the key rule](docs/explanation/about-the-key-rule.md) tells why they
are the same in each view.

![Notes drawn with i, typed on the home row with I, selected and transposed](docs/images/tui-pianoroll.gif)

### The terminal first

Each feature works in the terminal before it works in the graphical
window. The same views also open in the window, where you can use the
mouse, because a view is written once and the kernel sends it to each
frontend. See [About scenes](docs/explanation/about-scenes.md).

![Clips copied, trimmed and zoomed with the mouse](docs/images/gui-arrange.gif)

### Lua and Teal, and extensions

Each view, command and key is Lua, so your `init.lua` can change any of
them while the song plays. New code of paw is written in Teal, which is Lua
with types. An extension is a folder that adds commands, keys, views,
devices and kinds of track, and a view that an extension writes works in
the terminal and in the graphical window.

```lua
paw.ui.hl("Playhead", { bg = "#f38ba8" })
paw.keymap.set("<leader>tS", "track.add Strings device=synth", { desc = "A strings track" })
```

[How to configure paw](docs/how-to/configure-paw.md) and
[Extensions](docs/reference/extensions.md) tell you more.

### MIDI is the truth

The MIDI notes of a clip are what plays, and each view edits the same
notes. A score, the piano roll and Ex are views of one set of notes, so a
project opens and plays without any extension. See
[About MIDI as the truth](docs/explanation/about-midi-as-the-truth.md).

### Files that paw never deletes

A project is a folder of text files, with a file for each track and for
each clip. A save moves a file that the project no longer uses to the
`unused` folder, and paw never empties it. See
[About project files](docs/explanation/about-project-files.md).

## Install paw

You need Linux and [Nix](https://nixos.org/download/) with flakes enabled.
The first run builds paw from source, which takes several minutes. paw is
installed with Nix only at this time.

```sh
git clone https://github.com/AlejandroGomezFrieiro/custom_daw paw && cd paw
nix run . -- -e 'dofile("examples/demo-song.lua")'
```

The commands start paw with the demo song. Press `Space` two times to play
it, press `?` to list the keys of the view, and type `:q` and press `Enter`
to quit. [How to install paw with Nix](docs/how-to/install-paw.md) shows
how to put paw in your profile.

## Try it in your browser

<!-- SLOT: Try it in your browser. TASK-108 builds the pod, and TASK-107
     builds the course page. Put the embed in the div below. -->

<div id="try-in-browser" class="landing-slot">

paw does not run in a browser yet. Until it does, [install paw](#install-paw).

</div>

## Where to go next

- [Make music with paw](docs/tutorials/make-music/README.md) has five lessons that make one song, from the first note to an MP3 file.
- [The course](docs/tutorials/course/README.md) has seventeen short lessons, and they are also inside paw as `:tutor`.
- [The manual](docs/README.md) has tutorials, how-to guides, reference pages and explanations.
- [Issues on GitHub](https://github.com/AlejandroGomezFrieiro/custom_daw/issues) take bug reports, questions and ideas.

paw is licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE).
