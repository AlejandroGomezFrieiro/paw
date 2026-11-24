-- Lesson 9: instruments, effects, parameters, plugins and their windows.
local function selected()
  local device, row = paw.ui.views:get("inspector"):selected()
  return device, row
end

return {
  id = "devices",
  title = "Devices, parameters and plugins",
  intro = [[
In this lesson, we make a synth brighter and darker, add an echo after it,
and bypass the echo.

Each part has a chain of devices. The first device is an instrument, which
makes sound from notes, and the effects come after it. Each effect changes
the sound of the device before it. The devices view shows the chain of the
part under the cursor as a row of cards, one for each device. The inspector
under it shows the parameters of the device under the cursor. You use the
same kind of keys there as in the other views.

The built-in devices include `synth`, `drums`, `gain`, `delay` and `limiter`.
The CLAP, LV2 and VST3 plugins that you installed are also devices, and most
of them have their own window.]],
  idea = [[
In the inspector, `j` and `k` select a row, which is the name of a device or
one of its parameters, and `w` and `b` select a device. `<C-w>k` goes up to
the devices view, where `l` and `h` go from card to card and `<CR>` comes
back to the inspector. `+` and `-`
change a parameter by one step, and a count before them, e.g., `10+`,
changes it by more steps.

`a` adds a device, `x` removes one and `gc` bypasses one. `yy`, `dd` and
`p` copy and move devices, also to other parts. `<A-j>` and `<A-k>` change
the order, and `ge` opens the window of a plugin.

`<leader>dd` shows and hides the devices view and the inspector. In the
arrange view, `ge` opens the plugin window of the part.]],
  vim = [[
`yy` `dd` `p` work on devices as they work on lines. `+` and `-` change a value as `<C-a>` and
`<C-x>` change a number, and `gc` bypasses a device as it changes a line to
a comment.]],
  setup = function(look)
    paw.project.tempo = 96
    local drums = paw.add_part({ name = "Drums", volume = -6 })
    drums:add_device("drums")
    drums:add_clip({ name = "beat", start = 0, length = 8, notes = look.drums(look.beat, 2) })
    local lead = paw.add_part({ name = "Lead", volume = -6 })
    lead:add_device("synth", { wave = 1, cutoff = 900, resonance = 0.3, release = 0.15 })
    lead:add_clip({
      name = "line",
      start = 0,
      length = 8,
      notes = look.notes("D4:0:0.5 F4:0.5:0.5 A4:1:1 G4:2:0.5 F4:2.5:0.5 D4:3:1 C4:4:1 D4:5:3"),
    })
    paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 8, true
  end,
  at = function() paw.cursor.set_part(paw.part("Lead")) end,
  steps = {
    {
      say = "The cursor is on Lead. Press `<leader>dd` (the space bar, then d two times) to show its devices on the right, and the inspector gets the keys.",
      keys = { "<leader>dd" },
      check = function(_, look) return look.focused() == "inspector" end,
      done = "The devices view at the top shows the synth as a card. The inspector under it shows the name of the synth, and below it one row for each parameter.",
      hint = "The leader key is the space bar, and it starts many commands of two keys.",
    },
    {
      say = "`j` and `k` select a row. Press `6j` to go down to `cutoff`, which sets how bright the sound is.",
      keys = { "6j" },
      check = function()
        local _, row = selected()
        return row and row.param and row.param.key == "cutoff"
      end,
      done = "`cutoff` is selected.",
    },
    {
      say = "`+` increases the parameter by one step, and `-` decreases it. A count before them gives the number of steps. Press `10+` three times.",
      keys = { "10+", "10+", "10+" },
      start = function(ctx, look) ctx.cutoff = look.param(look.device("Lead", "synth"), "cutoff") end,
      check = function(ctx, look)
        -- Each `10+` is a tenth of the range, some 2000 Hz.
        return look.param(look.device("Lead", "synth"), "cutoff") > ctx.cutoff + 5000
      end,
      done = "The sound is brighter, and the bar and the number show the new value.",
    },
    {
      say = "Listen while you change the value. Press `<leader><Space>`, and then press `-` some times to make the sound darker. Press `<leader><Space>` to stop.",
      keys = { "<leader><Space>", { advance = 200 }, "-", "-", "-", { advance = 200 }, "<leader><Space>" },
      start = function(ctx, look) ctx.cutoff = look.param(look.device("Lead", "synth"), "cutoff") end,
      check = function(ctx, look)
        return look.played(ctx) and look.param(look.device("Lead", "synth"), "cutoff") < ctx.cutoff
      end,
      done = "You can change parameters while the song plays.",
    },
    {
      say = "`a` adds a device after the instrument. Press `a`, type `delay` and press `<CR>`.",
      keys = { "a", "delay", "<CR>" },
      check = function(_, look) return look.device("Lead", "delay") ~= nil end,
      done = "An echo now comes after the synth.",
    },
    {
      say = "`w` goes to the next device. Press `w` to go down to the `Delay` heading.",
      keys = { "w" },
      check = function()
        local device, row = selected()
        return device and device.kind == "delay" and row and not row.param
      end,
      done = "The delay is selected.",
      hint = "`b` goes to the previous device, and `j` and `k` move one row at a time.",
    },
    {
      say = "`gcc` bypasses the selected device, so the device stays in the chain but does nothing. Press `gcc`, and then `gcc` again to enable the device.",
      keys = { "gcc", "gcc" },
      check = function(ctx, look)
        local off = look.device("Lead", "delay").bypass
        if off then ctx.was_off = true end
        return ctx.was_off == true and not off
      end,
      done = "With bypass, you can compare the sound with and without an effect. In the other views, `gc` mutes.",
    },
    {
      say = "`ge` opens the window of a plugin. Built-in devices have no window, and the message line says so. Press `ge`.",
      keys = { "ge" },
      check = function(ctx, look) return look.said(ctx, "has no window of its own") end,
      done = "For a plugin, the window opens, and `ge` again closes it, in every view.",
    },
    {
      say = "If you installed plugins, `a` shows them with the built-in devices. Press `a`, type a part of the name of a plugin and press `<CR>`, and then press `ge` to see its window. `:devices` shows all the devices.",
      keys = {},
      unchecked = "The installed plugins are different on each computer, and a plugin window needs a desktop.",
      done = "Done.",
    },
    {
      say = "`<leader>dd` hides the devices view and the inspector, and the arrange view gets the keys again. Press `<leader>dd`.",
      keys = { "<leader>dd" },
      check = function(ctx, look)
        return look.became(ctx, "closed", not look.visible("devices") and look.focused() == "arrange")
      end,
      done = "Both are hidden, and `<leader>dd` shows them again.",
    },
    {
      say = "Listen to the line with its echo. Press `<leader><Space>`, and `<leader><Space>` to stop.",
      keys = { "<leader><Space>", { advance = 300 }, "<leader><Space>" },
      check = function(ctx, look) return look.played(ctx) end,
      done = "You hear a synth and a delay that you adjusted by ear.",
    },
  },
  outro = "We used the devices view and the inspector to select and change parameters. We added and bypassed a device, and we found where plugin windows open.",
}
