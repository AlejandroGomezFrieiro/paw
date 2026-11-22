-- Lesson 3: tracks, instruments, clips, notes, hearing them.
return {
  id = "making",
  title = "Tracks, clips and notes",
  intro = [[
In this lesson, we add a track with a name and a synth, and we draw some
notes with the keyboard. Then we listen to the notes with a drum beat.

A track has clips on the timeline and a chain of devices. The first device is
an instrument, which makes sound from notes, and effects come after it. A
MIDI clip contains notes, and an audio clip contains a recording. A new
track makes no sound until it has an instrument.]],
  idea = [[
In normal mode, lowercase letters do an action on the item under the cursor.
For example, `o` opens a new track below, and `a` adds a device. Moreover,
`i` inserts clips and notes, and `x` deletes the clip while `&` repeats it.
`u` undoes and `<C-r>` redoes, so you can take back each change that you
make here.]],
  vim = [[
`o` and `O` add a track below and above, as they add lines in Vim. `i`
starts insert mode, where each key inserts an item, e.g., `m` a MIDI clip,
`r` a region and `'` a marker. `<CR>` opens the clip in the piano roll in
insert mode, where the cursor draws notes instead of text. `grn`
renames.]],
  setup = function(look)
    paw.project.tempo = 100
    local drums = paw.add_track({ name = "Drums" })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 16, notes = look.drums(look.beat, 4) })
    paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 16, true
  end,
  steps = {
    {
      say = "`o` adds a track below the track of the cursor. Press `o`.",
      keys = { "o" },
      start = function(ctx) ctx.tracks = #paw.tracks() end,
      check = function(ctx) return #paw.tracks() == ctx.tracks + 1 end,
      done = "A new empty track shows, and the cursor is on it.",
    },
    {
      say = "Give the track a name. Press `grn`, and press `<C-u>` to clear the old name. Type `Bass` and press `<CR>`.",
      keys = { "grn", "<C-u>", "Bass", "<CR>" },
      check = function(_, look) return look.cursor_track() == "Bass" end,
      done = "The name of the track is Bass.",
      hint = "`grn` shows the old name on the command line. `<C-u>` is Ctrl and u. `<Esc>` cancels.",
    },
    {
      say = "A track makes no sound until it has an instrument. Press `a`, type `synth` and press `<CR>`.",
      keys = { "a", "synth", "<CR>" },
      check = function(_, look) return look.device("Bass", "synth") ~= nil end,
      done = "Bass has a synth.",
      hint = "`a` opens a list of all the devices, and the text that you type makes the list shorter. `<CR>` selects the first item.",
    },
    {
      say = "`i` starts insert mode. In insert mode, `m` inserts a MIDI clip at the cursor, and `<CR>` opens the clip in the piano roll, where you draw notes. Press `i`, `m` and `<CR>`.",
      keys = { "i", "m", "<CR>" },
      check = function(_, look) return look.mode() == "i" and look.focused() == "pianoroll" end,
      done = "The mode is INSERT, and the piano roll is open on C4. The title row of the piano roll shows the note that you draw.",
    },
    {
      say = "`l` makes the note one step longer, so `4l` makes one beat. `<CR>` keeps the note and starts the next note at its end. `2+` moves the note up two semitones. Press `4l`, `<CR>`, `2+`, `4l`, `<CR>`, `2+`, `4l` and `<Esc>`.",
      keys = { "4l", "<CR>", "2+", "4l", "<CR>", "2+", "4l", "<Esc>" },
      check = function(_, look)
        local clip = look.clip("Bass")
        return clip and look.melody(clip) == "60@0+1 62@1+1 64@2+1" and look.mode() == "n"
      end,
      done = "The clip has three notes, C, D and E, and paw wrote them when you left insert mode.",
      hint = "The notes that you draw are green, and `<Esc>` writes them. `h` makes a note shorter, and `j` moves it down.",
    },
    {
      say = "Press `<C-w>p` to return to the arrange view, which is the previous window. `<Esc>` does not leave the piano roll, and the same is true in every view.",
      keys = { "<C-w>p" },
      check = function(ctx, look) return look.became(ctx, "back", look.mode() == "n" and look.focused() == "arrange") end,
      done = "The arrange view gets the keys again, in NORMAL mode.",
    },
    {
      say = "Press `<leader><Space>` to hear your notes with the drums. Press `<leader><Space>` again to stop.",
      keys = { "<leader><Space>", { wait = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.played(ctx) end,
      done = "You heard the bass line that you wrote.",
    },
    {
      say = "`&` puts a copy of the clip immediately after it. Press `&` two times.",
      keys = { "&", "&" },
      check = function(_, look) return #look.clips("Bass") == 3 end,
      done = "The track has three copies of the clip, one after the other.",
      hint = "The cursor must be on the clip. `0` moves it to the start.",
    },
    {
      say = "`u` undoes the last change and `<C-r>` (Ctrl and r) redoes it. Press `u`, then `<C-r>`.",
      keys = { "u", "<C-r>" },
      check = function(ctx, look) return look.ran(ctx, "undo") and look.ran(ctx, "redo") and #look.clips("Bass") == 3 end,
      done = "paw undid the change and did it again. Each key that changes the project is one undo step.",
    },
    {
      say = "`x` deletes the clip under the cursor. Press `x`.",
      keys = { "x" },
      check = function(_, look) return #look.clips("Bass") == 2 end,
      done = "paw deleted the clip, and `u` can bring it back.",
    },
    {
      say = "Listen to the result. Press `gs` to move to the start, `<leader><Space>` to play and `<leader><Space>` to stop.",
      keys = { "gs", "<leader><Space>", { wait = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.ran(ctx, "transport.start") and look.played(ctx) end,
      done = "You have a bass line on a track that you made.",
    },
  },
  outro = "We made a track and gave it a name and an instrument. We added notes, repeated and deleted clips, and undid a change.",
}
