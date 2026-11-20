<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 13: Save and render

*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 13`.*

In this lesson, we change a song, save it, and render it to a WAV file.

A project is a folder that contains all of the song. It has the tracks, the devices and their settings, the clips, the notes, the automation and the loop. Each part is in a file of its own. Recordings are in the `media` folder of the project. To render, paw plays the whole song into a WAV file, which other programs can play.

This practice project already has a folder of its own in the folder of the tutor, so `:w` saves it there. paw saves your own projects where you tell it: `:w song`.

## The idea

`:w` saves, and `<C-s>` also saves. `:w name` saves under a new name. `:e name` opens a project. `:e song.mid` makes a project from a MIDI file, and the project has no folder until `:w name`. `:new` starts an empty project. `:wq` or `ZZ` save and quit, and `:q` or `ZQ` quit without a save.

The status line shows the name of the project, with `[+]` when there are changes that are not saved. `:render name.wav` writes the song to a file. `tail=2` adds two seconds for the echoes to stop, and `bits=16` makes a 16-bit file. A name without a folder goes into the folder of the project. `:pwd` shows that folder, and `:cd` changes it.

## If you know Vim

`:w`, `:e`, `:wq`, `:x`, `ZZ` and `ZQ` work as in Vim, but on projects, not on files. Only one project is open at a time, and `:e` replaces it. `:w name` is the `:saveas` of Vim: you continue to work in the new file. In Vim, `:w name` writes a copy and you stay in the old file. paw does not make such a copy.

## Steps

The tutor opens a practice project for this lesson. It checks each step when you do it.

1. First, change the song: `&` puts a copy of the chords after them. Press `&`. The name of the project in the status line gets a `[+]`.
   - ✓ The `[+]` shows that some changes are not saved.
2. Type `:w` and `<CR>` to save. `<C-s>` does the same.
   - ✓ The project is saved. The `[+]` is gone, and the message line shows the file.
3. `:render` plays the song into a WAV file. Type `:render tutor-song.wav tail=2` and `<CR>`.
   - *Hint:* `tail=2` keeps two more seconds after the last note, so the echo does not stop too early.
   - ✓ tutor-song.wav is in the folder of the practice project. The message line shows its length and peak level.
4. `:messages` shows the messages that you did not see. Type `:messages` and `<CR>`, then press `q` to close the list.
   - ✓ The list showed all the messages since paw started, with the saves and the renders.
5. You can play the rendered file in a different player. Here, `<Space><Space>` plays the song in paw. `<Space><Space>` stops.
   - ✓ The song is saved and rendered.

## What we did

We saved with `:w`, saw `[+]` for changes that are not saved, rendered with `:render name.wav tail=2` and read `:messages`.

Previous: [Record audio and MIDI](12-recording.md) · [All lessons](README.md) · Next: [Find a command or a key](14-finding.md)
