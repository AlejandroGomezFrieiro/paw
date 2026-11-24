---
id: TASK-222
title: >-
  Design: one model for exporting — render, stems, regions, bounce, freeze and
  project export
status: Done
assignee: []
created_date: '2026-11-23T06:48:00Z'
updated_date: '2026-11-23T07:07:00Z'
labels:
  - design
milestone: m-2
dependencies: []
priority: high
ordinal: 250000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner 2026-11-23: 'I might want to export/render mono/stereo, by track/selection/region/project etc. Let's make a task defining how exporting should work, and the difference between stems vs rendering clearly.'

Today there are many entry points that overlap and use words loosely (docs/reference/render.md, freezing.md, subprojects.md):
- :render <file> with range= (song, loop, selection, region), tracks= (selected or ids: 'a stem of those tracks'), stems=true (one file per track), channels= (mono/stereo), master=false, format/rate/bits/dither/normalize/loudness/tail.
- :render stems (one file per top-level group, with a plan to confirm), :render stems tracks (one per track), :render <Group>.
- :stems out (one file per track, paw.render_stems) — a second command for what :render stems tracks does.
- :render.regions out (one file per region, level=).
- :track.bounce (render a track to a new audio track, mute the original), :freeze / :unfreeze (render a track or a block, play the file in its place, stale check).
- :nest.export and :scope.write <folder> (TASK-7.14, in a batch): write a subproject or a view as a project folder, not audio.

The design defines, in the words of a musician:
1. The terms, one meaning each: render (an audio file of what you hear), mix (the whole song through the master), stem (one of a set of files that add up to the mix), bounce and freeze (a render that goes back into the project), export (a file for another program: audio, MIDI, a project folder). Say where 'stem' means a group and where a track.
2. One grammar: WHAT is heard (song, master, a track, selected tracks, a group, each track, each group, a subproject, a scope/view) x WHEN (song, loop, selection, a region, each region, a block) x WHERE in the signal (pre-fader, post-fader, through its groups and master, or not) x HOW the file is (format, channels mono/stereo/as the track, rate, bits, dither, loudness, tail) x HOW MANY files and how they are named.
3. Mono and stereo: per file, and 'as the source' (a mono track renders mono). What mono does to a stereo source (sum at -3 or -6 dB, or left only) and to pan.
4. Which commands stay, which merge, which go (no compatibility needed before a release), and the keys and the plan/confirm step. One way to do each thing; the key rule; terminal first.
5. MIDI export (a clip, a track, the song as a Standard MIDI file or MIDI 2 clip) — in or out of scope, and where it goes.
6. What the render presets are (for example 'stems for mixing engineer', 'mp3 for review') and where they live (project, user config).
7. What the user sees: the plan before many files, progress, the result message, where the files go.
8. Mapping from today's commands to the new ones, and the tickets to build it, in order.

Write the design in backlog/docs/designs/export.md (local). No code. The owner reviews it before any build ticket starts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 backlog/docs/designs/export.md defines each term once and the grammar of what, when, where, how and how many
- [x] #2 Mono and stereo are defined per file and as the source, with what mono does to stereo and pan
- [x] #3 Every current export command is mapped: kept, merged or removed, with the reason
- [x] #4 The design lists the build tickets in order and the questions for the owner
- [x] #5 The owner has reviewed the design
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design written 2026-11-23: backlog/docs/designs/export.md (local). Waits for the owner's review (AC #5).

Terms: render = the work of writing what you hear to a file (not a command). Mix = the whole song through the master, one file. Stem = one file of a set that adds up to the mix; by default of a group (each top-level group, and each track outside a group). Track stem = a stem of one track. Tap = where in the signal the render listens. Export = a file out of the project (audio, MIDI, project folder, other program's file, score). Bounce = a render back into the project as a new audio track. Freeze = a render that plays in place, undone by :unfreeze, with a stale check. Preset = a name for a set of export words. Plan = the list of files paw shows before it writes more than one.

Grammar: :[tracks] [time] export[!] [preset] [target] [words]. WHAT = Ex track range (t2,t4, t/Drums/, t'<,'>) or `clip`; default every track (the mix of the window's scope). WHEN = Ex time range (5,8, %, '<,'>) or in=loop / in=<region>; default the song. WHERE = tap=pre|post|groups|master (default master; only groups/master add up). HOW = target ending, format=, channels=stereo|mono|auto, rate, bits, dither, quality, bitrate, normalize, loudness, tail, tags. HOW MANY = each=group|track|region|clip, two joined (each=region,group = the region matrix). Names = target with fields {project} {track} {group} {tracks} {region} {n} {date}.

Mono: (L+R)/2, a -6 dB sum (as today): a centered mono source keeps its level; pan stays as heard (hard left is -3 dB); tap=pre ignores pan; auto = mono when both sides are equal to the bit. No left-only word.

Commands: :export stays and takes all files out. Merged into it: :render (options map: range= -> Ex range/in=, tracks= -> Ex track range, stems=true -> each=track, master=false -> tap=groups), :render stems (preset stems), :render stems tracks and :stems (preset tracks), :render <Group> (t/Group/), :render.regions (preset regions), :nest.export and :scope.write <folder> (:export project <folder>/), :export ... clip|selection (clip word, '<,'>). Renamed: :render.cancel -> :export.cancel, :render.tags -> :export.tags, :track.bounce -> :bounce (ranges, tap=post: fixes the bounce that holds the master), <Space>rR -> <Space>er. Stay: :freeze, :unfreeze, :utau.render, paw.render. Later (E9, m-11): :notation.export, :part.export, :utau.export become formats of :export. New keys: <Space>e domain (ee again, em, es, et, er, ep), <Space>tb bounce, <Space>tf/tF freeze.

Tickets in order: E1 tap= in the kernel (m-2 High M); E2 channels=auto (m-2 High S); E3 paw.export plan module (m-2 High M); E4 the :export command, plan, queue, keys, docs; old commands go (m-2 High L); E5 presets of user and project (m-2 Medium M); E6 :bounce (m-2 Medium S); E7 MIDI and project folders in the grammar, after TASK-7.14 (m-2 Medium M); E8 one gain for a set of stems (m-2 Low S); E9 notation and utau exports as formats (m-11 Low M).

Questions for the owner (recommendation): 1 :export or :render as the one command (:export). 2 stem = group or track (stems = groups, tracks = per track). 3 tap of :export tracks (post). 4 mono sum (-6 dB, no left-only). 5 channels default (stereo; auto in stems/tracks presets). 6 replace files (silently in renders/, else plan or !). 7 default tail (2 s for all; tail=auto later). 8 where presets live (project, then init.lua, then built-in). 9 subproject as project folder (:export project in its scope; :nest.export goes). 10 :utau.freeze (later utau ticket uses paw.freeze).

Owner 2026-11-23: all recommendations accepted. Build tickets: TASK-222.1 TASK-222.2  TASK-222.3     .

PO 2026-11-23: E4 (L) is split: TASK-222.4 is E4a (the :export command, plan, queue, progress, result, keys; old commands stay) and TASK-222.10 is E4b (the old commands go; render.md becomes export.md). Each build ticket of E1 to E8 has criteria from the design. TASK-222.7 also depends on TASK-7.14.
<!-- SECTION:NOTES:END -->
