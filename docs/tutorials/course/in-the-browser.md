<!-- Made by extensions/tutor/make-docs.lua from the tutor's lessons. Do not edit: change the lesson and run it again. -->

# The course in your browser

In this course, we make and change small songs with paw, and paw runs here, beside the steps. Each lesson takes about ten minutes and opens a practice project of its own. The tutor at the bottom of paw tells you what to do next, and it checks each step when you do it.

## How to use the page

First, press "Start paw" beside the lessons, and after a few seconds paw shows a short song. Second, press the button of a lesson, and paw opens the practice project of the lesson. Third, do each step. You can click paw and type the keys of the step, or you can press "Type it" beside the step, and the page types the keys for you.

When you press "Start paw", your browser loads BrowserPod from browserpod.io, about 6 MB, and paw from this site, about 26 MB. BrowserPod runs Linux programs in a browser tab, and it runs paw here. Nothing loads before you press the button, and nothing that you type leaves your browser. The page works best in Chromium, on a screen that is wide enough for paw to show beside the lessons.

paw in the browser has no plugins, no MIDI ports and no sound input, so the page gives no keys for lesson 12.

## Do the course on your computer

1. Install paw, as [How to install paw with Nix](../../how-to/install-paw.md) shows.
2. Start paw, type `:ext.load tutor` and press Enter.
3. Type `:tutor 1` and press Enter, and lesson 1 starts.

The tutor keeps your place, so `:tutor` starts the next lesson the next time. [The course](README.md) has a page for each lesson.

<div class="paw-course">
<div class="paw-live" data-paw-live data-paw-worker="../../../coi-sw.js"></div>
<div class="paw-course-text">

## Lesson 1: First steps: the screen, play and quit

In this lesson, we play a short song, change its tempo and quit paw.

You use paw from the keyboard, and each part of the screen is a view. The arrange view in the middle has one row for each track, and time goes to the right. The status line at the bottom shows the current mode, which is `NORMAL` now. Below the status line, you type commands and paw shows messages.

The panel at the bottom is the tutor, which tells you what to do and checks each step when you do it.

The keys have the names that Vim gives them. For example, `j` is the j key, `J` is Shift and j, and `<C-r>` is Ctrl and r. Moreover, `<CR>` is Enter, `<Esc>` is Escape, `<Space>` is the space bar and `<BS>` is Backspace, and `gs` means g and then s.

<span data-paw-open='{"lesson":1,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 1 in paw'></span>

1. The song has three tracks, which are Drums, Bass and Keys. Press `<Space><Space>` to play it. <span data-paw-keys='["&lt;leader&gt;&lt;Space&gt;"]' data-paw-state='{"lesson":1,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* `<Space>` is the space bar. Look at the ▶ in the status line and at the playhead, which moves across the clips.
   - ✓ The song plays again and again, because the loop is on. The status line shows `loop`.
2. Press `<Space><Space>` again to stop. <span data-paw-keys='["&lt;leader&gt;&lt;Space&gt;"]' data-paw-state='{"lesson":1,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The song stops. The playhead stays where it stopped.
3. `gs` moves the playhead to the start. Press `g`, then `s`. <span data-paw-keys='["gs"]' data-paw-state='{"lesson":1,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* Press the two keys one after the other, not together.
   - ✓ The playhead is at the start. The clock in the status line shows 1.1.00 (bar 1, beat 1).
4. The highlighted track header is the cursor. `j` moves it down one track and `k` moves it up. Press `j` two times to go to Keys. <span data-paw-keys='["j",400,"j"]' data-paw-state='{"lesson":1,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* If the cursor is below Keys, press `k` to move it up.
   - ✓ The cursor is on Keys.
5. `?` shows each key of the current view. Press `?`, and type `mute` to make the list shorter. Then press `<Esc>` to close the list. <span data-paw-keys='["?",400,"mute",400,"&lt;Esc&gt;"]' data-paw-state='{"lesson":1,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* The text that you type makes the list shorter. `<Esc>` closes the list.
   - ✓ When you forget a key, you can find it in the list. `<CR>` (Enter) on a line does the action of its key.
6. `:` opens the command line at the bottom. Type `:tempo 130` and press `<CR>` (Enter). The song becomes faster. <span data-paw-keys='[":tempo 130",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":1,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* Type the colon too. `<Esc>` cancels a command line. `<BS>` on an empty command line closes it.
   - ✓ The tempo is 130 beats per minute. The status line shows it.
7. Press `<Space><Space>` to hear the faster song. Then press `<Space><Space>` to stop it.
   - ✓ The song plays faster now.
8. To quit paw, type `:q` and `<CR>`. `ZQ` also quits, and `ZZ` saves before it quits. Quit now. The tutor keeps your place, so `:tutor` starts lesson 2 the next time. <span data-paw-keys='[":q&lt;CR&gt;"]' data-paw-state='{"lesson":1,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* If you do not want to quit now, press `<Space>hn` to start lesson 2.
   - ✓ paw quits.

We played a song, moved the cursor, used the command line and found the list of all the keys.

[Lesson 1](01-first-steps.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 2: Move the cursor, and keys that change meaning

In this lesson, we move the cursor through a song by steps, clips, bars and tracks. Then we use the same keys in a different mode and in a different view.

In the arrange view, each track is a row, and time goes from left to right along it. One grid step is one beat. The keys that move the cursor are called motions, and a number before a motion repeats it. Some motions move by small steps or by bars, others move to clips or to the ends of clips, and others move to other tracks.

A key can have a different meaning in a different mode, e.g., normal, visual or insert mode. It can also have a different meaning in a different view, e.g., the arrange view, the piano roll or the mixer. The status line always shows the current mode, and the view that gets the keys has a brighter frame or highlight.

<span data-paw-open='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 2 in paw'></span>

1. The cursor is at the start of the Bass track. `l` moves it right one grid step (one beat), and `h` moves it left. Press `l` three times. <span data-paw-keys='["l",400,"l",400,"l"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The cursor moved three beats. The clock at the top left of the arrange view shows 1.4.00, bar 1 beat 4.
2. A number before a motion repeats the motion. Press `4l` to move four beats. <span data-paw-keys='["4l"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* Type the 4 and then the l. If the cursor is at a different beat, press `0` and then `3l`.
   - ✓ The cursor is on beat 7, near the end of the clip `verse`.
3. `0` moves the cursor to the start of the project. Press `0`. <span data-paw-keys='["0"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The cursor is at the start.
4. `w` moves to the start of the next clip on the track. Press `w`. <span data-paw-keys='["w"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The cursor is on `chorus`, which starts at beat 12 (bar 4).
5. `e` moves to the end of the clip, and `b` moves to its start. Press `e`, then `b`. <span data-paw-keys='["e",400,"b"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ `w`, `b` and `e` move to the start of the next clip, the start of the current clip and the end of the current clip.
6. `W` and `B` move by bars (four beats here). Press `2W` to move two bars. <span data-paw-keys='["2W"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The cursor is on bar 6 (beat 20).
7. `$` moves to the end of the last clip of the track, and `^` moves to its first clip. Press `$`. <span data-paw-keys='["$"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The cursor is at the end of `outro`, where the song ends.
8. `G` moves to the last track, and `gg` moves to the first track. Press `G`. <span data-paw-keys='["G"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The cursor is on Pad, the last track. `3G` moves to track 3.
9. `5|` moves to bar 5. `:5` and `<CR>` do the same. Press `5|`. <span data-paw-keys='["5|"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* `|` is the bar key. On many keyboards, it is Shift and backslash.
   - ✓ The cursor is on bar 5, where the pad starts.
10. Now we use the same keys in a different mode. Press `v`, and the status line shows VISUAL. In visual mode, each motion makes the selection larger. Press `l` two times. <span data-paw-keys='["v",400,"l",400,"l"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ In visual mode, `l` moves the cursor and also selects. Lesson 7 shows what you can do with a selection.
11. `<Esc>` always returns to NORMAL. Press `<Esc>`. <span data-paw-keys='["&lt;Esc&gt;"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ The mode is NORMAL again.
12. Now we use a different view. `<CR>` (Enter) on a clip opens it in the piano roll. Press `<CR>` on the pad clip. <span data-paw-keys='["&lt;CR&gt;"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - *Hint:* The cursor must be on a clip. Press `5|` on the Pad track to move it there.
    - ✓ The piano roll now gets the keys.
13. In the piano roll, the rows are pitches, so `k` moves up one semitone instead of one track. Press `k` two times, and you hear each pitch. <span data-paw-keys='["k",400,"k"]' data-paw-state='{"lesson":2,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ The key is the same as in the arrange view, and it still moves up, but in the piano roll it moves by pitch.
14. `<Esc>` does not leave the current window in any view, and `<C-w>p` returns to the previous window. Press `<C-w>p`. Then press `gp` to move the playhead to the cursor. Press `<Space><Space>` to play and `<Space><Space>` to stop.
    - *Hint:* `<Space><Space>` alone plays from the cursor. `gp` puts the playhead there first, and `<S-CR>` plays from the playhead.
    - ✓ The song played from bar 5, where the melody starts.

We moved by steps, clips, bars and tracks, with counts. The same keys had other meanings in visual mode and in the piano roll.

[Lesson 2](02-moving.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 3: Tracks, clips and notes

In this lesson, we add a track with a name and a synth, and we draw some notes with the keyboard. Then we listen to the notes with a drum beat.

A track has clips on the timeline and a chain of devices. The first device is an instrument, which makes sound from notes, and effects come after it. A MIDI clip contains notes, and an audio clip contains a recording. A new track makes no sound until it has an instrument.

<span data-paw-open='{"lesson":3,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 3 in paw'></span>

1. `o` adds a track below the track of the cursor. Press `o`. <span data-paw-keys='["o"]' data-paw-state='{"lesson":3,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ A new empty track shows, and the cursor is on it.
2. Give the track a name. Press `grn`, and press `<C-u>` to clear the old name. Type `Bass` and press `<CR>`. <span data-paw-keys='["grn",400,"&lt;C-u&gt;",400,"Bass",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":3,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* `grn` shows the old name on the command line. `<C-u>` is Ctrl and u. `<Esc>` cancels.
   - ✓ The name of the track is Bass.
3. A track makes no sound until it has an instrument. Press `a`, type `synth` and press `<CR>`. <span data-paw-keys='["a",400,"synth",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":3,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* `a` opens a list of all the devices, and the text that you type makes the list shorter. `<CR>` selects the first item.
   - ✓ Bass has a synth.
4. `i` starts insert mode. In insert mode, `m` inserts a MIDI clip at the cursor, and `<CR>` opens the clip in the piano roll, where you draw notes. Press `i`, `m` and `<CR>`. <span data-paw-keys='["i",400,"m",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":3,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The mode is INSERT, and the piano roll is open on C4. The title row of the piano roll shows the note that you draw.
5. `l` makes the note one step longer, so `4l` makes one beat. `<CR>` keeps the note and starts the next note at its end. `2+` moves the note up two semitones. Press `4l`, `<CR>`, `2+`, `4l`, `<CR>`, `2+`, `4l` and `<Esc>`. <span data-paw-keys='["4l",400,"&lt;CR&gt;",400,"2+",400,"4l",400,"&lt;CR&gt;",400,"2+",400,"4l",400,"&lt;Esc&gt;"]' data-paw-state='{"lesson":3,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* The notes that you draw are green, and `<Esc>` writes them. `h` makes a note shorter, and `j` moves it down.
   - ✓ The clip has three notes, C, D and E, and paw wrote them when you left insert mode.
6. Press `<C-w>p` to return to the arrange view, which is the previous window. `<Esc>` does not leave the piano roll, and the same is true in every view. <span data-paw-keys='["&lt;C-w&gt;p"]' data-paw-state='{"lesson":3,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The arrange view gets the keys again, in NORMAL mode.
7. Press `<Space><Space>` to hear your notes with the drums. Press `<Space><Space>` again to stop.
   - ✓ You heard the bass line that you wrote.
8. `&` puts a copy of the clip immediately after it. Press `&` two times. <span data-paw-keys='["&amp;",400,"&amp;"]' data-paw-state='{"lesson":3,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* The cursor must be on the clip. `0` moves it to the start.
   - ✓ The track has three copies of the clip, one after the other.
9. `u` undoes the last change and `<C-r>` (Ctrl and r) redoes it. Press `u`, then `<C-r>`. <span data-paw-keys='["u",400,"&lt;C-r&gt;"]' data-paw-state='{"lesson":3,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ paw undid the change and did it again. Each key that changes the project is one undo step.
10. `x` deletes the clip under the cursor. Press `x`. <span data-paw-keys='["x"]' data-paw-state='{"lesson":3,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ paw deleted the clip, and `u` can bring it back.
11. Listen to the result. Press `gs` to move to the start, `<Space><Space>` to play and `<Space><Space>` to stop.
    - ✓ You have a bass line on a track that you made.

We made a track and gave it a name and an instrument. We added notes, repeated and deleted clips, and undid a change.

[Lesson 3](03-making.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 4: The piano roll and insert mode

In this lesson, we add a line of notes and a chord to a short tune in the piano roll.

The piano roll shows the notes of one clip, with one row for each pitch and the names of the pitches on the left. Time goes to the right in steps of a sixteenth note. In normal mode, you move the cursor and change one note at a time. In insert mode, you draw notes with the cursor, and paw writes them when you leave insert mode.

The clip `tune` has three notes in its second bar.

<span data-paw-open='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 4 in paw'></span>

1. The cursor is on the clip `tune`. Press `<CR>` (Enter) to open it in the piano roll. <span data-paw-keys='["&lt;CR&gt;"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The piano roll opens, and the cursor is on E4 at the start of the clip.
2. `j` and `k` move one semitone down and up, and you hear each pitch. `<C-d>` and `<C-u>` move one octave. Press `k` three times to go to G4. <span data-paw-keys='["k",400,"k",400,"k"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* Look at the title row of the piano roll, which shows the pitch under the cursor.
   - ✓ The cursor is on G4. The title row shows the name of the pitch, and the name on the left is highlighted.
3. `<CR>` adds a note at the cursor, or removes the note that is there. Press `<CR>`. <span data-paw-keys='["&lt;CR&gt;"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ A short G4 shows, with a length of one step, which is a sixteenth note.
4. `<A-l>` makes the note under the cursor one step longer, and `<A-h>` makes it shorter. In the arrange view, the same keys change the length of a clip. Press `<A-l>` three times. <span data-paw-keys='["&lt;A-l&gt;",400,"&lt;A-l&gt;",400,"&lt;A-l&gt;"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The note is now one beat long.
5. `<C-a>` (or `+`) moves the note up one semitone and `<C-x>` (or `-`) moves it down. Press `<C-a>` two times. <span data-paw-keys='["&lt;C-a&gt;",400,"&lt;C-a&gt;"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* `<C-a>` is Ctrl and a. The cursor must be on the note.
   - ✓ The note is A4 now, and the cursor moved with it.
6. Press `4l` to move one beat. Then press `i` to draw a note there. <span data-paw-keys='["4l",400,"i"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The mode is INSERT at beat 2, and a note starts there with no length yet. The title row shows the pitch and the length of the note.
7. In insert mode, `l` makes the note one step longer, and `h` makes it shorter. `+` and `-` change its pitch. Press `2-` (down to G) and `4l` (one beat long). <span data-paw-keys='["2-",400,"4l"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* Counts work as in normal mode, so `4l` is `l` four times. `h` moves one step back.
   - ✓ A green G that is one beat long shows, and the cursor is at its end. paw has not written the note yet.
8. `<CR>` keeps the note and starts the next note at its end. Press `<CR>`, `2-` (F), `4l`, `<CR>`, `-` (E) and `4l`. <span data-paw-keys='["&lt;CR&gt;",400,"2-",400,"4l",400,"&lt;CR&gt;",400,"-",400,"4l"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* Each new note starts with no length, and `4l` makes it one beat long. `<BS>` removes the last note that you kept.
   - ✓ paw keeps G and F, and you now draw an E.
9. `<Esc>` writes the notes that you drew and leaves insert mode. Press `<Esc>`. <span data-paw-keys='["&lt;Esc&gt;"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ paw adds the notes A, G, F and E to the notes E, D and C that were there before, and the whole insert is one undo step.
10. Now we add a chord at the end of the clip. Press `$` (the end), `i`, `4-` (down to C) and `4l`. <span data-paw-keys='["$",400,"i",400,"4-",400,"4l"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ A C that is one beat long shows after the end of the clip, and the clip becomes longer to hold the note.
11. `c` makes the note a chord, and it shows a list of chords with the chord of the key on C first. Press `c`, then `<CR>` to take the first chord. <span data-paw-keys='["c",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ C, E and G show in green, and the keys of insert mode now change the whole chord as one note. To get another chord, type a symbol, e.g., `V7` or `Am`.
12. `<CR>` keeps the chord and continues after it. `K` and `J` move one octave. Press `<CR>`, `J` (the C below), `4l` and `<Esc>`. <span data-paw-keys='["&lt;CR&gt;",400,"J",400,"4l",400,"&lt;Esc&gt;"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - *Hint:* `<Space>` adds a rest of one step before the next note.
    - ✓ The clip has a C major chord, followed by a C3 below it.
13. With a MIDI keyboard, `I` starts step input, which enters the notes that you play at the cursor, one note or chord at a time. Press `I` in the piano roll. If you have a keyboard, play a key. <span data-paw-keys='["I"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ The title row shows `STEP`, and a caret shows where the next note goes. With no keyboard, a list of inputs opens, and step input stays on. `<Space>` rests one step, and `=` and a value sets the step.
14. `<Esc>` writes the notes that you played and leaves insert mode. Press `<Esc>`, and press it again if a list of inputs is open. <span data-paw-keys='["&lt;Esc&gt;",400,"&lt;Esc&gt;"]' data-paw-state='{"lesson":4,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ Step input is off, and one undo step takes back all the notes that you played.
15. In normal mode, `<Esc>` stays in the piano roll, and the same is true in every view. `<C-w>p` returns to the previous window. Press `<C-w>p`, then `gs` and `<Space><Space>` to listen, and `<Space><Space>` again to stop.
    - ✓ Your tune plays over the drums.

We moved by pitch and by time, and changed a note in normal mode. Then we drew a line and a chord in insert mode, and met step input from a MIDI keyboard.

[Lesson 4](04-pianoroll.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 5: The grammar: operators, motions, text objects

In this lesson, we delete, mute and loop clips with short commands, and we repeat the commands with `.`.

Most edits in paw use the same grammar. You type an operator, which is the action, and then a motion or a text object, which is the item. For example, `d` is delete and `w` is "to the next clip", so `dw` deletes up to the next clip. `ic` is "the clip under the cursor", so `dic` deletes the clip under the cursor.

A count gives the quantity, e.g., `d2W` deletes two bars. When you type the operator two times, as in `dd`, it acts on whole tracks. `.` repeats the last change at the cursor.

In the practice project, the Beat track has four clips, which are kick, snare, fill and crash, and the Bass track plays below them.

<span data-paw-open='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 5 in paw'></span>

1. The cursor is at the start of `kick`. `d` is the delete operator and `w` is the motion to the next clip. Press `dw`. <span data-paw-keys='["dw"]' data-paw-state='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* After `d`, the status line shows PENDING, which means that the operator waits for its motion. `<Esc>` cancels the operator.
   - ✓ paw deleted `kick`, because `dw` deletes from the cursor to the start of `snare`.
2. Press `u` to bring `kick` back. <span data-paw-keys='["u"]' data-paw-state='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The track has its four clips again.
3. A text object names an item instead of a movement, e.g., `ic` is the clip under the cursor. Press `w` to go to `snare`, then press `dic`. <span data-paw-keys='["w",400,"dic"]' data-paw-state='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ `dic` means "delete in clip", and there is now a gap where `snare` was.
4. `.` repeats the last change. Press `w` to go to `fill`, and then press `.` to delete it too. <span data-paw-keys='["w",400,"."]' data-paw-state='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ `.` did `dic` again, on the clip that is under the cursor now.
5. To undo the two changes, press `u` two times. <span data-paw-keys='["u",400,"u"]' data-paw-state='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The track has four clips again.
6. A count goes with the motion, so `d2W` deletes two bars from the cursor. Press `0`, then `d2W`. <span data-paw-keys='["0",400,"d2W"]' data-paw-state='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ paw deleted two bars of Beat. Bass did not change, because the operator works on the track of the cursor.
7. Press `u` to undo that change. <span data-paw-keys='["u"]' data-paw-state='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The two bars are back.
8. Other operators accept the same motions and objects, e.g., `gc` mutes. Press `gcic` to mute `kick`. <span data-paw-keys='["gcic"]' data-paw-state='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ `kick` is muted and shows in gray. To unmute it, press `gcic` again.
9. Press `w` to go to `snare`. Press `.` to mute it in the same way. <span data-paw-keys='["w",400,"."]' data-paw-state='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ `.` repeats each type of change, e.g., delete, mute and move.
10. An operator typed two times selects whole tracks, so `dd` deletes a track. Press `j` to go to Bass, then press `dd`. <span data-paw-keys='["j",400,"dd"]' data-paw-state='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ paw deleted the Bass track and keeps it in the register.
11. `p` puts the deleted item after the cursor, and a track goes below the cursor. Press `p`. <span data-paw-keys='["p"]' data-paw-state='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ Bass is back, with its synth and its clip, so a delete is also a cut.
12. `gl` is the loop operator. Press `k` to go up to Beat, and press `0` and `w` to put the cursor on `snare`. Then press `glic`. <span data-paw-keys='["k",400,"0",400,"w",400,"glic"]' data-paw-state='{"lesson":5,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ The loop is now over the snare clip, and the ruler shows the loop.
13. Press `gcic` to unmute `snare`. Press `<Space><Space>` to hear the loop, and `<Space><Space>` again to stop.
    - ✓ The snare bar and the bass play again and again.

We used operators with motions (`dw`, `d2W`) and with text objects (`dic`, `gcic`, `glic`), `dd` for tracks, and `.` to repeat.

[Lesson 5](05-grammar.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 6: The same grammar on notes

In this lesson, we change a short riff in the piano roll with the grammar of lesson 5.

All the keys of the last lesson work in the piano roll, where notes take the place of clips and pitches take the place of tracks. For example, `w` goes to the next note, so `dw` deletes up to the next note. `in` is the note under the cursor, and `ic` is the notes that sound together at the cursor. `ie` is all the notes of the clip.

`dd` deletes a whole row, which is all the notes of one pitch. `.` repeats, and `y` and `p` copy.

The clip `riff` is open in the piano roll. Its notes are C, D, E, G, E, D and C, and each note is one beat long.

<span data-paw-open='{"lesson":6,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 6 in paw'></span>

1. The cursor is on the first note. `w` goes to the next note, at any pitch. Press `w` two times. <span data-paw-keys='["w",400,"w"]' data-paw-state='{"lesson":6,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The cursor is on E4, which is the third note.
2. `dw` deletes from the cursor up to the next note. Press `dw`. <span data-paw-keys='["dw"]' data-paw-state='{"lesson":6,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ paw deleted E4, and the cursor stays in the gap.
3. Press `w` to go to G4, and press `.` to delete it in the same way. <span data-paw-keys='["w",400,"."]' data-paw-state='{"lesson":6,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* In a gap, `dw` goes up to the start of the next note. A note is part of the range where it starts, so `dw` deletes nothing. Move the cursor onto a note first.
   - ✓ `.` repeated `dw` from the new position.
4. Press `u` two times to bring back the two notes. <span data-paw-keys='["u",400,"u"]' data-paw-state='{"lesson":6,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The riff is complete again.
5. `in` is the note under the cursor, and `>in` moves it one step later. The cursor moves with the note. Press `>in`, then `.`. <span data-paw-keys='["&gt;in",400,"."]' data-paw-state='{"lesson":6,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* The cursor must be on G4 (beat 4). If a move is wrong, press `u`.
   - ✓ G4 is now two steps late, so it comes a little after the beat.
6. `yie` copies all the notes of the clip. `$` goes to the end of the clip, and `p` pastes the notes there. Press `yie`, `$` and `p`. <span data-paw-keys='["yie",400,"$",400,"p"]' data-paw-state='{"lesson":6,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The riff plays two times, and the clip became longer to hold the copy.
7. `c` is the change operator, and `cin` deletes the note under the cursor and starts insert mode at its position. Press `^` (the first note) and `cin`. Then press `7+`, `4l` and `<Esc>`. <span data-paw-keys='["^",400,"cin",400,"7+",400,"4l",400,"&lt;Esc&gt;"]' data-paw-state='{"lesson":6,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* `7+` moves the new note up to G, and `4l` makes it one beat long.
   - ✓ The riff now starts on G.
8. `/` finds a pitch, so `/d4` and `<CR>` go to the next D4. Then `dd` deletes all the notes of the pitch. Press `/d4`, `<CR>` and `dd`. <span data-paw-keys='["/d4",400,"&lt;CR&gt;",400,"dd"]' data-paw-state='{"lesson":6,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The clip now has no D4.
9. Press `<C-w>p` to return to the arrange view. Press `<Space><Space>` to listen, and `<Space><Space>` to stop.
   - ✓ Your changed riff plays.

We used the grammar of lesson 5 on notes: `dw`, `.`, `>in`, `yie` `p`, `cin`, `dd` and `/`.

[Lesson 6](06-grammar-notes.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 7: Visual mode: select, then act

In this lesson, we select clips and tracks first, and then we delete, copy, mute and transpose them.

Visual mode lets you see the items before you change them, because it changes the order of the keys. First, you select with the motions that you know. Second, you press an operator, and it does its action on the selection.

`v` selects a range of time, and `j` and `k` extend it across tracks. `V` selects whole tracks. In the piano roll, `<C-v>` selects a rectangle of pitches and time. In the practice project, each of the three tracks has four clips of one bar.

<span data-paw-open='{"lesson":7,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 7 in paw'></span>

1. Press `v` to start a selection, and the status line shows VISUAL. Then press `W` to extend the selection over the first bar. <span data-paw-keys='["v",400,"W"]' data-paw-state='{"lesson":7,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The first bar of Drums is selected.
2. `j` extends the selection down to the next track. Press `j`. <span data-paw-keys='["j"]' data-paw-state='{"lesson":7,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The first bar of Drums and Bass is selected.
3. Now do an action on the selection. `x` deletes the selection, so press `x`. <span data-paw-keys='["x"]' data-paw-state='{"lesson":7,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ paw deleted the clips from the two tracks, and the mode is NORMAL again.
4. Press `u` to undo the delete. <span data-paw-keys='["u"]' data-paw-state='{"lesson":7,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The clips are back.
5. `V` selects whole tracks. Press `V`, and press `j` to select Drums and Bass. Then press `y` to yank (copy) them. <span data-paw-keys='["V",400,"j",400,"y"]' data-paw-state='{"lesson":7,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* If the selection is wrong, press `<Esc>` to leave visual mode, and then press `gg` and start again.
   - ✓ The register contains two tracks.
6. `G` goes to the last track, and `p` pastes the tracks below it. Press `G`, then `p`. <span data-paw-keys='["G",400,"p"]' data-paw-state='{"lesson":7,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The song now has five tracks, with the copies of Drums and Bass at the bottom.
7. Press `u` to remove the copies. <span data-paw-keys='["u"]' data-paw-state='{"lesson":7,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The song has three tracks again.
8. `gv` selects the last selection again, which is the two tracks. Press `gv`, then `~` to mute them. <span data-paw-keys='["gv",400,"~"]' data-paw-state='{"lesson":7,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Drums and Bass are muted, and their `M` flags are lit. On whole tracks, `~` mutes the tracks, and on a range of time, it mutes the clips in the range.
9. Press `gv` and `~` again to unmute them. <span data-paw-keys='["gv",400,"~"]' data-paw-state='{"lesson":7,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ `~` mutes and unmutes.
10. Visual mode also works in the piano roll. Press `3G` to go to Keys, and press `<CR>` to open its first clip. <span data-paw-keys='["3G",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":7,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ The piano roll shows the A minor chord of `k1`.
11. `v` selects a range of time at all pitches. Press `v`, and then press `12<C-a>` to move all notes that start in the range up one octave. <span data-paw-keys='["v",400,"12&lt;C-a&gt;"]' data-paw-state='{"lesson":7,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - *Hint:* While the status line shows VISUAL, type 1, 2, and then Ctrl and a.
    - ✓ The chord is one octave higher, because in visual mode a count gives the amount.
12. Press `<C-w>p` to return to the arrange view. Press `<Space><Space>` to listen, and `<Space><Space>` to stop.
    - ✓ The first chord sounds one octave higher.

We selected with `v`, `V` and motions, and then used `x`, `y`, `~`, or a count and `<C-a>`. We also used `gv` to select again, and we used visual mode in the piano roll.

[Lesson 7](07-visual.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 8: Yank, paste, registers and macros

In this lesson, we copy a short hook along a track and keep two bass clips in named registers. Then we record a macro that changes the hook.

A delete or a yank puts the items in a register, and a paste takes them from the register. Usually you use the register without a name, but the named registers (`"a` to `"z`) let you keep several items at the same time. You can undo each change, and with a count you undo more than one change. A macro records keys into a register, so that you can play the keys again.

The Lead track has a short hook, and the Bass track has two clips, A and B.

<span data-paw-open='{"lesson":8,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 8 in paw'></span>

1. The cursor is on the hook. Press `yic` to yank (copy) the clip. <span data-paw-keys='["yic"]' data-paw-state='{"lesson":8,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The hook is in the unnamed register, and also in register 0, which keeps the last yank.
2. `p` pastes after the clip under the cursor. Press `p`. <span data-paw-keys='["p"]' data-paw-state='{"lesson":8,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ A second hook shows immediately after the first.
3. A count pastes more than one copy, and `p` again continues from the last paste. Press `2p`. <span data-paw-keys='["2p"]' data-paw-state='{"lesson":8,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Four hooks fill four bars.
4. Named registers keep more than one item. Press `j` to go to Bass and `0` to go to its start. Press `"ayic` to yank clip A into register a. <span data-paw-keys='["j",400,"0",400,"\"ayic"]' data-paw-state='{"lesson":8,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* `"` is the double quote key. Press `"`, then `a`, then `yic`.
   - ✓ Register a contains A.
5. Press `w` to go to B. Press `"byic` to yank it into register b. <span data-paw-keys='["w",400,"\"byic"]' data-paw-state='{"lesson":8,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Register b contains B.
6. `:registers` shows the contents of each register. Type `:registers` and `<CR>`, look at the list, and then press `q` to close it. <span data-paw-keys='[":registers",400,"&lt;CR&gt;",400,"q"]' data-paw-state='{"lesson":8,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The list showed `"a` and `"b`, with `"0` and the unnamed `""`.
7. Press `$` to go to the end of B. Press `"ap` to paste A there, and `"bp` to paste B after it. <span data-paw-keys='["$",400,"\"ap",400,"\"bp"]' data-paw-state='{"lesson":8,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The bass line is A B A B, so it plays two times.
8. Undo also accepts a count. Press `2u` to undo the two pastes. <span data-paw-keys='["2u"]' data-paw-state='{"lesson":8,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The bass line is A B again, and `2<C-r>` would redo the two pastes.
9. Now we record a macro. Press `k` to go up to Lead and `0` to go to its start. Then press `qq` to record keys into register q. <span data-paw-keys='["k",400,"0",400,"qq"]' data-paw-state='{"lesson":8,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The status line shows `recording @q`.
10. Type the change. `vic` selects the clip, and `12<C-a>` moves its notes up one octave. `w` goes to the next clip, and then `q` stops the recording. <span data-paw-keys='["vic",400,"12&lt;C-a&gt;",400,"w",400,"q"]' data-paw-state='{"lesson":8,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - *Hint:* Without the selection, `<C-a>` on a track moves the fader. If the result is wrong, press `u` to undo the change, and `qq` to record again.
    - ✓ The first hook went up one octave while you recorded, and register q contains `vic12<C-a>w`.
11. `@q` plays the macro on the clip under the cursor, and `@@` plays it again. Press `@q`, then `@@`. <span data-paw-keys='["@q",400,"@@"]' data-paw-state='{"lesson":8,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ Three hooks are one octave higher, and the last hook did not change.
12. Listen to the result. Press `gs` and `<Space><Space>`, and press `<Space><Space>` again to stop.
    - ✓ The hook goes up and then comes down again.

We used `yic` and `p` with counts, and we used named registers, `:registers` and `2u`. Then we recorded a macro with `qq` and played it with `@q` and `@@`.

[Lesson 8](08-registers.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 9: Devices, parameters and plugins

In this lesson, we make a synth brighter and darker, add an echo after it, and bypass the echo.

Each track has a chain of devices. The first device is an instrument, which makes sound from notes, and the effects come after it. Each effect changes the sound of the device before it. The device panel shows the chain of the track under the cursor, with the parameters of each device, and you use the same kind of keys there as in the other views.

The built-in devices include `synth`, `drums`, `gain`, `delay` and `limiter`. The CLAP, LV2 and VST3 plugins that you installed are also devices, and most of them have their own window.

<span data-paw-open='{"lesson":9,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 9 in paw'></span>

1. The cursor is on Lead. Press `<Space>dd` (the space bar, then d two times) to show its device panel on the right, and the panel gets the keys. <span data-paw-keys='["&lt;leader&gt;dd"]' data-paw-state='{"lesson":9,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* The leader key is the space bar, and it starts many commands of two keys.
   - ✓ The panel shows the name of the synth, and below it one row for each parameter.
2. `j` and `k` select a row. Press `6j` to go down to `cutoff`, which sets how bright the sound is. <span data-paw-keys='["6j"]' data-paw-state='{"lesson":9,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ `cutoff` is selected.
3. `+` increases the parameter by one step, and `-` decreases it. A count before them gives the number of steps. Press `10+` three times. <span data-paw-keys='["10+",400,"10+",400,"10+"]' data-paw-state='{"lesson":9,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The sound is brighter, and the bar and the number show the new value.
4. Listen while you change the value. Press `<Space><Space>`, and then press `-` some times to make the sound darker. Press `<Space><Space>` to stop.
   - ✓ You can change parameters while the song plays.
5. `a` adds a device after the instrument. Press `a`, type `delay` and press `<CR>`. <span data-paw-keys='["a",400,"delay",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":9,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ An echo now comes after the synth.
6. `w` goes to the next device. Press `w` to go down to the `Delay` heading. <span data-paw-keys='["w"]' data-paw-state='{"lesson":9,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* `b` goes to the previous device, and `j` and `k` move one row at a time.
   - ✓ The delay is selected.
7. `gcc` bypasses the selected device, so the device stays in the chain but does nothing. Press `gcc`, and then `gcc` again to enable the device. <span data-paw-keys='["gcc",400,"gcc"]' data-paw-state='{"lesson":9,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ With bypass, you can compare the sound with and without an effect. In the other views, `gc` mutes.
8. `ge` opens the window of a plugin. Built-in devices have no window, and the message line says so. Press `ge`. <span data-paw-keys='["ge"]' data-paw-state='{"lesson":9,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ For a plugin, the window opens, and `ge` again closes it, in every view.
9. If you installed plugins, `a` shows them with the built-in devices. Press `a`, type a part of the name of a plugin and press `<CR>`, and then press `ge` to see its window. `:devices` shows all the devices. <span data-paw-keys='["&lt;leader&gt;hn"]' data-paw-state='{"lesson":9,"keys":"&lt;Esc&gt;"}' data-paw-label='Next step'></span>
   - *The tutor cannot check this step* (The installed plugins are different on each computer, and a plugin window needs a desktop). `<Space>hn` moves to the next step.
10. `<C-w>c` closes the panel, and the arrange view gets the keys again. Press `<C-w>c`. <span data-paw-keys='["&lt;C-w&gt;c"]' data-paw-state='{"lesson":9,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ The panel is closed, and `<Space>dd` shows it again.
11. Listen to the line with its echo. Press `<Space><Space>`, and `<Space><Space>` to stop.
    - ✓ You hear a synth and a delay that you adjusted by ear.

We used the device panel to select and change parameters. We added and bypassed a device, and we found where plugin windows open.

[Lesson 9](09-devices.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 10: The mix: faders, pan, buses, sends, automation

In this lesson, we mix a short song. We change the level and the pan of the bass, and we send the keys through a bus. Then we give the melody an echo and make the chords fade in.

To mix, you set the level of each track with its fader, in dB, and its position from left to right with the pan. You mute some tracks, or solo a track to hear it alone. You also set where the sound of each track goes, which is either the master or a bus that groups tracks under one fader. A send can also take a part of the sound to an effect track.

Automation changes a fader, or a parameter, over time. The mixer shows one strip for each track, and you can make the same changes from the arrange view.

<span data-paw-open='{"lesson":10,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 10 in paw'></span>

1. Press `<Space>mm` to open the mixer at the bottom, with one strip for each track. Each strip has a fader and a meter. <span data-paw-keys='["&lt;leader&gt;mm"]' data-paw-state='{"lesson":10,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The mixer gets the keys, and the master is on the right.
2. In the mixer, `h` and `l` select a strip, and the cursor starts on its fader. `-` and `+` change the row under the cursor by 1 dB. Press `l` to go to Bass, then press `-` three times. <span data-paw-keys='["l",400,"-",400,"-",400,"-"]' data-paw-state='{"lesson":10,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Bass is at -7 dB, which is 3 dB lower than before. `3-` or `3<C-x>` does the same in one step.
3. `]` and `[` pan the strip to the right and to the left, at each row of the strip. Press `]` three times. <span data-paw-keys='["]",400,"]",400,"]"]' data-paw-state='{"lesson":10,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Bass is a little to the right.
4. `s` solos a track, so you hear only the soloed tracks. Press `<Space><Space>` to play and `s` to hear Bass alone. Press `s` again to hear all tracks, and `<Space><Space>` to stop.
   - ✓ With solo, you can listen to one track closely, and solo does not change the mix.
5. `M` mutes a track. Press `l` to go to Keys, and `M` to mute it. <span data-paw-keys='["l",400,"M"]' data-paw-state='{"lesson":10,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Keys is muted, and its `M` is lit.
6. Press `M` again to unmute Keys, and press `<C-w>c` to close the mixer. <span data-paw-keys='["M",400,"&lt;C-w&gt;c"]' data-paw-state='{"lesson":10,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The arrange view gets the keys again, and the cursor is still on Keys. In the arrange view too, `+` and `-` change the fader, and `]` and `[` change the pan.
7. A bus is a track that other tracks play into. Type `:track.add Bus` and press `<CR>` to add one. <span data-paw-keys='[":track.add Bus",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":10,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ A track with the name Bus shows below Keys, and the cursor is on it.
8. Now send Keys into the bus. Type `/Keys` and `<CR>` to find the track, and then type `:track.output Bus` and `<CR>`. <span data-paw-keys='["/Keys",400,"&lt;CR&gt;",400,":track.output Bus",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":10,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Keys now plays through Bus. The fader of Bus changes the level of the chords and of each other track that you send there.
9. A send copies a part of a track to a different track, which here is Echo, a track with a delay. Type `/Lead` and `<CR>` to find the track, and then type `:send Echo -6` and `<CR>`. <span data-paw-keys='["/Lead",400,"&lt;CR&gt;",400,":send Echo -6",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":10,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* `<Space>ts` does the same, but it asks for the track and sends at the default level.
   - ✓ Lead sends to Echo at -6 dB, so the melody now has an echo. The fader of Echo sets the level of the echo.
10. Now we add automation. `A` adds a volume point at the cursor and asks for its value. Type `/Keys` and `<CR>` to return to Keys, and then press `0` and `A`. Press `<C-u>` to clear the value, type `-30` and press `<CR>`. <span data-paw-keys='["/Keys",400,"&lt;CR&gt;",400,"0",400,"A",400,"&lt;C-u&gt;",400,"-30",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":10,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - *Hint:* The cursor must be on Keys. Type `/Keys` and `<CR>`.
    - ✓ A point of -30 dB is at the start, and an `A` shows in the track header.
11. Press `2W` to move two bars. Then press `A` and `<C-u>`, type `-10` and press `<CR>`, so that the chords fade in over two bars. <span data-paw-keys='["2W",400,"A",400,"&lt;C-u&gt;",400,"-10",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":10,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
    - ✓ The lane of the track shows the line between the points.
12. Listen from the start. Press `gs` and `<Space><Space>`, and `<Space><Space>` to stop.
    - ✓ The chords fade in through a bus, the melody has an echo, and the bass is on the right.

We used the faders, pan, solo and mute of the mixer. We made a bus with `:track.output`, and we added a send and volume automation with `A`.

[Lesson 10](10-mixing.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 11: Loops, marks and jumps

In this lesson, we loop the chorus of a song with a click, and then we jump between marks and loop two bars of the verse.

The loop plays one part of the song again and again while you work on it. You can enable and disable the loop, and set it with the `gl` operator, and the ruler shows the loop.

In a long song, you need keys that move quickly. `/` finds clips and tracks by name, and `m` sets a mark that `'` returns to. Other keys return to the position before a jump.

The song in the practice project has an intro, a verse and a chorus.

<span data-paw-open='{"lesson":11,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 11 in paw'></span>

1. `gL` enables and disables the loop. When the loop is on, the status line shows `loop`, and the ruler shows the loop. Press `gL`. <span data-paw-keys='["gL"]' data-paw-state='{"lesson":11,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The loop is on, over the first two bars.
2. `/` finds a clip or a track by its name. Type `/chorus` and press `<CR>`. <span data-paw-keys='["/chorus",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":11,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The cursor is on the chorus, and `n` goes to the next match, which is the chorus of Bass.
3. `gl` is the loop operator. Press `glic` to loop the clip under the cursor. <span data-paw-keys='["glic"]' data-paw-state='{"lesson":11,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The loop is now over the chorus.
4. `gm` enables the metronome (the click). Press `gm`, and then press `gp` to move the playhead to the cursor and `<Space><Space>` to play. Press `<Space><Space>` again to stop.
   - ✓ The chorus played with a click.
5. Press `gm` to disable the click. <span data-paw-keys='["gm"]' data-paw-state='{"lesson":11,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The click is off.
6. `ma` sets mark a at the cursor. Press `ma`. <span data-paw-keys='["ma"]' data-paw-state='{"lesson":11,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Mark a is on the chorus, and `:marks` shows the marks.
7. Move to a different position. Press `G` (the last track) and `0` (the start), and then press `'a` to jump to the mark. <span data-paw-keys='["G",400,"0",400,"&#39;a"]' data-paw-state='{"lesson":11,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* `'` is the apostrophe key.
   - ✓ The cursor is on the chorus of Drums again.
8. `''` returns to the position before the jump. Press `''`. <span data-paw-keys='["&#39;&#39;"]' data-paw-state='{"lesson":11,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The cursor is at the start of Lead, where it was before `'a`. `''` again returns to the chorus, and `<C-o>` goes further back.
9. `gl` also accepts motions. Press `3|` to go to bar 3, and then press `gl2W` to loop two bars from there. <span data-paw-keys='["3|",400,"gl2W"]' data-paw-state='{"lesson":11,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The loop is now over the first two bars of the verse.
10. Press `gp` and `<Space><Space>` to listen, and `<Space><Space>` again to stop.
    - ✓ Two bars of the verse play again and again.

We set the loop with `gL`, `glic` and `gl2W`, and the click with `gm`. We used `/` to find clips, and `ma`, `'a` and `''` to jump.

[Lesson 11](11-loops.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 12: Record audio and MIDI

In this lesson, we record an audio take and a MIDI take on two tracks, over a drum beat.

A track records its input, which is either audio from an input of your sound card, e.g., a microphone or a guitar, or notes from a MIDI keyboard. To record, first arm the tracks that you want to record. Second, start the recording and play, and third, stop the recording. Each armed track gets a new clip at the position where the recording started. A track with an audio input records audio, and an armed track with no input records MIDI.

For the first part of the lesson, you need a microphone or another input, and for the second part, you need a MIDI keyboard. If you do not have them, read the steps and press `<Space>hn` to skip a step. The recordings of the practice project go in the folder of the tutor.

In the browser, paw has no sound input or MIDI keyboard, so do the lesson in paw on your computer.

1. The cursor is on Voice, a track with no device, and `I` shows the inputs that the track can use. Press `I`, and type some letters of the input of your microphone. Type `1/2` for the first pair of channels, or `· 1` for the first channel, and press `<CR>`.
   - *Hint:* If the list has no channels, no input device is open. `:audio` shows the devices, and you can select one there.
   - ✓ Voice gets its sound from the input that you selected, and the header shows the input and its level. With `<A-i>`, you hear the input without a recording.
2. `r` arms the track for a recording, and its `R` becomes red. Press `r`.
   - ✓ The track is armed, and you also hear the input of an armed track.
3. `R` starts the recording from the cursor, as `<Space><Space>` plays from it. Press `R`, and sing or play for some seconds. Then press `R` to stop the recording, and `<Space><Space>` to stop the song.
   - *Hint:* Press `R` before `<Space><Space>`. If you press only `<Space><Space>`, record mode stays on, with `rec` lit in the status line, and the next `<Space><Space>` records again.
   - ✓ A new audio clip with your take shows where the recording started, and the clip shows its waveform.
4. Now we record MIDI. Press `r` to disarm Voice, `j` to go to Keys, and `r` to arm Keys.
   - *Hint:* `:midi.inputs` shows the MIDI ports that paw finds.
   - ✓ Keys is armed and has no audio input, so it records MIDI. When you play your keyboard, you hear the synth.
5. Press `0` to put the cursor at the start, and `R` to record. Play some notes on your MIDI keyboard, and then press `R` and `<Space><Space>` to stop.
   - ✓ A MIDI clip contains the notes that you played, and `<CR>` on the clip opens it in the piano roll.
6. Press `r` to disarm Keys. Then press `gs` and `<Space><Space>` to listen, and `<Space><Space>` to stop.
   - ✓ Your recordings play with the drums.

We selected an input with `I`, armed the track with `r`, recorded with `R` and stopped with `<Space><Space>`, and we made an audio take and a MIDI take.

[Lesson 12](12-recording.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 13: Save and export

In this lesson, we change a song, save it, and export it to a WAV file.

A project is a folder that contains the whole song, e.g., the tracks, the devices and their settings, the clips and the notes. It also contains the automation and the loop, and each part is in a file of its own. Recordings are in the `media` folder of the project. To export, paw plays the whole song into a WAV file, which other programs can play.

The practice project already has a folder of its own in the folder of the tutor, so `:w` saves it there. paw saves your own projects where you tell it to, e.g., `:w song`.

<span data-paw-open='{"lesson":13,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 13 in paw'></span>

1. First, change the song. `&` puts a copy of the chords after them, so press `&`, and the name of the project in the status line gets a `[+]`. <span data-paw-keys='["&amp;"]' data-paw-state='{"lesson":13,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The `[+]` shows that some changes are not saved.
2. Type `:w` and `<CR>` to save. `<C-s>` does the same. <span data-paw-keys='[":w",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":13,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The project is saved, the `[+]` is gone, and the message line shows the file.
3. `:export` plays the song into a WAV file. Type `:export tutor-song.wav tail=2` and `<CR>`. <span data-paw-keys='[":export tutor-song.wav tail=2",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":13,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* `tail=2` keeps two more seconds after the last note, so the echo does not stop too early.
   - ✓ tutor-song.wav is in the folder `renders` of the practice project, and the message line shows its length and peak level.
4. `:messages` shows the messages that you missed. Type `:messages` and `<CR>`, and then press `q` to close the list. <span data-paw-keys='[":messages",400,"&lt;CR&gt;",400,"q"]' data-paw-state='{"lesson":13,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The list showed all the messages since paw started, with the saves and the export.
5. You can play the rendered file in a different player. In paw, press `<Space><Space>` to play the song, and `<Space><Space>` again to stop.
   - ✓ The song is saved and exported.

We saved with `:w`, and we saw `[+]` for changes that are not saved. Then we exported with `:export name.wav tail=2` and read `:messages`.

[Lesson 13](13-saving.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 14: Find a command or a key

In this lesson, we find keys and commands from a part of their name, and then we use them.

You do not need to remember all the keys, because paw shows what you can do at each point. When you stop in the middle of a key sequence, paw shows the keys that can come next, and `?` shows all the keys of the current view. `:` runs a command by its name, and Tab completes the name. Pickers find a command, a key, a track or a clip from some letters of its name.

Each key runs a command with a name, so you can type the name of each action that a key does. You can also map each command that you find to a key.

<span data-paw-open='{"lesson":14,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 14 in paw'></span>

1. Press `g` and wait. After half a second, a box shows all the keys that can come after `g`, and then you can press `<Esc>` to close the box.
   - *Hint:* Do not press a key until the box shows.
   - ✓ Each key sequence that is not complete shows what can come next. Later, try `<Space>`, `d` or `"`.
2. `:commands` shows each command and what it does. Type `:commands` and `<CR>`, look at the list, and then press `q` to close it. <span data-paw-keys='[":commands",400,"&lt;CR&gt;",400,"q"]' data-paw-state='{"lesson":14,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Each key that you used runs one of the commands in the list.
3. Tab completes the names of commands. Press `j` to go to Bass. Type `:track.vol` and press `<Tab>`, and the name becomes `track.volume`. Then press `<Space>`, type `-6` and press `<CR>`. <span data-paw-keys='["j",400,":track.vol",400,"&lt;Tab&gt;",400,"&lt;Space&gt;",400,"-6",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":14,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Bass is at -6 dB, and `+` and `-` run the same command, `track.volume`.
4. `<Space>f:` opens a picker of all the commands. When you type some letters, `<CR>` runs the first command in the list. Press `<Space>f:`, type `metro` and press `<CR>`. <span data-paw-keys='["&lt;leader&gt;f:",400,"metro",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":14,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The metronome is on. You ran `transport.metronome` without knowing its name or its key.
5. `<Space>fk` finds a key from its action. Press `<Space>fk` and type `loop` to see all the keys for the loop, and then press `<Esc>`. <span data-paw-keys='["&lt;leader&gt;fk",400,"loop",400,"&lt;Esc&gt;"]' data-paw-state='{"lesson":14,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The list showed `gL`, `gl` and `il`, and `<CR>` on a line types its key for you.
6. `<Space>ft` goes to a track by its name. Press `<Space>ft`, type `dr` and press `<CR>`. <span data-paw-keys='["&lt;leader&gt;ft",400,"dr",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":14,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The cursor is on Drums, and `<Space>fc` does the same for clips.
7. `K` gives data about the item under the cursor, which is the clip, the track and its devices, in a small float under the cursor. Press `K`, and then `<Esc>` to close the float. <span data-paw-keys='["K",400,"&lt;Esc&gt;"]' data-paw-state='{"lesson":14,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ With `K`, you can see the devices, sends and automation of a track with one key.
8. Listen with the click. Press `<Space><Space>`, and then `<Space><Space>` to stop and `gm` to disable the click.
   - ✓ The bass is quieter, and the click came from a command that you found by its name.

We used key hints, `?`, `:commands`, Tab on the command line, the `<Space>f` pickers and `K`.

[Lesson 14](14-finding.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 15: Make paw your own: options, keys, commands

In this lesson, we set an option, map a key and make a command with `:lua`, and then we put them in `init.lua`.

Each key that you used is a usual mapping, and each command is a usual Lua function, which paw makes with the same functions that you can use. Your own file, `~/.config/paw/init.lua`, runs when paw starts, so paw applies the options, mappings and commands in it each time.

`:lua` runs one line of Lua, and the values that you set with it stay until you quit. The grid is an exception, because the tutor sets it back to its old value when you leave the tutor.

<span data-paw-open='{"lesson":15,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 15 in paw'></span>

1. First, set an option. Type `:lua paw.opt.grid = 0.5` and `<CR>`, and then press `l`, and the cursor now moves half a beat. <span data-paw-keys='[":lua paw.opt.grid = 0.5",400,"&lt;CR&gt;",400,"l"]' data-paw-state='{"lesson":15,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* Type the text exactly, with the spaces. On the command line, `<Up>` shows the text that you typed before.
   - ✓ The grid is half a beat, and the status line shows `grid 0.5`. `]g` and `[g` also change the grid.
2. Now map a key of your own. Type `:lua paw.keymap.set("<leader>k", "transport.metronome", { desc = "Click" })` and `<CR>`, and then press `<Space>k`. <span data-paw-keys='[":lua paw.keymap.set(\"&lt;leader&gt;k\", \"transport.metronome\", { desc = \"Click\" })",400,"&lt;CR&gt;",400,"&lt;leader&gt;k"]' data-paw-state='{"lesson":15,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ `<Space>k` enables and disables the click, and `?` shows your mapping with its description.
3. Now make a command of your own. Type `:lua paw.command("hello", function() paw.notify("hello from my command") end)` and `<CR>`, and then type `:hello` and `<CR>`. <span data-paw-keys='[":lua paw.command(\"hello\", function() paw.notify(\"hello from my command\") end)",400,"&lt;CR&gt;",400,":hello",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":15,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Your command ran, and `:commands` and the `<Space>f:` picker now show it with the built-in commands.
4. To keep the option, the mapping and the command, open `~/.config/paw/init.lua` in your text editor. Add the same three lines without `:lua`, and save the file. Then type `:reload` in paw. <span data-paw-keys='["&lt;leader&gt;hn"]' data-paw-state='{"lesson":15,"keys":"&lt;Esc&gt;"}' data-paw-label='Next step'></span>
   - *Hint:* In init.lua, each line is usual Lua, for example `paw.opt.grid = 0.5`. If there is an error, `:extensions` and `:messages` show it.
   - *The tutor cannot check this step* (The tutor does not read or write your configuration). `<Space>hn` moves to the next step.
5. Listen with your click. Press `<Space><Space>`, and then `<Space><Space>` to stop and `<Space>k` to disable the click.
   - ✓ The key that you mapped works.

We set an option, made a mapping and a command with `:lua`, and found where to keep them.

[Lesson 15](15-your-own.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 16: The bundled extensions

In this lesson, we load seven of the extensions that come with paw, and we try one feature of each.

Much of what paw can do comes from extensions. An extension is a folder of Lua in `extensions/` next to the program, and it uses the same `paw` module as your `init.lua`. `:tutor.try` loads an extension for this session only. To load an extension each time, link its folder into `~/.config/paw/extensions`.

The README.md of each extension describes all that it does. Each extension has its keys under its own prefix, e.g., `]]` `[[` and `\S` for sections, `gz` for musicops and `\t` for pattern. Moreover, mixdiag uses `<Space>m`, undotree uses `<Space>p` `g-` `g+`, and utau uses `\V`.

<span data-paw-open='{"lesson":16,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 16 in paw'></span>

1. pattern writes drum parts as text. Type `:tutor.try pattern` and `<CR>`, and then type `:pattern.set bd*2 [~ sn]` and `<CR>`. A new clip on Drums plays the pattern. <span data-paw-keys='[":tutor.try pattern",400,"&lt;CR&gt;",400,":pattern.set bd*2 [~ sn]",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":16,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The clip plays kick, kick, rest and snare, and `\tt` edits the text of the clip under the cursor.
2. musicops adds musical operators under `gz`. Type `:tutor.try musicops` and `<CR>`, and press `j` to go to Keys. Then press `gzkic` to move each note of the clip one step up the scale. <span data-paw-keys='[":tutor.try musicops",400,"&lt;CR&gt;",400,"j",400,"gzkic"]' data-paw-state='{"lesson":16,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The tune is now D E F A F E D, because it moved in C major. `gzh` humanizes, `gzs` strums, and `.` repeats them.
3. sections gives names to the parts of a song. Type `:tutor.try sections` and `<CR>`, and then press `\Sa`, type `Verse` and press `<CR>` to mark a section at the cursor. <span data-paw-keys='[":tutor.try sections",400,"&lt;CR&gt;",400,"\\Sa",400,"Verse",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":16,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Verse shows on the ruler, and `is` is now a text object. `yis` yanks the section on all tracks, and `]]` goes to the next section.
4. undotree shows each state of the project. Type `:tutor.try undotree` and `<CR>`, and press `<Space>pu` to open the undo tree. Look at the tree, and then press `q` to close it. <span data-paw-keys='[":tutor.try undotree",400,"&lt;CR&gt;",400,"&lt;leader&gt;pu",400,"q"]' data-paw-state='{"lesson":16,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ paw keeps each change that you undo, and `g-` and `g+` move through the states in order of time, across branches.
5. mixdiag measures the mix and shows problems. Type `:tutor.try mixdiag` and `<CR>`, and then press `<Space>ma` to measure the song. <span data-paw-keys='[":tutor.try mixdiag",400,"&lt;CR&gt;",400,"&lt;leader&gt;ma"]' data-paw-state='{"lesson":16,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ mixdiag measures in the background, and the message line shows the loudness when the measurement is complete. `<Space>mx` shows the problems that it found.
6. interop opens and writes REAPER projects and DAWproject files. Type `:tutor.try interop` and `<CR>`, and then type `:export tutor-song.rpp` and `<CR>`. A list of the items that REAPER cannot use opens, and `q` closes it. <span data-paw-keys='[":tutor.try interop",400,"&lt;CR&gt;",400,":export tutor-song.rpp",400,"&lt;CR&gt;",400,"q"]' data-paw-state='{"lesson":16,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ tutor-song.rpp is in the folder where you started paw. As the list said, the file does not contain the built-in devices.
7. utau sings notes with lyrics through the engines of OpenUtau. Type `:tutor.try utau` and `<CR>`, and press `o` to add a track. Then type `:utau.voice` and `<CR>` to make it a vocal track. In the browser, paw has no native code for the engines of utau, so skip the step. <span data-paw-keys='["&lt;leader&gt;hn"]' data-paw-state='{"lesson":16,"keys":"&lt;Esc&gt;"}' data-paw-label='Next step'></span>
   - ✓ The track is a vocal track, and it sings when you install `paw-utau-engine` and a voicebank (see extensions/utau/README.md). After that, `\Vt` adds a vocal track and asks for its singer in one step.
8. Listen to the pattern and the tune. Press `gs` and `<Space><Space>`, and `<Space><Space>` to stop.
   - ✓ You hear the drum pattern and the tune that musicops changed.

We tried one feature of each of pattern, musicops, sections, undotree, mixdiag, interop and utau, and their READMEs describe the rest.

[Lesson 16](16-extensions.md) has the same steps with the idea of the lesson and notes for Vim users.

## Lesson 17: Ranges, :s and :g: edit by line

In this lesson, we change bars, tracks and notes of a song from the command line.

Operators and visual mode do their action at the cursor, but the command line can do an action at many places at the same time. A range before a command gives the places as bars and tracks. For example, `:2,3d` makes bars 2 and 3 empty, and `:t2 4d` makes only bar 4 of track 2 empty. `:%s/c4/d4/g` changes each C4 of the song to a D4.

In the practice project, each of the three tracks has four clips of one bar. While you type, look at the right end of the command line, which shows what the line will do. The views also highlight the items before paw changes them.

<span data-paw-open='{"lesson":17,"keys":"&lt;Esc&gt;"}' data-paw-label='Open lesson 17 in paw'></span>

1. Type `:2,3d` (bars 2 to 3, delete). Before you press Enter, look at the right end of the line, which shows `bars 2–3`, and at the ruler, which shades the bars. Then press `<CR>`. <span data-paw-keys='[":2,3d",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":17,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Bars 2 and 3 are empty on all tracks, and the register contains the deleted clips.
2. The whole command line is one change, so one `u` undoes it. Press `u`. <span data-paw-keys='["u"]' data-paw-state='{"lesson":17,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The bars are back after one undo step.
3. The tracks come first in a range, so `:t2 4d` makes only bar 4 of track 2, Bass, empty. Type it and press `<CR>`. <span data-paw-keys='[":t2 4d",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":17,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Only Bass lost its last bar.
4. Press `u` again. <span data-paw-keys='["u"]' data-paw-state='{"lesson":17,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The bar is back.
5. `t*` is all the tracks. To make them all 3 dB quieter, type `:t* volume -=3`, and then press `<CR>`. <span data-paw-keys='[":t* volume -=3",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":17,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ Each fader went down by 3 dB, and `:t* volume -6` would set them all to -6 dB.
6. Now we use `:s`. Type `:%s/c4/d4/g`, and the line counts the C4 notes of the song while the clips that contain them are highlighted. Press `<CR>`. <span data-paw-keys='[":%s/c4/d4/g",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":17,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - *Hint:* `<Esc>` leaves the line and changes nothing, so you can type `:` and the command again.
   - ✓ Each C4 is now a D4, because `%` was the whole song, and `g` was each match in each bar.
7. `:g` runs a command on each match. To mute the Bass clips by their name, type `:g/name:b/mute`, and then press `<CR>`. <span data-paw-keys='[":g/name:b/mute",400,"&lt;CR&gt;"]' data-paw-state='{"lesson":17,"keys":"&lt;Esc&gt;"}' data-paw-label='Type it'></span>
   - ✓ The four Bass clips are muted. `:g/vel>100/` with no command puts the matches in the quickfix list, where `]q` goes to the next match.

We used `:2,3d`, `:t2 4d`, `:t* volume -=3`, `:%s/c4/d4/g` and `:g/name:b/mute`, which are each a range followed by a command, with one undo step for each.

[Lesson 17](17-ranges.md) has the same steps with the idea of the lesson and notes for Vim users.

</div>
</div>

<script type="module" src="../../../pod/paw-live.js"></script>
