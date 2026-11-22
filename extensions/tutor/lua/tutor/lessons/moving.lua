-- Lesson 2: motions, counts, and why keys change meaning.
return {
  id = "moving",
  title = "Move the cursor, and keys that change meaning",
  intro = [[
In this lesson, we move the cursor through a song by steps, clips, bars and
tracks. Then we use the same keys in a different mode and in a different view.

In the arrange view, each track is a row, and time goes from left to right
along it. One grid step is one beat. The keys that move the cursor are
called motions, and a number before a motion repeats it. Some motions move
by small steps or by bars, others move to clips or to the ends of clips, and
others move to other tracks.

A key can have a different meaning in a different mode, e.g., normal, visual
or insert mode. It can also have a different meaning in a different view,
e.g., the arrange view, the piano roll or the mixer. The status line always
shows the current mode, and the view that gets the keys has a brighter
frame or highlight.]],
  idea = [[
`h` and `l` move one grid step. `w`, `b` and `e` move by clips, to the
start of the next clip, the start of the current clip and the end of the
current clip. `W` and `B` move by bars.

`0` goes to the start of the project, and `^` goes to the first clip. `$`
goes to the end of the last clip. `j` and `k` move by tracks, and `gg` and
`G` go to the first and the last track. `5|` goes to bar 5. You type a
count before the motion, e.g., `4l`, `2W` or `3j`.

NORMAL mode is for moving and for actions, VISUAL mode (`v`) is for
selecting, and INSERT mode (`i`) is for adding notes. PENDING shows while an
operator waits for its motion, and `<Esc>` returns to NORMAL.]],
  vim = [[
`hjkl`, `w` `b` `e`, `W` `B`, `0` `^` `$`, `gg` `G`, counts and `|` are all
in paw, with a few differences from Vim. `w` goes to the starts of clips,
and there is no WORD, so `W` and `B` move by bars instead. `0` is the start
of the project and `^` is the first clip. `|` and `:5` take a bar number,
not a column or a line.]],
  setup = function(look)
    paw.project.tempo = 96
    local drums = paw.add_track({ name = "Drums" })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 28, notes = look.drums(look.beat, 7) })
    local bass = paw.add_track({ name = "Bass", volume = -4 })
    bass:add_device("synth", { wave = 2, cutoff = 700, release = 0.05 })
    bass:add_clip({ name = "verse", start = 0, length = 8, notes = look.pulse("D2", 8) })
    bass:add_clip({ name = "chorus", start = 12, length = 8, notes = look.pulse("G1", 8) })
    bass:add_clip({ name = "outro", start = 24, length = 4, notes = look.pulse("D2", 4) })
    local lead = paw.add_track({ name = "Lead", volume = -8 })
    lead:add_device("synth", { wave = 1, cutoff = 2500, release = 0.2 })
    lead:add_clip({
      name = "melody",
      start = 16,
      length = 8,
      notes = look.notes("D5:0:1 F5:1:1 A5:2:2 G5:4:1 F5:5:1 E5:6:2"),
    })
    local pad = paw.add_track({ name = "Pad", volume = -12 })
    pad:add_device("synth", { wave = 3, attack = 0.3, release = 0.6, cutoff = 1500 })
    pad:add_clip({ name = "pad", start = 16, length = 12, notes = look.chord({ "D4", "F4", "A4" }, 12) })
  end,
  at = function() paw.cursor.set_track(paw.track("Bass")) end,
  steps = {
    {
      say = "The cursor is at the start of the Bass track. `l` moves it right one grid step (one beat), and `h` moves it left. Press `l` three times.",
      keys = { "l", "l", "l" },
      check = function() return paw.cursor.beat == 3 end,
      done = "The cursor moved three beats. The clock at the top left of the arrange view shows 1.4.00, bar 1 beat 4.",
    },
    {
      say = "A number before a motion repeats the motion. Press `4l` to move four beats.",
      keys = { "4l" },
      check = function() return paw.cursor.beat == 7 end,
      done = "The cursor is on beat 7, near the end of the clip `verse`.",
      hint = "Type the 4 and then the l. If the cursor is at a different beat, press `0` and then `3l`.",
    },
    {
      say = "`0` moves the cursor to the start of the project. Press `0`.",
      keys = { "0" },
      check = function(ctx, look) return look.ran(ctx, "cursor.start") and paw.cursor.beat == 0 end,
      done = "The cursor is at the start.",
    },
    {
      say = "`w` moves to the start of the next clip on the track. Press `w`.",
      keys = { "w" },
      check = function() return paw.cursor.beat == 12 end,
      done = "The cursor is on `chorus`, which starts at beat 12 (bar 4).",
    },
    {
      say = "`e` moves to the end of the clip, and `b` moves to its start. Press `e`, then `b`.",
      keys = { "e", "b" },
      check = function(ctx, look)
        return look.ran(ctx, "cursor.clip_end") and look.ran(ctx, "cursor.prev_clip") and paw.cursor.beat == 12
      end,
      done = "`w`, `b` and `e` move to the start of the next clip, the start of the current clip and the end of the current clip.",
    },
    {
      say = "`W` and `B` move by bars (four beats here). Press `2W` to move two bars.",
      keys = { "2W" },
      check = function() return paw.cursor.beat == 20 end,
      done = "The cursor is on bar 6 (beat 20).",
    },
    {
      say = "`$` moves to the end of the last clip of the track, and `^` moves to its first clip. Press `$`.",
      keys = { "$" },
      check = function() return paw.cursor.beat == 28 end,
      done = "The cursor is at the end of `outro`, where the song ends.",
    },
    {
      say = "`G` moves to the last track, and `gg` moves to the first track. Press `G`.",
      keys = { "G" },
      check = function(_, look) return look.cursor_track() == "Pad" end,
      done = "The cursor is on Pad, the last track. `3G` moves to track 3.",
    },
    {
      say = "`5|` moves to bar 5. `:5` and `<CR>` do the same. Press `5|`.",
      keys = { "5|" },
      check = function() return paw.cursor.beat == 16 end,
      done = "The cursor is on bar 5, where the pad starts.",
      hint = "`|` is the bar key. On many keyboards, it is Shift and backslash.",
    },
    {
      say = "Now we use the same keys in a different mode. Press `v`, and the status line shows VISUAL. In visual mode, each motion makes the selection larger. Press `l` two times.",
      keys = { "v", "l", "l" },
      check = function() return paw.keymap.mode == "x" and paw.cursor.beat == 18 end,
      done = "In visual mode, `l` moves the cursor and also selects. Lesson 7 shows what you can do with a selection.",
    },
    {
      say = "`<Esc>` always returns to NORMAL. Press `<Esc>`.",
      keys = { "<Esc>" },
      check = function(ctx, look) return look.became(ctx, "normal", paw.keymap.mode == "n") end,
      done = "The mode is NORMAL again.",
    },
    {
      say = "Now we use a different view. `<CR>` (Enter) on a clip opens it in the piano roll. Press `<CR>` on the pad clip.",
      keys = { "<CR>" },
      check = function(_, look) return look.focused() == "pianoroll" end,
      done = "The piano roll now gets the keys.",
      hint = "The cursor must be on a clip. Press `5|` on the Pad track to move it there.",
    },
    {
      say = "In the piano roll, the rows are pitches, so `k` moves up one semitone instead of one track. Press `k` two times, and you hear each pitch.",
      keys = { "k", "k" },
      start = function(ctx) ctx.pitch = paw.ui.views.pianoroll.pitch end,
      check = function(ctx, look)
        return look.focused() == "pianoroll" and paw.ui.views.pianoroll.pitch == ctx.pitch + 2
      end,
      done = "The key is the same as in the arrange view, and it still moves up, but in the piano roll it moves by pitch.",
    },
    {
      say = "`<Esc>` does not leave the current window in any view, and `<C-w>p` returns to the previous window. Press `<C-w>p`. Then press `gp` to move the playhead to the cursor. Press `<leader><Space>` to play and `<leader><Space>` to stop.",
      keys = { "<C-w>p", "gp", "<leader><Space>", { wait = 300 }, "<leader><Space>" },
      check = function(ctx, look)
        return look.focused() == "arrange" and look.ran(ctx, "transport.to_cursor") and look.played(ctx)
      end,
      done = "The song played from bar 5, where the melody starts.",
      hint = "`<leader><Space>` alone plays from the cursor. `gp` puts the playhead there first, and `<S-CR>` plays from the playhead.",
    },
  },
  outro = "We moved by steps, clips, bars and tracks, with counts. The same keys had other meanings in visual mode and in the piano roll.",
}
