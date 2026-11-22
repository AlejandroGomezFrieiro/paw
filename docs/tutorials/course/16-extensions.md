<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 16: The bundled extensions

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 16`.*

In this lesson, we load seven of the extensions that come with paw, and we try one feature of each.

Much of what paw can do comes from extensions. An extension is a folder of Lua in `extensions/` next to the program, and it uses the same `paw` module as your `init.lua`. `:tutor.try` loads an extension for this session only. To load an extension each time, link its folder into `~/.config/paw/extensions`.

The README.md of each extension describes all that it does. Each extension has its keys under its own prefix, e.g., `]]` `[[` and `\S` for sections, `gz` for musicops and `\t` for pattern. Moreover, mixdiag uses `<Space>m`, undotree uses `<Space>p` `g-` `g+`, and utau uses `\V`.

## The idea

An extension adds commands, keys, text objects, operators and views with the functions of lesson 15, so what it adds follows the grammar that you know. For example, sections are text objects (`dis`, `yis`), and musicops are operators (`gzkip`), so `.`, counts and macros work with them.

## If you know Vim

`:tutor.try name` works as `:packadd` does in Vim, and `:extensions` shows the loaded extensions.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. pattern writes drum parts as text. Type `:tutor.try pattern` and `<CR>`, and then type `:pattern.set bd*2 [~ sn]` and `<CR>`. A new clip on Drums plays the pattern.
   - ✓ The clip plays kick, kick, rest and snare, and `\tt` edits the text of the clip under the cursor.
2. musicops adds musical operators under `gz`. Type `:tutor.try musicops` and `<CR>`, and press `j` to go to Keys. Then press `gzkic` to move each note of the clip one step up the scale.
   - ✓ The tune is now D E F A F E D, because it moved in C major. `gzh` humanizes, `gzs` strums, and `.` repeats them.
3. sections gives names to the parts of a song. Type `:tutor.try sections` and `<CR>`, and then press `\Sa`, type `Verse` and press `<CR>` to mark a section at the cursor.
   - ✓ Verse shows on the ruler, and `is` is now a text object. `yis` yanks the section on all tracks, and `]]` goes to the next section.
4. undotree shows each state of the project. Type `:tutor.try undotree` and `<CR>`, and press `<Space>pu` to open the undo tree. Look at the tree, and then press `q` to close it.
   - ✓ paw keeps each change that you undo, and `g-` and `g+` move through the states in order of time, across branches.
5. mixdiag measures the mix and shows problems. Type `:tutor.try mixdiag` and `<CR>`, and then press `<Space>ma` to measure the song.
   - ✓ mixdiag measures in the background, and the message line shows the loudness when the measurement is complete. `<Space>mx` shows the problems that it found.
6. interop opens and writes REAPER projects and DAWproject files. Type `:tutor.try interop` and `<CR>`, and then type `:export tutor-song.rpp` and `<CR>`. A list of the items that REAPER cannot use opens, and `q` closes it.
   - ✓ tutor-song.rpp is in the folder where you started paw. As the list said, the file does not contain the built-in devices.
7. utau sings notes with lyrics through the engines of OpenUtau. Type `:tutor.try utau` and `<CR>`, and press `o` to add a track. Then type `:utau.voice` and `<CR>` to make it a vocal track.
   - ✓ The track is a vocal track, and it sings when you install `paw-utau-engine` and a voicebank (see extensions/utau/README.md). After that, `\Vt` adds a vocal track and asks for its singer in one step.
8. Listen to the pattern and the tune. Press `gs` and `<Space><Space>`, and `<Space><Space>` to stop.
   - ✓ You hear the drum pattern and the tune that musicops changed.

## What we did

We tried one feature of each of pattern, musicops, sections, undotree, mixdiag, interop and utau, and their READMEs describe the rest.

- Previous: [Make paw your own: options, keys, commands](15-your-own.md)
- Next: [Ranges, :s and :g: edit by line](17-ranges.md)
- [All lessons](README.md)
