<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 13: Save and export

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 13`.*

In this lesson, we change a song, save it, and export it to a WAV file.

A project is a folder that contains the whole song, e.g., the tracks, the devices and their settings, the clips and the notes. It also contains the automation and the loop, and each part is in a file of its own. Recordings are in the `media` folder of the project. To export, paw plays the whole song into a WAV file, which other programs can play.

The practice project already has a folder of its own in the folder of the tutor, so `:w` saves it there. paw saves your own projects where you tell it to, e.g., `:w song`.

## The idea

`:w` and `<C-s>` save, and `:w name` saves under a new name. `:e name` opens a project, and `:e song.mid` makes a project from a MIDI file, which has no folder until you type `:w name`. `:new` starts an empty project. `:wq` or `ZZ` save and quit, and `:q` or `ZQ` quit without a save.

The status line shows the name of the project, with `[+]` when there are changes that are not saved. `:export name.wav` writes the song to a file. `tail=2` adds two seconds for the echoes to stop, and `bits=16` makes a 16-bit file.

A file name without a folder goes into the folder `renders` of the project. `:pwd` shows the folder of the project, and `:cd` changes it.

## If you know Vim

`:w`, `:e`, `:wq`, `:x`, `ZZ` and `ZQ` work as in Vim, but on projects instead of files. Only one project is open at a time, and `:e` replaces it. `:w name` works as `:saveas` in Vim, so you continue to work in the new project. In Vim, `:w name` writes a copy and you stay in the old file, but paw does not make such a copy.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. First, change the song. `&` puts a copy of the chords after them, so press `&`, and the name of the project in the status line gets a `[+]`.
   - ✓ The `[+]` shows that some changes are not saved.
2. Type `:w` and `<CR>` to save. `<C-s>` does the same.
   - ✓ The project is saved, the `[+]` is gone, and the message line shows the file.
3. `:export` plays the song into a WAV file. Type `:export tutor-song.wav tail=2` and `<CR>`.
   - *Hint:* `tail=2` keeps two more seconds after the last note, so the echo does not stop too early.
   - ✓ tutor-song.wav is in the folder `renders` of the practice project, and the message line shows its length and peak level.
4. `:messages` shows the messages that you missed. Type `:messages` and `<CR>`, and then press `q` to close the list.
   - ✓ The list showed all the messages since paw started, with the saves and the export.
5. You can play the rendered file in a different player. In paw, press `<Space><Space>` to play the song, and `<Space><Space>` again to stop.
   - ✓ The song is saved and exported.

## What we did

We saved with `:w`, and we saw `[+]` for changes that are not saved. Then we exported with `:export name.wav tail=2` and read `:messages`.

- Previous: [Record audio and MIDI](12-recording.md)
- Next: [Find a command or a key](14-finding.md)
- [All lessons](README.md)
