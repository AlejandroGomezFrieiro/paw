-- Robustness of the kernel's interface: values out of range, big projects,
-- and what is said when something cannot be done. tests/api_boundary.lua
-- gives wrong arguments to every `paw.api` function.
local T = ...
local eq, fresh = T.eq, T.fresh
local paw = require("paw")
local api = paw.api

-- These tests say a great deal. What they said is forgotten after each, so
-- that the list of messages (500 at most) has room for the tests after
-- them, which count what is added to it.
local function test(name, fn)
  T.test(name, function()
    T.after(function()
      local messages = paw.ui.messages
      for i = #messages, 1, -1 do
        messages[i] = nil
      end
    end)
    return fn()
  end)
end

test("ui_caps_set takes a table and says so when it is given something else", function()
  local before = api.ui_caps()
  for _, bad in ipairs({ 1, "abc", true }) do
    local ok, err = pcall(api.ui_caps_set, bad)
    eq(ok, false, "refused: " .. tostring(bad))
    eq(tostring(err):find("takes a table", 1, true) ~= nil, true, tostring(err))
  end
  api.ui_caps_set({})
  api.ui_caps_set({ cell = 3 })
  api.ui_caps_set(before)
end)

-- What the screen said last, at a level.
local function said(level)
  for i = #paw.ui.messages, 1, -1 do
    local m = paw.ui.messages[i]
    if not level or m.level == level then return m.text end
  end
  return ""
end

local function has(text, part, what)
  eq(tostring(text):find(part, 1, true) ~= nil, true, (what or "message") .. ": " .. tostring(text))
end

test("an option takes values of its type and range, and :set says what it takes", function()
  fresh()
  local grid = paw.opt.grid
  T.keys(":set grid=abc<CR>")
  has(said("error"), 'grid takes a number from 0.0078125 to 64, not "abc"', ":set grid=abc")
  eq(paw.opt.grid, grid, "and grid keeps what it had")
  for _, bad in ipairs({ 0, -1, 1e-9, 1e300, 0 / 0, "2", true }) do
    local ok, err = pcall(function() paw.opt.grid = bad end)
    eq(ok, false, "grid = " .. tostring(bad) .. " is refused")
    has(err, "grid takes a number", "grid = " .. tostring(bad))
  end
  eq(paw.opt.grid, grid, "grid unchanged")
  paw.add_track({ name = "Steps" })
  T.keys(":set grid=0.5<CR>")
  eq(paw.opt.grid, 0.5, ":set grid=0.5")
  T.keys("l")
  eq(paw.cursor.beat, 0.5, "and l steps by it")
  paw.opt.grid = grid
  T.keys(":set track_height=3<CR>")
  eq(paw.opt.track_height, 3, 'a number where "auto" is the default')
  T.keys(":set track_height=auto<CR>")
  eq(paw.opt.track_height, "auto", '"auto" again')
  T.keys(":set track_height=40<CR>")
  has(said("error"), 'track_height takes a whole number from 1 to 12, or "auto"', "out of range")
  local ffmpeg = paw.opt.ffmpeg
  T.keys(":set ffmpeg=7<CR>")
  eq(paw.opt.ffmpeg, "7", "text stays text for an option that takes text")
  paw.opt.ffmpeg = ffmpeg
  paw.option.define("zz_lanes", 4, { min = 1, max = 16, integer = true })
  T.fails(
    function() paw.opt.zz_lanes = 2.5 end,
    "zz_lanes takes a whole number from 1 to 16",
    "an extension's own range"
  )
  paw.opt.zz_lanes = 16
  eq(paw.opt.zz_lanes, 16, "in range is taken")
  paw.opt.zz_free = { 1 }
  eq(paw.opt.zz_free[1], 1, "an option nobody defined takes anything")
end)

local function step()
  local tree = api.undo_tree()
  for _, s in ipairs(tree.states) do
    if s.id == tree.current then return s end
  end
end

test("an undo step is named by what changed the project, and a command line by the line", function()
  T.three_clips()
  T.keys("x")
  local x = step().label
  eq(x ~= nil, true, "x names its step")
  paw.undo()
  T.keys("ggGx")
  eq(step().label, x, "a motion before it in the same turn leaves the name to x")
  T.keys(":%d<CR>")
  eq(step().label, ":%d", "a command line is named by the line")
  paw.undo()
  T.keys(":track.add<CR>")
  eq(step().label, ":track.add", "a command without a range too")
  for _, s in ipairs(api.undo_tree().states) do
    eq(s.label ~= "Type a command" and s.keys ~= "<CR>", true, "no step is named by the keys that typed a line")
  end
end)

test("setting a value to what it already is makes no undo step", function()
  fresh()
  local t = paw.add_track({ name = "Same" })
  local clip = t:add_clip({ start = 4, length = 4 })
  t.volume = -6
  paw.project.meta = { a = 1 }
  api.undo_checkpoint()
  local before = #api.undo_tree().states
  t.volume = -6
  t.name = "Same"
  clip.start = 4
  paw.project.tempo = paw.project.tempo
  paw.project.meta = { a = 1 }
  api.tempo_set(0, paw.project.tempo)
  api.undo_checkpoint()
  eq(#api.undo_tree().states, before, "no step")
  eq(api.undo_tree().pending, false, "and nothing pending")
  t.volume = -5
  api.undo_checkpoint()
  eq(#api.undo_tree().states, before + 1, "a real change is a step")
end)

test("commands given what they cannot take say so and change nothing", function()
  fresh()
  local a = paw.add_track({ name = "A" })
  paw.add_track({ name = "B" })
  paw.cursor.set_track(a)
  local tempo = paw.project.tempo
  T.expect_error("^a tempo is from 1 to 999 bpm")
  T.expect_error("^track.remove removes the track at the cursor and takes no argument")
  T.expect_error("^clip.add puts a clip at the cursor and takes length= and name=")
  T.expect_error("^a clip's length is a number of beats above 0")
  for _, line in ipairs({ "tempo abc", "tempo 0", "tempo -1", "tempo by=abc" }) do
    T.keys(":" .. line .. "<CR>")
    has(said("error"), "a tempo is from 1 to 999 bpm", ":" .. line)
  end
  eq(paw.project.tempo, tempo, "the tempo is as it was")
  T.keys(":tempo 133<CR>")
  eq(paw.project.tempo, 133, ":tempo 133 sets it")
  has(said("info"), "133 bpm", "and says so")
  for _, line in ipairs({ "track.remove 99", "track.remove abc" }) do
    T.keys(":" .. line .. "<CR>")
    has(said("error"), "takes no argument", ":" .. line)
  end
  eq(#paw.tracks(), 2, "no track was removed")
  for line, why in pairs({
    ["clip.add -1 4"] = "takes length= and name=",
    ["clip.add abc"] = "takes length= and name=",
    ["clip.add length=-4"] = "not -4",
    ["clip.add length=0"] = "not 0",
    ["clip.add length=abc"] = "not abc",
  }) do
    T.keys(":" .. line .. "<CR>")
    has(said("error"), why, ":" .. line .. " is refused")
  end
  eq(#a:clips(), 0, "no clip was made")
  T.fails(
    function() T.render({ rate = -5 }) end,
    "a sample rate is a whole number of Hz from 8000 to 384000, not %-5",
    "rate=-5"
  )
  a:add_clip({ start = 0, length = 1 })
  T.fails(function() T.render({ tail = 1e9 }) end, "tail is at most 600 seconds", "an absurd tail")
end)

test("stems add up to the mix with buses and returns on the way", function()
  fresh()
  local ffi = require("ffi")
  local function samples(path)
    local data = T.read_file(path)
    local at = data:find("data", 1, true) + 8
    local n = math.floor((#data - at + 1) / 4)
    local buf = ffi.new("float[?]", n)
    ffi.copy(buf, data:sub(at, at + n * 4 - 1), n * 4)
    return buf, n
  end
  local bus = paw.add_track({ name = "Bus" })
  bus.volume = -6
  local ret = paw.add_track({ name = "Return" })
  ret.volume = -3
  T.tone("A", 4, "A3").output = bus.id
  T.tone("C", 4, "E4"):send(ret, -6)
  local d = T.tone("D", 4, "C5")
  d:send(ret, -3)
  d.volume = -4
  paw.flush()
  local mix = T.render({ master = false, bits = 32, tail = 0 })
  local files = {}
  paw.export.run(paw.export.plan(T.scratch .. "/bus-stems/ each=track tap=groups bits=32 tail=0 wait=true"))
  for i, r in ipairs(paw.export.last().results) do
    files[i] = r.path
  end
  eq(#files, 3, "a stem for each track with clips")
  local m, n = samples(mix.path)
  local sum = {}
  for i = 0, n - 1 do
    sum[i] = 0
  end
  for _, f in ipairs(files) do
    local x, k = samples(f)
    for i = 0, math.min(n, k) - 1 do
      sum[i] = sum[i] + x[i]
    end
  end
  local worst = 0
  for i = 0, n - 1 do
    worst = math.max(worst, math.abs(sum[i] - m[i]))
  end
  eq(worst < 1e-5, true, "they add up to the mix: " .. worst)
end)

test("a MIDI file cut short does not open as an empty project", function()
  fresh()
  paw.add_track({ name = "Keep" })
  api.undo_checkpoint()
  -- A header that promises a track, and the track cut off after its start.
  local path = T.scratch .. "/cut.mid"
  T.write_file(path, "MThd\0\0\0\6\0\1\0\1\1\224MTrk\0\0\1\0\0\255")
  T.keys(":open! " .. path .. "<CR>")
  eq(paw.tracks()[1] and paw.tracks()[1].name, "Keep", "the project is as it was")
  has(said("error"), "no notes", "and it says why")
end)

test("thousands of tracks and the warnings they bring stay usable", function()
  fresh()
  for i = 1, 1200 do
    api.track_add({ name = "T" .. i })
  end
  local said_count, notify = 0, paw.notify
  paw.notify = function(...)
    said_count = said_count + 1
    return notify(...)
  end
  T.after(function() paw.notify = notify end)
  paw.flush()
  paw.notify = notify
  eq(said_count >= 2 and said_count <= 6, true, "a few warnings and how many more, not hundreds: " .. said_count)
  eq(#paw.tracks(), 1200, "paw.tracks() lists them all")
  eq(#api.track_list(), 1200, "and so does the api")
  fresh()
end)

test("muting twice says the second time that they were muted already", function()
  fresh()
  for i = 1, 4 do
    paw.add_track({ name = "M" .. i })
  end
  T.keys(":t2,t4 mute<CR>")
  eq(said("info"), "muted 3 tracks", "the first time")
  T.keys(":t2,t4 mute<CR>")
  eq(said("info"), "3 tracks were muted already", "the second time")
  T.keys(":t1,t2 mute<CR>")
  eq(said("info"), "muted 1 track (1 was already)", "some of them")
end)

test("a yank and a paste say how many beats they took, in the singular for one", function()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  local t = paw.add_track({ name = "Lead" })
  t:add_clip({ name = "tune", start = 16, length = 16, notes = { { pitch = 60, start = 0, length = 1 } } })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(20)
  paw.opt.grid, paw.opt.ripple = 1, false
  api.undo_checkpoint()
  T.keys("vicy")
  eq(said("info"), "yanked 16 beats", "the yank of a clip of 16 beats")
  T.keys("0P")
  eq(said("info"), "pasted 16 beats", "and its paste")
  eq(T.layout(t), "tune@0+16 tune@16+16", "which put the clip at the start")
  paw.cursor.set_beat(40)
  T.keys("vy")
  eq(said("info"), "yanked 1 beat", "one beat")
  T.keys("P")
  eq(said("info"), "pasted 1 beat", "and its paste")
end)

test("Ctrl-^ goes back to what the window showed before, from a text buffer too", function()
  fresh()
  paw.add_track({ name = "Back" })
  T.keys(":e paw://tracks<CR>")
  eq(paw.layout.buf_of(paw.layout.current()).name, "paw://tracks", ":e shows the listing here")
  T.keys("<C-^>")
  eq(paw.layout.current().view, "arrange", "Ctrl-^ goes back to the arrange view")
  T.keys(":b #<CR>")
  eq(paw.layout.buf_of(paw.layout.current()).name, "paw://tracks", ":b # goes to the listing again")
  T.keys("<C-^>")
  eq(paw.layout.current().view, "arrange", "and back")
end)

test(":vimgrep takes % as Vim does, for the whole project", function()
  fresh()
  paw.add_track({ name = "Lead g3" })
  paw.add_track({ name = "Bass" })
  T.keys(":vimgrep /g3/j %<CR>")
  local list = paw.qf.current(paw.qf.stack())
  eq(list and #list.entries, 1, "found with % as without")
end)

test(":query in a tab narrowed to a group sees that group, as Ex ranges do", function()
  fresh()
  local a, b = paw.add_track({ name = "Violins" }), paw.add_track({ name = "Cellos" })
  paw.add_track({ name = "Drums" })
  paw.groups.make({ a, b }, "Strings")
  paw.flush()
  eq(#paw.query("track"), 4, "the whole song: the group and its tracks, and the drums")
  paw.scope.narrow("Strings")
  local names = {}
  for _, n in ipairs(paw.query("track")) do
    names[#names + 1] = n.data.name
  end
  eq(table.concat(names, " "), "Strings Violins Cellos", "narrowed: the group's")
  paw.scope.widen()
end)

test("a Lua device that fails or hangs in a render is ended as soon as it would be live", function()
  fresh()
  local dir = T.scratch .. "/failing-devices"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(
    dir .. "/zz_fails.lua",
    [[
local dev = require("paw.dsp").device { name = "Fails" }
local n = 0
function dev.process(b) n = n + 1 if n > 3 then error("broken") end end
return dev
]]
  )
  T.write_file(
    dir .. "/zz_hangs.lua",
    [[
local dev = require("paw.dsp").device { name = "Hangs" }
local n = 0
function dev.process(b) n = n + 1 if n > 3 then while true do end end end
return dev
]]
  )
  paw.luadev.add_dir(dir)
  for _, kind in ipairs({ "lua:zz_fails", "lua:zz_hangs" }) do
    fresh()
    local t = T.tone("T", 8)
    t:add_device(kind)
    paw.flush()
    local info = T.render({ tail = 0 })
    eq(info.peak > 0, true, kind .. ": the rest was rendered without it")
  end
  fresh()
end)
