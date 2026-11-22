<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# Lesson 6: The same grammar on notes

*The lesson takes about ten minutes. To do it in paw, type `:ext.load tutor`, then `:tutor 6`.*

In this lesson, we change a short riff in the piano roll with the grammar of lesson 5.

All the keys of the last lesson work in the piano roll, where notes take the place of clips and pitches take the place of tracks. For example, `w` goes to the next note, so `dw` deletes up to the next note. `in` is the note under the cursor, and `ic` is the notes that sound together at the cursor. `ie` is all the notes of the clip.

`dd` deletes a whole row, which is all the notes of one pitch. `.` repeats, and `y` and `p` copy.

The clip `riff` is open in the piano roll. Its notes are C, D, E, G, E, D and C, and each note is one beat long.

## The idea

You learn the grammar one time and use it in each view. The operators are the same (`d` `y` `c` `>` `<` `=` `gl`), and the motions are the same keys (`w` `b` `e` `0` `$` `W` `B`, and `j` `k` by pitch). The text objects are `in` (the note), `ib` (the bar), `ie` (the whole clip) and `ic` (the chord).

Longer songs also have `ip` (the phrase) and `iv` (the voice), and `)` and `]c` go to the next phrase and the next chord. A note is part of the range where it starts, so `dw` from the middle of a gap deletes nothing.

## If you know Vim

`in` takes the place of `iw`, and `dd` selects a whole row, which is a pitch. `/d4` finds a pitch by its name, and `n` goes to the next match.

## Steps

The tutor opens a practice project for the lesson, and it checks each step when you do it.

1. The cursor is on the first note. `w` goes to the next note, at any pitch. Press `w` two times.
   - ✓ The cursor is on E4, which is the third note.
2. `dw` deletes from the cursor up to the next note. Press `dw`.
   - ✓ paw deleted E4, and the cursor stays in the gap.
3. Press `w` to go to G4, and press `.` to delete it in the same way.
   - *Hint:* In a gap, `dw` goes up to the start of the next note. A note is part of the range where it starts, so `dw` deletes nothing. Move the cursor onto a note first.
   - ✓ `.` repeated `dw` from the new position.
4. Press `u` two times to bring back the two notes.
   - ✓ The riff is complete again.
5. `in` is the note under the cursor, and `>in` moves it one step later. The cursor moves with the note. Press `>in`, then `.`.
   - *Hint:* The cursor must be on G4 (beat 4). If a move is wrong, press `u`.
   - ✓ G4 is now two steps late, so it comes a little after the beat.
6. `yie` copies all the notes of the clip. `$` goes to the end of the clip, and `p` pastes the notes there. Press `yie`, `$` and `p`.
   - ✓ The riff plays two times, and the clip became longer to hold the copy.
7. `c` is the change operator, and `cin` deletes the note under the cursor and starts insert mode at its position. Press `^` (the first note) and `cin`. Then press `7+`, `4l` and `<Esc>`.
   - *Hint:* `7+` moves the new note up to G, and `4l` makes it one beat long.
   - ✓ The riff now starts on G.
8. `/` finds a pitch, so `/d4` and `<CR>` go to the next D4. Then `dd` deletes all the notes of the pitch. Press `/d4`, `<CR>` and `dd`.
   - ✓ The clip now has no D4.
9. Press `<C-w>p` to return to the arrange view. Press `<Space><Space>` to listen, and `<Space><Space>` to stop.
   - ✓ Your changed riff plays.

## What we did

We used the grammar of lesson 5 on notes: `dw`, `.`, `>in`, `yie` `p`, `cin`, `dd` and `/`.

- Previous: [The grammar: operators, motions, text objects](05-grammar.md)
- Next: [Visual mode: select, then act](07-visual.md)
- [All lessons](README.md)
