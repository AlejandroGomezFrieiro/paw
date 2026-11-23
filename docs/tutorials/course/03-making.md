<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 3: Tracks, clips and notes

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 3`.*

In this lesson, we add a track with a name and a synth, and we draw some notes with the keyboard. Then we listen to the notes with a drum beat.

A track has clips on the timeline and a chain of devices. The first device is an instrument, which makes sound from notes, and effects come after it. A MIDI clip contains notes, and an audio clip contains a recording. A new track makes no sound until it has an instrument.

## The idea

In normal mode, lowercase letters do an action on the item under the cursor. For example, `o` opens a new track below, and `a` adds a device. Moreover, `i` inserts clips and notes, and `x` deletes the clip while `&` repeats it. `u` undoes and `<C-r>` redoes, so you can take back each change that you make here.

## If you know Vim

`o` and `O` add a track below and above, as they add lines in Vim. `i` starts insert mode, where each key inserts an item, e.g., `m` a MIDI clip, `r` a region and `'` a marker. `<CR>` opens the clip in the piano roll in insert mode, where the cursor draws notes instead of text. `grn` renames.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. `o` adds a track below the track of the cursor. Press `o`.
   - ✓ A new empty track shows, and the cursor is on it.
2. Give the track a name. Press `grn`, and press `<C-u>` to clear the old name. Type `Bass` and press `<CR>`.
   - *Hint:* `grn` shows the old name on the command line. `<C-u>` is Ctrl and u. `<Esc>` cancels.
   - ✓ The name of the track is Bass.
3. A track makes no sound until it has an instrument. Press `a`, type `synth` and press `<CR>`.
   - *Hint:* `a` opens a list of all the devices, and the text that you type makes the list shorter. `<CR>` selects the first item.
   - ✓ Bass has a synth.
4. `i` starts insert mode. In insert mode, `m` inserts a MIDI clip at the cursor, and `<CR>` opens the clip in the piano roll, where you draw notes. Press `i`, `m` and `<CR>`.
   - ✓ The mode is INSERT, and the piano roll is open on C4. The title row of the piano roll shows the note that you draw.
5. `l` makes the note one step longer, so `4l` makes one beat. `<CR>` keeps the note and starts the next note at its end. `2+` moves the note up two semitones. Press `4l`, `<CR>`, `2+`, `4l`, `<CR>`, `2+`, `4l` and `<Esc>`.
   - *Hint:* The notes that you draw are green, and `<Esc>` writes them. `h` makes a note shorter, and `j` moves it down.
   - ✓ The clip has three notes, C, D and E, and paw wrote them when you left insert mode.
6. Press `<C-w>p` to return to the arrange view, which is the previous window. `<Esc>` does not leave the piano roll, and the same is true in every view.
   - ✓ The arrange view gets the keys again, in NORMAL mode.
7. Press `<Space><Space>` to hear your notes with the drums. Press `<Space><Space>` again to stop.
   - ✓ You heard the bass line that you wrote.
8. `&` puts a copy of the clip immediately after it. Press `&` two times.
   - *Hint:* The cursor must be on the clip. `0` moves it to the start.
   - ✓ The track has three copies of the clip, one after the other.
9. `u` undoes the last change and `<C-r>` (Ctrl and r) redoes it. Press `u`, then `<C-r>`.
   - ✓ paw undid the change and did it again. Each key that changes the project is one undo step.
10. `x` deletes the clip under the cursor. Press `x`.
    - ✓ paw deleted the clip, and `u` can bring it back.
11. Listen to the result. Press `gs` to move to the start, `<Space><Space>` to play and `<Space><Space>` to stop.
    - ✓ You have a bass line on a track that you made.

## What we did

We made a track and gave it a name and an instrument. We added notes, repeated and deleted clips, and undid a change.

- Previous: [Move the cursor, and keys that change meaning](02-moving.md)
- Next: [The piano roll and insert mode](04-pianoroll.md)
- [All lessons](README.md)
