# paw against other open-source DAWs: a feature comparison

**Tickets (product owner review, 2026-11-23):** milestone m-14 "DAW parity",
TASK-227 to TASK-254 (TASK-233 is not part of it; TASK-254 holds the owner questions). Each claim about paw was
checked against the code. The marks **[WRONG: ...]** and **[CHECKED: ...]**
below give the result. The list "Mapped to existing tickets" is at the end.

Date: 2026-11-23. Status: research, for future reference. The research
created no ticket. The review of 2026-11-23 filed the m-14 tickets.

## Summary

Method: the list of paw features comes from the repository (docs/reference,
docs/how-to, the extension READMEs, `docs/reference/limits.md` and the
Backlog). The facts about other DAWs come from their own sites, listed at
the end. Where a fact comes from general knowledge and no page was read,
the table says "(not verified)".

### Top 10 gaps (features that most DAWs have, and that block real work)

| # | Gap | Size | Where | Ticket |
| --- | --- | --- | --- | --- |
| 1 | Sync to other gear: MIDI clock, MIDI Time Code (MTC), MMC, JACK transport, LTC | M | Core (clock and transport), extension (UI) | none: propose |
| 2 | Onset and beat detection for audio: warp markers by hand only, no tempo detection, no slicing | M | Extension | none: propose |
| 3 | OSC and control surface support (Mackie, HUI, Launchpad, Push) | M | Extension | none: propose |
| 4 | LADSPA, and LV2 as a path in `plugins.add_dir` | S | Core (plugin host) | none: propose |
| 5 | Video on the timeline (film scoring) | L | Extension on clip kinds | TASK-23 and TASK-10 (clip kinds, media): partly |
| 6 | Audio editing tools: ripple edit, spectral view and edit, per-clip loudness (a "normalize clip") **[WRONG: paw has ripple (`paw.opt.ripple`, `:d!` `:m!` `:co!`) and `:clip.normalize`. Missing: ripple of automation, markers and tempo (TASK-235)]** | M | Core (ripple), extension (spectral) | none: propose |
| 7 | AAF, OMF and Ardour or Cubase session import (the interchange that studios use) | M | Extension (`interop`) | none: propose |
| 8 | Surround and wide buses (more than a stereo main pair, more than one side-chain) | L | Core | none: propose |
| 9 | Per-track loudness and spectrum meters (peak only now) **[WRONG in part: the `meter` device on any track gives LUFS, RMS, correlation and a spectrum; mixdiag `<Space>mk` measures one track. Only the mixer track meters are peaks (TASK-239)]** | S | Core meter, extension view | none: propose |
| 10 | Clip launcher follow actions, and launching without a capture to the timeline | S | Extension (`launcher`) | none: propose (TASK-23 is near) |

### Top 5 improvements (paw has the feature, it needs work)

1. Notation: draws and writes, but has no Rust engraver yet and no
   keys, sysex or text in MIDI import. Tickets TASK-135 to TASK-139.
2. Export: one model for render, stems, regions, bounce, freeze and
   project export. TASK-222 (high).
3. Offline render of plugins: tell CLAP and VST3 plugins that the
   render is offline. TASK-80.1. **[WRONG: TASK-80.1 is done.]**
4. Stretch: ratios 0.25 to 4, always from the file start, no onset
   markers, formants only in the `tonal` method. TASK-80 is the nearest
   ticket. **[WRONG: TASK-80 leaves stretch out. The stretch from the
   playhead is part M4 of TASK-10 (media). Onsets: TASK-234.]**
5. MIDI 2.0 and MIDI files: velocity stays 7 bits in the project, SysEx
   is not sent or read, and an `:export` drops per-note bend. No ticket:
   propose.

### Where paw is ahead

- Modal grammar of Vim on a timeline (operators, motions, text objects,
  `.`, counts, Ex ranges), and a key rule that holds in every view.
- One view for two frontends (terminal and window) through scenes.
- Project as a folder of text files, with `projdiff`, git drivers, and a
  persistent undo tree with named states.
- One Lua and Teal API for everything, a `paw ctl` socket, an MCP server,
  and a headless `paw -l` mode.
- Queries (`:select clip[name~=pizz] > note[pitch>=c5]`), quickfix,
  pickers with audition.
- Harmony reading, snippets, completion sources and language servers for
  music.
- Subprojects and scopes (nests), linked clips, narrowing.
- Plugins run in a process of their own, and so a crash does not stop
  the song.
- Per-note articulations through MIDI 2.0 attributes.
- Speed: the terminal frontend uses less CPU than REAPER, Ardour and
  LMMS (bench/DAWS.md).

## 1. What paw has

Marks: done, partial (the missing part is said), planned (ticket), none.
Sources for paw: the file in `docs/reference` or the extension README that
is named in each row.

### Recording

| Feature | State | Note |
| --- | --- | --- |
| Audio recording | done | `recording.md`, how-to `record-a-guitar-or-a-bass` |
| MIDI recording | done | `record-midi-from-a-keyboard` |
| Takes and comping | done | `takes.md`, `record-takes-and-comp` |
| Punch in and out | done | `punch-in-over-a-part` |
| Loop recording into takes | done | |
| Count-in and click | done | `use-the-metronome` |
| Recording offset | done | `set-the-recording-offset` |
| Pre-roll | partial | None without a punch; no pre-roll in parts of a bar (limits.md) **[WRONG in part: `paw.opt.pre_roll_seconds` gives parts of a bar; the limits page is stale there. Without a punch: TASK-236]** |
| Step input | done | TASK-55 to TASK-63 |
| Input monitoring, tuner | done | `tuner` device |
| Record count of bytes | partial | Shows `take N`, no bytes (limits.md) |

### Editing

| Feature | State | Note |
| --- | --- | --- |
| Audio clips: split, trim, fade, gain | done | `media.md`; fades and gain are keys, no drag |
| MIDI piano roll | done | `piano-roll.md` |
| Notation | partial | Extension `notation`; Rust rewrite planned (TASK-135 to 139); MusicXML and LilyPond out |
| Drum grid | done | Extension `drums` |
| Pattern text (TidalCycles) | done | Extension `pattern` |
| Automation, curve editor | partial | Moves of a controller only hold; send levels and clip gain are not curves (limits.md) |
| Tempo map, ramps, time signatures | done | `tempo.md`; also per subproject |
| Time stretch and pitch shift | partial | 0.25 to 4, 24 semitones, two methods; manual warp markers only |
| Warp markers | partial | Placed by hand, no detection |
| Ripple edit | none | **[WRONG: `paw.opt.ripple` and `:d!`, `:m!`, `:co!` ripple the clips. Automation, markers and tempo do not follow: TASK-235]** |
| Spectral edit | none | |
| Quantize, humanize, strum, arpeggio | done | Extension `musicops` |
| Chords, key, suggestions | done | `harmony.md`, extension `continue` |
| Linked clips | done | TASK-85 |
| Undo tree | done | Extension `undotree`, TASK-82 |
| Vocal and singing editor | done | Extension `utau` |
| Pitch correction | partial | Through ARA plugins (extension `ara`) |
| MIDI modifier stacks | planned | TASK-75 |
| Links between values (drivers) | planned | TASK-86 |

### Arrangement

| Feature | State | Note |
| --- | --- | --- |
| Tracks, groups as folders and buses | done | `organize-tracks` |
| VCAs | partial | No VCA on a group fader, no VCA under a VCA (limits.md) |
| Regions, markers, sections | done | `markers.md`, extension `sections` |
| Nested regions, subprojects | done in part | TASK-5 done; TASK-7 has parts S11 to S12 open |
| Clip launcher (cues, scenes) | partial | Extension `launcher`; no follow actions; no direct render |
| Track templates | done | Extension `templates` |
| Layouts and tabs | done | `windows.md`; TASK-84 planned (workspaces) |

### Mixing

| Feature | State | Note |
| --- | --- | --- |
| Sends, buses, groups | done | `routing.md` |
| Side-chain | partial | One side-chain per plugin (limits.md) |
| CLAP, LV2, VST3 hosting | done | Sandboxed process each |
| LADSPA, VST2, AU | none | |
| Windows plugins | partial | Through yabridge; TASK-52 (bridge) planned |
| Plugin delay compensation | done | `engine.md#delay-compensation`; Lua devices have no own latency |
| Built-in effects | done | 14 devices: EQ, compressor, gate, reverb, delay, limiter, and more |
| Meters, LUFS, true peak | partial | Master and `meter` device; tracks give peak only **[CHECKED: the `meter` device works on any track, so per-track LUFS exists; the mixer meters are peaks: TASK-239]** |
| Mix diagnostics | done | Extension `mixdiag` |
| Freeze, bounce | done | `freezing.md`; TASK-214 (background freeze) planned |
| Surround | none | Stereo main pair and one side-chain only |
| MIDI learn | done | `learn.md` |
| Samplers (SFZ, Decent Sampler) | partial | Extension `sampler`; LFO, v2 envelopes, effects missing |
| Scripted devices | partial | `luafx`; no window, no block-rate params |

### Render and export

| Feature | State | Note |
| --- | --- | --- |
| WAV, FLAC | done | `render.md` |
| MP3, Ogg, Opus | partial | Need `ffmpeg` |
| Stems, regions, selection, loop | done | `render-stems` |
| Mono or stereo, bits, rate, dither | done | |
| Loudness target, normalize | done | BS.1770 |
| Tags | partial | Text only, no ISRC, no lyrics |
| MIDI export | partial | MIDI clips only; per-note bend lost |
| Background render | done | |
| Offline flag for plugins | planned | TASK-80.1 **[WRONG: done]** |
| One export model | planned | TASK-222 |

### Project and interchange

| Feature | State | Note |
| --- | --- | --- |
| Project as folder of text files | done | `project-files.md` |
| Persistent undo, history | done | TASK-81, TASK-82 |
| Relink of missing media | done | `media.md` |
| Standard MIDI file import | partial | Drops key signatures, sysex, text **[CHECKED: true. The project has a place for key changes (key markers, `project.key`): TASK-244]** |
| REAPER `.rpp` | done | Extension `interop` |
| DAWproject | done | Extension `interop` |
| AAF, OMF, Ardour, Ardour sessions | none | |
| Project diff and merge | done | Extension `projdiff`; TASK-210 bug open for folders |
| Version control | done | git drivers |

### Sync and control

| Feature | State | Note |
| --- | --- | --- |
| Audio backends | done | PipeWire, ALSA, JACK (`programs.md`) |
| MIDI ports, MIDI 2.0, MPE | partial | No SysEx, no MIDI-CI discovery **[CHECKED: true. `Wire` holds three bytes at most: TASK-228, TASK-229]** |
| MIDI clock, MTC, MMC, LTC | none | No page in the manual mentions them |
| JACK transport | none | JACK is audio backend only (not verified in code) **[CHECKED: true. JACK is a cpal host only; no transport code: TASK-227.3]** |
| OSC | none | **[WRONG in part: custom clips keep OSC signals in the model, and TASK-23 part C2 sends them. No OSC control: TASK-231]** |
| Control surfaces | none | |
| Remote control | done | `paw ctl` socket, `paw attach`, TLS over network, `paw-mcp` |
| Ableton Link | none | |

### Scripting, accessibility, collaboration, platforms, documentation

| Feature | State | Note |
| --- | --- | --- |
| Scripting | done | Lua and Teal, one `paw` API; extensions |
| Wasm devices and extensions | planned | TASK-1, TASK-2 |
| Lazy extension load | planned | TASK-3 |
| Keyboard only | done | The key rule |
| Screen reader | none | No page; terminal text is possible but not tested (not verified) |
| Mouse | partial | Terminal mouse has limits (mouse.md) |
| Real-time collaboration | none | Remote seats share one project (`about-seats.md`) |
| Linux | done | Nix; TASK-38 (no Nix) planned |
| macOS, Windows | planned | TASK-39, TASK-40 |
| Browser | planned | TASK-29 to TASK-36 |
| Manual, tutorials, tutor | done | Diataxis docs, 17 lessons |

## 2. The other DAWs

| DAW | Version seen | License and platform | Summary | Source |
| --- | --- | --- | --- | --- |
| Ardour | 9 | Free software; Linux, macOS, Windows | Full DAW. VST2, VST3, AU, LADSPA, LV2; LTC; Lua scripting; OSC; control surfaces; video timeline; clip launching with cue markers; Loudness Assistant; playlist comping; MIDI step entry | [features](https://ardour.org/features.html), [manual](https://manual.ardour.org/) |
| LMMS | 1.2.2 stable, 1.3 alpha | Free; Linux, macOS, Windows | Pattern and song editor, piano roll, automation. VST and LADSPA; LV2 basic in 1.3 alpha. No audio recording on the site | [site](https://lmms.io/), [releases](https://github.com/LMMS/lmms/releases) |
| Zrythm | v2 alpha | Copyleft; Linux first | LV2, VST2, VST3, AU, CLAP, JSFX; SFZ and SF2; Carla sandbox; automation with LFOs and envelopes; chord tools; backups | [site](https://www.zrythm.org/en/index.html) |
| Qtractor | 1.7.0 (2026-11-14) | Free; Linux | JACK audio, ALSA MIDI; LADSPA, DSSI, LV2, VST2, VST3, CLAP; MIDI clock, SPP, MMC; JACK transport; Rubber Band stretch; MIDI learn | [site](https://qtractor.org/) |
| MusE | 4.3 (2026-10-19) | Free; Linux | Audio and MIDI; VST, LV2, DSSI, LADSPA; piano roll, drum, list and score editors; JACK audio and MIDI; scripting | [site](https://muse-sequencer.github.io/) |
| Rosegarden | 26.06 | Free; Linux | MIDI sequencer with strong notation; basic audio. Other details (JACK, plugins, MusicXML) not read on the site | [site](https://www.rosegardenmusic.com/) |
| Audacity | 4.0.2 | Free; Windows, macOS, Linux | Audio editor: VST3, Nyquist, spectrogram, Vamp analysis, label tracks | [site](https://www.audacityteam.org/) |
| Non Timeline (Non-DAW) | last copyright 2021 | Free; Linux | JACK timeline: non-destructive edit, crossfades, punch, loop record, tempo map that drives JACK transport, plain-text journal sessions, imports Ardour 1 to 3. Appears to be unmaintained | [wiki](https://non.tuxfamily.org/wiki/Non%20DAW) |
| Jackdaw | unreleased | GPL-3.0; macOS, Linux | Keyboard-focused DAW in C with SDL. Slash opens a searchable command lookup. Piano roll, effects, automation, UDP API | [repo](https://github.com/chvolow24/jackdaw) |
| Tek | alpha | not read | Keyboard-only terminal DAW. MIDI sequencer through JACK; sampling and LV2 prototyped; keys in a DSL; not scriptable yet | [Hackaday](https://hackaday.com/2025/04/30/terminal-daw-does-it-in-style) |
| trk, Imbolc | early | not read | Terminal trackers and DAWs in Rust, from a search result; not checked | [search result](https://github.com/delaudio/trk), [Imbolc](https://github.com/mohsenil85/imbolc) |
| REAPER (closed) | current | Paid license; Windows, macOS, Linux | ReaScript (Lua, EEL, Python), JSFX, thousands of actions, 128-channel tracks, nested folders, VST2, VST3, LV2, CLAP, PDC, video, LUFS render, take lanes | [about](https://www.reaper.fm/about.php) |
| Bitwig Studio (closed) | current | Paid; Windows, macOS, Linux | Clip launcher, modulators, The Grid, plugin sandbox | [site](https://www.bitwig.com/) |

Observations:

- No open-source DAW pairs a modal key grammar with a scripting API of
  the size of paw's. The nearest are Jackdaw and Tek, and both are small
  and young.
- The older Linux DAWs (Qtractor, MusE, Non) are built on JACK and
  ALSA, so they have sync that paw lacks.
- REAPER is the model for scripting and for custom actions. paw already
  has the same openness through Lua.

## 3. The matrix

Importance is for paw users: musicians who like the keyboard and the
terminal. H = high, M = medium, L = low. Symbols: Y = yes, P = partial, N =
no, ? = not verified. Columns: Ard = Ardour, LMMS, Zry = Zrythm, Qtr =
Qtractor, MusE, Ros = Rosegarden, Aud = Audacity, REA = REAPER.

Facts about the other DAWs come from the sources in section 2, unless
marked "?". A "?" fact comes from general knowledge and was not read on a
page now.

### Recording

| Feature | paw | Ard | LMMS | Zry | Qtr | MusE | Ros | Aud | REA | Importance |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Audio record | Y | Y | ? | Y? | Y | Y | P | Y | Y | H |
| MIDI record | Y | Y | Y | Y | Y | Y | Y | N | Y | H |
| Takes, comping | Y | Y (playlists) | N? | N? | ? | ? | ? | N | Y (lanes) | H |
| Punch, loop record | Y | Y? | N? | ? | Y? | ? | ? | P | Y | H |
| Pre-roll | P | Y? | N? | ? | ? | ? | ? | N | Y | M |
| Step input | Y | Y | Y? | ? | ? | Y? | Y | N | Y? | M |

### Editing

| Feature | paw | Ard | LMMS | Zry | Qtr | MusE | Ros | Aud | REA | Importance |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Piano roll | Y | Y | Y | Y | Y | Y | Y | N | Y | H |
| Score notation | P (ext) | N | N | N | N? | Y | Y | N | P? | M |
| Automation | P | Y | Y | Y | Y | Y? | ? | P? | Y | H |
| Tempo map and meter changes | Y | Y? | ? | ? | Y? | ? | ? | N | Y | H |
| Time stretch | P | P? | N? | ? | Y (Rubber Band) | ? | ? | Y? | Y | H |
| Warp by onsets, tempo detect | N | ? | N | ? | ? | ? | ? | ? | Y | M |
| Spectral edit | N | P? (analysis) | N | N | N | N | N | Y (spectrogram) | Y | L |
| Ripple edit | Y **[WRONG: was N]** | ? | N | ? | ? | ? | ? | ? | Y? | M |
| Undo tree | Y | N? | N? | P (history) | N? | N? | N? | N? | P? | M |

### Arrangement

| Feature | paw | Ard | LMMS | Zry | Qtr | MusE | Ros | Aud | REA | Importance |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Track folders, groups | Y | Y | P? | Y | ? | Y (group tracks) | ? | N | Y | H |
| Markers, regions | Y | Y | Y? | Y | Y? | Y? | Y? | Y (labels) | Y | H |
| Clip launcher | P (ext) | Y (cue) | N | N? | N | N | N | N | P? | M |
| Nested projects | P | N? | N | N | N | N | N | N | Y (sub-projects)? | M |
| Video | N | Y | N | N? | N | N | N | N | Y | L for paw users |

### Mixing

| Feature | paw | Ard | LMMS | Zry | Qtr | MusE | Ros | Aud | REA | Importance |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sends, buses | Y | Y | Y? | Y | Y? | Y | P? | N | Y | H |
| Side-chain | P | Y? | N? | ? | ? | ? | N | N | Y | H |
| CLAP | Y | N? | N | Y | Y | ? | N | N | Y | H |
| VST3 | Y | Y | N | Y | Y | Y (VST) | N | Y | Y | H |
| LV2 | Y | Y | P (1.3 alpha) | Y | Y | Y | N | ? | Y | H |
| LADSPA | N | Y | Y | ? | Y | Y | Y? | N | N? | L |
| Plugin sandbox | Y | P? | N | Y (Carla) | N | N | N | N | P? | M |
| Delay compensation | Y | Y | N? | ? | ? | ? | ? | N | Y | H |
| LUFS meter | P | Y (Loudness Assistant) | N | ? | N | N | N | P? | Y | M |
| Surround | N | Y | N | ? | N | N | N | N | Y | L |

### Render and export

| Feature | paw | Ard | LMMS | Zry | Qtr | MusE | Ros | Aud | REA | Importance |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Stems | Y | Y | ? | ? | ? | ? | ? | N | Y | H |
| Regions to files | Y | Y? | N | ? | N? | N | N | P? | Y | M |
| Formats | WAV, FLAC, MP3, Ogg, Opus (ffmpeg) | many, plus FFmpeg | WAV, OGG? | ? | ? | ? | ? | many | many | H |
| Loudness-targeted render | Y | Y | N | ? | N | N | N | P? | Y | M |
| MIDI export | P | Y | Y | Y | Y | Y | Y | N | Y | M |
| Faster than real time | Y | Y | ? | ? | ? | ? | ? | ? | Y | H |

### Project and interchange

| Feature | paw | Ard | LMMS | Zry | Qtr | MusE | Ros | Aud | REA | Importance |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Text project, git-friendly | Y | N (XML) | N | N | N (XML) | N | N | N | P (RPP text) | H |
| DAWproject | Y (ext) | N? | N | N | N | N | N | N | Y? | M |
| AAF, OMF | N | N? | N | N | N | N | N | N | P? | L |
| Foreign session import | REAPER, DAWproject | Y? (older Ardour) | N | N | N | N | N | N | Y | M |
| Non-Timeline sessions | n/a | | | | | | | | | |
| Session archive | P (folder copy) | Y (FLAC archive) | N | ? | ? | ? | ? | N | Y | M |

### Sync and control

| Feature | paw | Ard | LMMS | Zry | Qtr | MusE | Ros | Aud | REA | Importance |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| JACK | Y (audio) | Y | Y? | Y? | Y (audio and transport) | Y (audio and MIDI) | Y? | N | Y? | M |
| PipeWire | Y | via JACK | ? | ? | ? | ? | ? | ? | Y | H |
| MIDI clock | N | Y? | N | ? | Y | ? | ? | N | Y | M |
| MTC, MMC, LTC | N | Y (LTC and others) | N | N | MMC | ? | ? | N | Y | L to M |
| OSC | N | Y | N | N | N | N | N | N | Y | M |
| Control surfaces | N | Y | N | N | P (MMC) | ? | ? | N | Y | M |
| MIDI learn | Y | Y | Y? | ? | Y | ? | ? | N | Y | H |
| Remote API | Y (socket, MCP) | Y (Lua, OSC) | N | N | N | P? | N | N | Y | H |

### Scripting, accessibility, collaboration, platforms, docs

| Feature | paw | Ard | LMMS | Zry | Qtr | MusE | Ros | Aud | REA | Importance |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Scripting | Y (Lua, Teal, full API) | Y (Lua) | N | N? | N | Y (external) | N | Y (Nyquist) | Y (Lua, EEL, Python) | H |
| Custom keys and actions | Y | P | P | P | Y | ? | ? | ? | Y | H |
| Keyboard-first | Y | P | N | P | P | P | P | P | Y | H |
| Terminal UI | Y | N | N | N | N | N | N | N | N | H for paw |
| Collaboration | N | N | N | N | N | N | N | Audio.com | N | L |
| Version control | Y (git) | N | N | N | N | N | N | Audio.com backups | N | M |
| Platforms | Linux | Linux, macOS, Windows | all three | Linux first | Linux | Linux | Linux | all three | all three | M |
| Manual | Y (Diataxis) | Y | Y | Y | Y | P | Y | Y | Y | H |

## 4. Results

### 4.1 Gaps: what paw lacks that most DAWs have

Rank order by the effect on real work for a paw user.

| Rank | Gap | Evidence | Size | Core or extension | Ticket |
| --- | --- | --- | --- | --- | --- |
| 1 | MIDI clock out and in, MMC, and a transport master or follower (JACK transport) | Qtractor lists them ([site](https://qtractor.org/)); Ardour has a Synchronization chapter ([manual](https://manual.ardour.org/synchronization/)); no page in paw's manual has MIDI clock | M | Core: the clock and transport. An extension may set the mode | Propose: "Sync: MIDI clock, MMC and JACK transport", m-3 style milestone (record and play), medium |
| 2 | Audio onset and tempo detection, and slicing | limits.md: "paw does not find warp markers at onsets" | M | Extension (`audiotools`), using the stretch and media cores | Propose: "Audio: onset and tempo detection for warp markers", medium |
| 3 | OSC server and client; control surfaces (Mackie, HUI, Launchpad) | Ardour has both ([features](https://ardour.org/features.html)); paw has only MIDI learn and `paw ctl` | M | Extension (`osc`, `surfaces`) over `paw.api`; the core needs only a generic socket or MIDI sysex port | Propose: "OSC extension", "Control surface extension"; low to medium |
| 4 | LADSPA, and LV2 in `plugins.add_dir` **[CHECKED: both true. LV2: TASK-242. LADSPA: owner decision]** | limits.md | S | Core (plugin host) | Propose: "plugins.add_dir finds LV2"; low. LADSPA: low, skip unless asked |
| 5 | MIDI SysEx and MIDI-CI | limits.md: ports do not send or read SysEx; MIDI file import drops it | M | Core (ports) | Propose: "MIDI ports: SysEx", medium. It also unblocks step 1 for MMC and the hardware synth patch dumps |
| 6 | Ripple edit, and gap-closing delete in the arrange view **[WRONG: paw has both; TASK-235 adds automation, markers and tempo]** | REAPER has ripple; paw's Ex `d` and `m` do not move later clips **[WRONG: `:d!` and `:m!` do]** | S | Core (operator option) | Propose: "Ripple editing mode", medium |
| 7 | Video clip kind | Ardour and REAPER have video | L | Extension on clip kinds | TASK-23 (clip kinds) and TASK-10 (media): partly; propose "video clip kind extension", low |
| 8 | Session interchange: AAF, OMF, Ardour sessions | Ardour imports others; Non Timeline reads Ardour 1 to 3 ([wiki](https://non.tuxfamily.org/wiki/Non%20DAW)) | M each | Extension (`interop`) | Propose: "interop: Ardour session import" (low), "AAF" (low) |
| 9 | Surround, wide buses, several side-chains | limits.md | L | Core | Propose: "Wide buses", low. Few users in paw's target |
| 10 | Per-track LUFS and spectrum **[WRONG in part: the `meter` device gives them on any track]** | limits.md: tracks give only peak | S | Core meter | Propose: "Track meters: RMS and LUFS", low |

Other gaps of lower rank:

- Ableton Link and tap tempo: none. Link is closed-ish and low in
  importance. **[WRONG for tap tempo: `:tempo.tap` and `<Space>Tt` exist.
  Link is GPL-2.0 or paid, not closed: TASK-230.]**
- A built-in spectrogram or spectral editor (Audacity has it):
  extension, low.
- Session archive as one file (Ardour: FLAC-compressed archive; see
  [features](https://ardour.org/features.html)). Extension, low. A
  project folder is plain, so a `tar` does the job.
- Real-time collaboration: none and not planned. Seats share one
  project, which is enough for a studio.
- Screen reader support: unknown. A terminal frontend should help.
  Propose a check: "Accessibility: test paw with a screen reader",
  low priority, but it is a strong claim if true.

### 4.2 Improvements: paw has it, but it needs work

| Area | Evidence | Ticket |
| --- | --- | --- |
| Export model is split across render, stems, regions, bounce, freeze, project export | `render.md` command table; design in TASK-222 | TASK-222 (high) |
| Offline render for plugins | TASK-80.1 | TASK-80, TASK-80.1 |
| Freeze renders in the foreground and keys no state | TASK-214 | TASK-214 |
| Stretch limits: always from the start of the file, ratios, formants | limits.md | TASK-80 (partly); propose "Stretch: render from the playhead" (medium) **[WRONG: TASK-80 leaves stretch out; TASK-10 part M4 covers the playhead]** |
| Notation engraving | TASK-135 to TASK-139 | planned (low) |
| MIDI 2.0: 7-bit velocity in project, no note-off attribute, no NRPN form in files | limits.md | none: propose "MIDI 2.0: 16-bit velocity in the project" (low) |
| MIDI file import loses sysex, key signature, text; karaoke words | limits.md | none: propose "Project: a place for key signatures, text and sysex events" (medium) **[WRONG in part: key markers and `project.key` are the place; TASK-244, TASK-228.3]** |
| Sampler: no LFO, v2 envelopes, effects; whole-file load | limits.md | none: propose "sampler: SFZ v2" (low) |
| Lua devices: no window, no block-rate params, no own latency | limits.md | none: propose "Lua devices: latency and state" (low) |
| Clip launcher: no follow actions | limits.md | TASK-23 may cover; propose a ticket if not |
| Mouse in the terminal: no drag of fades, gain, track height | limits.md | none: low (the keys work) |
| Tags: no ISRC, lyrics | limits.md | none: low |
| projdiff does not read a project folder in all cases | TASK-210 (bug, high) | TASK-210 |
| Tests and CI: flaky tests | TASK-207, TASK-145 to TASK-151 | open |
| Platform: Linux with Nix only | TASK-38 to TASK-53 | planned |
| Window frontend paused, so "two frontends" is true only for the terminal now | AGENTS.md | none (owner decision) |

### 4.3 Where paw is ahead

Keep each of these strong. For each, a reason that other DAWs do not do
the same.

1. **Modal grammar on a timeline.** Jackdaw has a command lookup
   ([repo](https://github.com/chvolow24/jackdaw)) and Tek has Vim-like
   keys ([Hackaday](https://hackaday.com/2025/04/30/terminal-daw-does-it-in-style)),
   but none has operators, motions, text objects, `.`, counts and Ex
   ranges together.
2. **Project as text, with diff, merge and an undo tree.** Non Timeline
   uses a plain-text journal ([wiki](https://non.tuxfamily.org/wiki/Non%20DAW)),
   but it is old. Other open-source DAWs save XML that does not merge.
3. **One API for all** (Lua and Teal, `paw ctl`, `paw -l`, MCP). Only
   REAPER ([about](https://www.reaper.fm/about.php)) and Ardour (Lua,
   [features](https://ardour.org/features.html)) come near.
4. **Queries, quickfix, pickers with sound preview.**
5. **Terminal speed.** See bench/DAWS.md.
6. **Subprojects and scopes**, linked clips, narrowed views. No other
   open-source DAW has them (not verified for REAPER sub-projects).
7. **Plugin sandbox** (Zrythm has one through Carla:
   [site](https://www.zrythm.org/en/index.html)).
8. **Per-note articulations (MIDI 2.0 attributes), harmony reading,
   snippets, language servers for music.**
9. **Documentation**: Diataxis, a tutor with 17 lessons, doc tests.
10. **Remote seats**: a terminal or window attached to a kernel over TLS.

### 4.4 Ideas worth taking from other DAWs

| Idea | Source | Fit for paw | Proposed ticket |
| --- | --- | --- | --- |
| Loudness Assistant: one command that measures the mix against streaming targets and proposes a gain | Ardour ([features](https://ardour.org/features.html)) | paw has `mixdiag` and a `loudness=` render option; join them in one `:loudness` command with presets (Spotify, YouTube, EBU R128) **[WRONG: mixdiag has targets already (`:mix.target`, `<Space>mt`); only the apply of the gain is missing: TASK-243]** | "mixdiag: delivery targets" (low, extension) |
| Cue markers in the timeline that trigger clips | Ardour | paw has cues and a launcher; a marker kind that fires a slot makes a bridge | covered by `launcher`; propose "launcher: cue markers on the ruler" (low) |
| Playlists per track (take sets that you swap) | Ardour ([features](https://ardour.org/features.html)) | paw has takes and comps; check that a named comp can be swapped with one key | check only |
| Searchable command lookup | Jackdaw | paw already has `:help`, pickers and `K` | none |
| Custom actions (chains of commands bound to a key) | REAPER ([about](https://www.reaper.fm/about.php)) | paw has Lua and `:adjust`; a `:macro` that records keys exists in Vim (`q`) **[CHECKED: `qa`, `@a`, `@@` exist]** | check that `q` records macros; propose if not |
| Take lanes and a batch render with HTML stats | REAPER | paw has takes; stats page is a small extension | low |
| MIDI Time Code and MMC for hardware | Qtractor | gap 1 above | gap 1 |
| JACK session and NSM (Non Session Manager) | Qtractor lists JACK session ([site](https://qtractor.org/)); Non uses NSM | Linux studio tools; low demand with PipeWire | low |
| Modulators and a modular device (The Grid) | Bitwig ([site](https://www.bitwig.com/)) | TASK-86 (drivers) and TASK-75 (modifier stacks) already aim here | TASK-75, TASK-86 |
| Plugin sandboxing | Bitwig, Zrythm | paw has it | none |
| Chord tools: generate a chord progression from a scale | Zrythm ([site](https://www.zrythm.org/en/index.html)) | paw has harmony reading, snippets, suggestions | none: covered |
| Automation with LFOs and envelopes as shapes | Zrythm | TASK-86 drivers; curve editor waves exist | TASK-86 |
| Microtonal tuning (Scala files) | Ardour ([features](https://ardour.org/features.html)) | paw has MPE and MIDI 2.0 pitch; a Scala tuning option is a small extension | propose "tuning: Scala files" (low) |
| Hardware synth patch names (MIDNAM) | Ardour | paw has `play-a-hardware-synth`; names would help | propose (low) |
| Rubber Band stretch as a second engine | Qtractor ([site](https://qtractor.org/)) | paw has its own two methods; Rubber Band gives formant and transient control | consider only after TASK-80 |
| Audio clip editor window (basic) | Qtractor 1.7.0 | paw has clip keys; a view for one audio clip (like the piano roll) may help | propose "Audio clip view" (medium) |
| Session archive in one file | Ardour | `:archive` that writes a tar of the folder, with media | propose (low) |

## 5. Proposed tickets (summary)

Do not create them here. Milestone names are suggestions.

| Title | Milestone | Priority | Size | Where |
| --- | --- | --- | --- | --- |
| Sync: MIDI clock, MMC and JACK transport | New: "Sync and control" | Medium | M | core |
| MIDI ports: SysEx send and read | Sync and control | Medium | M | core |
| OSC extension | Sync and control | Low | M | extension |
| Control surface extension (Mackie, Launchpad) | Sync and control | Low | M | extension |
| Audio: onset and tempo detection for warp markers | m-5 (media) | Medium | M | extension |
| Ripple editing mode **[WRONG: exists; TASK-235 for the rest]** | m-2 style (editing) | Medium | S | core |
| plugins.add_dir finds LV2 | m-5 | Low | S | core |
| Track meters: RMS and LUFS | m-5 | Low | S | core |
| Launcher: follow actions | Clip kinds | Low | S | extension (check TASK-23 first) |
| interop: Ardour session import and AAF | Interop | Low | M each | extension |
| Project: events for key signatures, text and sysex in MIDI import | m-5 | Medium | M | core |
| Stretch: render from the playhead **[mapped to TASK-10 part M4]** | m-5 | Medium | M | core |
| Audio clip view (one view for one audio clip) | Editing | Medium | M | core view |
| mixdiag: delivery targets in one command **[WRONG: exists; TASK-243 applies the gain]** | Mix | Low | S | extension |
| Accessibility: test with a screen reader | Docs | Low | S | docs and tests |
| Wide buses (surround) | Later | Low | L | core |

## Limits of this study

- Pages of other DAWs were read through a summary tool. Some claims
  ("?" in the matrix) were not found on a page and come from general
  knowledge. Check them before you use them in a public text.
- The Ardour sync page named the sync methods only as chapter titles, and
  the Ardour entries for MIDI clock and MTC are not verified.
- I did not run any DAW or paw.
- Rosegarden, trk and Imbolc were not read in depth.

## Sources

paw (this repository): `README.md`, `docs/README.md`,
`docs/reference/limits.md`, `render.md`, `devices.md`, `plugins.md`,
`learn.md`, `ctl.md`, `midi.md`, `programs.md`, `engine.md`, `stretch.md`,
`takes.md`, `tempo.md`, `media.md`, the `extensions/*/README.md` files,
`bench/DAWS.md`, and `backlog task list --plain` (read 2026-11-23).

Other DAWs:

- Ardour features: https://ardour.org/features.html
- Ardour manual: https://manual.ardour.org/ and https://manual.ardour.org/synchronization/
- LMMS: https://lmms.io/ and https://github.com/LMMS/lmms/releases
- Zrythm: https://www.zrythm.org/en/index.html
- Qtractor: https://qtractor.org/
- MusE: https://muse-sequencer.github.io/
- Rosegarden: https://www.rosegardenmusic.com/
- Audacity: https://www.audacityteam.org/
- Non Timeline: https://non.tuxfamily.org/wiki/Non%20DAW
- Jackdaw: https://github.com/chvolow24/jackdaw
- Tek: https://hackaday.com/2025/04/30/terminal-daw-does-it-in-style
- trk: https://github.com/delaudio/trk, Imbolc: https://github.com/mohsenil85/imbolc
- REAPER: https://www.reaper.fm/about.php
- Bitwig Studio: https://www.bitwig.com/

Date: 2026-11-23.

## Review of 2026-11-23: mapped to existing tickets, and not filed

Mapped to existing tickets (no new m-14 ticket):

- Export model, stems, regions, bounce: TASK-222 and TASK-222.1 to TASK-222.10.
- Offline flag for plugins: TASK-80.1 (done). Edit quality: TASK-80.
- Stretch from the playhead: TASK-10 part M4 (note added to TASK-10).
- Video on the timeline: TASK-23 part E4 and TASK-10 part M10 (note added to TASK-23).
- OSC output from custom clips: TASK-23 part C2. TASK-231 shares its encoder.
- Background freeze: TASK-214. projdiff of folders: TASK-210.
- Notation engraving: TASK-135 to TASK-139 (m-11).
- Modulators and links between values: TASK-75, TASK-86.
- Windows plugins: TASK-52. Platforms: TASK-38 to TASK-40. Wasm: TASK-1, TASK-2.

Not filed, with the reason:

- Ripple edit as a new feature: it exists. TASK-235 adds the missing parts.
- Delivery targets in mixdiag: they exist. TASK-243 adds the apply of the gain.
- Tap tempo and key macros: they exist.
- LADSPA, AAF and OMF, spectral edit, LTC: owner decisions (see the report).
- Stretch ratios and formants, VST2, AU, session archive (`:collect` and the
  project folder do it), real-time collaboration, JACK session and NSM, mouse
  drags of fades and gain in the terminal (the keys do it): low value for
  musicians who use the keyboard and the terminal.
