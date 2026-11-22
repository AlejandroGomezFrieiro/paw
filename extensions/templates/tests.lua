-- Tests of the templates extension; tests/suite.lua runs them.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh

local templates
local function load()
  if not templates then
    paw.opt.templates_dir = T.scratch .. "/templates"
    paw.ext.load("extensions/templates")
    templates = require("templates")
  end
  paw.opt.templates_dir = T.scratch .. "/templates"
  return templates
end

local function order()
  local out = {}
  for i, track in ipairs(paw.tracks()) do
    out[i] = string.rep(">", paw.groups.depth(track.id)) .. track.name
  end
  return table.concat(out, " ")
end

test("templates: a track comes back with its devices and settings, in another project", function()
  fresh()
  load()
  local bus = paw.add_track({ name = "Bus" })
  local track = paw.add_track({ name = "Lead", volume = -7, pan = 0.25 })
  track:add_device("synth", { cutoff = 900 })
  track:add_device("delay", { mix = 0.4 })
  track.output = bus
  track:send(bus, -12)
  track:add_clip({ start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  track:devices()[1]:automate("cutoff"):set_points({ { 0, 500 }, { 4, 1500 } })
  local path = templates.save_track(track, "Lead sound")
  eq(path, T.scratch .. "/templates/track/Lead sound.json", "the template is a file under its name")
  eq(#templates.list("track") .. " " .. templates.list()[1].name, "1 Lead sound", "and is listed")

  fresh()
  paw.add_track({ name = "First" })
  local made = templates.load("Lead sound")
  eq(made.name .. " " .. made.volume .. " " .. made.pan, "Lead -7 0.25", "the track is made again with its settings")
  eq(order(), "First Lead", "below the cursor track")
  local devices = made:devices()
  eq(
    #devices .. " " .. devices[1].kind .. " " .. devices[1].params.cutoff,
    "2 synth 900",
    "with its devices as they were set"
  )
  near(devices[2].params.mix, 0.4, 1e-6, "each of them")
  eq(#made:clips() .. " " .. #made:lanes(), "0 1", "its automation, and not its clips")
  eq(
    tostring(made.output) .. " " .. #made.sends,
    "nil 0",
    "nor where it played into: that belonged to the other project"
  )
  templates.save_track(paw.tracks()[1], "With music", { clips = true })
  eq(templates.delete("Lead sound"), true, "a template is deleted")
  eq(#templates.list("track"), 1, "and gone from the list")
  T.fails(function() templates.load("Lead sound") end, "no template", "a template that is not there")
end)

test("templates: a chain of devices is added to another track", function()
  fresh()
  load()
  local a = paw.add_track({ name = "Vocal" })
  a:add_device("gain", { gain = -3 })
  a:add_device("delay", { time = 0.25 })
  templates.save_fx(a, "Vocal chain")
  local b = paw.add_track({ name = "Other" })
  b:add_device("limiter")
  paw.cursor.set_track(b)
  paw.cmd("template.load", { "vocal ch" })
  local kinds = {}
  for i, d in ipairs(b:devices()) do
    kinds[i] = d.kind
  end
  eq(table.concat(kinds, " "), "limiter gain delay", "the chain is added after what the track has")
  eq(b:devices()[2].params.gain, -3, "with its settings")
  T.fails(
    function() templates.save_fx(paw.add_track({ name = "Empty" }), "Nothing") end,
    "no devices",
    "a chain of nothing"
  )
end)

test("templates: a group comes back with every track in it", function()
  fresh()
  load()
  local names = { "Violins", "Violas", "Cellos" }
  local members = {}
  for i, name in ipairs(names) do
    members[i] = paw.add_track({ name = name })
    members[i]:add_device("synth")
  end
  local strings = paw.groups.make(members, "Strings")
  strings:add_device("limiter")
  paw.groups.make({ members[1] }, "Firsts")
  eq(order(), "Strings >Firsts >>Violins >Violas >Cellos", "a group with a group inside")
  paw.cursor.set_track(strings)
  paw.cmd("template.save", { "String section" })
  eq(templates.list("group")[1].name, "String section", "saving a group's track saves the group")

  fresh()
  paw.add_track({ name = "Piano" })
  local made = templates.load("String section")
  eq(
    order(),
    "Piano Strings >Firsts >>Violins >Violas >Cellos",
    "the whole group is made again, under the cursor track"
  )
  eq(made:devices()[1].kind, "limiter", "the group's own devices with it")
  local violas = paw.track("Violas")
  eq(violas.output, made.id, "and its tracks play into it")
  eq(violas:devices()[1].kind, "synth", "each with its devices")
end)

test("templates: the window's menus offer them", function()
  fresh()
  load()
  local labels = {}
  for _, entry in ipairs(paw.frontend.menus.timeline) do
    labels[entry.label] = true
  end
  for _, entry in ipairs(paw.frontend.menus.track) do
    labels[entry.label] = true
  end
  eq(
    labels["From a template…"]
      and labels["Save as a template…"]
      and labels["Save its devices as a chain…"]
      and labels["Add devices from a template…"],
    true,
    "making and saving are in the track button's menu and a track's own"
  )
end)

test(
  "templates: saving over a template asks first, an empty name says nothing was saved, a changed name is told",
  function()
    fresh()
    load()
    local track = paw.add_track({ name = "Pad", volume = -3 })
    paw.cursor.set_track(track)
    paw.ui.focus("arrange")
    T.keys(":template.save Keep me<CR>")
    eq(paw.ui.message.text:find("saved as a template", 1, true) ~= nil, true, "saved: " .. paw.ui.message.text)
    track.volume = -9
    T.keys(":template.save Keep me<CR>")
    T.keys("n<CR>")
    eq(paw.ui.message.text, "nothing saved: the template “Keep me” stays as it was", "n keeps the old one")
    fresh()
    eq(templates.load("Keep me").volume, -3, "as it was")
    local again = paw.add_track({ name = "Pad", volume = -9 })
    paw.cursor.set_track(again)
    T.keys(":template.save Keep me<CR>y<CR>")
    eq(paw.ui.message.text:find("saved as a template", 1, true) ~= nil, true, "y replaces it")
    fresh()
    eq(templates.load("Keep me").volume, -9, "with the new settings")
    paw.cursor.set_track(paw.tracks()[1])
    T.keys(":template.save<CR><C-u><CR>")
    eq(paw.ui.message.text, "no name given: nothing saved", "an empty name")
    T.keys(":template.save Bass/Sub<CR>")
    eq(
      paw.ui.message.text:find("“Bass_Sub” saved", 1, true) ~= nil
        and paw.ui.message.text:find("cannot hold", 1, true) ~= nil,
      true,
      "the name kept is told: " .. paw.ui.message.text
    )
  end
)

test("templates: the path a template is saved to is said from ~ when it is under the home directory", function()
  fresh()
  load()
  local track = paw.add_track({ name = "Pad" })
  paw.cursor.set_track(track)
  paw.ui.focus("arrange")
  T.keys(":template.save Home path<CR>")
  local path, home = templates.path("track", "Home path"), os.getenv("HOME") or ""
  local said = home ~= "" and path:sub(1, #home + 1) == home .. "/" and "~" .. path:sub(#home + 1) or path
  eq(paw.ui.message.text, "track “Home path” saved as a template (" .. said .. ")", "the message")
end)
