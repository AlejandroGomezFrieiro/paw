-- One key rule in every view (docs/reference/key-rule.md): the
-- motion keys only move (the structural `]c` `]n` `]]` `[[` `]s` `[s` `[{` `]}` too), `<` `>` are the time operators, `+` `-` `Ctrl-a`
-- `Ctrl-x` change the main value and `[` `]` the second, `K` describes,
-- `ge` is the plugin window, `gc` mutes and `gC` opens a curve, and Escape
-- cancels and stays. The first tests walk every view's mappings; the others
-- drive the mixer, the device panel and the piano roll as grids. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local advance = T.advance
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local api = paw.api
local keymap = paw.keymap

local function start()
  fresh()
  api.engine_restart({})
  keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  for _, name in ipairs({ "pianoroll", "mixer", "devices" }) do
    paw.ui.hide(name)
  end
  paw.ui.focus("arrange")
end

local keys = T.keys

--- A key that also starts longer mappings (`]` and `]d`): it runs when the
--- wait for the rest is over, as it does at the keyboard.
local function waited(text)
  local before = paw.opt.timeoutlen
  paw.opt.timeoutlen = 20
  keymap.feed(text)
  advance(150)
  paw.opt.timeoutlen = before
  api.undo_checkpoint()
end

local broken = paw.keyrule.broken

test("every view's keys keep to the one rule, the bundled extensions' too", function()
  start()
  eq(table.concat(broken(), "\n"), "", "the core's mappings that break the rule")
  -- Loading every extension here would change the suite's kernel for the
  -- tests after this one: a kernel of its own walks them.
  -- The shell's parent is this kernel: the same program runs the walk.
  local cmd =
    'exec "$(readlink /proc/$PPID/exe)" --clean --no-plugins --no-listen --audio null -l tests/fixtures/keys_walk.lua 2>&1'
  local out = io.popen(cmd):read("*a")
  eq(out:match("done%s*$") ~= nil, true, "the walk ran to its end:\n" .. out)
  local wrong = {}
  for line in out:gmatch("[^\n]+") do
    if line:match("^wrong: ") then wrong[#wrong + 1] = line:sub(8) end
  end
  eq(table.concat(wrong, "\n"), "", "with every extension loaded")
end)

test("the structural keys are motions wherever they are mapped: the arrange view's groups, the piano roll", function()
  start()
  local found = {}
  for _, map in ipairs(keymap.every()) do
    local keys = table.concat(map.keys)
    if
      map.mode == "n"
      and (
        keys == "]]"
        or keys == "[["
        or keys == "]c"
        or keys == "]n"
        or keys == "[{"
        or keys == "]}"
        or keys == "]s"
        or keys == "[s"
      )
    then
      found[#found + 1] = map.scope .. " " .. keys
    end
  end
  table.sort(found)
  local text = table.concat(found, ", ")
  eq(
    text:find("arrange [{", 1, true) ~= nil and text:find("arrange ]}", 1, true) ~= nil,
    true,
    "the arrange view's group keys: " .. text
  )
  eq(text:find("pianoroll ]n", 1, true) ~= nil, true, "the roll's next note of a pitch")
  keymap.set("]}", function() end, { view = "keyrule.test", desc = "test: not a motion" })
  local wrong = table.concat(broken(), "\n")
  keymap.del("]}", { view = "keyrule.test" })
  eq(wrong:find("keyrule.test n ]}: a motion key that does not move", 1, true) ~= nil, true, wrong)
end)

test("the rule holds for a mapping made later, and says what it broke", function()
  start()
  keymap.set("j", function() end, { view = "keyrule.test", desc = "test: a fader on j" })
  local found = table.concat(broken(), "\n")
  keymap.del("j", { view = "keyrule.test" })
  eq(found:find("keyrule.test n j: a motion key that does not move", 1, true) ~= nil, true, found)
  eq(table.concat(paw.keyrule.lost_groups(), ", "), "", "and every named group of keys leads to keys")
end)

test("a view's own keys may not shadow a global leader key", function()
  start()
  keymap.set("<leader>mm", function() end, { view = "keyrule.test", desc = "test: the mixer taken away" })
  keymap.set("<localleader>m", function() end, { view = "keyrule.test", desc = "test: on the local leader" })
  local found = table.concat(broken(), "\n")
  keymap.del("<leader>mm", { view = "keyrule.test" })
  keymap.del("<localleader>m", { view = "keyrule.test" })
  eq(found:find("keyrule.test n <leader>mm: shadows a global leader key", 1, true) ~= nil, true, found)
  eq(found:find("<localleader>m", 1, true), nil, "the local leader is free")
  eq(paw.opt.localleader ~= paw.opt.leader, true, "the two leaders are two keys")
  eq(
    table.concat(keymap.parse("<LocalLeader>x")),
    paw.opt.localleader .. "x",
    "<LocalLeader> is expanded like <leader>"
  )
  eq(keymap.human("<localleader>d"), paw.opt.localleader .. "d", "and shown as typed")
end)

test("Escape cancels and stays in every view", function()
  start()
  local t = paw.add_part({ name = "Keys" })
  t:add_device("synth")
  local clip = t:add_clip({ name = "c", start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  api.undo_checkpoint()
  local moved = {}
  local function stays(name, open)
    open()
    if paw.ui.focused ~= name then
      moved[#moved + 1] = name .. " did not open"
      return
    end
    keymap.feed("3d<Esc>")
    keymap.feed("<Esc><Esc>")
    if paw.ui.focused ~= name then moved[#moved + 1] = name .. " -> " .. tostring(paw.ui.focused) end
    eq(keymap.pending(), "", name .. ": the count and operator are cancelled")
    eq(keymap.mode, "n", name .. ": normal mode")
    paw.ui.focus("arrange")
  end
  stays("pianoroll", function()
    paw.ui.views:get("pianoroll"):edit(clip)
    paw.ui.focus("pianoroll")
  end)
  stays("mixer", function()
    paw.ui.show("mixer")
    paw.ui.focus("mixer")
  end)
  stays("devices", function()
    paw.ui.show("devices")
    paw.ui.focus("devices")
  end)
  eq(table.concat(moved, ", "), "", "views Escape left")
  -- A second Escape soon after says how to leave.
  paw.ui.show("mixer")
  paw.ui.focus("mixer")
  keymap.feed("<Esc><Esc>")
  eq((paw.ui.message and paw.ui.message.text or ""):find("<C-w>p goes back", 1, true) ~= nil, true, "the hint")
  for _, name in ipairs({ "pianoroll", "mixer", "devices" }) do
    paw.ui.hide(name)
  end
end)

-- The mixer as a grid -----------------------------------------------------------------------

local function mixer(parts)
  start()
  local out = {}
  for i, name in ipairs(parts) do
    out[i] = paw.add_part({ name = name })
  end
  api.undo_checkpoint()
  paw.cursor.set_part(out[1])
  paw.ui.show("mixer")
  paw.ui.focus("mixer")
  paw.ui.views:get("mixer").row = "volume"
  return unpack(out)
end

test("in the mixer h l go between strips and j k along a strip's rows, which + - change", function()
  local a, b = mixer({ "A", "B" })
  b:add_device("gain")
  a:send(b, -12)
  api.undo_checkpoint()
  keys("6<C-x>")
  near(a.volume, -6, 1e-6, "6 Ctrl-x is -6 dB on the fader")
  keys("j3+")
  near(a.pan, 0.3, 1e-6, "j is the pan, 3+ three tenths right")
  waited("]")
  near(a.pan, 0.4, 1e-6, "] pans wherever the cursor is")
  keys("gg")
  eq(paw.mixer_rows.current().kind, "send", "gg is the strip's top row: its send")
  keys("2-")
  near(api.part_get(a.id).sends[1].level, -14, 1e-6, "- lowers the send")
  keys("x")
  eq(#api.part_get(a.id).sends, 0, "x clears the row: the send goes")
  keys("l")
  eq(paw.cursor.part_id(), b.id, "l is the next strip")
  eq(paw.mixer_rows.current().kind, "volume", "on the row of the same kind, else the fader: B has no send")
  keys("gg")
  eq(paw.mixer_rows.current().kind, "insert", "gg: the strip's top row, its first device")
  keys("-")
  eq(b:devices()[1].bypass, true, "- on an insert switches it off")
  keys("G")
  eq(paw.mixer_rows.current().field, "monitor", "G is the bottom row")
  keys("K")
  eq(paw.ui.hovered ~= nil, true, "K describes")
  paw.ui.close()
  paw.ui.hide("mixer")
end)

test("in the mixer operators and a selection work over strips and rows, and . repeats", function()
  local a, b, c = mixer({ "A", "B", "C" })
  keys("Vl-")
  near(a.volume, -1, 1e-6, "V over two strips: - lowers both faders")
  near(b.volume, -1, 1e-6, "the second too")
  near(c.volume, 0, 1e-6, "not the third")
  keys("2l.")
  near(c.volume, -1, 1e-6, ". does it again from the strip the cursor is on (the last: there is none after it)")
  near(b.volume, -1, 1e-6, "and not to the strips before")
  paw.cursor.set_part(a)
  keys("j5+")
  keys("kyj")
  eq(keymap.getreg().kind, "mixrows", "y over two rows yanks their settings")
  keys("lp")
  near(b.volume, a.volume, 1e-6, "p puts the fader")
  near(b.pan, 0.5, 1e-6, "and the pan on the next strip")
  keys("gcc")
  eq(api.part_get(b.id).mute, true, "gcc mutes the strip")
  keys("dj")
  near(b.volume, 0, 1e-6, "dj clears the fader")
  near(b.pan, 0, 1e-6, "and the pan")
  eq(#api.part_list(), 3, "rows are cleared, not parts")
  keys("dd")
  eq(#api.part_list(), 2, "dd cuts the strip's part, as it cuts a line")
  paw.ui.hide("mixer")
end)

-- The device panel as a grid -------------------------------------------------------------------

local function panel()
  start()
  local t = paw.add_part({ name = "Lead" })
  local synth = t:add_device("synth")
  local delay = t:add_device("delay")
  api.undo_checkpoint()
  paw.cursor.set_part(t)
  paw.ui.show("devices")
  paw.ui.focus("devices")
  paw.ui.views:get("devices").row = 1
  return t, synth, delay
end

local function param_row(device, key)
  for i, row in ipairs(paw.ui.views:get("devices"):rows()) do
    if row.param and row.device.id == device.id and row.param.key == key then return i end
  end
end

test("in the device panel w b go from device to device, + - change a parameter, gc bypasses, M r the part", function()
  local t, synth, delay = panel()
  keys("w")
  local device, row = paw.ui.views:get("devices"):selected()
  eq(device.id == delay.id and not row.param, true, "w is the next device's heading")
  keys("gcc")
  eq(api.device_get(delay.id).bypass, true, "gcc bypasses it")
  keys("Mr")
  eq(
    api.part_get(t.id).mute and api.part_get(t.id).armed,
    true,
    "M r mute and arm the panel's part, as wherever there is a part"
  )
  keys("b")
  eq(paw.ui.views:get("devices").row, 1, "b is the device before")
  paw.ui.views:get("devices").row = param_row(synth, "cutoff")
  local before = api.device_get(synth.id).params.cutoff
  keys("5<C-a>")
  local after = api.device_get(synth.id).params.cutoff
  eq(after > before, true, "5 Ctrl-a raises the parameter")
  keys(".")
  eq(api.device_get(synth.id).params.cutoff > after, true, ". does it again")
  keys("dd")
  near(
    api.device_get(synth.id).params.cutoff,
    synth:get().param_info[param_row(synth, "cutoff") - 1].default,
    1e-3,
    "dd on a parameter puts it back at its default"
  )
  paw.ui.views:get("devices").row = 1
  paw.ui.hide("devices")
end)

test("in the device panel y p copy a device's settings onto another", function()
  local t, synth = panel()
  local other = t:add_device("synth")
  api.undo_checkpoint()
  paw.ui.views:get("devices").row = param_row(synth, "cutoff")
  keys("10+")
  keys("yy")
  eq(keymap.getreg().kind, "params", "yy on a parameter yanks its setting")
  paw.ui.views:get("devices").row = param_row(other, "cutoff")
  keys("p")
  near(
    api.device_get(other.id).params.cutoff,
    api.device_get(synth.id).params.cutoff,
    1e-6,
    "p puts it on the device under the cursor"
  )
  eq(#t:devices(), 3, "no device was added")
  paw.ui.views:get("devices").row = 1
  paw.ui.hide("devices")
end)

-- The piano roll ---------------------------------------------------------------------------

test(
  "in the piano roll + - are the pitch, Alt-l Alt-h the length, and a selection takes in the note under its end",
  function()
    start()
    local t = paw.add_part({ name = "Keys" })
    local clip = t:add_clip({
      name = "c",
      start = 0,
      length = 4,
      notes = { { pitch = 60, start = 0, length = 1 }, { pitch = 60, start = 2, length = 1 } },
    })
    api.undo_checkpoint()
    local roll = paw.ui.views:get("pianoroll")
    roll:edit(clip)
    paw.ui.focus("pianoroll")
    roll:set(60, 0)
    keys("2+")
    eq(T.melody(clip), "62@0+1 60@2+1", "2+ raises the note two semitones")
    keys("<A-l>")
    eq(T.melody(clip), "62@0+1.25 60@2+1", "Alt-l lengthens it")
    keys("<C-d>")
    eq(roll.pitch, 50, "Ctrl-d is an octave down")
    roll:set(60, 2)
    keys("vd")
    eq(T.melody(clip), "62@0+1.25", "v d on a note takes the whole note")
    keymap.feed("<Esc>")
    eq(paw.ui.focused, "pianoroll", "Escape stays")
    paw.ui.hide("pianoroll")
  end
)

-- The old keys ---------------------------------------------------------------------------------

test("paw.opt.keys = classic puts the old keys back, and the default takes them away again", function()
  local a = mixer({ "A" })
  T.after(function() paw.opt.keys = "default" end)
  paw.opt.keys = "classic"
  keys("j")
  near(a.volume, -1, 1e-6, "classic: j is the fader")
  keys("<lt>")
  near(a.pan, -0.1, 1e-6, "classic: < pans")
  paw.opt.keys = "default"
  keys("j")
  near(a.volume, -1, 1e-6, "default: j moves")
  eq(paw.mixer_rows.current().kind, "pan", "to the pan row")
  eq(table.concat(broken(), "\n"), "", "and the rule holds again")
  paw.ui.hide("mixer")
end)
