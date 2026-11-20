<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 4: The piano roll and insert mode

*This lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 4`.*

In this lesson, we add a line of notes and a chord to a short tune in the piano roll.

The piano roll shows the notes of one clip. It has one row for each pitch, with the names on the left. Time goes to the right in steps of a sixteenth note. In normal mode, you move the cursor and change one note at a time. In insert mode, you draw notes with the cursor, and paw writes them when you leave insert mode.

The clip `tune` has three notes in its second bar.

## The idea

To move, use `h` `l` for one step and `j` `k` for one semitone. Use `<C-d>` `<C-u>` for one octave and `w` `b` for notes. `0` `$` go to the start and the end of the clip.

To change the note under the cursor: `<CR>` adds or removes a note. `+` `-` (and `<C-a>` `<C-x>`) change its pitch. `<A-h>` `<A-l>` change its length, `H` `L` move it, `[` `]` change the velocity and `gh` plays the pitch.

Insert mode (`i`, or `a` after the note) draws a note from the cursor. `l` `h` make it longer and shorter, and `j` `k` `<C-d>` `<C-u>` change its pitch. `<CR>` keeps the note and draws the next note at its end. `<Space>` adds a rest first. `o` draws a note from the same start, for a chord. `<BS>` removes the last note, and `<Esc>` writes the notes and leaves insert mode.

`I` makes the keyboard a piano: `a w s e d f t g y h u j k` are C up to the next C. In normal mode, `<Esc>` stays in the piano roll. `<C-w>p` returns to the arrange view.

## If you know Vim

In Vim, `<C-a>` and `<C-x>` add to a number and subtract from it. Here they change the pitch of a note, as `+` `-` do. The pitch is the main value of a note. Insert mode does not insert text. It draws a note, and all of it is one undo step. `.` repeats it at the cursor, as Vim repeats an insert.

## Steps

The tutor opens a practice project for this lesson. It checks each step when you do it.

1. The cursor is on the clip `tune`. Press `<CR>` (Enter) to open it in the piano roll.
   - ✓ The piano roll opens. The cursor is on E4 at the start of the clip.
2. `j` and `k` move one semitone down and up, and you hear each pitch. `<C-d>` `<C-u>` move one octave, half a page as in Vim. Press `k` three times to go to G4.
   - *Hint:* Look at the title row of the piano roll. It shows the pitch under the cursor.
   - ✓ The cursor is on G4. The title row shows the name, and the name on the left is highlighted.
3. `<CR>` adds a note at the cursor, or removes the note that is there. Press `<CR>`.
   - ✓ A short G4 shows. Its length is one step, a sixteenth.
4. `<A-l>` makes the note under the cursor one step longer and `<A-h>` makes it shorter. They do the same to a clip in the arrange view. Press `<A-l>` three times.
   - ✓ The note is one beat long now.
5. `<C-a>` (or `+`) moves the note up one semitone and `<C-x>` (or `-`) moves it down. Press `<C-a>` two times.
   - *Hint:* `<C-a>` is Ctrl and a. The cursor must be on the note.
   - ✓ The note is A4 now, and the cursor moved with it.
6. Press `4l` to move one beat. Then press `i` to draw a note there.
   - ✓ The mode is INSERT at beat 2. A note starts here, with no length yet. The title row shows its pitch and length.
7. In insert mode, `l` makes the note one step longer and `h` makes it shorter. `j` `k` change its pitch. Press `2j` (down to G) and `4l` (one beat long).
   - *Hint:* Counts work as in normal mode: `4l` is `l` four times. `h` moves one step back.
   - ✓ A green G that is one beat long shows. paw did not write it yet. The cursor is at its end.
8. `<CR>` keeps the note and starts the next note at its end. Press `<CR>`, `2j` (F), `4l`, `<CR>`, `j` (E) and `4l`.
   - *Hint:* Each new note starts with no length, and `4l` draws it. `<BS>` removes the last note that you kept.
   - ✓ G and F are kept, and you draw an E now.
9. `<Esc>` writes the notes that you drew and leaves insert mode. Press `<Esc>`.
   - ✓ The notes A G F E go into the notes E D C that were there before. All of this is one undo step.
10. Now we add a chord at the end of the clip. Press `$` (the end), `i`, `4j` (down to C) and `4l`.
   - ✓ A C that is one beat long shows after the end of the clip. The clip becomes longer to hold it.
11. `o` keeps the note and starts a note with the same start and length, for a chord. Press `o` and `4k` (E). Then press `o` and `3k` (G).
   - ✓ C and E are kept, and you draw a G now.
12. `<CR>` continues after the chord. `<C-d>` and `<C-u>` move one octave. Press `<CR>`, `<C-d>` and `7j` (the C below), `4l` and `<Esc>`.
   - *Hint:* `<Space>` adds a rest of one step before the next note.
   - ✓ The clip has a C major chord, then a C3 below it.
13. In normal mode, `<Esc>` stays in the piano roll, as in each view. `<C-w>p` returns to the previous window. Press `<C-w>p`, then `gs` and `<Space><Space>` to listen. `<Space><Space>` stops.
   - ✓ Your tune plays over the drums.

## What we did

We moved by pitch and by time, and changed a note in normal mode. Then we drew a line and a chord in insert mode.

Previous: [Tracks, clips and notes](03-making.md) · [All lessons](README.md) · Next: [The grammar: operators, motions, text objects](05-grammar.md)
