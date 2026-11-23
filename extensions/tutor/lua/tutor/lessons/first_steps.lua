-- Lesson 1: the screen, playing, the command line, quitting.
return {
  id = "first-steps",
  title = "First steps: the screen, play and quit",
  intro = [[
In this lesson, we play a short song, change its tempo and quit paw.

You use paw from the keyboard, and each part of the screen is a view. The
arrange view in the middle has one row for each track, and time goes to the
right. The status line at the bottom shows the current mode, which is
`NORMAL` now. Below the status line, you type commands and paw shows
messages.

The panel at the bottom is the tutor, which tells you what to do and checks
each step when you do it.

The keys have the names that Vim gives them. For example, `j` is the j key,
`J` is Shift and j, and `<C-r>` is Ctrl and r. Moreover, `<CR>` is Enter,
`<Esc>` is Escape, `<Space>` is the space bar and `<BS>` is Backspace, and
`gs` means g and then s.]],
  idea = [[
You do not need the mouse in paw. Some keys do an action immediately, e.g.,
`x` deletes. Other keys start an action that more keys complete. For
example, `:` starts a command line, and `g` starts commands of two keys,
such as `gs`. Moreover, `<leader>` starts the keys that work in every view,
such as `<leader><Space>`, which plays.

If you do not know which mode you are in, press `<Esc>` to return to normal
mode. To see the keys of the current view, press `?`.]],
  vim = [[
`:q`, `ZZ` and `ZQ` do the same as in Vim, and `:w` saves. The command line
accepts commands by name, e.g., `:tempo 120`. It also accepts Ex commands
over bars and tracks, e.g., `:5,8d` and `:%s/c4/d4/g`, and lesson 17 shows
how to use them.]],
  setup = function(look)
    paw.project.tempo = 100
    local drums = paw.add_track({ name = "Drums" })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 8, notes = look.drums(look.beat, 2) })
    local bass = paw.add_track({ name = "Bass", volume = -4 })
    bass:add_device("synth", { wave = 2, cutoff = 600, release = 0.05 })
    local line = look.pulse("A1", 4)
    for _, n in ipairs(look.pulse("F1", 4, 4)) do
      line[#line + 1] = n
    end
    bass:add_clip({ name = "bass", start = 0, length = 8, notes = line })
    local keys = paw.add_track({ name = "Keys", volume = -10 })
    keys:add_device("synth", { wave = 3, attack = 0.05, release = 0.4, cutoff = 2000 })
    local chords = look.chord({ "A3", "C4", "E4" }, 4)
    for _, n in ipairs(look.chord({ "F3", "A3", "C4" }, 4, 4)) do
      chords[#chords + 1] = n
    end
    keys:add_clip({ name = "chords", start = 0, length = 8, notes = chords })
    paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 8, true
  end,
  steps = {
    {
      say = "The song has three tracks, which are Drums, Bass and Keys. Press `<leader><Space>` to play it.",
      keys = { "<leader><Space>" },
      check = function() return paw.transport.playing end,
      done = "The song plays again and again, because the loop is on. The status line shows `loop`.",
      hint = "`<Space>` is the space bar. Look at the ▶ in the status line and at the playhead, which moves across the clips.",
    },
    {
      say = "Press `<leader><Space>` again to stop.",
      keys = { "<leader><Space>" },
      check = function(ctx, look) return look.became(ctx, "stopped", not paw.transport.playing) end,
      done = "The song stops. The playhead stays where it stopped.",
    },
    {
      say = "`gs` moves the playhead to the start. Press `g`, then `s`.",
      keys = { "gs" },
      check = function(ctx, look) return look.ran(ctx, "transport.start") and paw.transport.position == 0 end,
      done = "The playhead is at the start. The clock in the status line shows 1.1.00 (bar 1, beat 1).",
      hint = "Press the two keys one after the other, not together.",
    },
    {
      say = "The highlighted track header is the cursor. `j` moves it down one track and `k` moves it up. Press `j` two times to go to Keys.",
      keys = { "j", "j" },
      check = function(_, look) return look.cursor_track() == "Keys" end,
      done = "The cursor is on Keys.",
      hint = "If the cursor is below Keys, press `k` to move it up.",
    },
    {
      say = "`?` shows each key of the current view. Press `?`, and type `mute` to make the list shorter. Then press `<Esc>` to close the list.",
      keys = { "?", "mute", "<Esc>" },
      check = function(ctx, look) return look.ran(ctx, "pick.keys") and not look.float() end,
      done = "When you forget a key, you can find it in the list. `<CR>` (Enter) on a line does the action of its key.",
      hint = "The text that you type makes the list shorter. `<Esc>` closes the list.",
    },
    {
      say = "`:` opens the command line at the bottom. Type `:tempo 130` and press `<CR>` (Enter). The song becomes faster.",
      keys = { ":tempo 130", "<CR>" },
      check = function() return paw.project.tempo == 130 end,
      done = "The tempo is 130 beats per minute. The status line shows it.",
      hint = "Type the colon too. `<Esc>` cancels a command line. `<BS>` on an empty command line closes it.",
    },
    {
      say = "Press `<leader><Space>` to hear the faster song. Then press `<leader><Space>` to stop it.",
      keys = { "<leader><Space>", { advance = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.played(ctx) end,
      done = "The song plays faster now.",
    },
    {
      say = "To quit paw, type `:q` and `<CR>`. `ZQ` also quits, and `ZZ` saves before it quits. Quit now. The tutor keeps your place, so `:tutor` starts lesson 2 the next time.",
      keys = { { sim = "quit", instead = { ":q", "<CR>" } } },
      on_quit = true,
      done = "paw quits.",
      hint = "If you do not want to quit now, press `<leader>hn` to start lesson 2.",
    },
  },
  outro = "We played a song, moved the cursor, used the command line and found the list of all the keys.",
}
