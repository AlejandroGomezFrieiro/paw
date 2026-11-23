-- Lesson 11: looping, the metronome, marks, jumps and search.
return {
  id = "loops",
  title = "Loops, marks and jumps",
  intro = [[
In this lesson, we loop the chorus of a song with a click, and then we jump
between marks and loop two bars of the verse.

The loop plays one part of the song again and again while you work on it.
You can enable and disable the loop, and set it with the `gl` operator, and
the ruler shows the loop.

In a long song, you need keys that move quickly. `/` finds clips and tracks
by name, and `m` sets a mark that `'` returns to. Other keys return to the
position before a jump.

The song in the practice project has an intro, a verse and a chorus.]],
  idea = [[
`gL` enables and disables the loop, and `gl` with a motion or an object sets
the loop, e.g., `glic` or `gl2W`. `il` is the loop as a text object, e.g.,
`yil` or `dil`. `gm` is the metronome. `gs` moves the playhead to the
start, and `gp` moves it to the cursor.

`ma` sets a mark and `'a` returns to it, and `''` returns to the position
before the last jump. `<C-o>` and `<C-i>` move back and forward through
jumps. `/name` finds a clip or a track, and `n` and `N` go to the next and
the previous match. `*` goes to the next clip with the same name.]],
  vim = [[
Marks, `''`, `<C-o>` `<C-i>`, `/` `n` `N` and `*` come from Vim. Each view
has its own marks, so the marks of the arrange view are not the marks of the
piano roll. When a track moves, its marks move with it, and `:marks` shows
the marks.]],
  setup = function(look)
    paw.project.tempo = 110
    local drums = paw.add_track({ name = "Drums", volume = -4 })
    drums:add_device("drums")
    drums:add_clip({ name = "intro", start = 0, length = 8, notes = look.drums({ [42] = "x.o.x.o.x.o.x.o." }, 2) })
    drums:add_clip({ name = "verse", start = 8, length = 16, notes = look.drums(look.beat, 4) })
    drums:add_clip({
      name = "chorus",
      start = 24,
      length = 16,
      notes = look.drums({ [36] = "x...x...x...x...", [38] = "....x.......x...", [46] = "..x...x...x...x." }, 4),
    })
    local bass = paw.add_track({ name = "Bass", volume = -4 })
    bass:add_device("synth", { wave = 2, cutoff = 700, release = 0.05 })
    bass:add_clip({ name = "verse", start = 8, length = 16, notes = look.pulse("E2", 16) })
    bass:add_clip({ name = "chorus", start = 24, length = 16, notes = look.pulse("A1", 16) })
    local lead = paw.add_track({ name = "Lead", volume = -8 })
    lead:add_device("synth", { wave = 1, cutoff = 2600, release = 0.2 })
    lead:add_clip({
      name = "hook",
      start = 24,
      length = 8,
      notes = look.notes("E5:0:1 E5:1:0.5 D5:1.5:0.5 C5:2:1 A4:3:1 C5:4:2 B4:6:2"),
    })
    paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 8, false
  end,
  at = function() paw.cursor.set_track(paw.track("Drums")) end,
  steps = {
    {
      say = "`gL` enables and disables the loop. When the loop is on, the status line shows `loop`, and the ruler shows the loop. Press `gL`.",
      keys = { "gL" },
      check = function() return paw.transport.loop_enabled end,
      done = "The loop is on, over the first two bars.",
    },
    {
      say = "`/` finds a clip or a track by its name. Type `/chorus` and press `<CR>`.",
      keys = { "/chorus", "<CR>" },
      check = function() return paw.cursor.beat == 24 end,
      done = "The cursor is on the chorus, and `n` goes to the next match, which is the chorus of Bass.",
    },
    {
      say = "`gl` is the loop operator. Press `glic` to loop the clip under the cursor.",
      keys = { "glic" },
      check = function()
        return paw.transport.loop_start == 24 and paw.transport.loop_end == 40 and paw.transport.loop_enabled
      end,
      done = "The loop is now over the chorus.",
    },
    {
      say = "`gm` enables the metronome (the click). Press `gm`, and then press `gp` to move the playhead to the cursor and `<leader><Space>` to play. Press `<leader><Space>` again to stop.",
      keys = { "gm", "gp", "<leader><Space>", { advance = 300 }, "<leader><Space>" },
      check = function(ctx, look) return paw.transport.metronome and look.played(ctx) end,
      done = "The chorus played with a click.",
    },
    {
      say = "Press `gm` to disable the click.",
      keys = { "gm" },
      check = function(ctx, look) return look.became(ctx, "quiet", not paw.transport.metronome) end,
      done = "The click is off.",
    },
    {
      say = "`ma` sets mark a at the cursor. Press `ma`.",
      keys = { "ma" },
      start = function(ctx) ctx.before = paw.keymap.marks("arrange").a end,
      check = function(ctx)
        local m = paw.keymap.marks("arrange").a
        return m and m ~= ctx.before and m.beat == 24
      end,
      done = "Mark a is on the chorus, and `:marks` shows the marks.",
    },
    {
      say = "Move to a different position. Press `G` (the last track) and `0` (the start), and then press `'a` to jump to the mark.",
      keys = { "G", "0", "'a" },
      check = function(ctx, look)
        local there = look.cursor_track() == "Drums" and paw.cursor.beat == 24
        if not there then ctx.away = true end
        return there and ctx.away
      end,
      done = "The cursor is on the chorus of Drums again.",
      hint = "`'` is the apostrophe key.",
    },
    {
      say = "`''` returns to the position before the jump. Press `''`.",
      keys = { "''" },
      check = function(_, look) return look.cursor_track() == "Lead" and paw.cursor.beat == 0 end,
      done = "The cursor is at the start of Lead, where it was before `'a`. `''` again returns to the chorus, and `<C-o>` goes further back.",
    },
    {
      say = "`gl` also accepts motions. Press `3|` to go to bar 3, and then press `gl2W` to loop two bars from there.",
      keys = { "3|", "gl2W" },
      check = function() return paw.transport.loop_start == 8 and paw.transport.loop_end == 16 end,
      done = "The loop is now over the first two bars of the verse.",
    },
    {
      say = "Press `gp` and `<leader><Space>` to listen, and `<leader><Space>` again to stop.",
      keys = { "gp", "<leader><Space>", { advance = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.ran(ctx, "transport.to_cursor") and look.played(ctx) end,
      done = "Two bars of the verse play again and again.",
    },
  },
  outro = "We set the loop with `gL`, `glic` and `gl2W`, and the click with `gm`. We used `/` to find clips, and `ma`, `'a` and `''` to jump.",
}
