-- Lesson 17: Ex lines, ranges of time and parts, `:s` and `:g`.
return {
  id = "ranges",
  title = "Ranges, :s and :g: edit by line",
  intro = [[
In this lesson, we change bars, parts and notes of a song from the command
line.

Operators and visual mode do their action at the cursor, but the command
line can do an action at many places at the same time. A range before a
command gives the places as bars and parts.
For example, `:2,3d` makes bars 2 and 3 empty, and `:t2 4d` makes only bar
4 of part 2 empty. `:%s/c4/d4/g` changes each C4 of the song to a D4.

In the practice project, each of the three parts has four clips of one
bar. While you type, look at the right end of the command line, which
shows what the line will do. The views also highlight the items before paw
changes them.]],
  idea = [[
A range can be of time, e.g., `5,8` is bars and `5.3` is a beat. `%` is
all, `.` is the bar of the cursor, and `$` is the last bar. Moreover, `'a,'b`
is marks, `'<,'>` is the selection, and `.+4` is an offset. A range can also
be of parts (`t2,t4`, `t*`, `t/Drums/`), or of both (`:t2 5,8d`).

The commands are `d` `y` `co` `m` `>` `<` `j`, `mute` `solo` `volume` `pan`,
`transpose` `quantize`, `normal`, `s` and `g`. A pattern selects notes or
clips by their fields, e.g., `c4`, `vel>100`, `len<1/8` or `name:Verse`.
Each line is one undo step.]],
  vim = [[
Ranges, `:d` `:y` `:co` `:m` `:>` `:j` and `:normal` come from Vim, and so
do `:s` with `g`, `c` and `n`, `:&`, `:g` and `:v`. A bar takes the place
of a line, and `inccommand` comes from Neovim.

Without `g`, only the first match in each bar changes, as only the first
match on each line changes in Vim. paw does not have the `:t` of Vim,
because `t` starts a range of parts.]],
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
      say = "Type `:2,3d` (bars 2 to 3, delete). Before you press Enter, look at the right end of the line, which shows `bars 2–3`, and at the ruler, which shades the bars. Then press `<CR>`.",
      keys = { ":2,3d", "<CR>" },
      check = function(_, look) return look.names("Drums") == "d1 d4" and look.names("Keys") == "k1 k4" end,
      done = "Bars 2 and 3 are empty on all parts, and the register contains the deleted clips.",
    },
    {
      say = "The whole command line is one change, so one `u` undoes it. Press `u`.",
      keys = { "u" },
      check = function(ctx, look) return look.ran(ctx, "undo") and look.names("Drums") == "d1 d2 d3 d4" end,
      done = "The bars are back after one undo step.",
    },
    {
      say = "The parts come first in a range, so `:t2 4d` makes only bar 4 of part 2, Bass, empty. Type it and press `<CR>`.",
      keys = { ":t2 4d", "<CR>" },
      check = function(_, look) return look.names("Bass") == "b1 b2 b3" and look.names("Drums") == "d1 d2 d3 d4" end,
      done = "Only Bass lost its last bar.",
    },
    {
      say = "Press `u` again.",
      keys = { "u" },
      check = function(ctx, look) return look.ran(ctx, "undo") and look.names("Bass") == "b1 b2 b3 b4" end,
      done = "The bar is back.",
    },
    {
      say = "`t*` is all the parts. To make them all 3 dB quieter, type `:t* volume -=3`, and then press `<CR>`.",
      keys = { ":t* volume -=3", "<CR>" },
      check = function(_, look) return look.part("Keys").volume == -13 and look.part("Drums").volume == -7 end,
      done = "Each fader went down by 3 dB, and `:t* volume -6` would set them all to -6 dB.",
    },
    {
      say = "Now we use `:s`. Type `:%s/c4/d4/g`, and the line counts the C4 notes of the song while the clips that contain them are highlighted. Press `<CR>`.",
      keys = { ":%s/c4/d4/g", "<CR>" },
      check = function(_, look)
        local c4, d4 = 0, 0
        for _, c in ipairs(look.clips("Keys")) do
          for _, n in ipairs(c:notes()) do
            if n.pitch == 60 then
              c4 = c4 + 1
            elseif n.pitch == 62 then
              d4 = d4 + 1
            end
          end
        end
        return c4 == 0 and d4 == 4
      end,
      done = "Each C4 is now a D4, because `%` was the whole song, and `g` was each match in each bar.",
      hint = "`<Esc>` leaves the line and changes nothing, so you can type `:` and the command again.",
    },
    {
      say = "`:g` runs a command on each match. To mute the Bass clips by their name, type `:g/name:b/mute`, and then press `<CR>`.",
      keys = { ":g/name:b/mute", "<CR>" },
      check = function(_, look) return look.layout("Bass"):gsub("[^m]", "") == "mmmm" end,
      done = "The four Bass clips are muted. `:g/vel>100/` with no command puts the matches in the quickfix list, where `]q` goes to the next match.",
    },
  },
  outro = "We used `:2,3d`, `:t2 4d`, `:t* volume -=3`, `:%s/c4/d4/g` and `:g/name:b/mute`, which are each a range followed by a command, with one undo step for each.",
}
