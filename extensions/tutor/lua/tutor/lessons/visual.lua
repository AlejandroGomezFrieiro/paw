-- Lesson 7: visual mode, selecting first and acting after.
return {
  id = "visual",
  title = "Visual mode: select, then act",
  intro = [[
In this lesson, we select clips and parts first, and then we delete, copy,
mute and transpose them.

Visual mode lets you see the items before you change them, because it
changes the order of the keys. First, you select with the motions that you
know. Second, you press an operator, and it does its action on the
selection.

`v` selects a range of time, and `j` and `k` extend it across parts. `V`
selects whole parts. In the piano roll, `<C-v>` selects a rectangle of
pitches and time. In the practice project, each of the three parts has
four clips of one bar.]],
  idea = [[
In visual mode, the motions extend the selection, and `o` goes to its other
end. An operator (`d` `y` `c` `>` `<` `gc` `gl`) or a selection key does an
action on the selection. For example, `x` deletes, `p` replaces the
selection with the register, and `~` mutes. Moreover, `J` joins clips, and
`<C-a>` and `<C-x>` transpose, so with a count, `12<C-a>` transposes one
octave.

`gv` selects the last selection again, and `<Esc>` leaves visual mode and
does nothing.]],
  vim = [[
`v` `V` `<C-v>`, `o`, `gv` and operators on a selection come from Vim. In
visual mode, a count before `>` `<` or `<C-a>` is the amount, as in Vim. In
the arrange view, `v` with `j` and `k` already selects a block of time on
some parts, and `V` selects whole parts, as Vim selects whole lines.]],
  setup = function(look)
    paw.project.tempo = 100
    local function part(name, device, params, make)
      local t = paw.add_part({ name = name, volume = name == "Keys" and -10 or -4 })
      t:add_device(device, params)
      for i = 1, 4 do
        t:add_clip({ name = name:sub(1, 1):lower() .. i, start = (i - 1) * 4, length = 4, notes = make(i) })
      end
    end
    part("Drums", "drums", {}, function() return look.drums(look.beat) end)
    local roots = { "A1", "F1", "C2", "G1" }
    part("Bass", "synth", { wave = 2, cutoff = 600, release = 0.05 }, function(i) return look.pulse(roots[i], 4) end)
    local chords = { { "A3", "C4", "E4" }, { "F3", "A3", "C4" }, { "G3", "C4", "E4" }, { "G3", "B3", "D4" } }
    part(
      "Keys",
      "synth",
      { wave = 3, attack = 0.05, release = 0.4, cutoff = 1800 },
      function(i) return look.chord(chords[i], 4) end
    )
    paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 16, true
  end,
  at = function() paw.cursor.set_part(paw.part("Drums")) end,
  steps = {
    {
      say = "Press `v` to start a selection, and the status line shows VISUAL. Then press `W` to extend the selection over the first bar.",
      keys = { "v", "W" },
      check = function()
        local s = paw.keymap.selection()
        return s and s.kind == "char" and s.c0 == 0 and s.c1 == 4
      end,
      done = "The first bar of Drums is selected.",
    },
    {
      say = "`j` extends the selection down to the next part. Press `j`.",
      keys = { "j" },
      check = function()
        local s = paw.keymap.selection()
        return s and s.r0 == 1 and s.r1 == 2 and s.c1 == 4
      end,
      done = "The first bar of Drums and Bass is selected.",
    },
    {
      say = "Now do an action on the selection. `x` deletes the selection, so press `x`.",
      keys = { "x" },
      check = function(_, look) return look.names("Drums") == "d2 d3 d4" and look.names("Bass") == "b2 b3 b4" end,
      done = "paw deleted the clips from the two parts, and the mode is NORMAL again.",
    },
    {
      say = "Press `u` to undo the delete.",
      keys = { "u" },
      check = function(ctx, look)
        return look.ran(ctx, "undo") and look.names("Drums") == "d1 d2 d3 d4" and look.names("Bass") == "b1 b2 b3 b4"
      end,
      done = "The clips are back.",
    },
    {
      say = "`V` selects whole parts. Press `V`, and press `j` to select Drums and Bass. Then press `y` to yank (copy) them.",
      keys = { "V", "j", "y" },
      -- The register can hold two parts from before the lesson: only a
      -- new yank does the step.
      start = function(ctx) ctx.before = paw.keymap.getreg() end,
      check = function(ctx)
        local r = paw.keymap.getreg()
        return r and r ~= ctx.before and r.kind == "parts" and #r.parts == 2 and paw.keymap.mode == "n"
      end,
      done = "The register contains two parts.",
      hint = "If the selection is wrong, press `<Esc>` to leave visual mode, and then press `gg` and start again.",
    },
    {
      say = "`G` goes to the last part, and `p` pastes the parts below it. Press `G`, then `p`.",
      keys = { "G", "p" },
      check = function() return #paw.parts() == 5 end,
      done = "The song now has five parts, with the copies of Drums and Bass at the bottom.",
    },
    {
      say = "Press `u` to remove the copies.",
      keys = { "u" },
      check = function(ctx, look) return look.ran(ctx, "undo") and #paw.parts() == 3 end,
      done = "The song has three parts again.",
    },
    {
      say = "`gv` selects the last selection again, which is the two parts. Press `gv`, then `~` to mute them.",
      keys = { "gv", "~" },
      check = function(_, look) return look.part("Drums").mute and look.part("Bass").mute end,
      done = "Drums and Bass are muted, and their `M` flags are lit. On whole parts, `~` mutes the parts, and on a range of time, it mutes the clips in the range.",
    },
    {
      say = "Press `gv` and `~` again to unmute them.",
      keys = { "gv", "~" },
      check = function(ctx, look)
        return look.became(ctx, "unmuted", not look.part("Drums").mute and not look.part("Bass").mute)
      end,
      done = "`~` mutes and unmutes.",
    },
    {
      say = "Visual mode also works in the piano roll. Press `3G` to go to Keys, and press `<CR>` to open its first clip.",
      keys = { "3G", "<CR>" },
      check = function(_, look)
        local _, clip = look.roll()
        return look.focused() == "pianoroll" and clip and clip.name == "k1"
      end,
      done = "The piano roll shows the A minor chord of `k1`.",
    },
    {
      say = "`v` selects a range of time at all pitches. Press `v`, and then press `12<C-a>` to move all notes that start in the range up one octave.",
      keys = { "v", "12<C-a>" },
      check = function(_, look)
        local _, clip = look.roll()
        return clip and look.melody(clip) == "69@0+4 72@0+4 76@0+4" and paw.keymap.mode == "n"
      end,
      done = "The chord is one octave higher, because in visual mode a count gives the amount.",
      hint = "While the status line shows VISUAL, type 1, 2, and then Ctrl and a.",
    },
    {
      say = "Press `<C-w>p` to return to the arrange view. Press `<leader><Space>` to listen, and `<leader><Space>` to stop.",
      keys = { "<C-w>p", "<leader><Space>", { advance = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.focused() == "arrange" and look.played(ctx) end,
      done = "The first chord sounds one octave higher.",
    },
  },
  outro = "We selected with `v`, `V` and motions, and then used `x`, `y`, `~`, or a count and `<C-a>`. We also used `gv` to select again, and we used visual mode in the piano roll.",
}
