> Approved by the owner on 2026-11-23 with all recommendations. Build tickets: TASK-222.1 (E1) to TASK-222.9 (E9).

# Export: one model for render, stems, regions, bounce, freeze and project export (TASK-222)

Status: design, 2026-11-23. For the owner's review. No build ticket
starts before the review.
Source: TASK-222. Read before: `docs/reference/render.md`,
`freezing.md`, `subprojects.md`, `markers.md`, `ex.md`, `key-rule.md`;
`runtime/lua/paw/render.tl`, `stems.lua`, `freeze.lua`,
`defaults/clips.lua` (`:export`), `defaults/project.lua`
(`:track.bounce`), `paw.bounce` in `init.lua`;
`crates/paw-core/src/session/render.rs`, `freeze.rs`. Branches:
TASK-7.13 (commit b474b2bf, frozen blocks) and TASK-7.14
(`worktree-agent-a0332da24e5271487`, `:nest.export`, `:scope.write
<folder>`).

## 0. Summary

- Three verbs, by where the sound goes:
  - `:export` writes files **out** of the project: audio, MIDI, a
    project folder, a file of another program.
  - `:bounce` renders **into** the project: a new audio track.
  - `:freeze` renders **in place**: the track or block plays the file,
    and `:unfreeze` plays it live again.
- One grammar for `:export`. The Ex range gives **what** (tracks) and
  **when** (time), as in each other Ex command. Words after the command
  give **where** in the signal (`tap=`), **how** the file is, and **how
  many** files (`each=`). The file name gives the format and the names.
- A preset is a named set of these words: `:export stems`,
  `:export review`. paw has built-in presets. You add your own in your
  configuration or in the project.
- Before more than one file, paw shows the plan. `y` writes it.
- `:render`, `:render stems`, `:stems`, `:render.regions`, `:track.bounce`,
  `:nest.export` and `:scope.write <folder>` go. Each one has one
  replacement (see "Today's commands").

## 1. The terms

Each term has one meaning. The docs, messages and commands use these
words only.

| Term | Meaning, in the words of a musician |
| --- | --- |
| **render** | paw plays a part of the song faster than real time and writes what you would hear to a sound file. Render is the work, not a command. Export, bounce and freeze all render. |
| **mix** | The whole song, all tracks, through the master. One file. What you send to a listener. |
| **stem** | One file of a **set** of files that **add up to the mix**. Put all stems of a set at 0 dB from the start, and you hear the mix. A stem is of a **group** by default (drums, bass, keys, vocals), because that is what a mastering or mixing engineer calls a stem. |
| **track stem** | A stem of one track (each track of the song, one file each). The set still adds up to the mix. Other programs call these "track outs". |
| **tap** | The point in the signal where the render listens: before the fader, after the fader, after the groups, or after the master (see "Where in the signal"). |
| **export** | A file for another program or another person: audio (mix, stems, regions), MIDI, a project folder, a project of another program, a score. |
| **bounce** | A render of tracks that comes back into the project as a new audio track. The old tracks stay, muted. You can then edit the audio. It is permanent: undo removes it, but it does not follow later edits. |
| **freeze** | A render of a track or of a subproject block that plays in place of it. Its devices rest, so it costs no CPU. `:unfreeze` plays it live again. paw tells you when the file is stale. Freeze is for speed, not to make a file for someone. |
| **preset** | A name for a set of export words: `stems`, `review`. |
| **plan** | The list of files that an export will write, which paw shows before it writes more than one file. |

Where "stem" means a group and where a track:

- `each=group` makes the stems of the groups: one file for each group
  at the top level, and one for each track outside a group that plays.
  This is the meaning of the bare word "stems".
- `each=track` makes track stems.
- In a window narrowed to a group, "the top level" is the inside of that
  group. In a subproject, it is the top level of the subproject.

## 2. The grammar

```
:[tracks] [time] export[!] [preset] [target] [word=value ...]
   WHAT     WHEN            HOW MANY+HOW  WHERE+NAMES   WHERE, HOW, HOW MANY
```

| Part | Given by | Values | Default |
| --- | --- | --- | --- |
| WHAT is heard | the Ex range of tracks (`ex.md`), or the word `clip` | `t2,t4`, `t/Drums/`, `t'<,'>`, `t.`, `clip` (the clip at the cursor) | every track: the mix. In a narrowed window or a subproject, that scope. |
| WHEN | the Ex range of time, or `in=` | `5,8`, `%`, `'a,'b`, `'<,'>`; `in=loop`, `in=Chorus` (a region by name, or its path `Chorus 2/Verse A`) | `%`: the song, to the end of the last clip, plus the tail |
| WHERE in the signal | `tap=` | `pre`, `post`, `groups`, `master` | `master` |
| HOW the file is | the ending of the target, and words | `format=`, `channels=stereo\|mono\|auto`, `rate=`, `bits=`, `dither=`, `quality=`, `bitrate=`, `normalize=`, `loudness=`, `tail=`, tags | WAV, stereo, the project's rate, 24 bits, `tail=2` |
| HOW MANY files | `each=` | `group`, `track`, `region`, `clip`, or two joined: `each=region,group` | one file |
| WHERE the files go, their names | the target: a file, a folder (ends in `/`) or a name with fields | `mix.flac`, `out/`, `stems/{group}.flac`, `{n} {region}.wav` | see "Where the files go" |

Rules of the grammar:

1. The range comes first, as in each Ex command. `:'<,'>export` takes
   the tracks and the time of the selection. `:` in visual mode already
   types `'<,'>`.
2. `:export` with no range takes the whole song and every track. This is
   different from most Ex commands (they take the bar of the cursor),
   and the same as `:g`. An export of one bar by accident helps nobody.
3. The first word is a preset when it is the name of a preset. Else it
   is the target. `./stems` is always a path.
4. The words after it change the preset: `:export stems format=flac`.
5. One render plays each file. `each=` makes one render for each item.
6. `!` replaces files and skips the plan (see "What the user sees").

Examples, as a musician types them:

| Wish | Line |
| --- | --- |
| The song as a WAV | `:export` |
| The song as a FLAC for the band | `:export song.flac` |
| An MP3 to listen to on the phone | `:export review` |
| Bars 17 to 32 | `:17,32export bridge.wav` |
| The loop | `:export in=loop loop.wav` |
| The chorus region | `:export in=Chorus` |
| Each region, one file each | `:export regions` |
| The stems for the mastering engineer | `:export stems` |
| Each track, for a mixing engineer | `:export tracks` |
| The drums alone, through the master | `:t/Drums/export drums.wav` |
| The selected tracks, as one file | `:t'<,'>export` |
| The selected tracks, one file each | `:t'<,'>export each=track` |
| The bass before its fader, mono | `:t/Bass/export tap=pre channels=mono` |
| Stems of each region (the region matrix) | `:export stems each=region,group` |
| The song as a MIDI file | `:export song.mid` |
| The clip at the cursor as MIDI | `:export clip riff.mid` |
| The song as a REAPER project | `:export song.rpp` |
| This subproject as a project folder | `:export project ~/lib/Ballad/` (in the subproject) |
| Bounce the selected tracks to audio | `:t'<,'>bounce` |
| Freeze a heavy synth | `:freeze` |

## 3. Where in the signal: `tap=`

The signal of a track goes through four points. Each point holds all
before it.

```
clips -> devices -> [pre] -> fader, pan, mute -> [post] -> its groups -> [groups] -> master devices, fader -> [master]
                                 sends ------------------------------> returns (heard at groups and master)
```

| `tap=` | The file holds | Adds up to the mix | Same as today |
| --- | --- | --- | --- |
| `pre` | the clips and devices of the track (and of the tracks inside a group). No fader, pan, mute or sends. | no | what `:freeze` renders |
| `post` | `pre`, plus the fader, pan and mute. No sends, no groups, no master. | no, unless the groups and the master do nothing | nothing |
| `groups` | the track as when it is soloed: its groups, and the returns that its sends reach. No master. | yes, before the master | `master=false` |
| `master` | `groups`, plus the devices, fader and pan of the master | yes, for filters, delays and mixers (see below) | `tracks=`, `:render stems` |

- `tap=master` is the default, because only then do the stems add up to
  the file that you hear.
- A compressor or limiter on a shared group or on the master hears each
  stem alone. So with such a device, the stems differ a little from the
  mix. This is true today and in each DAW. The plan says so when the
  master or a group has such a device (a device of the kind `dynamics`).
- For a mixing engineer, `tap=post` is usual: the tracks with their own
  devices and fader, without your bus and master processing.
- A muted track is not in the mix. So `each=` leaves it out, and the
  plan names it (`left out: Gtr 2, muted`). A range that holds only
  muted tracks gives a clear message and no file.
- The mix (no track range) is always `tap=master`. `tap=groups` on the
  mix is the mix without the master's devices and fader.

## 4. Mono and stereo

paw is stereo inside. Each track, group and the master has two sides. A
mono sound file plays the same on both sides. The pan is equal power,
with the center at 0 dB, so a mono source in the center has the same
signal on both sides.

`channels=` is per file:

| `channels=` | The file |
| --- | --- |
| `stereo` | two channels, as you hear it. The default. |
| `mono` | one channel: (left + right) / 2. This is a sum at -6 dB. |
| `auto` ("as the source") | one channel when the two sides of the whole file are equal to the bit, else two. |

What mono does:

- A sound that is the same on both sides (a mono source, panned center)
  keeps its level exactly. This is why paw sums at -6 dB and not at -3
  dB: a sum at -3 dB makes a centered mono source 3 dB louder.
- A wide stereo sound gets quieter where its sides differ, and parts in
  opposite phase cancel. This is what a mono speaker plays, so a mono
  export of the mix is also the mono check.
- Pan stays as you hear it. A mono source panned hard left comes out 3
  dB quieter than in the center (equal power: the left side is +3 dB,
  the right side is silent, and the average is -3 dB). To ignore the pan,
  use `tap=pre`, which is before the pan.
- paw has no "left only". To take one side, put a `utility` device on
  the track. One way to do each thing.
- `auto` looks at the result, not at the files on the track. A mono
  recording through a stereo reverb, or panned off center, is stereo.
  A mono recording in the center with mono devices is mono. This is the
  same as REAPER's "tracks with only mono media to mono files", but it
  needs no guess about the devices.
- Surround and more than two channels: not in scope. The engine has only
  stereo (`routing.md`).

## 5. MIDI and other files

MIDI export is in scope, and it uses the same grammar. The format of
the target says what paw writes. `paw.formats` (paw/formats.tl) already
holds these writers. The extension of an exporter registers a format.

| Target | The file | WHAT and WHEN |
| --- | --- | --- |
| `.mid` | a Standard MIDI file, type 1, one track for each track | the range of tracks and time; `clip` for the clip at the cursor; `each=track` or `each=clip` for one file each |
| `.midi2` | a MIDI 2 clip file, as the project keeps a clip | one clip: `clip`, or `each=clip` over the range |
| `.rpp`, `.dawproject` | a project of another program (interop) | the whole project; a range is refused with a message, until the format can cut |
| `.musicxml`, `.ly` | a score (notation) | the range of tracks and time |
| `project <folder>/` | a paw project folder | the scope of the window: the song, a view or a subproject (see "Today's commands") |

- `tap=`, `channels=` and the other words of sound do not apply to MIDI.
  paw refuses them by name: `tap= is for sound; song.mid is MIDI`.
- The limits of MIDI export stay as `limits.md` tells them (a loop once,
  tempo ramps as steps, no per-note controllers in MIDI 1.0).
- The score exports of the notation extension (`:notation.export`,
  `:part.export` to PDF, SVG and PNG) and `:utau.export` become formats
  of their extensions, so `:export score.pdf` works. That work belongs to
  the extensions (ticket E9). Until then they stay.

## 6. Presets

A preset is a name for a table of export words. `:export stems` is
`:export` with the words of `stems`. The words that you type after it
win.

Built-in presets:

| Preset | Words | Use |
| --- | --- | --- |
| `mix` | (the defaults) target `{project}.wav` | the default when you type no preset |
| `review` | `format=mp3 quality=high loudness=-14` target `{project}.mp3` | an MP3 to listen to or send |
| `stems` | `each=group tap=master channels=auto` target `stems/{group}.wav` | stems for a mastering engineer |
| `tracks` | `each=track tap=post channels=auto` target `tracks/{track}.wav` | the tracks for a mixing engineer |
| `regions` | `each=region` target `regions/{n} {region}.wav` | one file for each region |
| `project` | `format=project` target `{project}-export/` | a project folder |

Where presets live, in this order (the first one found wins):

1. The project: `project.toml` holds them under `[export.presets]`, so
   the presets of a song go with it to a collaborator. Undo and save
   treat them as project data.
2. The user: `paw.export.presets.<name> = { ... }` in `init.lua`.
3. paw's built-in presets.

Commands:

- `:export.preset <name>` saves the words of the last `:export` as a
  preset of the project. `:export.preset! <name>` replaces it.
- `:export.preset` alone lists the presets and where each comes from.
- `<Space>ep` picks a preset from a list, shows its plan, and exports.

A preset of a project can name a list of exports, for example
`delivery = { {preset = "mix", format = "flac"}, {preset = "stems"} }`:
one plan, one confirm, one queue. The list is "master mix and stems" of
REAPER, with no extra word.

## 7. What the user sees

### 7.1 The plan

- An export of one file starts at once.
- An export of more than one file, or one that replaces a file outside
  `renders/`, shows the plan first, in a float, as `:render stems` does
  today. The plan lists each file, its tracks, its time, its tap and
  channels, and what it leaves out (muted tracks, a range a format
  cannot cut). It also says when the stems will not add up exactly (a
  dynamics device on a group or the master).
- `y` or `Enter` writes, `n` or `Esc` goes back. `j` `k` scroll.
- `:export!` skips the plan and replaces files.

### 7.2 Progress

- The exports go into one queue, one render at a time, on the render
  thread. The status line shows `exporting 3/12 Bass.wav 43% · Esc
  cancels`.
- `Esc` in normal mode cancels the whole queue, as today. `:export.cancel`
  does the same for scripts.
- An edit during an export changes the project, not the files (each
  render plays a copy made when it starts, as today).

### 7.3 The result

- One message at the end: `wrote 12 files to renders/stems (1:42 each,
  peak -0.8 dB)`, or `wrote renders/song.flac (3:21, -14.1 LUFS, peak
  -1.0 dB)`. A failure names the file and why: `Bass.wav: no space left
  on the disk; 11 files written`.
- `:messages` keeps it. `paw.export.last()` gives the results to a script.

### 7.4 Where the files go and their names

- A target with no folder goes into `renders/` of the project, as today.
  A path with a folder goes there. `~/` is the home folder.
- The fields of a name are `{project}`, `{track}`, `{group}` (the name of
  the stem: a group, or a track outside a group), `{tracks}` (the names
  of the range, joined with `+`), `{region}` (its path, joined with
  ` - `), `{n}` (the number in the set, two digits), `{date}`.
- With `each=` and a target with no field, paw adds the field: `:export
  stems out/` writes `out/{group}.wav`.
- Two files of the same name get a number, as the stems do today.
- A file in `renders/` is replaced with no question, because paw owns
  that folder. A file in another place needs `!`, or `y` in the plan,
  as `:w` needs `!` in Vim.
- The defaults: the mix `renders/{project}.wav`; a range of tracks
  `renders/{tracks}.wav`; the presets as "Presets" tells.

### 7.5 Keys

`<Space>e` is a free domain. It becomes **export**.

| Keys | Action |
| --- | --- |
| `<Space>ee` | the last export again (REAPER's "render with the last settings") |
| `<Space>em` | `:export` (the mix) |
| `<Space>es` | `:export stems` (shows the plan) |
| `<Space>et` | `:export tracks` |
| `<Space>er` | `:export regions` (replaces `<Space>rR`) |
| `<Space>ep` | pick a preset |
| `<Space>e` in visual mode | the same keys, for the range of the selection (`:'<,'>export ...`) |
| `<Space>tb` | `:bounce` the track at the cursor, or the selected tracks |
| `<Space>tf` `<Space>tF` | `:freeze`, `:unfreeze` |

The `<Space>e` keys obey the key rule: they are on the leader, in a domain, and
no view uses them.

## 8. Bounce and freeze

`:bounce` replaces `:track.bounce`.

- `:bounce` renders the track at the cursor to a new audio track below
  it, and mutes the old track. `:t2,t4bounce` and `:t'<,'>bounce` bounce
  those tracks to one new track. `:'<,'>bounce` bounces the time of the
  selection only.
- `tap=post` is the default: the new track has the sound with the fader
  and pan, and its own fader starts at 0 dB, so you hear no change. The
  new track goes to the same output as the old one.
- Today `paw.bounce` renders `tracks = {id}` with the master on, so a
  bounce holds the master's devices and fader, and the sum is wrong when
  the new track plays through the master again. `tap=post` fixes this.
- `tap=pre` keeps the fader live: the new track gets the fader, pan and
  sends of the old one.
- One undo step. The message names the new track.

`:freeze` and `:unfreeze` stay as they are (`freezing.md`, and the
frozen blocks of TASK-7.13). A freeze is always `tap=pre` (a track) or
the block into its row (a block). It takes no export words except
`tail=`, because its file must play in place. TASK-213 and TASK-214
are not changed by this design. `:utau.freeze` stays an extension
command until utau can use `paw.freeze` (see the questions for the owner).

## 9. Today's commands: stay, merge, go

| Today | Becomes | Why |
| --- | --- | --- |
| `:render <file> [opts]` | `:export <file> [opts]` | One command for files out. |
| `range=song\|loop\|selection\|<region>` | Ex range (`%`, `'<,'>`), `in=loop`, `in=<region>` | The Ex range is the way of each other command. Loop and regions have names, so they need a word. |
| `start=`, `end=` (beats) | Ex range in bars and beats (`5.3,9.1`) | One way. `paw.render` in Lua keeps `start`, `end`. |
| `tracks=selected\|3,5` | `:t'<,'>export`, `:t3,t5export` | Ex range of tracks. |
| `stems=true` | `each=track` | One word for how many. |
| `master=false` | `tap=groups` | One word for where. |
| `channels=mono\|stereo` | the same, plus `auto` | See "Mono and stereo". |
| `tail`, `rate`, `bits`, `dither`, `quality`, `bitrate`, `normalize`, `loudness`, tags, `wait` | the same | No change. |
| `:render stems [dir]` | `:export stems [dir/]` | A preset. |
| `:render stems tracks` | `:export tracks` | A preset. `tap=post`: see question 3. |
| `:render <Group>` | `:t/<Group>/export` | Ex range. The name is `{tracks}`. |
| `:stems out` | `:export tracks out/` | It did the same as `:render stems tracks`. It goes. |
| `:render.regions out level=1` | `:export regions out/ level=1` | A preset with `each=region`. |
| `<Space>rR` | `<Space>er` | The export keys are in one domain. |
| `:render.cancel` | `:export.cancel` (and `Esc`, as today) | Same name as the command. |
| `:render.tags` | `:export.tags` | Same name as the command. The tags stay in the project. |
| `:track.bounce` | `:bounce` | Ranges of tracks and time, `tap=post`. |
| `:freeze`, `:unfreeze` | stay | A freeze is not an export. |
| `:export <file> clip\|selection` | `:export clip <file>`, `:'<,'>export <file>` | `clip` is a WHAT word; the selection is the Ex range. |
| `:export song.rpp`, `.dawproject`, `.musicxml`, `.ly` | stay | Already one command by ending. |
| `:nest.export <folder>` (TASK-7.14) | `:export project <folder>/` in the subproject | One way to write a project folder: of the scope of the window. |
| `:scope.write <folder>` (TASK-7.14) | `:export project <folder>/` | `:scope.write` keeps its one meaning: save the view as a subproject. |
| `:notation.export`, `:part.export`, `:utau.export` | `:export` by ending, later (E9) | Formats of their extensions. |
| `:utau.render` | stays | It sings the voice again. It is not an export. |
| `paw.render(path, opts)` | stays | The one call for one file (Lua and the kernel). Gets `tap`. |
| `paw.render_stems`, `paw.stems.plan`, `paw.stems.render` | `paw.export.plan(words)`, `paw.export.run(plan)` | One plan model for all exports. |
| `paw.render_ranges` | `paw.export.ranges` (names for `in=`) | Same name as the command. |
| `paw.bounce` | stays, with `tap` | |
| the render dialog of the window | paused (`crates/paw-gui`) | It reads `modal.render`. It needs work when the window starts again. |

## 10. Build tickets, in order

| # | Title | Milestone | Priority | Size |
| --- | --- | --- | --- | --- |
| E1 | Export: `tap=pre\|post\|groups\|master` in the kernel render (`session/render.rs`); `master=false` goes | m-2 | High | M |
| E2 | Export: `channels=auto` (equal sides to the bit give a mono file); `render.md` tells the -6 dB sum and the pan | m-2 | High | S |
| E3 | Export: `paw.export` (Teal): words, presets and Ex ranges to a plan of renders; names with fields; `paw.stems` and `paw.render_stems` go | m-2 | High | M |
| E4 | Export: the `:export` command for sound: the plan float, `!`, the queue, progress, the result message, completion; `:render`, `:render stems`, `:stems`, `:render.regions` go; `:export.cancel`, `:export.tags`; `<Space>e` keys, `<Space>rR` goes; `render.md` becomes `export.md`, the how-to guides move | m-2 | High | L |
| E5 | Export: presets of the user and of the project (`[export.presets]`), lists of exports, `:export.preset`, `<Space>ep` | m-2 | Medium | M |
| E6 | Bounce: `:bounce` with ranges of tracks and time, `tap=post` by default; `:track.bounce` goes | m-2 | Medium | S |
| E7 | Export: MIDI and project folders in the grammar: Ex ranges and `clip` for `.mid` and `.midi2`, `each=track\|clip`; `:export project` replaces `:nest.export` and `:scope.write <folder>` (after TASK-7.14 is on main) | m-2 | Medium | M |
| E8 | Export: `normalize=` and `loudness=` on a set of stems: one gain for the whole set, from the mix, so the set still adds up | m-2 | Low | S |
| E9 | Notation and utau: their exports as formats of `:export` (`.pdf`, `.svg`, `.png` of parts, `.ustx`); `:notation.export`, `:part.export`, `:utau.export` go | m-11 | Low | M |

- E1 and E2 are Rust and independent. E3 needs neither, but its tests
  of `tap` need E1. E4 needs E3. E5, E6, E7 and E8 need E4.
- E4 changes each page that names `:render` (search `README.md`,
  `docs/`, the extension READMEs, the tutor's lessons, `bench/`,
  `.claude/skills` for `:render`, `render stems`, `:stems`,
  `render.regions`, `track.bounce`, `<Space>rR`).
- TASK-80 (quality) and TASK-80.1 (plugins offline) need no change: each
  export, bounce and freeze goes through `paw.render`, so they get full
  quality and the offline mode.

## 11. Questions for the owner

Each question has my recommendation. The design above uses it.

1. **`:export` or `:render` as the one command?** REAPER says render.
   Ardour and Bitwig say export. Your definition says export holds
   audio, MIDI and project folders. Recommendation: `:export`, and
   "render" is the work, not a command. Then bounce and freeze are the
   two renders that stay in the project.
2. **Is a stem of a group or of a track?** Recommendation: the word
   `stems` means the groups (with each track outside a group), and
   `tracks` means one file for each track. Both sets add up to the mix
   at `tap=master`.
3. **The tap of `:export tracks`.** Recommendation: `tap=post` (the
   tracks for a mixing engineer, without your bus and master
   processing). The other choice is `tap=master`, so that they add up to
   the mix as the stems do.
4. **The mono sum.** Recommendation: keep -6 dB (the average), as today.
   A centered mono source keeps its level. -3 dB makes it 3 dB louder.
   No "left only" word.
5. **The default of `channels=`.** Recommendation: `stereo` for the mix
   and for one file; `auto` in the presets `stems` and `tracks`, so a
   mono bass gives a mono file.
6. **Replace a file.** Recommendation: replace with no question in
   `renders/`; elsewhere ask in the plan, or `!`.
7. **The default `tail=`.** Today a render has 1 s, a freeze and a bounce
   2 s. Recommendation: 2 s for all. Later, `tail=auto` (until the sound
   is under -90 dB, at most 10 s), in a ticket of its own.
8. **Where the presets live.** Recommendation: the project first, then
   `init.lua`, then the built-in ones. A project preset goes with the
   song to a collaborator.
9. **A subproject as a project folder.** Recommendation: `:export project`
   writes the scope of the window, so you go into the subproject first
   (`<Space>zs`). `:nest.export` with the cursor on a block goes. The
   other choice is a WHAT word `nest` for the block at the cursor.
10. **`:utau.freeze`.** Recommendation: a later ticket of the utau
    extension (m-11) makes it use `paw.freeze` with a wait for the
    synthesis, so there is one `:freeze`. Not part of this design's
    tickets.

## 12. What we take from other programs

| Program | What it does | What paw takes, and why |
| --- | --- | --- |
| REAPER: the render dialog | Source: master mix, master mix and stems, stems of the selected tracks, the region render matrix, selected items. Bounds: entire project, time selection, project regions, selected regions, custom. Options: tail, "tracks with only mono media to mono files", stems pre-fader or through the master, wildcards in the file name (`$project`, `$track`, `$region`), render presets, "render with the last settings". | The axes: source = WHAT and `each=`, bounds = WHEN, wildcards = the fields of the target, presets, `<Space>ee`. We do not take its many modes of source: `each=` and the Ex range hold them all. The matrix becomes `each=region,group`. `channels=auto` takes the mono-media idea, but looks at the result. |
| Ardour: the export dialog and stem export | Tabs: file formats (several at once, as a preset), time span (session, ranges, several at once), channels (which tracks and buses, the master by default). File names with the session, the range, a label, a date. A warning before it writes over files. Stem export: one file for each track or bus, with or without the processing of the track. | Presets that hold more than one export (a list), the warning before replace (the plan), and "with or without processing" as `tap=`. |
| Bitwig: Export Audio | One dialog: the tracks (each one a file; groups as folders; the project master as a choice), the time range (from the selection by default, the arrangement, the loop), the rate, dither, pre-fader, real time. MIDI export is its own command. Bounce in place is separate and has no dialog. | The defaults come from the selection (our `'<,'>`), pre-fader as a tap, and bounce as its own fast command. We do not take a separate MIDI command: the ending of the file says it. |

Sources:

- REAPER, Render (the wiki of REAPER's maker):
  https://www.cockos.com/wiki/index.php/Render
- REAPER, the render dialog (REAPER Accessibility wiki):
  https://reaperaccessibility.com/wiki/The_render_and_Consolidate/Export_Tracks_Dialogs
- REAPER, Region Render Matrix:
  https://publish.obsidian.md/arendleejessurun/Atlas/Music+production/Reaper/Region+render+matrix+via+master+in+Reaper
- REAPER User Guide (render chapter: source, bounds, wildcards, presets,
  the mono-media option): https://www.reaper.fm/userguide.php
- Ardour, the export dialog: https://manual.ardour.org/exporting/export-dialog/
- Ardour, stem exports:
  https://manual.ardour.org/working-with-sessions/interchange-with-other-daws/stem-exports/
- Bitwig, Exporting Audio: https://www.bitwig.com/userguide/latest/exporting_audio/
- Bitwig, Bouncing to Audio: https://www.bitwig.com/userguide/latest/bouncing_to_audio

Note: the pages that I fetched for REAPER do not list the names of the
wildcards and the mono option. The names come from the REAPER User Guide
and from use of REAPER. Check them in the guide before E3 copies a name.

## 13. Facts from the code that the design relies on

- `render.rs` `select_render_tracks`: `tracks=` solos the tracks (so they
  play through their groups and the returns of their sends), and
  `master=false` bypasses the master's devices, fader and pan. This is
  `tap=groups` and `tap=master`.
- `render.rs` line 919: mono is `(left + right) * 0.5`.
- `paw-engine/src/engine/track.rs` `target_gains`: equal-power pan,
  center at unity (`gain * sqrt(2) * cos/sin`).
- `freeze.rs`: a freeze is before the fader; the tracks that feed a
  frozen group are held.
- `paw.bounce` (init.lua): `paw.render(path, { tracks = { id }, ... })`
  with the master on: the bounce holds the master processing (fixed by
  E6).
- `stems.lua`: the plan float, `y` `Enter` `n` `Esc`; it leaves out
  muted tracks and VCAs; two files of one name get a number.
- `ex.md`: the ranges of time and tracks, `'<,'>`, `t/name/`, and that a
  narrowed window sees only its scope.
