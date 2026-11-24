-- Lesson 10: faders, pan, mute, solo, buses, sends, automation.
local api = paw.api

local function near(a, b) return math.abs(a - b) < 1e-6 end

return {
  id = "mixing",
  title = "The mix: faders, pan, buses, sends, automation",
  intro = [[
In this lesson, we mix a short song. We change the level and the pan of the
bass, and we send the keys through a bus. Then we give the melody an echo
and make the chords fade in.

To mix, you set the level of each part with its fader, in dB, and its
position from left to right with the pan. You mute some parts, or solo a
part to hear it alone. You also set where the sound of each part goes,
which is either the master or a bus that groups parts under one fader. A
send can also take a part of the sound to an effect part.

Automation changes a fader, or a parameter, over time. The mixer shows one
strip for each part, and you can make the same changes from the arrange
view.]],
  idea = [[
In the mixer, the parts go across. `h` and `l` select a strip, and `j` and
`k` select a row of the strip. The rows are devices, sends, fader, pan,
mute, solo and arm. `+` and `-` change the row under the cursor, by 1 dB on
the fader. `]` and `[` pan, and `M`, `s` and `r` mute, solo and arm. In the
arrange view, the same keys are `+` `-`, `]` `[` and `M` `s` `r`.

You set the routing with commands. `:part.output Bus` sends the part into
the part with the name Bus, and `:part.output master` sends it to the
master again. With no name, `:part.output` shows the parts that you can
select.

`A` adds a volume automation point at the cursor. `<leader>at` disables and
enables the automation, and `<leader>ax` clears it.]],
  vim = [[
In the mixer, the parts are columns instead of rows, so `h` and `l` move
between parts. `j` and `k` only move, as in every view. `6<C-x>` decreases
the row by six, as `<C-x>` decreases a number in Vim, and `<C-w>c` closes
the mixer.]],
  setup = function(look)
    paw.project.tempo = 100
    local drums = paw.add_part({ name = "Drums", volume = -6 })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 16, notes = look.drums(look.beat, 4) })
    local bass = paw.add_part({ name = "Bass", volume = -4 })
    bass:add_device("synth", { wave = 2, cutoff = 600, release = 0.05 })
    local line = {}
    for i, root in ipairs({ "A1", "F1", "C2", "G1" }) do
      for _, n in ipairs(look.pulse(root, 4, (i - 1) * 4)) do
        line[#line + 1] = n
      end
    end
    bass:add_clip({ name = "bass", start = 0, length = 16, notes = line })
    local keys = paw.add_part({ name = "Keys", volume = -10 })
    keys:add_device("synth", { wave = 3, attack = 0.05, release = 0.4, cutoff = 1800 })
    local chords = {}
    for i, chord in ipairs({ { "A3", "C4", "E4" }, { "F3", "A3", "C4" }, { "G3", "C4", "E4" }, { "G3", "B3", "D4" } }) do
      for _, n in ipairs(look.chord(chord, 4, (i - 1) * 4)) do
        chords[#chords + 1] = n
      end
    end
    keys:add_clip({ name = "chords", start = 0, length = 16, notes = chords })
    local lead = paw.add_part({ name = "Lead", volume = -8 })
    lead:add_device("synth", { wave = 1, cutoff = 2400, release = 0.2 })
    lead:add_clip({
      name = "melody",
      start = 0,
      length = 16,
      notes = look.notes("E5:0:1 C5:1:1 A4:2:2 F4:4:1 A4:5:1 C5:6:2 E5:8:1 G5:9:1 E5:10:2 D5:12:2 B4:14:2"),
    })
    local echo = paw.add_part({ name = "Echo", volume = -6 })
    echo:add_device("delay", { mix = 1, feedback = 0.45 })
    paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 16, true
  end,
  at = function() paw.cursor.set_part(paw.part("Drums")) end,
  steps = {
    {
      say = "Press `<leader>mm` to open the mixer at the bottom, with one strip for each part. Each strip has a fader and a meter.",
      keys = { "<leader>mm" },
      check = function(_, look) return look.focused() == "mixer" end,
      done = "The mixer gets the keys, and the master is on the right.",
    },
    {
      say = "In the mixer, `h` and `l` select a strip, and the cursor starts on its fader. `-` and `+` change the row under the cursor by 1 dB. Press `l` to go to Bass, then press `-` three times.",
      keys = { "l", "-", "-", "-" },
      check = function(_, look) return look.cursor_part() == "Bass" and near(look.part("Bass").volume, -7) end,
      done = "Bass is at -7 dB, which is 3 dB lower than before. `3-` or `3<C-x>` does the same in one step.",
    },
    {
      say = "`]` and `[` pan the strip to the right and to the left, at each row of the strip. Press `]` three times.",
      keys = { "]", "]", "]" },
      check = function(_, look) return near(look.part("Bass").pan, 0.3) end,
      done = "Bass is a little to the right.",
    },
    {
      say = "`s` solos a part, so you hear only the soloed parts. Press `<leader><Space>` to play and `s` to hear Bass alone. Press `s` again to hear all parts, and `<leader><Space>` to stop.",
      keys = { "<leader><Space>", "s", { advance = 200 }, "s", "<leader><Space>" },
      check = function(ctx, look)
        local _, n = look.ran(ctx, "part.solo")
        return n >= 2 and not look.part("Bass").solo and look.played(ctx)
      end,
      done = "With solo, you can listen to one part closely, and solo does not change the mix.",
    },
    {
      say = "`M` mutes a part. Press `l` to go to Keys, and `M` to mute it.",
      keys = { "l", "M" },
      check = function(_, look) return look.part("Keys").mute end,
      done = "Keys is muted, and its `M` is lit.",
    },
    {
      say = "Press `M` again to unmute Keys, and press `<C-w>c` to close the mixer.",
      keys = { "M", "<C-w>c" },
      check = function(ctx, look)
        return look.became(ctx, "back", not look.part("Keys").mute and not look.visible("mixer"))
      end,
      done = "The arrange view gets the keys again, and the cursor is still on Keys. In the arrange view too, `+` and `-` change the fader, and `]` and `[` change the pan.",
    },
    {
      say = "A bus is a part that other parts play into. Type `:part.add Bus` and press `<CR>` to add one.",
      keys = { ":part.add Bus", "<CR>" },
      check = function(_, look) return look.part("Bus") ~= nil end,
      done = "A part with the name Bus shows below Keys, and the cursor is on it.",
    },
    {
      say = "Now send Keys into the bus. Type `/Keys` and `<CR>` to find the part, and then type `:part.output Bus` and `<CR>`.",
      keys = { "/Keys", "<CR>", ":part.output Bus", "<CR>" },
      check = function(_, look) return api.part_get(look.part("Keys").id).output == look.part("Bus").id end,
      done = "Keys now plays through Bus. The fader of Bus changes the level of the chords and of each other part that you send there.",
    },
    {
      say = "A send copies some of the sound of a part to a different part, which here is Echo, a part with a delay. Type `/Lead` and `<CR>` to find the part, and then type `:send Echo -6` and `<CR>`.",
      keys = { "/Lead", "<CR>", ":send Echo -6", "<CR>" },
      check = function(_, look)
        for _, send in ipairs(api.part_get(look.part("Lead").id).sends) do
          if send.target == look.part("Echo").id and near(send.level, -6) then return true end
        end
      end,
      done = "Lead sends to Echo at -6 dB, so the melody now has an echo. The fader of Echo sets the level of the echo.",
      hint = "`<leader>ts` does the same, but it asks for the part and sends at the default level.",
    },
    {
      say = "Now we add automation. `A` adds a volume point at the cursor and asks for its value. Type `/Keys` and `<CR>` to return to Keys, and then press `0` and `A`. Press `<C-u>` to clear the value, type `-30` and press `<CR>`.",
      keys = { "/Keys", "<CR>", "0", "A", "<C-u>", "-30", "<CR>" },
      check = function(_, look)
        local lane = look.part("Keys"):lane("volume")
        return lane and #lane:points() == 1 and lane:points()[1][1] == 0 and near(lane:points()[1][2], -30)
      end,
      done = "A point of -30 dB is at the start, and an `A` shows in the part header.",
      hint = "The cursor must be on Keys. Type `/Keys` and `<CR>`.",
    },
    {
      say = "Press `2W` to move two bars. Then press `A` and `<C-u>`, type `-10` and press `<CR>`, so that the chords fade in over two bars.",
      keys = { "2W", "A", "<C-u>", "-10", "<CR>" },
      check = function(_, look)
        local lane = look.part("Keys"):lane("volume")
        local p = lane and lane:points()
        return p and #p == 2 and p[2][1] == 8 and near(p[2][2], -10)
      end,
      done = "The lane of the part shows the line between the points.",
    },
    {
      say = "Listen from the start. Press `gs` and `<leader><Space>`, and `<leader><Space>` to stop.",
      keys = { "gs", "<leader><Space>", { advance = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.ran(ctx, "transport.start") and look.played(ctx) end,
      done = "The chords fade in through a bus, the melody has an echo, and the bass is on the right.",
    },
  },
  outro = "We used the faders, pan, solo and mute of the mixer. We made a bus with `:part.output`, and we added a send and volume automation with `A`.",
}
