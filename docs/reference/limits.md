# Limits: what paw does not do yet

<!-- tags: missing -->

This page lists what paw does not do, and the known limits of what it does.
Each item is a fact about the current version. An item goes away when paw
gets the function.

- Undo: the steps share the notes of a clip in runs of a few hundred, but
  not its controller moves. A step that changes a clip keeps a full copy of
  its controller moves. The engine plays a changed clip again from all its
  notes. So an edit or an undo on a clip of 200,000 notes takes some
  milliseconds to reach the engine.
- A MIDI clip has its own length, as in REAPER. When you delete its last
  notes, the clip does not become shorter. `:clip.resize`, or a drag on its
  end, changes the length.

- Harmony:
  - The reading uses steps of half a beat. So it reads a chord shorter
    than about a beat as passing tones (a technical name).
  - The arrange ruler does not show the chords and the key. Only the piano
    roll shows them.
  - A slash chord can have a bass that is not a chord tone. Then its name
    comes from the full set of pitches: C G B D is Cmaj9, not G/C.
  - paw reads the full song again after each edit. This is fast for songs
    of some thousands of notes, but it is not incremental.
- Snippets:
  - Only the piano roll offers snippets. A snippet can name other views,
    but nothing opens the picker there yet.
  - A snippet taken as a suggestion (`Ctrl-Space`) has no choices.
  - The preview of the picker uses the layer of the snippet, not
    `paw.complete.show`.
  - A melody of eighth notes alone can give chords, because a beat with
    two pitches is a sign of a chord.
- Pickers that you can hear:
  - `paw.opt.audition_level` sets the level of sound files only. A phrase plays through the track at the level of the track, to give the sound of the preset in the mix.
  - The timers of the kernel time a phrase, not the engine. So under load, a phrase can be a few milliseconds uneven.
  - A factory preset of a plugin takes as long to try as to load. Some plugins stop the program for up to a third of a second.
  - You cannot hear the pickers of templates, UTAU presets and singers, sends and drum maps.
  - The graphical window shows the pane of a picker as text, and the outline of a sound file in block characters, not as a waveform.
- paw's sampler (extensions/sampler):
  - It reads the samples of an instrument whole into memory while the
    program waits. Nothing streams from disk. The time limit of the plugin
    helper stops a library that takes more than 30 s to read.
  - It does not play these parts of SFZ: the LFOs (`amplfo_*`, `fillfo_*`,
    `pitchlfo_*`, `lfoN_*`), the v2 envelopes (`egN_*`), `<effect>`,
    `amp_keytrack` and `sw_vel`. It also does not play controllers on
    envelope times and offsets, and smoothing for each controller
    (`_smoothccN`).
  - It does not play these parts of Decent Sampler: effects, modulators,
    buses, glide, `legatoInterval` and oscillators.
  - It does not read SoundFont 2, folders of samples or `.dslibrary`
    archives.
  - It keeps FLAC samples as floats (two times the memory of 16-bit).
  - The plugin lists no presets for `:preset`. It has no editor window of
    its own and only one stereo output. It ignores per-note controllers,
    MPE and note-off velocity.
- The waveform of an audio clip in cells (`paw.opt.wave_scale`) shows the
  lowest to the highest sample of each column. It does not show the
  loudness: there is no darker inner band for the RMS. The graphical window
  draws the peaks of a clip from the same data as before (`paw.frontend.peaks`:
  the lowest, the highest and the loudness of each point).
- Windows, buffers and tabs:
  - The arrange view, the piano roll, the notation view, the mixer, the device panel and the session view of the clip launcher have a state for each window. The views of extensions that name no state for each window show in one window at a time.
  - The edit cursor of the arrange view (the track and the time) and the selections are one for all the windows of a frontend.
  - Floats (help, pickers, pages) are not windows of a tab yet.
  - Each view draws its own window title bar (the winbar of Neovim).
  - The project keeps a layout for each kind of seat (the graphical window, the terminal), not for each seat. Two terminals attached at the same time share one layout in the project: that of the terminal that saved it last.
  - `:new` starts a new project. `:vnew` and `Ctrl-w n` open an empty window.
- The quickfix list:
  - `:g/pattern/` and `:vimgrep` fill it. paw has no `:grep`, because it has no files to run a program on. `/` does not fill it.
  - `:cfdo` runs one time for each track, as there are no files.
  - The project does not keep the lists, and they do not stay between runs.
  - A location list stays with the number of its window after the window closes.
  - The status bar of the graphical window does not count the entries.
- Ex (`:5,8d`, `:%s`, `:g`):
  - `d`, `m` and `co` move clips, not the automation, tempo changes or markers in the range.
  - `:m`, `:co` and `:>` move notes as the piano roll does.
  - Notation does not keep the name of a note typed in a replacement (`:s/c4/db4/`). It spells the note by the key.
  - A term of a pattern has no spaces. So `name=` cannot name a clip with a space in its name.
  - The `:t` of Vim (copy) is not there, because `t` starts a range of tracks. `:k`, `:j!`, `:retab` and similar commands are not there.
  - The graphical window shows the matches and ghosts of the piano roll as the terminal draws them. It gets the count (`prompt.note`), but does not show it yet. It does not shade the range or light clips in the arrange view.

- Search:
  - The regex mode of the pickers and `:vimgrep` change the common kind of regular expression into Lua patterns. So a group cannot repeat (`(ab)+`), and there is no `\b`, no backreference and no lookaround.
  - The preview of a picker draws a clip as a piano roll or a waveform, not as a score (the notation extension draws staves only in its own view).
  - A picker over a hundred thousand notes takes most of a second to open.
  - The live grep of `,fg` searches the text in the project, not the text that a plugin shows. It does not search the text of automation and of device parameters.
  - `:select` chooses notes and clips. The tracks, devices, markers and points that it finds go only to the quickfix list.
  - `]c` and `[c` stay on the track of the cursor.
  - In a picker, the keys that open a split open only the first marked line. A view shows in one window at a time.

- Help (`:help`):
  - The pages are 78 columns wide, not the width of the window.
  - `:helpgrep` takes words, not patterns.
  - paw has no `:helptags`. paw makes the tags the first time that you ask for help, in about half a second.
  - Help is only in English.
  - The Nix package installs the extensions next to the program, but not `docs/`. So an installed paw has the pages of the extensions, but not the manual, unless `PAW_HOME` names a source tree.

- Lists edited as text (`paw://tracks` and the others):
  - The input, MIDI ports, height and automation of a track are not fields of its line. The side-chain, outputs and parameters of a device are not fields either. The place of a send among the sends of a track is not a field. A copy keeps all of them.
  - An edit of the name of a device does not rename or replace the device.
  - paw puts the lines in columns again only when it reads the buffer again (`:w`, `:e!`).
  - `:s` takes Lua patterns with `\d` `\s` `\w` `\(` `\)` of Vim, not the full syntax of Vim.
  - These buffers have no `:g`. They do not complete track and device names while you type.
  - paw has no buffer of clips, lanes or notes yet.
  - The graphical frontend draws a text buffer as the terminal does, in the monospace font, not with its own widgets.

- The key rule ([The key rule](key-rule.md)):
  - A selection across mixer strips with different devices or sends chooses rows by their kind (the fader, the second send). It skips a strip that does not have that row.
  - `]` and `[` wait a moment for `]d`, `]g` and similar keys before they run. Vim does the same when a longer mapping starts with a key.
  - `paw.opt.keys = "classic"` gives the old keys. It will go after a release.
  - In the session view of the clip launcher, `m` is still the launch mode and `n` a new clip. They are not the mark and the next match of Vim.

- Notation:
  - A tempo mark writes a point of the song's tempo map when it is
    written. After that, nothing keeps the two together. If you move the
    clip or the mark, the point stays where it was. No option makes the
    score own the song's tempo.
  - Repeats and endings are written, not unfolded.
  - Trills, mordents, turns and tremolos are written, not played. A fermata
    holds the whole value of its note, but it does not stop the time.
  - Techniques (`pizz.`, `con sord.`) switch an articulation only on a
    track with an articulation map (extensions/articulations). They switch
    it only from where they are written to the end of the clip or the range.
  - paw does not render swing. It writes no CC1 or CC11 for sustained
    instruments.
  - `paw.harmony` does not read a key change after the first bar. The core
    has no key track: the key that the score starts in is the key of the
    project.
  - A time signature written in notation is the time signature of the
    song, for every track.
  - A mark writes the MIDI only when it is written. Notes that the piano
    roll moves under a dynamic later keep their velocities. A slur writes
    nothing (the notes are as long as they are).
  - What notation keeps of a note does not hold a tie that the meter does
    not need. A tied note is one MIDI note, written again as the meter
    divides it.
  - A grace note before the first beat of a clip stays before the clip.
    There it is hidden and does not play.
  - paw keeps the clefs that a clip was written on, where its notes would
    choose others. So a note that the roll puts far below a treble staff
    does not make it a grand staff.
  - The notation window outlines the note of the roll only in the terminal.
    The export of a track transcribes what the clips play.
  - Tuplets are read from the MIDI within a beat (and quarter-note triplets
    over two beats). Nine to a beat, five over two beats and similar
    tuplets are written only when you write them in notation.
  - The full score is at concert pitch only.
  - A staff of the score and a part are every MIDI clip of their track.
    But a tie does not join two clips.
  - In a clip that starts after the first clip of the score, the beat of a
    mark does not move with the clip.
  - A note entered before the first clip of a track goes nowhere. A note
    entered in a gap goes into the clip before.
  - In a transposed part, the keys and clefs of the popovers and `:s` go
    by the notes that sound (concert pitch).
  - A selection over staves takes every pitch of each staff. A block keeps
    its pitches within one staff only.
  - A pasted passage is written as it was. paw does not move it to the
    clef or range of the instrument that it goes to.
  - A condensed staff pairs two players, as two voices where they part. An
    edit applies to both only where they are written `a2` (`:score.split`
    parts them).
  - `:score` takes the tracks of an arrange selection, not a selection of
    clips.
  - Cues are flagged, not beamed.

- MusicXML in notation:
  - A file that paw writes does not keep a stem direction set by hand or
    a beam joined over a beat. It does not keep a system kept on the line
    before (`zj`) or the count of bars in a system.
  - In a file that paw reads, the layout sets the stems. Cross-staff chords
    are split by staff. Nested tuplets read as one ratio.
  - paw counts these parts of a file and leaves them out: D.C., D.S.,
    segno, coda, pedal and octave lines. It also leaves out fingering,
    string and fret, bowings, glissandi and figured bass. It also leaves
    out cue notes, microtones and tablature staves.
  - A pickup is a first bar whose start is before the clip. The clip shows
    its rests.
  - A `rit.` read from a file is written, not ramped in the tempo map.
  - Only the time signatures of the first part go to the song.
  - A drag of a file onto the graphical window, and the file pickers, do
    not offer MusicXML. `:open` and `:import` with a path do.
  - A score read from a file goes out again as the transcription of the
    clip.
  - MusicXML carries no multi-measure rests or cues.
  - LilyPond output writes chord symbols as text, not `ChordNames`.

- The grammar for music in notation:
  - `!` does not run a snippet (snippets expand in the piano roll). It does
    not give MusicXML to a filter: it gives the filter a line of text for
    each event.
  - `in` takes no count.
  - If you move or paste a chord that is tied only in some of its notes,
    paw writes it again without those ties.
  - `Tab` takes suggestions made for the clip of the piano roll (notation
    does not ask for them).
  - `Ctrl-t` asks on the command line, not in a popover.

- Articulations (extensions/articulations):
  - The graphical window shows the tags and colors of the notes and the
    shaded, named rows. It does not show the band, the labels of the
    keyboard or menus of its own.
  - Keyswitch rows are labeled, not folded away.
  - The score draws the mark of an articulation in the same ink as a
    written mark. The techniques popover does not offer the articulations
    of the map first.
  - A modifier writes MIDI 1.0 controllers, not the registered controllers
    of the profile (mute type, playing position).
  - `:art.edit` (a map edited in a text buffer) is not available.
  - paw does not make a generated map again when its library changes.
  - paw does not read Kontakt and SF2 libraries.
  - `:art.measure` finds onsets by level alone (a sample with a slow swell
    reads late). It does not yet use the onsets that the `describe` of a
    sampler could report.
  - Linked controllers are a curve of their own, not one of the choices of
    the strip under the roll.

- Engraved notation does not have:
  - Page breaks of your own (pages fill as systems come).
  - The engraving options as a buffer to edit (staff size, spacing, font).
  - Articulations inside a slur.
  - Systems whose skylines interlock.
  - Skylines in the cell view of the terminal: there, marks keep fixed rows.
  - Searchable text in an exported PDF: its text is outlines.

- Language servers:
  - paw sends each document complete. It does not send incremental changes.
  - paw keeps the related notes of other tracks that a diagnostic names,
    but does not draw them.
  - paw draws annotations on mixer strips, devices and the ruler, not yet
    on clips or notes.
  - A fix that renders again is not an undo step, because a render is not
    an edit of the project.
  - The graphical window shows the marks only on notes. The terminal marks
    tracks, devices, time and renders. The graphical window shows them
    through `:diagnostics` and the float.
  - The settings check of MIDI LSP names the render dialog of REAPER in its
    messages.

- Pictures in the terminal:
  - paw sends pictures only by the kitty graphics protocol, as direct
    placements. It does not use Sixel, the protocol of iTerm, or Unicode
    placeholders. So pictures do not go through tmux, which does not pass
    them on.
  - paw knows a terminal that puts images over images well only by its
    name (kitty, Ghostty, herdr). In any other terminal, paw draws the
    parts that move into the page.
  - paw also knows a terminal that puts text over images (a strip `under`
    the text) only by its name (kitty, Ghostty, herdr, WezTerm). In any
    other terminal (Konsole), paw paints the backgrounds of the cells into
    the picture. There, a single run along one row hides the line under
    it, for example a cursor block, the note under the cursor or a
    selection one row high.
  - The score, the plot of the curve editor, the controller strip of the
    piano roll, audio waveforms, and the pitch and curves of the utau
    editor are pictures. The automation lanes of the arrange view, the
    velocity strip, the tempo lane and the meters are still cells.
  - In Konsole, a scrolled strip sends again the pieces at its edges,
    because their painted backgrounds changed.
- Scenes (the panes of the graphical window, and windows of views that
  the kernel draws; see "Scenes" in [the protocol](protocol.md)):
  - A scene has runs, fills, pictures, the widget roles, hit regions
    (`buf:mark`, `buf:hit`), planes, and notes, clips and curves on them.
  - The graphical window paints only the roles of the core. The own
    role of an extension (`paw.ui.role`) shows in its cells there, because
    it has no `pixels` drawing yet.
  - A view can draw over a role in cells (the cursor and selection of the
    roll, the tag of an articulation). The graphical window shows this over
    the role in cells too, not as a part of the note.
  - The graphical window does not scroll or zoom a plane itself. The wheel
    goes to the kernel, which draws the plane again.
  - paw-raster makes pictures into images when their drawing changes. They
    are not drawn as egui shapes.
  - The name of a node is the place where it is written. So a view that
    scrolls sends again what scrolled.
  - A drag on a hit region costs a turn of the kernel for each move, also
    over `--connect`.
- The piano roll of the graphical window is the piano roll of the
  terminal, laid out in cells:
  - A row is one pitch, at the cell size of the graphical window. Alt and
    the wheel do not make the rows taller. A taller row would be two cells,
    in the terminal too, and the roll does not do that yet.
  - The tracks near the roll are in the `:roll.tracks` list, not in a side
    panel beside it.
  - The alternatives of a suggestion show with `Alt-1`…`Alt-9`, not as
    chips to click.
  - It opens at the zoom of the roll (`note_zoom`), not fitted to the clip.
    So short notes are too narrow for their names until you zoom in.
  - While you drag a note, the note stays where it was and a copy of it
    follows the pointer.
- The arrange view of the graphical window is the arrange view of the
  terminal, laid out in cells. Before, the window had its own drawing of
  it. These details of that drawing are not there now:
  - A track's height is a whole number of lines.
  - The timeline has no box of zoom buttons in its corner. `Ctrl -`,
    `Ctrl +`, `Ctrl 0` and the arrows with `Ctrl` do the same.
  - The ruler is one row. A drag along it loops. The lower half of the
    ruler of the old drawing moved the playhead.
  - Automation shows the lanes of the selected track as rows, not one lane
    of each track over its clips.
  - The bar numbers, the names on the ruler and the text in the headers
    are in cells. The clips, the bar lines, the curves and the playhead
    are where they are, between cells. At a zoom that is not a whole
    number of columns a beat, a bar's number can be up to half a cell
    from its line.
- The mixer of the graphical window is the mixer of the terminal, laid out
  in cells. Its switches are a cell wide. Its devices have rows of their
  own only when the mixer is at least twenty rows tall. At the usual
  height of the graphical window, they fold into one row that counts them.
  The accent of the theme still differs between the terminal (amber focus)
  and the graphical window (blue selection). This is the decision of the
  owner.
- The device panel of the graphical window is the device panel of the
  terminal, laid out in cells:
  - A row is one cell high, lower than the cards of the earlier panel of
    the window. A parameter has no row of its own for its buttons.
  - You add a device with the picker of devices, not with a box in the
    panel that lists the matches as you type. `Ctrl-f` in the picker makes
    a device a favorite.
  - The heading of a device has a menu of presets, but no buttons for the
    next and the previous preset. `]p` and `[p` step through them.
  - A drag of a device onto the header of a track does not move it to that
    track. A drag in the panel moves it along the chain. `:device.move_to`
    and `:device.copy_to` move it to a different track, and `dd` and `p`
    too.
  - The wheel over a slider moves the cursor from row to row. `Ctrl` and
    the wheel change the parameter, as in the terminal.
  - The pictures of the built-in effects (the curve of the equalizer, the
    gain reduction, the loudness, the tuner) are drawn in cells. While one
    shows, the window gets a new scene while the song plays.
- The drum grid is one view for both frontends, in cells. In the graphical
  window:
  - A step is three cells wide for all lengths of clip.
  - The wheel does not zoom the steps or scroll them sideways. The grid
    follows the cursor.
  - A hit is a block character, not a box shaded by velocity.
- A smooth tempo curve: a drawn stroke makes a change about each beat,
  each change a ramp to the next. The curve editor writes a smooth part as
  ramps of a sixteenth of a beat.
- In the curve editor:
  - Send levels and clip gain are not curves yet.
  - The moves of a controller only hold. A ramp is written as many moves.
  - The graphical window draws the held and smooth parts of a lane
    straight, but they play as shaped.
  - Waves are not `paw.snippet` snippets, which write notes.
- The mouse in the terminal:
  - You cannot drag the fades and gain of an audio clip. The keys and the
    commands of the clip set them.
  - You cannot drag the height of a track. The wheel with Ctrl over the
    headers changes the height of every track.
  - You cannot edit with the pointer the volume curve drawn over the lane
    of a track. You can edit its lane when it shows as a row.
  - Heights in a lane are as fine as its two lines. They are finer only
    when you drag a point.
  - Where the terminal keeps Shift for its own selection, Shift does not
    reach the program.
- Stretch:
  - Ratios are 0.25 to 4 (also each part between warp markers). Shifts are
    24 semitones at most in each direction.
  - paw always makes a stretch from the start of its file. If you put the
    playhead far into a long clip that changed a short time before, the clip is silent
    there until paw reaches that point.
  - Only the `tonal` method keeps formants.
  - A looped clip that follows the tempo stretches evenly. paw does not
    bend it along a ramp inside it.
  - paw does not find warp markers at onsets: you put each marker by hand.
    The other takes of a clip share its markers.
- Plugins with main buses wider than stereo (surround), and inputs other
  than the main pair and one side-chain.
- ARA plugins ([ara](../../extensions/ara/README.md)):
  - Only CLAP plugins with ARA 2. Not ARA as VST3, and not ARA 1.
  - Windows plugins through yabridge give no ARA. See
    [About ARA plugins](../explanation/about-ara.md).
  - The plugin plays the files of the clips without their gain, fades and
    edit list.
  - paw reads only the notes that a plugin found, not its tempo, key or
    chords.
  - An edit in the window of the plugin is not an undo step of paw.
  - Attachments take CLAP plugins only.
- Pre-roll without a punch: a take from the playhead does not play in from
  before it. Pre-roll in parts of a bar.
- MIDI-CI: no discovery, profiles or property exchange. MIDI-CI uses
  SysEx, and the MIDI ports do not send or read SysEx yet. So a loopback
  test is not possible.
- MPE for plugins that take only MIDI 1.0 (LV2, some CLAP plugins): the
  bend and controllers of a note do not reach them. MPE is a form of MIDI
  output only.
- The MIDI 2.0 attribute of a note (articulations):
  - The velocity of a note stays seven bits (1 to 127) in the project. The
    sixteen bits of MIDI 2.0 reach and leave the engine.
  - paw does not keep the attribute of a note-off (the endings of M2-123).
  - The `attr_map` of a track does not change notes played on a MIDI
    keyboard into keyswitches. It changes clips and `track:play_note`.
  - In a chord on one channel with different articulations, each
    keyswitch goes before its note. But a controller or a program change
    applies to the full chord (route one with `ch=`).
  - A MIDI file keeps the attribute in an event of paw, not in the NRPN
    form that some other programs read.
  - `paw.plugins.add_dir` finds CLAP and VST3 plugins, not LV2 plugins.
  - paw reads key names only from CLAP plugins. The piano roll of the
    graphical window shows the articulation of a note as a chip, but does
    not show the names on its keyboard.
  - A note that the `delay` of an articulation moves before the loop start
    is late after the loop turns. It starts with the loop, not before its
    end.
  - In a clip that a cue plays (a slot of the clip launcher), paw moves
    notes by the tempo of the song at the beats of the clip.
- MIDI 2.0 output through the sequencer is not tried: the test computer
  has no `CONFIG_SND_SEQ_UMP`, so its MIDI ports are MIDI 1.0. The tests try
  the MIDI 1.0 forms (plain, MPE and 14-bit) through the ports of paw.
- A freeze after the fader: paw takes a freeze before the fader, so the
  mix stays live (`:track.bounce` also renders the fader).
  - A send from a track inside a frozen group to a track outside it is not
    heard while the group is frozen.
  - paw does not render a frozen track again when the tempo changes.
  - The graphical window does not draw `F` on the header of a frozen track
    yet. The terminal does, and `paw.freeze.state(id)` tells it.
- Narrowed tabs:
  - `:layout save` does not keep a narrowed tab, because the id of a group
    belongs to its project.
  - The graphical window has no mark for a narrowed tab other than the
    name of the tab.
  - With `scope_rest=frozen`, a part of the rest that you edit from a
    different tab plays live until paw renders it again. Renders always
    play it live.
  - A terminal and a graphical window can attach at the same time, each
    with its own tabs. Then the last frontend to change tabs sets what the
    rest does.
- VCAs:
  - No VCA over the own fader of a group, no VCA under a VCA, and no VCA
    gain on the master.
  - A VCA is a track, so it shows in the arrange view as a row, with lanes
    as any other track.
  - A VCA moves the tracks assigned to it, not the tracks that they play
    into. The solo of a VCA makes its members the only sound. It does not
    solo what they feed.
- MP3, Ogg Vorbis and Opus without `ffmpeg`. No encoder for these formats
  in pure Rust has enough quality, and paw links no C library for them.
  They need `ffmpeg` (see [Render](render.md)). The Nix package puts one on
  the PATH.
- Tags:
  - No cover in a WAV file, because players do not read one. The other
    formats have the cover.
  - The render dialog has no file dialog for the cover: you type its path.
  - Tags are text only: no lyrics, ISRC, composer, disc number or replay
    gain.
- For instances on other machines:
  - paw sends the sound as plain 16-bit samples (about 1 Mbit/s), not as
    Opus. Opus has no encoder in pure Rust that is good enough.
  - paw sends nothing the other way, so you cannot record from the
    microphone of the client.
  - paw sends and imports only sound files from the disk of the client. It
    cannot import a MIDI file from there. Projects open and save on the
    disk of the instance.
  - Every seat shares the options, for example the zoom, MIDI step input,
    and the automation lanes and tempo lane that show.
  - The seat of a window does not survive `:reload`.
- Per-track loudness and spectrum in the painted mix report: the measurement
  gives each track only its peak, so the track meters are peaks, not LUFS
  or RMS. What an extension draws on the terminal's arrange view shows in
  the window only as a band it adds too.
- A drop of files where the pointer is: the graphical window cannot learn
  where you drop a file from a file manager (winit 0.30 reports no
  position). On Wayland, it gets no drops at all. When the graphical window
  is attached to a kernel, it shows the file dialog of the desktop only to
  import, and sends the chosen file to the kernel. Open and Save as browse
  the disk of the kernel.
- Lua devices do not have:
  - a window of their own drawn by the script. They show their parameters
    as sliders, as any device.
  - parameter moves inside a block. A block reads each parameter one time.
  - state other than the values of the parameters (for example, the
    pattern of an arpeggiator).
  - more than one stereo output.
  - their own latency for delay compensation.
- The graphical window measured on a real graphics card: it is tried only
  on Mesa's llvmpipe so far. There, playback costs more than a core.
- In the window, kanji, hanzi and hangul where the system has no font for
  them: only kana are built in, and the rest show as boxes then.
- Cues and the clip launcher:
  - No follow actions (a clip that launches the next clip, or a random
    clip, after some bars).
  - Under a tempo ramp, a clip that a cue plays spreads the beats of each
    block evenly. Its notes can be about one frame from where the timeline
    puts them.
  - paw does not render cues directly. Capture them into the timeline
    first.
  - In the graphical window, a clip dragged from the timeline onto the
    session view shows no mark of the slot that takes it until you let it
    go.
- The window's position on Wayland: the compositor places windows and a
  program cannot ask for a place, so only X11 keeps it.
- The flake's `flake.lock` names the `nixpkgs` of this machine as a path in
  its Nix store, so the package builds here but not from a URL elsewhere
  until it is locked to a release (`nix flake update`). The package is built
  for x86_64 and aarch64 Linux, and tried only on the first.
- The piano roll with several clips:
  - `i` on a selection of clips in the arrange view does not open them,
    because `i` there starts a text object. `Enter` opens them.
  - The phrase and chord text objects of musicops see only the active
    clip.
  - The graphical window does not shade the gaps between the edited clips.
  - A click on a context note always makes its clip active. So a click
    cannot add a note on top of a context note. A drag draws it.
- Insert mode's drawing writes nothing until it ends: notes drawn are not
  heard when the song plays meanwhile, nor seen by suggestions or language
  servers, and the window shows them as marks, not as notes to drag. The
  keyboard as a piano (`I`) still writes as it goes, a step to undo each key.
  Notes drawn have no length shorter than the grid, and a count before `i`
  does not draw the insert several times.
- Suggestions:
  - Sources can say that they offer suggestions in the arrange view
    (whole clips) and the drum view (`views`). But only the piano roll asks
    for them and shows them.
  - paw writes the controller moves of a suggestion when you accept it,
    but does not draw them before.
  - The badge has no list of the details of the alternatives.
  - To play a suggestion, paw uses the live input of the track. So the
    timers of the kernel set its time, not the clock of the engine.
- MIDI files:
  - paw does not import key signatures, sysex, text and copyright events,
    and SMPTE offsets. The message counts them. The project has no place
    for them.
  - Lyrics go only on notes of their own track. So a karaoke file with its
    words in a separate track keeps no words.
  - paw does not import controller moves on a channel or track with no
    notes.
  - A format 1 track that plays on several channels stays one track. Each
    note keeps its channel in `meta.channel`, and paw merges the controls.
  - A melodic track gets no instrument. Only channel 10 gets the drum kit.
  - `:export` writes only MIDI clips. It writes a looped clip one time, a
    tempo ramp as steps a sixteenth apart, and every control on the channel
    of its track. It does not write the bend and controllers of a note
    (MIDI 2.0).
- Kinds of track:
  - A kind says how a track is made and how its clips open. It does not
    say how a new clip on it starts. Kinds have no `new_clip`: a double click
    makes an empty clip on any track.
  - Commands of the extension change the kind of a track (`:utau.voice`,
    `:drums.map off`), not a list.
  - The header shows the letter of a kind in the column before the name.
    Diagnostics mark the same column and draw over it.
  - Extensions bring devices written in Lua. An extension cannot bring a
    native plugin (CLAP, VST3) of its own to be found when it loads, or
    package one with Nix. paw finds plugins where the system keeps them.
- Packaged extensions (`paw.withExtensions`) load at startup. To leave
  them out for one run, you must run the plain program.
- Extensions:
  - `paw.ext.unload` takes away what an extension registers later only
    when a function of its files is in it, or its code put it there. A key
    mapped later to the name of a command from a module of the core that
    it called is not its own.
  - `paw.ext.unload` does not stop the timers that an extension started
    with `paw.api.timer_start`. It stops only those of `paw.every` and
    `paw.defer`.
  - Requirements name extensions and the version of the API, not versions
    of the program or of plugins.
  - `:checkhealth` has no check of the latency of MIDI ports or of the
    frontends attached. The graphical window does not show it in a view of
    its own: it is a page, as `:messages` is.
  - `edit.before` sees the edits of a turn as the change events that they
    made, not as the calls that made them. paw does not ask it during an
    audition trial, but it asks at the end of the trial.
  - The API reference documents the `paw.api` functions whose definition
    it can read in `crates/paw-core/src/api.rs`. It lists the others (the
    functions of the tempo map, and a few written across lines) without
    their parameters.
- The status line and the files:
  - The graphical window does not show the line of `paw.statusline` (it
    gets the pieces, `modal.statusline`). It does not draw the own sections
    of the tab line, and `tabline.always` is for the terminal only.
  - A "scope" component has no meaning here, so paw has none.
  - Disk recording shows as `take N`, with no count of bytes written. The
    engine does not report one.
  - The file manager moves nothing between disks as a folder: it copies a
    file and then moves it.
  - The file manager has no undo of a file operation other than the trash.
  - The file manager cannot drag a line into `paw://tracks`. To bring a
    file in, use `Enter` or `go`.
  - `paw` started with a folder does not open it.
  - The graphical window shows a files buffer as any text buffer.
- Project diff and merge (extensions/projdiff):
  - The diff and conflict views are drawn in cells, as the graphical window
    draws any such view. They have no painted version of their own (they
    were tried in the terminal, not in the graphical window).
  - The folds are the own folds of the view, because a text buffer has no
    folds.
  - A merge keeps a note edited on both sides as a conflict only when its
    id is the same. A note that an edit on each side gives a new id is two
    notes.
  - Lists with nothing to name their items (controllers) merge as sets. So
    a controller moved on both sides shows two times.
  - To settle a conflict, you take one side whole. You cannot edit the two
    sides together.
  - Two sides can give different things the same id. Then paw renumbers
    tracks, devices, clips and lanes, with what points at them in the own
    fields of the model only. It does not follow what an extension keeps in
    `meta` and points at ids with.
