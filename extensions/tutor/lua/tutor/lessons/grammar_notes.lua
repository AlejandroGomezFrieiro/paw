-- Lesson 6: the same grammar on notes.
return {
  id = "grammar-notes",
  title = "The same grammar on notes",
  intro = [[
In this lesson, we change a short riff in the piano roll with the grammar of
lesson 5.

All the keys of the last lesson work in the piano roll. Notes take the place
of clips, and pitches take the place of tracks. `w` goes to the next note, so
`dw` deletes up to it. `in` is the note under the cursor. `ic` is the notes
that sound together at the cursor, and `ie` is all the notes of the clip. 

`dd` deletes a whole row, which is all the notes of one pitch. `.` repeats,
and `y` and `p` copy.

The clip `riff` is open in the piano roll. Its notes are C D E G E D C, each
one beat long.]],
  idea = [[
Learn the grammar one time and use it in each view. The operators are the
same (`d` `y` `c` `>` `<` `=` `gl`). The motions are the same keys (`w` `b`
`e` `0` `$` `W` `B`, and `j` `k` by pitch). The text objects are `in` (the
note), `ib` (the bar), `ie` (the whole clip) and `ic` (the chord). Longer
songs also have `ip` (the phrase) and `iv` (the voice). `)` and `]c` go to
the next phrase and the next chord. A note is part of the range where it
starts. So `dw` from the middle of a gap deletes nothing.]],
  vim = [[
`in` has the place of `iw`. `dd` selects a whole row, which is a pitch. `/d4`
finds a pitch by its name, and `n` goes to the next match.]],
  setup = function(look)
    paw.project.tempo = 100
    local drums = paw.add_track({ name = "Drums", volume = -4 })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 16, notes = look.drums(look.beat, 4) })
    local lead = paw.add_track({ name = "Lead" })
    lead:add_device("synth", { wave = 1, cutoff = 2400, release = 0.2 })
    lead:add_clip({ name = "riff", start = 0, length = 8, notes = look.notes("C4:0:1 D4:1:1 E4:2:1 G4:3:1 E4:4:1 D4:5:1 C4:6:1") })
  end,
  at = function(look)
    local lead = paw.track("Lead")
    paw.cursor.set_track(lead)
    paw.ui.views.pianoroll:edit(look.clip(lead, "riff"))
  end,
  steps = {
    {
      say = "The cursor is on the first note. `w` goes to the next note, at any pitch. Press `w` two times.",
      keys = { "w", "w" },
      check = function() local roll = paw.ui.views.pianoroll return roll.beat == 2 and roll.pitch == 64 end,
      done = "The cursor is on E4, the third note.",
    },
    {
      say = "`dw` deletes from the cursor up to the next note. Press `dw`.",
      keys = { "dw" },
      check = function(_, look) return not look.melody(look.clip("Lead")):find("64@2+", 1, true) end,
      done = "E4 is deleted. The cursor stays in the gap.",
    },
    {
      say = "Press `w` to go to G4. Press `.` to delete it in the same way.",
      keys = { "w", "." },
      check = function(_, look) return look.melody(look.clip("Lead")) == "60@0+1 62@1+1 64@4+1 62@5+1 60@6+1" end,
      done = "`.` repeated `dw` from the new position.",
      hint = "In a gap, `dw` goes up to the start of the next note. A note is part of the range where it starts, so `dw` deletes nothing. Go onto a note first.",
    },
    {
      say = "Press `u` two times to bring back the two notes.",
      keys = { "u", "u" },
      check = function(ctx, look) return look.ran(ctx, "undo") and look.melody(look.clip("Lead")) == "60@0+1 62@1+1 64@2+1 67@3+1 64@4+1 62@5+1 60@6+1" end,
      done = "The riff is complete again.",
    },
    {
      say = "`in` is the note under the cursor. `>in` moves it one step later, and the cursor moves with it. Press `>in`, then `.`.",
      keys = { ">in", "." },
      check = function(_, look) return look.melody(look.clip("Lead")):find("67@3.5+1", 1, true) ~= nil end,
      done = "G4 is two steps late now. It gives a small push before the beat.",
      hint = "The cursor must be on G4 (beat 4). If a move is wrong, press `u`.",
    },
    {
      say = "`yie` copies all the notes of the clip. `$` goes to the end of the clip, and `p` pastes the notes there. Press `yie`, `$` and `p`.",
      keys = { "yie", "$", "p" },
      check = function(_, look) return #look.clip("Lead"):notes() == 14 end,
      done = "The riff plays two times, and the clip became longer to hold it.",
    },
    {
      say = "`c` changes. `cin` deletes the note under the cursor and starts insert mode at its position. Press `^` (the first note) and `cin`. Then press `7k`, `4l` and `<Esc>`.",
      keys = { "^", "cin", "7k", "4l", "<Esc>" },
      check = function(_, look)
        local m = look.melody(look.clip("Lead"))
        return m:find("^67@0%+1") ~= nil and not m:find("^60@0") and paw.keymap.mode == "n"
      end,
      done = "The riff starts on G now.",
      hint = "`7k` moves the new note up to G, and `4l` makes it one beat long.",
    },
    {
      say = "`/` finds a pitch: `/d4` and `<CR>` go to the next D4. Then `dd` deletes all the notes of that pitch. Press `/d4`, `<CR>` and `dd`.",
      keys = { "/d4", "<CR>", "dd" },
      check = function(_, look) return not look.melody(look.clip("Lead")):find("62@", 1, true) end,
      done = "The clip has no D4 now.",
    },
    {
      say = "Press `<C-w>p` to return to the arrange view. Press `<leader><Space>` to listen, and `<leader><Space>` to stop.",
      keys = { "<C-w>p", "<leader><Space>", { wait = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.focused() == "arrange" and look.played(ctx) end,
      done = "Your changed riff plays.",
    },
  },
  outro = "We used the grammar of lesson 5 on notes: `dw`, `.`, `>in`, `yie` `p`, `cin`, `dd` and `/`.",
}
