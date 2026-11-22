-- Lesson 17: Ex lines, ranges of time and tracks, `:s` and `:g`.
return {
  id = "ranges",
  title = "Ranges, :s and :g: edit by line",
  intro = [[
In this lesson, we change bars, tracks and notes of a song from the command
line.

Operators and visual mode do their action at the cursor. The command line can
do an action at many places at the same time. A range before a command gives
the places, as in the Ex of Vim, with bars for lines. `:2,3d` makes bars 2
and 3 empty. `:t2 4d` makes only bar 4 of track 2 empty. `:%s/c4/d4/g`
changes each C4 of the song to a D4.

Each of the three tracks here has four clips of one bar. While you type, look
at the right end of the command line. It shows what the line will do, and
the views highlight the items, before paw changes them.]],
  idea = [[
A range can be of time. `5,8` is bars and `5.3` is a beat. `%` is all, `.`
is the bar of the cursor and `$` is the last bar. `'a,'b` is marks, `'<,'>`
is the selection and `.+4` is an offset. It can be of tracks (`t2,t4`, `t*`, `t/Drums/`), or of the two
(`:t2 5,8d`).

The commands are `d` `y` `co` `m` `>` `<` `j`, `mute` `solo` `volume` `pan`,
`transpose` `quantize`, `normal`, `s` and `g`. A pattern selects notes or
clips by their fields: `c4`, `vel>100`, `len<1/8`, `name:Verse`. Each line is
one undo step.]],
  vim = [[
Ranges, `:d` `:y` `:co` `:m` `:>` `:j` and `:normal` are from Vim. `:s`
with `g`, `c` and `n`, `:&`, `:g` and `:v` are also from Vim. A bar is in
place of a line. `inccommand` is from Neovim.

Without `g`, only the first
match in each bar changes. In Vim, only the first match on each line changes. paw does not
have the `:t` of Vim, because `t` starts a range of tracks.]],
  setup = function(look)
    paw.project.tempo = 100
    local function track(name, device, params, make)
      local t = paw.add_track({ name = name, volume = name == "Keys" and -10 or -4 })
      t:add_device(device, params)
      for i = 1, 4 do
        t:add_clip({ name = name:sub(1, 1):lower() .. i, start = (i - 1) * 4, length = 4, notes = make(i) })
      end
    end
    track("Drums", "drums", {}, function() return look.drums(look.beat) end)
    local roots = { "A1", "F1", "C2", "G1" }
    track("Bass", "synth", { wave = 2, cutoff = 600, release = 0.05 }, function(i) return look.pulse(roots[i], 4) end)
    local chords = { { "A3", "C4", "E4" }, { "F3", "A3", "C4" }, { "G3", "C4", "E4" }, { "G3", "B3", "D4" } }
    track(
      "Keys",
      "synth",
      { wave = 3, attack = 0.05, release = 0.4, cutoff = 1800 },
      function(i) return look.chord(chords[i], 4) end
    )
    paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 16, true
  end,
  at = function() paw.cursor.set_track(paw.track("Drums")) end,
  steps = {
    {
      say = "Type `:2,3d` (bars 2 to 3, delete). Before you press Enter, look at the right end of the line: it shows `bars 2–3`, and the ruler shades them. Then press `<CR>`.",
      keys = { ":2,3d", "<CR>" },
      check = function(_, look) return look.names("Drums") == "d1 d4" and look.names("Keys") == "k1 k4" end,
      done = "Bars 2 and 3 are empty on all tracks. The register contains the deleted clips.",
    },
    {
      say = "The whole line is one change. Press `u`.",
      keys = { "u" },
      check = function(ctx, look) return look.ran(ctx, "undo") and look.names("Drums") == "d1 d2 d3 d4" end,
      done = "The bars are back, in one step.",
    },
    {
      say = "The tracks come first: `:t2 4d` makes only bar 4 of track 2, Bass, empty. Type it and press `<CR>`.",
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
      say = "`t*` is all the tracks. Make them all 3 dB quieter: type `:t* volume -=3`, then press `<CR>`.",
      keys = { ":t* volume -=3", "<CR>" },
      check = function(_, look) return look.track("Keys").volume == -13 and look.track("Drums").volume == -7 end,
      done = "Each fader went down by 3 dB. `:t* volume -6` sets them all to -6 dB.",
    },
    {
      say = "Now we use `:s`. Type `:%s/c4/d4/g`. The line counts the C4 notes of the song, and the clips that contain them are highlighted. Press `<CR>`.",
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
      done = "Each C4 is a D4 now. `%` was the whole song, and `g` was each match in each bar.",
      hint = "`<Esc>` leaves the line and changes nothing. Then type `:` and the command again.",
    },
    {
      say = "`:g` runs a command on each match. Mute the Bass clips by their name: type `:g/name:b/mute`, then press `<CR>`.",
      keys = { ":g/name:b/mute", "<CR>" },
      check = function(_, look) return look.layout("Bass"):gsub("[^m]", "") == "mmmm" end,
      done = "The four Bass clips are muted. `:g/vel>100/` with no command puts the matches in the quickfix list, for `]q`.",
    },
  },
  outro = "We used `:2,3d`, `:t2 4d`, `:t* volume -=3`, `:%s/c4/d4/g` and `:g/name:b/mute`: a range, then a command, one undo step for each.",
}
