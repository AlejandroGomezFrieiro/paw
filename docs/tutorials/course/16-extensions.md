<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 16: The bundled extensions

*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 16`.*

In this lesson, we load seven of the extensions that come with paw, and we try one feature of each.

Extensions give much of what paw can do. An extension is a folder of Lua in `extensions/` next to the program. It uses the same `paw` module as your `init.lua`. `:tutor.try` loads an extension for this session only. To load an extension each time, link its folder into `~/.config/paw/extensions`.

The README.md of each extension tells all that it does. Each extension has its keys under its own prefix. These are `]s` `[s` and `,S` (sections), `gz` (musicops) and `,t` (pattern). They are also `,x` and `]d` `[d` (mixdiag), `,u` `g-` `g+` (undotree) and `,v` (utau).

## The idea

An extension adds commands, keys, text objects, operators and views with the functions of lesson 15. So its additions obey the grammar that you know. Sections are text objects (`dis`, `yis`), and musicops are operators (`gzkip`). `.`, counts and macros work with them.

## If you know Vim

`:tutor.try name` is like `:packadd`. `:extensions` shows the loaded extensions.

## Steps

The tutor opens a practice project for this lesson. It checks each step when you do it.

1. pattern writes drum parts as text. Type `:tutor.try pattern` and `<CR>`. Then type `:pattern.set bd*2 [~ sn]` and `<CR>`. A new clip on Drums plays the pattern.
   - ✓ The clip plays kick, kick, rest, snare. `,tt` edits the text of the clip under the cursor.
2. musicops adds musical operators under `gz`. Type `:tutor.try musicops` and `<CR>`. Press `j` to go to Keys. Press `gzkic` to move each note of the clip one step up the scale.
   - ✓ The tune is D E F A F E D now. It moved in C major. `gzh` humanizes, `gzs` strums, and `.` repeats them.
3. sections gives names to the parts of a song. Type `:tutor.try sections` and `<CR>`. Press `,Sa`, type `Verse` and press `<CR>` to mark a section at the cursor.
   - ✓ Verse shows on the ruler. `is` is now a text object: `yis` yanks the section on all tracks, and `]s` goes to the next section.
4. undotree shows each state of the project. Type `:tutor.try undotree` and `<CR>`. Press `,uu` to open the undo tree. Look at it, then press `q` to close it.
   - ✓ paw keeps each change that you undo. `g-` and `g+` move through time, across branches.
5. mixdiag measures the mix and shows problems. Type `:tutor.try mixdiag` and `<CR>`. Then press `,xa` to measure the song.
   - ✓ mixdiag measures in the background. The message line shows the loudness when it is complete, and `,xx` shows the problems that it found.
6. interop opens and writes REAPER projects and DAWproject files. Type `:tutor.try interop` and `<CR>`. Then type `:export tutor-song.rpp` and `<CR>`. A list of the items that REAPER cannot use opens. Press `q` to close it.
   - ✓ tutor-song.rpp is in the folder where you started paw. As the list told you, the file does not contain the built-in devices.
7. utau sings notes with lyrics through the engines of OpenUtau. Type `:tutor.try utau` and `<CR>`. Press `o` to add a track. Then type `:utau.voice` and `<CR>` to make it a vocal track.
   - ✓ The track is a vocal track. It sings when you install `paw-utau-engine` and a voicebank (see extensions/utau/README.md). Then `,v` adds a vocal track and asks for its singer in one step.
8. Listen to the pattern and the tune. Press `gs` and `<Space>`, and `<Space>` to stop.
   - ✓ You hear the drum pattern and the tune that musicops changed.

## What we did

We tried one feature of pattern, musicops, sections, undotree, mixdiag, interop and utau. Their READMEs tell the rest.

Previous: [Make paw your own: options, keys, commands](15-your-own.md) · [All lessons](README.md) · Next: [Ranges, :s and :g: edit by line](17-ranges.md)
