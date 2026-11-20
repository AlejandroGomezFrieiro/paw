-- Lesson 4: the piano roll and insert mode.
return {
  id = "pianoroll",
  title = "The piano roll and insert mode",
  intro = [[
In this lesson, we add a line of notes and a chord to a short tune in the
piano roll.

The piano roll shows the notes of one clip. It has one row for each pitch,
with the names on the left. Time goes to the right in steps of a sixteenth
note. In normal mode, you move the cursor and change one note at a time. In
insert mode, you draw notes with the cursor, and paw writes them when you
leave insert mode.

The clip `tune` has three notes in its second bar.]],
  idea = [[
To move, use `h` `l` for one step and `j` `k` for one semitone. Use
`<C-d>` `<C-u>` for one octave and `w` `b` for notes. `0` `$` go to the start
and the end of the clip.

To change the note under the cursor: `<CR>` adds or removes a note. `+` `-`
(and `<C-a>` `<C-x>`) change its pitch. `<A-h>` `<A-l>` change its length,
`H` `L` move it, `[` `]` change the velocity and `gh` plays the pitch.

Insert mode (`i`, or `a` after the note) draws a note from the cursor. `l`
`h` make it longer and shorter, and `j` `k` `<C-d>` `<C-u>` change its pitch.
`<CR>` keeps the note and draws the next note at its end. `<Space>` adds a
rest first. `o` draws a note from the same start, for a chord. `<BS>` removes
the last note, and `<Esc>` writes the notes and leaves insert mode.

`I` makes the keyboard a piano: `a w s e d f t g y h u j k` are C up to the
next C. In normal mode, `<Esc>` stays in the piano roll. `<C-w>p` returns to
the arrange view.]],
  vim = [[
In Vim, `<C-a>` and `<C-x>` add to a number and subtract from it. Here they
change the pitch of a note, as `+` `-` do. The pitch is the main value of a
note. Insert mode does not insert text. It draws a note, and all
of it is one undo step. `.` repeats it at the cursor, as Vim repeats an insert.]],
  setup = function(look)
    paw.project.tempo = 90
    local drums = paw.add_track({ name = "Drums", volume = -4 })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 12, notes = look.drums(look.beat, 3) })
    local piano = paw.add_track({ name = "Piano" })
    piano:add_device("synth", { wave = 1, cutoff = 2200, release = 0.3 })
    piano:add_clip({ name = "tune", start = 0, length = 8, notes = look.notes("E4:4:1 D4:5:1 C4:6:2") })
  end,
  at = function() paw.cursor.set_track(paw.track("Piano")) end,
  steps = {
    {
      say = "The cursor is on the clip `tune`. Press `<CR>` (Enter) to open it in the piano roll.",
      keys = { "<CR>" },
      check = function(_, look) return look.focused() == "pianoroll" end,
      done = "The piano roll opens. The cursor is on E4 at the start of the clip.",
    },
    {
      say = "`j` and `k` move one semitone down and up, and you hear each pitch. `<C-d>` `<C-u>` move one octave, half a page as in Vim. Press `k` three times to go to G4.",
      keys = { "k", "k", "k" },
      check = function() return paw.ui.views.pianoroll.pitch == 67 end,
      done = "The cursor is on G4. The title row shows the name, and the name on the left is highlighted.",
      hint = "Look at the title row of the piano roll. It shows the pitch under the cursor.",
    },
    {
      say = "`<CR>` adds a note at the cursor, or removes the note that is there. Press `<CR>`.",
      keys = { "<CR>" },
      check = function(_, look) return look.melody(look.clip("Piano")):find("67@0+0.25", 1, true) ~= nil end,
      done = "A short G4 shows. Its length is one step, a sixteenth.",
    },
    {
      say = "`<A-l>` makes the note under the cursor one step longer and `<A-h>` makes it shorter. They do the same to a clip in the arrange view. Press `<A-l>` three times.",
      keys = { "<A-l>", "<A-l>", "<A-l>" },
      check = function(_, look) return look.melody(look.clip("Piano")):find("67@0+1", 1, true) ~= nil end,
      done = "The note is one beat long now.",
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
      check = function() return paw.keymap.mode == "i" and paw.ui.views.pianoroll.beat == 1 end,
      done = "The mode is INSERT at beat 2. A note starts here, with no length yet. The title row shows its pitch and length.",
    },
    {
      say = "In insert mode, `l` makes the note one step longer and `h` makes it shorter. `j` `k` change its pitch. Press `2j` (down to G) and `4l` (one beat long).",
      keys = { "2j", "4l" },
      check = function() return select(2, paw.roll_draw.text()) == "67@1+1" end,
      done = "A green G that is one beat long shows. paw did not write it yet. The cursor is at its end.",
      hint = "Counts work as in normal mode: `4l` is `l` four times. `h` moves one step back.",
    },
    {
      say = "`<CR>` keeps the note and starts the next note at its end. Press `<CR>`, `2j` (F), `4l`, `<CR>`, `j` (E) and `4l`.",
      keys = { "<CR>", "2j", "4l", "<CR>", "j", "4l" },
      check = function() return paw.roll_draw.text() == "67@1+1 65@2+1" and select(2, paw.roll_draw.text()) == "64@3+1" end,
      done = "G and F are kept, and you draw an E now.",
      hint = "Each new note starts with no length, and `4l` draws it. `<BS>` removes the last note that you kept.",
    },
    {
      say = "`<Esc>` writes the notes that you drew and leaves insert mode. Press `<Esc>`.",
      keys = { "<Esc>" },
      check = function(_, look)
        return paw.keymap.mode == "n" and look.melody(look.clip("Piano")):find("69@0+1 67@1+1 65@2+1 64@3+1 64@4+1", 1, true) ~= nil
      end,
      done = "The notes A G F E go into the notes E D C that were there before. All of this is one undo step.",
    },
    {
      say = "Now we add a chord at the end of the clip. Press `$` (the end), `i`, `4j` (down to C) and `4l`.",
      keys = { "$", "i", "4j", "4l" },
      check = function() return select(2, paw.roll_draw.text()) == "60@8+1" end,
      done = "A C that is one beat long shows after the end of the clip. The clip becomes longer to hold it.",
    },
    {
      say = "`o` keeps the note and starts a note with the same start and length, for a chord. Press `o` and `4k` (E). Then press `o` and `3k` (G).",
      keys = { "o", "4k", "o", "3k" },
      check = function() return paw.roll_draw.text() == "60@8+1 64@8+1" and select(2, paw.roll_draw.text()) == "67@8+1" end,
      done = "C and E are kept, and you draw a G now.",
    },
    {
      say = "`<CR>` continues after the chord. `<C-d>` and `<C-u>` move one octave. Press `<CR>`, `<C-d>` and `7j` (the C below), `4l` and `<Esc>`.",
      keys = { "<CR>", "<C-d>", "7j", "4l", "<Esc>" },
      check = function(_, look)
        local m = look.melody(look.clip("Piano"))
        return paw.keymap.mode == "n" and m:find("60@8+1 64@8+1 67@8+1", 1, true) ~= nil and m:find("48@9+1", 1, true) ~= nil
      end,
      done = "The clip has a C major chord, then a C3 below it.",
      hint = "`<Space>` adds a rest of one step before the next note.",
    },
    {
      say = "In normal mode, `<Esc>` stays in the piano roll, as in each view. `<C-w>p` returns to the previous window. Press `<C-w>p`, then `gs` and `<leader><Space>` to listen. `<leader><Space>` stops.",
      keys = { "<C-w>p", "gs", "<leader><Space>", { wait = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.focused() == "arrange" and look.played(ctx) end,
      done = "Your tune plays over the drums.",
    },
  },
  outro = "We moved by pitch and by time, and changed a note in normal mode. Then we drew a line and a chord in insert mode.",
}
