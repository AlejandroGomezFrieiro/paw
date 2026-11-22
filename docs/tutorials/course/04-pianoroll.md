<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 4: The piano roll and insert mode

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 4`.*

In this lesson, we add a line of notes and a chord to a short tune in the piano roll.

The piano roll shows the notes of one clip, with one row for each pitch and the names of the pitches on the left. Time goes to the right in steps of a sixteenth note. In normal mode, you move the cursor and change one note at a time. In insert mode, you draw notes with the cursor, and paw writes them when you leave insert mode.

The clip `tune` has three notes in its second bar.

## The idea

To move the cursor, use `h` and `l` for one step and `j` and `k` for one semitone. `<C-d>` and `<C-u>` move one octave, and `w` and `b` move by notes. `0` and `$` go to the start and the end of the clip.

In normal mode, `<CR>` adds or removes a note, and `gh` plays the pitch. `+` and `-` (or `<C-a>` and `<C-x>`) change the pitch of the note under the cursor. `<A-h>` and `<A-l>` change its length, and `H` and `L` move it. Moreover, `[` and `]` change its velocity.

Insert mode (`i`, or `a` after the note) draws a note from the cursor, or takes the note under the cursor. `l` and `h` move the edge of the note where the cursor is, so at the end of the note, `l` makes the note longer. `+` and `-` change the pitch, and `K` and `J` change the octave. `k` and `j` bend the note.

In insert mode, `<CR>` keeps the note and draws the next note at its end, and `<Space>` adds a rest first. `c` makes the note a chord. `<BS>` removes the last note, and `<Esc>` writes the notes and leaves insert mode.

In normal mode, `<Esc>` stays in the piano roll, and `<C-w>p` returns to the arrange view.

## If you know Vim

In Vim, `<C-a>` and `<C-x>` add to a number and subtract from it. In paw, they change the pitch of a note in the same way as `+` and `-`, because the pitch is the main value of a note. Insert mode draws notes instead of text, and one insert is one undo step. `.` repeats the insert at the cursor, as Vim repeats an insert.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. The cursor is on the clip `tune`. Press `<CR>` (Enter) to open it in the piano roll.
   - ✓ The piano roll opens, and the cursor is on E4 at the start of the clip.
2. `j` and `k` move one semitone down and up, and you hear each pitch. `<C-d>` and `<C-u>` move one octave. Press `k` three times to go to G4.
   - *Hint:* Look at the title row of the piano roll, which shows the pitch under the cursor.
   - ✓ The cursor is on G4. The title row shows the name of the pitch, and the name on the left is highlighted.
3. `<CR>` adds a note at the cursor, or removes the note that is there. Press `<CR>`.
   - ✓ A short G4 shows, with a length of one step, which is a sixteenth note.
4. `<A-l>` makes the note under the cursor one step longer, and `<A-h>` makes it shorter. In the arrange view, the same keys change the length of a clip. Press `<A-l>` three times.
   - ✓ The note is now one beat long.
5. `<C-a>` (or `+`) moves the note up one semitone and `<C-x>` (or `-`) moves it down. Press `<C-a>` two times.
   - *Hint:* `<C-a>` is Ctrl and a. The cursor must be on the note.
   - ✓ The note is A4 now, and the cursor moved with it.
6. Press `4l` to move one beat. Then press `i` to draw a note there.
   - ✓ The mode is INSERT at beat 2, and a note starts there with no length yet. The title row shows the pitch and the length of the note.
7. In insert mode, `l` makes the note one step longer, and `h` makes it shorter. `+` and `-` change its pitch. Press `2-` (down to G) and `4l` (one beat long).
   - *Hint:* Counts work as in normal mode, so `4l` is `l` four times. `h` moves one step back.
   - ✓ A green G that is one beat long shows, and the cursor is at its end. paw has not written the note yet.
8. `<CR>` keeps the note and starts the next note at its end. Press `<CR>`, `2-` (F), `4l`, `<CR>`, `-` (E) and `4l`.
   - *Hint:* Each new note starts with no length, and `4l` makes it one beat long. `<BS>` removes the last note that you kept.
   - ✓ paw keeps G and F, and you now draw an E.
9. `<Esc>` writes the notes that you drew and leaves insert mode. Press `<Esc>`.
   - ✓ paw adds the notes A, G, F and E to the notes E, D and C that were there before, and the whole insert is one undo step.
10. Now we add a chord at the end of the clip. Press `$` (the end), `i`, `4-` (down to C) and `4l`.
   - ✓ A C that is one beat long shows after the end of the clip, and the clip becomes longer to hold the note.
11. `c` makes the note a chord, and it shows a list of chords with the chord of the key on C first. Press `c`, then `<CR>` to take the first chord.
   - ✓ C, E and G show in green, and the keys of insert mode now change the whole chord as one note. To get another chord, type a symbol, e.g., `V7` or `Am`.
12. `<CR>` keeps the chord and continues after it. `K` and `J` move one octave. Press `<CR>`, `J` (the C below), `4l` and `<Esc>`.
   - *Hint:* `<Space>` adds a rest of one step before the next note.
   - ✓ The clip has a C major chord, followed by a C3 below it.
13. In normal mode, `<Esc>` stays in the piano roll, and the same is true in every view. `<C-w>p` returns to the previous window. Press `<C-w>p`, then `gs` and `<Space><Space>` to listen, and `<Space><Space>` again to stop.
   - ✓ Your tune plays over the drums.

## What we did

We moved by pitch and by time, and changed a note in normal mode. Then we drew a line and a chord in insert mode.

- Previous: [Tracks, clips and notes](03-making.md)
- Next: [The grammar: operators, motions, text objects](05-grammar.md)
- [All lessons](README.md)
