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
  -- Each test starts with no templates: the folder outlives the test that
  -- saved into it.
  os.execute("rm -rf '" .. T.scratch .. "/templates'")
  paw.opt.templates_dir = T.scratch .. "/templates"
  return templates
end

local function order()
  local out = {}
  for i, part in ipairs(paw.parts()) do
    out[i] = string.rep(">", paw.groups.depth(part.id)) .. part.name
  end
  return table.concat(out, " ")
end

test("templates: a part comes back with its devices and settings, in another project", function()
  fresh()
  load()
  local bus = paw.add_part({ name = "Bus" })
  local part = paw.add_part({ name = "Lead", volume = -7, pan = 0.25 })
  part:add_device("synth", { cutoff = 900 })
  part:add_device("delay", { mix = 0.4 })
  part.output = bus
  part:send(bus, -12)
  part:add_clip({ start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  part:devices()[1]:automate("cutoff"):set_points({ { 0, 500 }, { 4, 1500 } })
  local path = templates.save_part(part, "Lead sound")
  eq(path, T.scratch .. "/templates/part/Lead sound.json", "the template is a file under its name")
  eq(#templates.list("part") .. " " .. templates.list()[1].name, "1 Lead sound", "and is listed")

  fresh()
  paw.add_part({ name = "First" })
  local made = templates.load("Lead sound")
  eq(made.name .. " " .. made.volume .. " " .. made.pan, "Lead -7 0.25", "the part is made again with its settings")
  eq(order(), "First Lead", "below the cursor part")
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
  templates.save_part(paw.parts()[1], "With music", { clips = true })
  eq(templates.delete("Lead sound"), true, "a template is deleted")
  eq(#templates.list("part"), 1, "and gone from the list")
  T.fails(function() templates.load("Lead sound") end, "no template", "a template that is not there")
end)

test("templates: a chain of devices is added to another part", function()
  fresh()
  load()
  local a = paw.add_part({ name = "Vocal" })
  a:add_device("gain", { gain = -3 })
  a:add_device("delay", { time = 0.25 })
  templates.save_fx(a, "Vocal chain")
  local b = paw.add_part({ name = "Other" })
  b:add_device("limiter")
  paw.cursor.set_part(b)
  paw.cmd("template.load", { "vocal ch" })
  local kinds = {}
  for i, d in ipairs(b:devices()) do
    kinds[i] = d.kind
  end
  eq(table.concat(kinds, " "), "limiter gain delay", "the chain is added after what the part has")
  eq(b:devices()[2].params.gain, -3, "with its settings")
  T.fails(
    function() templates.save_fx(paw.add_part({ name = "Empty" }), "Nothing") end,
    "no devices",
    "a chain of nothing"
  )
end)

test("templates: a group comes back with every part in it", function()
  fresh()
  load()
  local names = { "Violins", "Violas", "Cellos" }
  local members = {}
  for i, name in ipairs(names) do
    members[i] = paw.add_part({ name = name })
    members[i]:add_device("synth")
  end
  local strings = paw.groups.make(members, "Strings")
  strings:add_device("limiter")
  paw.groups.make({ members[1] }, "Firsts")
  eq(order(), "Strings >Firsts >>Violins >Violas >Cellos", "a group with a group inside")
  paw.cursor.set_part(strings)
  paw.cmd("template.save", { "String section" })
  eq(templates.list("group")[1].name, "String section", "saving a group's part saves the group")

  fresh()
  paw.add_part({ name = "Piano" })
  local made = templates.load("String section")
  eq(order(), "Piano Strings >Firsts >>Violins >Violas >Cellos", "the whole group is made again, under the cursor part")
  eq(made:devices()[1].kind, "limiter", "the group's own devices with it")
  local violas = paw.part("Violas")
  eq(violas.output, made.id, "and its parts play into it")
  eq(violas:devices()[1].kind, "synth", "each with its devices")
end)

test("templates: the window's menus offer them", function()
  fresh()
  load()
  local labels = {}
  for _, entry in ipairs(paw.frontend.menus.timeline) do
    labels[entry.label] = true
  end
  for _, entry in ipairs(paw.frontend.menus.part) do
    labels[entry.label] = true
  end
  eq(
    labels["From a template…"]
      and labels["Save as a template…"]
      and labels["Save its devices as a chain…"]
      and labels["Add devices from a template…"],
    true,
    "making and saving are in the part button's menu and a part's own"
  )
end)

test(
  "templates: saving over a template asks first, an empty name says nothing was saved, a changed name is told",
  function()
    fresh()
    load()
    local part = paw.add_part({ name = "Pad", volume = -3 })
    paw.cursor.set_part(part)
    paw.ui.focus("arrange")
    T.keys(":template.save Keep me<CR>")
    eq(paw.ui.message.text:find("saved as a template", 1, true) ~= nil, true, "saved: " .. paw.ui.message.text)
    part.volume = -9
    T.keys(":template.save Keep me<CR>")
    T.keys("n<CR>")
    eq(paw.ui.message.text, "nothing saved: the template “Keep me” stays as it was", "n keeps the old one")
    fresh()
    eq(templates.load("Keep me").volume, -3, "as it was")
    local again = paw.add_part({ name = "Pad", volume = -9 })
    paw.cursor.set_part(again)
    T.keys(":template.save Keep me<CR>y<CR>")
    eq(paw.ui.message.text:find("saved as a template", 1, true) ~= nil, true, "y replaces it")
    fresh()
    eq(templates.load("Keep me").volume, -9, "with the new settings")
    paw.cursor.set_part(paw.parts()[1])
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
  local part = paw.add_part({ name = "Pad" })
  paw.cursor.set_part(part)
  paw.ui.focus("arrange")
  -- The templates are in T.scratch/templates (see load).
  T.home(T.scratch)
  T.keys(":template.save Home path<CR>")
  eq(paw.ui.message.text, "part “Home path” saved as a template (~/templates/part/Home path.json)", "the message")
end)
