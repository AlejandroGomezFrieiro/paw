-- Lesson 4: the piano roll and insert mode.
local stepped = false

return {
  id = "pianoroll",
  title = "The piano roll and insert mode",
  intro = [[
In this lesson, we add a line of notes and a chord to a short tune in the
piano roll.

The piano roll shows the notes of one clip, with one row for each pitch and
the names of the pitches on the left. Time goes to the right in steps of a
sixteenth note. In normal mode, you move the cursor and change one note at
a time. In insert mode, you draw notes with the cursor, and paw writes them
when you leave insert mode.

The clip `tune` has three notes in its second bar.]],
  idea = [[
To move the cursor, use `h` and `l` for one step and `j` and `k` for one
semitone. `<C-d>` and `<C-u>` move one octave, and `w` and `b` move by
notes. `0` and `$` go to the start and the end of the clip.

In normal mode, `<CR>` adds or removes a note, and `gh` plays the pitch.
`+` and `-` (or `<C-a>` and `<C-x>`) change the pitch of the note under the
cursor. `<A-h>` and `<A-l>` change its length, and `H` and `L` move it.
Moreover, `[` and `]` change its velocity.

Insert mode (`i`, or `a` after the note) draws a note from the cursor, or
takes the note under the cursor. `l` and `h` move the edge of the note
where the cursor is, so at the end of the note, `l` makes the note longer.
`+` and `-` change the pitch, and `K` and `J` change the octave. `k` and
`j` bend the note.

In insert mode, `<CR>` keeps the note and draws the next note at its end,
and `<Space>` adds a rest first. `c` makes the note a chord. `<BS>` removes
the last note, and `<Esc>` writes the notes and leaves insert mode.

In normal mode, `<Esc>` stays in the piano roll, and `<C-w>p` returns to
the arrange view.]],
  vim = [[
In Vim, `<C-a>` and `<C-x>` add to a number and subtract from it. In paw,
they change the pitch of a note in the same way as `+` and `-`, because
the pitch is the main value of a note. Insert mode draws notes instead of
text, and one insert is one undo step. `.` repeats the insert at the
cursor, as Vim repeats an insert.]],
  setup = function(look)
    stepped = false
    paw.project.tempo = 90
    local drums = paw.add_part({ name = "Drums", volume = -4 })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 12, notes = look.drums(look.beat, 3) })
    local piano = paw.add_part({ name = "Piano" })
    piano:add_device("synth", { wave = 1, cutoff = 2200, release = 0.3 })
    piano:add_clip({ name = "tune", start = 0, length = 8, notes = look.notes("E4:4:1 D4:5:1 C4:6:2") })
  end,
  at = function() paw.cursor.set_part(paw.part("Piano")) end,
  steps = {
    {
      say = "The cursor is on the clip `tune`. Press `<CR>` (Enter) to open it in the piano roll.",
      keys = { "<CR>" },
      check = function(_, look) return look.focused() == "pianoroll" end,
      done = "The piano roll opens, and the cursor is on E4 at the start of the clip.",
    },
    {
      say = "`j` and `k` move one semitone down and up, and you hear each pitch. `<C-d>` and `<C-u>` move one octave. Press `k` three times to go to G4.",
      keys = { "k", "k", "k" },
      -- The view keeps its pitch while it is closed: an earlier session
      -- can have left it on G4.
      check = function(_, look) return look.focused() == "pianoroll" and paw.ui.views:get("pianoroll").pitch == 67 end,
      done = "The cursor is on G4. The title row shows the name of the pitch, and the name on the left is highlighted.",
      hint = "Look at the title row of the piano roll, which shows the pitch under the cursor.",
    },
    {
      say = "`<CR>` adds a note at the cursor, or removes the note that is there. Press `<CR>`.",
      keys = { "<CR>" },
      check = function(_, look) return look.melody(look.clip("Piano")):find("67@0+0.25", 1, true) ~= nil end,
      done = "A short G4 shows, with a length of one step, which is a sixteenth note.",
    },
    {
      say = "`<A-l>` makes the note under the cursor one step longer, and `<A-h>` makes it shorter. In the arrange view, the same keys change the length of a clip. Press `<A-l>` three times.",
      keys = { "<A-l>", "<A-l>", "<A-l>" },
      check = function(_, look) return look.melody(look.clip("Piano")):find("67@0+1", 1, true) ~= nil end,
      done = "The note is now one beat long.",
    },
    {
      say = "`<C-a>` (or `+`) moves the note up one semitone and `<C-x>` (or `-`) moves it down. Press `<C-a>` two times.",
      keys = { "<C-a>", "<C-a>" },
      check = function(_, look) return look.melody(look.clip("Piano")):find("^69@0%+1") ~= nil end,
      done = "The note is A4 now, and the cursor moved with it.",
      hint = "`<C-a>` is Ctrl and a. The cursor must be on the note.",
    },
    {
      say = "Press `4l` to move one beat. Then press `i` to draw a note there.",
      keys = { "4l", "i" },
      check = function() return paw.keymap.mode == "i" and paw.ui.views:get("pianoroll").beat == 1 end,
      done = "The mode is INSERT at beat 2, and a note starts there with no length yet. The title row shows the pitch and the length of the note.",
    },
    {
      say = "In insert mode, `l` makes the note one step longer, and `h` makes it shorter. `+` and `-` change its pitch. Press `2-` (down to G) and `4l` (one beat long).",
      keys = { "2-", "4l" },
      check = function() return select(2, paw.roll_draw.text()) == "67@1+1" end,
      done = "A green G that is one beat long shows, and the cursor is at its end. paw has not written the note yet.",
      hint = "Counts work as in normal mode, so `4l` is `l` four times. `h` moves one step back.",
    },
    {
      say = "`<CR>` keeps the note and starts the next note at its end. Press `<CR>`, `2-` (F), `4l`, `<CR>`, `-` (E) and `4l`.",
      keys = { "<CR>", "2-", "4l", "<CR>", "-", "4l" },
      check = function() return paw.roll_draw.text() == "67@1+1 65@2+1" and select(2, paw.roll_draw.text()) == "64@3+1" end,
      done = "paw keeps G and F, and you now draw an E.",
      hint = "Each new note starts with no length, and `4l` makes it one beat long. `<BS>` removes the last note that you kept.",
    },
    {
      say = "`<Esc>` writes the notes that you drew and leaves insert mode. Press `<Esc>`.",
      keys = { "<Esc>" },
      check = function(_, look)
        return paw.keymap.mode == "n"
          and look.melody(look.clip("Piano")):find("69@0+1 67@1+1 65@2+1 64@3+1 64@4+1", 1, true) ~= nil
      end,
      done = "paw adds the notes A, G, F and E to the notes E, D and C that were there before, and the whole insert is one undo step.",
    },
    {
      say = "Now we add a chord at the end of the clip. Press `$` (the end), `i`, `4-` (down to C) and `4l`.",
      keys = { "$", "i", "4-", "4l" },
      check = function() return select(2, paw.roll_draw.text()) == "60@8+1" end,
      done = "A C that is one beat long shows after the end of the clip, and the clip becomes longer to hold the note.",
    },
    {
      say = "`c` makes the note a chord, and it shows a list of chords with the chord of the key on C first. Press `c`, then `<CR>` to take the first chord.",
      keys = { "c", "<CR>" },
      check = function() return select(2, paw.roll_draw.text()) == "60@8+1 64@8+1 67@8+1" end,
      done = "C, E and G show in green, and the keys of insert mode now change the whole chord as one note. To get another chord, type a symbol, e.g., `V7` or `Am`.",
    },
    {
      say = "`<CR>` keeps the chord and continues after it. `K` and `J` move one octave. Press `<CR>`, `J` (the C below), `4l` and `<Esc>`.",
      keys = { "<CR>", "J", "4l", "<Esc>" },
      check = function(_, look)
        local m = look.melody(look.clip("Piano"))
        return paw.keymap.mode == "n"
          and m:find("60@8+1 64@8+1 67@8+1", 1, true) ~= nil
          and m:find("48@9+1", 1, true) ~= nil
      end,
      done = "The clip has a C major chord, followed by a C3 below it.",
      hint = "`<Space>` adds a rest of one step before the next note.",
    },
    {
      say = "With a MIDI keyboard, `I` starts step input, which enters the notes that you play at the cursor, one note or chord at a time. Press `I` in the piano roll. If you have a keyboard, play a key.",
      keys = { "I" },
      check = function()
        if paw.roll_draw.stepping() then stepped = true end
        return stepped
      end,
      done = "The title row shows `STEP`, and a caret shows where the next note goes. With no keyboard, a list of inputs opens, and step input stays on. `<Space>` rests one step, and `=` and a value sets the step.",
    },
    {
      say = "`<Esc>` writes the notes that you played and leaves insert mode. Press `<Esc>`, and press it again if a list of inputs is open.",
      keys = { "<Esc>", "<Esc>" },
      check = function() return stepped and paw.keymap.mode == "n" and not paw.roll_draw.stepping() end,
      done = "Step input is off, and one undo step takes back all the notes that you played.",
    },
    {
      say = "In normal mode, `<Esc>` stays in the piano roll, and the same is true in every view. `<C-w>p` returns to the previous window. Press `<C-w>p`, then `gs` and `<leader><Space>` to listen, and `<leader><Space>` again to stop.",
      keys = { "<C-w>p", "gs", "<leader><Space>", { advance = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.focused() == "arrange" and look.played(ctx) end,
      done = "Your tune plays over the drums.",
    },
  },
  outro = "We moved by pitch and by time, and changed a note in normal mode. Then we drew a line and a chord in insert mode, and met step input from a MIDI keyboard.",
}
