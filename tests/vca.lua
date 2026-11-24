-- VCAs (runtime/lua/paw/vca.tl): faders, mutes and solos over parts that
-- are not routed to them, and groups whose faders move together. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fails, fresh, render = T.test, T.eq, T.near, T.fails, T.fresh, T.render
local api = paw.api

local function db(x) return 10 ^ (x / 20) end

--- A part holding a steady level of `level` for 8 beats (4 s at 120 BPM).
local function steady_part(name, level)
  local t = paw.add_part({ name = name })
  t:add_clip({
    file = T.write_wav(
      T.scratch .. "/vca-" .. name .. ".wav",
      (function()
        local s = {}
        for i = 1, 4 * 48000 do
          s[i] = level
        end
        return s
      end)()
    ),
    start = 0,
    length = 8,
  })
  return t
end

local function setup()
  fresh()
  paw.project.tempo = 120
  return steady_part("Kick", 0.5), steady_part("Snare", 0.25), steady_part("Pad", 0.125)
end

--- The loudest of both channels between two seconds of a render.
local function peak(from, to, opts)
  local info = render(opts or { tail = 0, bits = 16 })
  local l, r = T.channel_peaks(info, from, to)
  return math.max(l, r)
end

test("a VCA fader moves its members by as many dB without changing their own faders", function()
  local kick, snare = setup()
  local drums = paw.vca.make({ kick }, "Drums")
  eq(paw.vca.is_vca(drums), true, "it is marked")
  eq(paw.vca.is_vca(kick), false, "and a part is not")
  eq(paw.groups.is_group(drums), false, "it is not a group")
  eq(paw.vca.members(drums)[1], kick.id, "the parts under it are named")
  eq(paw.vca.of(kick)[1], drums.id, "and each knows its VCAs")
  local only = { tail = 0, bits = 16, parts = { kick.id } }
  near(peak(0.2, 3, only), 0.5, 0.002, "at 0 dB the member is as it was")
  drums.volume = -6
  near(peak(0.2, 3, only), 0.5 * db(-6), 0.002, "6 dB down on the VCA")
  eq(kick.volume, 0, "the member's own fader is where it was")
  kick.volume = -6
  near(peak(0.2, 3, only), 0.5 * db(-12), 0.002, "its own fader adds to the VCA's")
  drums.volume = 6
  near(peak(0.2, 3, only), 0.5, 0.002, "and the VCA can raise it")
  near(peak(0.2, 3, { tail = 0, bits = 16, parts = { snare.id } }), 0.25, 0.002, "parts outside it are as they were")
  eq(api.part_get(kick.id).output, nil, "nothing is routed")
end)

test("a part in two VCAs has both their gains", function()
  local kick, snare = setup()
  local a, b = paw.vca.make({ kick, snare }, "A"), paw.vca.make({ kick }, "B")
  a.volume, b.volume = -6, -6
  near(peak(0.2, 3, { tail = 0, bits = 16, parts = { kick.id } }), 0.5 * db(-12), 0.002, "they add in dB")
  near(peak(0.2, 3, { tail = 0, bits = 16, parts = { snare.id } }), 0.25 * db(-6), 0.002, "a part in one has one")
  paw.vca.unassign(kick, a)
  near(peak(0.2, 3, { tail = 0, bits = 16, parts = { kick.id } }), 0.5 * db(-6), 0.002, "taken out of one")
  paw.vca.unassign(kick)
  near(peak(0.2, 3, { tail = 0, bits = 16, parts = { kick.id } }), 0.5, 0.002, "and out of all")
  fails(function() paw.vca.assign(a, b) end, "VCA", "a VCA cannot be under a VCA")
  fails(function() paw.vca.assign(kick, snare) end, "not a VCA", "and only a VCA takes parts")
end)

test("a VCA's mute silences its members and its solo makes them the only sound", function()
  local kick, snare, pad = setup()
  local drums = paw.vca.make({ kick, snare }, "Drums")
  near(peak(0.2, 3), 0.875, 0.003, "all three sound")
  drums.mute = true
  near(peak(0.2, 3), 0.125, 0.002, "the pad alone while the VCA is muted")
  eq(kick.mute, false, "the members' own mutes are not touched")
  drums.mute = false
  drums.solo = true
  near(peak(0.2, 3), 0.75, 0.003, "its members alone while it is soloed")
  eq(kick.solo, false, "without their own solos being set")
  drums.solo = false
  pad.solo = true
  near(peak(0.2, 3), 0.125, 0.002, "a part's own solo still works")
  pad.solo = false
  near(peak(0.2, 3), 0.875, 0.003, "and all is as it was")
end)

test("a VCA's automation moves its members sample by sample, with their own lanes", function()
  local kick = setup()
  local drums = paw.vca.make({ kick }, "Drums")
  -- At 120 BPM a beat is half a second: beat 2 is at 1 s, beat 6 at 3 s.
  drums:automate("volume"):set_points({ { 0, 0 }, { 4, -20 } })
  kick.volume = -6
  local only = { tail = 0, bits = 16, parts = { kick.id } }
  local info = render(only)
  near(T.channel_peaks(info, 0.99, 1.01), 0.5 * db(-16) + 0.0, 0.004, "10 dB down half way, and 6 of its own")
  near(T.channel_peaks(info, 1.98, 2.0), 0.5 * db(-26), 0.004, "20 dB down at the end of the lane")
  near(T.channel_peaks(info, 3.5, 3.9), 0.5 * db(-26), 0.004, "held after it")
  -- The member's own lane adds to the VCA's: jumps and slopes included.
  kick.volume = 0
  kick:automate("volume"):set_points({ { 0, 0 }, { 8, -12 } })
  drums:lane("volume"):set_points({ { 0, -8 }, { 4, 0 }, { 4, -6 }, { 8, -6 } })
  info = render(only)
  near(T.channel_peaks(info, 0.99, 1.01), 0.5 * db(-3 - 4), 0.004, "beat 2: -3 and -4")
  near(T.channel_peaks(info, 1.98, 1.995), 0.5 * db(-6), 0.004, "just before the jump: -6 and 0")
  near(T.channel_peaks(info, 2.99, 3.01), 0.5 * db(-9 - 6), 0.004, "beat 6: -9 and -6")
  -- The VCA's lane off, its fader is what counts.
  drums:lane("volume").enabled = false
  drums.volume = -3
  info = render(only)
  near(T.channel_peaks(info, 0.99, 1.01), 0.5 * db(-3 - 3), 0.004, "a lane that is off leaves the fader")
  drums:lane("volume").enabled = true
  kick:lane("volume").enabled = false
  info = render(only)
  near(T.channel_peaks(info, 0.99, 1.01), 0.5 * db(-4), 0.004, "and the same for the member's lane")
  -- Taken out of the VCA, the lane the VCA made is gone.
  kick:lane("volume").enabled = true
  paw.vca.unassign(kick)
  info = render(only)
  near(T.channel_peaks(info, 0.99, 1.01), 0.5 * db(-3), 0.004, "out of the VCA the part has its own lane only")
end)

test("renders with VCA automation are the same on any number of threads", function()
  local kick, snare = setup()
  local drums = paw.vca.make({ kick, snare }, "Drums")
  drums:automate("volume"):set_points({ { 0, 0 }, { 4, -20 }, { 8, -3 } })
  snare:automate("volume"):set_points({ { 0, -2 }, { 6, 0 } })
  local first
  for _, threads in ipairs({ 1, 2, 7 }) do
    local info = render({ tail = 0, bits = 32, threads = threads })
    local data = T.read_file(info.path)
    first = first or data
    eq(
      data == first,
      true,
      "the render on " .. threads .. " thread" .. (threads == 1 and "" or "s") .. " is the same bytes"
    )
  end
end)

test("VCAs are saved with the project and undone", function()
  local kick, snare = setup()
  api.undo_checkpoint()
  local drums = paw.vca.make({ kick, snare }, "Drums")
  api.undo_checkpoint()
  drums.volume = -9
  api.undo_checkpoint()
  paw.undo()
  eq(drums:get().volume, 0, "undoing the VCA's fader")
  paw.redo()
  near(peak(0.2, 3, { tail = 0, bits = 16, parts = { kick.id } }), 0.5 * db(-9), 0.002, "redone, it sounds")
  drums:automate("volume"):set_points({ { 0, -9 }, { 4, -9 } })
  api.undo_checkpoint()

  local path = paw.project.save(T.scratch .. "/vca.json")
  paw.project.load(path)
  local loaded = paw.part("Drums")
  eq(paw.vca.is_vca(loaded), true, "the VCA comes back")
  eq(#paw.vca.members(loaded), 2, "with its members")
  eq(paw.vca.of(paw.part("Kick"))[1], loaded.id, "which know it")
  near(
    peak(0.2, 3, { tail = 0, bits = 16, parts = { paw.part("Kick").id } }),
    0.5 * db(-9),
    0.002,
    "and sounds the same"
  )

  api.undo_checkpoint()
  paw.vca.unassign(paw.part("Snare"), loaded)
  api.undo_checkpoint()
  eq(#paw.vca.members(loaded), 1, "a part taken out")
  paw.undo()
  eq(#paw.vca.members(loaded), 2, "is put back by undo")
  paw.vca.dissolve(loaded)
  eq(paw.part("Drums"), nil, "a dissolved VCA is gone")
  eq(#(paw.part("Kick"):get().meta.vcas or {}), 0, "and the parts forget it")
  near(
    peak(0.2, 3, { tail = 0, bits = 16, parts = { paw.part("Kick").id } }),
    0.5,
    0.002,
    "and are at their own faders"
  )
  api.undo_checkpoint()
  paw.undo()
  eq(#paw.vca.members(paw.part("Drums")), 2, "undone, it holds them again")
end)

test("VCA commands put the selected parts under a VCA and take them out", function()
  local kick, snare, pad = setup()
  paw.cursor.set_part(kick)
  paw.commands.exec("vca.make Drums")
  local drums = paw.part("Drums")
  eq(paw.vca.is_vca(drums), true, "vca.make makes a VCA")
  eq(paw.vca.members(drums)[1], kick.id, "over the cursor's part")
  eq(paw.cursor.part_id(), drums.id, "and leaves the cursor on it")
  paw.cursor.set_part(snare)
  paw.commands.exec("vca.assign drum")
  eq(#paw.vca.members(drums), 2, "vca.assign finds a VCA by part of its name")
  paw.commands.exec("vca.release drum")
  eq(#paw.vca.members(drums), 1, "vca.release takes the part out")
  paw.cursor.set_part(kick)
  paw.commands.exec("vca.release")
  eq(#paw.vca.members(drums), 0, "alone it takes the part out of all")
  paw.cursor.set_part(drums)
  paw.commands.exec("vca.dissolve")
  eq(paw.part("Drums"), nil, "vca.dissolve takes it away")
  paw.keymap.feed("<Esc>")
  paw.ui.focus("arrange")
  paw.cursor.set_part(pad)
  paw.keymap.feed("<leader>tv")
  eq(require("paw.views.cmdline").state() ~= nil, true, "the key asks for a name")
  paw.keymap.feed("<C-u>Strings<CR>")
  eq(paw.vca.is_vca(paw.part("Strings")), true, "Space tv makes a VCA")
  eq(paw.vca.of(pad)[1], paw.part("Strings").id, "over the cursor's part")
end)

test("VCAs are drawn after the parts, in the arrange view's rows and the mixer's strips", function()
  local kick = setup()
  paw.vca.make({ kick }, "Drums")
  paw.add_part({ name = "Late" })
  local names = {}
  for i, id in ipairs(paw.groups.rows()) do
    names[i] = api.part_get(id).name
  end
  eq(table.concat(names, " "), "Kick Snare Pad Late Drums", "the VCA comes last however it was made")
  local state = paw.frontend.state(0)
  local by_name = {}
  for _, t in ipairs(state.parts) do
    by_name[t.name] = t
  end
  eq(by_name.Drums.vca, true, "the window is told which part is a VCA")
  eq(by_name.Drums.vcas, "Kick", "and whom it moves")
  eq(by_name.Kick.vcas, "Drums", "a member, which VCAs move it")
  eq(by_name.Snare.vca, false, "other parts are not")
  local shown = paw.ui.visible("mixer")
  if not shown then paw.ui.toggle("mixer") end
  local was = paw.opt.mixer_height
  paw.opt.mixer_height = 16
  paw.ui.focus("mixer")
  local screen = table.concat(api.ui_snapshot(120, 60), "\n")
  eq(
    screen:find("Drums", 1, true) ~= nil and screen:find("no parts", 1, true) == nil,
    true,
    "the mixer draws the VCA's strip"
  )
  eq(screen:find("vca Dru", 1, true) ~= nil, true, "and names a member's VCA\n" .. screen)
  paw.opt.mixer_height = was
  paw.ui.focus("arrange")
  if not shown then paw.ui.toggle("mixer") end
end)

test("the window's gestures make VCAs and assign parts through commands", function()
  local kick, snare = setup()
  local act = paw.frontend.act
  act.part_command(kick.id, "vca.make Drums")
  local drums = paw.part("Drums")
  eq(paw.vca.members(drums)[1], kick.id, "the part menu makes a VCA over the part")
  act.part_command(snare.id, "vca.assign Drums")
  eq(#paw.vca.members(drums), 2, "and puts another under it")
  act.set_volume(drums.id, -4)
  eq(drums:get().volume, -4, "the VCA's strip moves its fader like any other")
  act.toggle(drums.id, "mute")
  eq(drums:get().mute, true, "and its mute")
  act.part_command(snare.id, "vca.release")
  eq(#paw.vca.members(drums), 1, "the menu takes a part out")
end)

test("linked faders move the members of a group together, in dB", function()
  fresh()
  local a, b, c = paw.add_part({ name = "A" }), paw.add_part({ name = "B" }), paw.add_part({ name = "C" })
  local group = paw.groups.make({ a, b }, "Pair")
  a.volume, b.volume = -3, -9
  paw.flush()
  a.volume = -6
  paw.flush()
  eq(b.volume, -9, "unlinked, a fader moves alone")
  paw.groups.link(group, true)
  eq(paw.groups.linked(group), true, "the link is a group's option")
  a.volume = -10
  paw.flush()
  near(b.volume, -13, 0.001, "linked, the others move by as many dB")
  eq(c.volume, 0, "parts outside the group do not")
  eq(group.volume, 0, "nor does the group's own fader")
  b.volume = -3
  paw.flush()
  near(a.volume, 0, 0.001, "from any member")
  api.undo_checkpoint()
  a.volume = 24
  paw.flush()
  near(b.volume, 21, 0.001, "the other follows by the same dB")
  api.undo_checkpoint()
  paw.undo()
  paw.flush()
  near(a.volume, 0, 0.001, "undone, both go back at once")
  near(b.volume, -3, 0.001, "to what they were")
  api.undo_checkpoint()

  local path = paw.project.save(T.scratch .. "/linked.json")
  paw.project.load(path)
  paw.flush()
  eq(paw.groups.linked(paw.part("Pair")), true, "the link is saved")
  paw.part("A").volume = -5
  paw.flush()
  near(paw.part("B").volume, -8, 0.001, "and works when the project is opened")
  paw.groups.link(paw.part("Pair"), false)
  paw.part("A").volume = -6
  paw.flush()
  near(paw.part("B").volume, -8, 0.001, "until it is let go")
end)

test("part.group with no name asks for one", function()
  fresh()
  local a = paw.add_part({ name = "A" })
  paw.cursor.set_part(a)
  paw.commands.exec("part.group")
  eq(require("paw.views.cmdline").state() ~= nil, true, "the prompt opens")
  paw.keymap.feed("<C-u>Pair<CR>")
  eq(paw.groups.is_group(paw.part("Pair")), true, "and the answer names the group")
end)
