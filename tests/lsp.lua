-- Tests of paw.lsp: the protocol, the document a clip becomes, and a server
-- of its own (tests/fixtures/range_lint.py, a range lint in Python) driven
-- through its whole life. Loaded by tests/suite.lua with its helpers.
local T = ...
local eq, fresh = T.eq, T.fresh

-- Each test leaves things as the next expects them: no servers, no
-- diagnostics, the piano roll closed, whether it passed or not.
local function test(name, fn)
  T.test(name, function()
    local result = { xpcall(fn, debug.traceback) }
    paw.lsp.stop()
    paw.diagnostic.reset()
    while paw.ui.float do
      paw.ui.close()
    end
    paw.ui.views:get("pianoroll").clip_id = nil
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
    if not result[1] then error(result[2], 0) end
    return result[2]
  end)
end
local api = paw.api
local rpc = require("paw.lsp.rpc")
local document = require("paw.lsp.document")
local derived = require("paw.derived")

local SERVER = "tests/fixtures/range_lint.py"

local function python()
  local found = io.popen("command -v python3 2>/dev/null"):read("*l")
  return found and found ~= "" and found or nil
end

local until_ = T.until_

local function start()
  fresh()
  paw.lsp.stop()
  for name in pairs(paw.lsp.configs:entries()) do
    paw.lsp.configs:remove(name)
  end
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
end

--- A clip on a flute track: middle C, then a C two octaves above the
--- server's range; opened in the piano roll.
local function flute()
  local t = paw.add_track({ name = "Flute" })
  local clip = t:add_clip({
    start = 4,
    length = 4,
    notes = { { pitch = 60, start = 0, length = 1 }, { pitch = 96, start = 1, length = 1 } },
  })
  paw.ui.views:get("pianoroll"):edit(clip)
  return clip
end

local function range(extra)
  paw.lsp.config(
    "range",
    paw.util.merge({ cmd = { python(), SERVER }, init_options = { lo = 48, hi = 84 } }, extra or {})
  )
  paw.lsp.enable("range")
end

local function status(name)
  for _, c in ipairs(paw.lsp.clients()) do
    if c.name == name then return c.status end
  end
end

-- The protocol ---------------------------------------------------------------

test("lsp: messages are framed as lines or with Content-Length, and read back whole however they arrive", function()
  local message =
    { jsonrpc = "2.0", id = 3, method = "midi/hover", params = { tick = 960, pitch = 60.0, name = 'é "q"\n' } }
  for _, framing in ipairs({ "lines", "headers" }) do
    local bytes = rpc.frame(message, framing)
      .. rpc.frame({ jsonrpc = "2.0", method = "initialized", params = rpc.object() }, framing)
    local reader, got = rpc.reader(framing), {}
    for i = 1, #bytes, 7 do
      for _, m in ipairs(reader:push(bytes:sub(i, i + 6))) do
        got[#got + 1] = m
      end
    end
    eq(#got, 2, framing .. ": two messages")
    eq(got[1].params.name, 'é "q"\n', framing .. ": text survives")
    eq(got[1].params.pitch, 60, framing .. ": numbers survive")
    eq(paw.json.encode(got[2].params), "{}", framing .. ": an empty object stays an object")
  end
  eq(rpc.encode({ 960, 0.5, {} }), "[960,0.5,[]]", "whole numbers are written as integers")
  eq(rpc.reader("lines"):push("not json\n")[1].invalid, "not json", "what is not JSON is said so")
end)

test("lsp: a clip becomes MIDI LSP's document, with what sounds with it", function()
  start()
  paw.tempo.set(0, 100)
  local clip = flute()
  local bass = paw.add_track({ name = "Bass" })
  bass:add_clip({
    start = 2,
    length = 8,
    notes = { { pitch = 36, start = 3, length = 2 }, { pitch = 40, start = 7, length = 1 } },
  })
  paw
    .add_track({ name = "Drums" })
    :add_clip({ start = 4, length = 4, notes = { { pitch = 36, start = 0, length = 0.25 } } })
  paw.harmony.set_key("D harmonic minor")
  paw.flush()
  local doc = document.build(clip.id)
  eq(doc.uri, "paw://clip/" .. clip.id, "named by the clip")
  eq(doc.hash, document.key_of(clip.id), "under its key")
  eq(doc.ppq, 960, "ticks to the beat")
  eq(#doc.notes, 2, "its notes")
  eq(
    string.format(
      "%d %d %d %d %d",
      doc.notes[2].id,
      doc.notes[2].pitch,
      doc.notes[2].start,
      doc.notes[2]["end"],
      doc.notes[2].vel
    ),
    clip:notes()[2].id .. " 96 960 1920 100",
    "the second note: its own id, ticks from the clip's start"
  )
  eq(doc.track.name, "Flute", "the track")
  eq(doc.key.root .. " " .. doc.key.scale, "2 harmonic minor", "the project's key")
  eq(doc.tempi[1].bpm, 100, "the tempo")
  eq(doc.barStart, 0, "it starts on a bar line")
  eq(#doc.context, 2, "two other tracks sound with it")
  local by = {}
  for _, c in ipairs(doc.context) do
    by[c.track.name] = c
  end
  eq(#by.Bass.notes, 1, "the bass note that overlaps it")
  eq(by.Bass.notes[1].start, 960, "in this clip's ticks")
  eq(by.Drums.track.tag, "drums", "drums say so")
  local before = doc.hash
  clip:set_note(1, { pitch = 62 })
  paw.flush()
  eq(document.key_of(clip.id) ~= before, true, "an edit changes the key")
  eq(document.clip_of(doc.uri), clip.id, "the URI names the clip again")
end)

test("lsp: an edit of a clip that does not overlap the document keeps its key, and lists no clips", function()
  start()
  local clip = flute()
  local bass = paw.add_track({ name = "Bass" })
  local under = bass:add_clip({ start = 2, length = 8, notes = { { pitch = 36, start = 3, length = 2 } } })
  local far = bass:add_clip({ start = 32, length = 4, notes = { { pitch = 40, start = 0, length = 1 } } })
  paw.flush()
  local before = document.key_of(clip.id)
  far:set_note(1, { pitch = 43 })
  paw.flush()
  -- The edit is taken in in slices, as after a pause of the keys.
  derived.run()
  local lists, clip_list = 0, api.clip_list
  api.clip_list = function(...)
    lists = lists + 1
    return clip_list(...)
  end
  local ok, key = pcall(document.key_of, clip.id)
  api.clip_list = clip_list
  assert(ok, key)
  eq(key, before, "the key is as it was")
  eq(lists, 0, "no list of clips is read")
  under:set_note(1, { pitch = 38 })
  paw.flush()
  eq(document.key_of(clip.id) ~= before, true, "an edit of a clip under it changes the key")
end)

-- A server of the tests' own -------------------------------------------------------

test("lsp: a server is sent the piano roll's clip, and its diagnostics land on the notes", function()
  if not python() then return "no python3" end
  start()
  local clip = flute()
  range()
  until_(function() return #paw.diagnostic.get(clip.id) == 1 end, "the range diagnostic")
  eq(status("range"), "running", "running")
  local d = paw.diagnostic.get(clip.id)[1]
  eq(d.notes[1], 2, "on the second note")
  eq(d.severity, paw.diagnostic.severity.WARN, "a warning")
  eq(d.source .. " " .. d.rule, "range-lint range", "from the server, with its rule")
  eq(d.message, "C7 is outside C3-C6", "what it says")
  eq(d.at .. " " .. d.length, "1 1", "where, in the clip's beats")
  eq(paw.lsp.clients()[1].documents[1], clip.id, "the clip is open in the server")
  -- An edit is sent, and what the server says then replaces what it said.
  clip:set_note(2, { pitch = 72 })
  paw.flush()
  T.advance_until(function() return #paw.diagnostic.get(clip.id) == 0 end, "the diagnostic to go", 5000)
  paw.lsp.stop()
  eq(#paw.lsp.clients(), 0, "stopped")
end)

test("lsp: a server's fix changes the notes in one undo step", function()
  if not python() then return "no python3" end
  start()
  local clip = flute()
  range()
  until_(function() return #paw.diagnostic.get(clip.id) == 1 end, "the range diagnostic")
  api.undo_checkpoint()
  local actions = paw.diagnostic.actions(clip.id, 2)
  eq(#actions, 1, "one fix for the note")
  eq(actions[1].title, "Move C7 to C6", "named by the server")
  actions[1].run()
  paw.flush()
  api.undo_checkpoint()
  eq(clip:notes()[2].pitch, 84, "moved an octave down")
  paw.undo()
  eq(clip:notes()[2].pitch, 96, "one undo takes it back")
  paw.lsp.stop()
end)

test("lsp: the fixes are offered at the cursor with <leader>la, and Enter applies one", function()
  if not python() then return "no python3" end
  start()
  local clip = flute()
  range()
  until_(function() return #paw.diagnostic.get(clip.id) == 1 end, "the range diagnostic")
  paw.ui.views:get("pianoroll"):set(96, 1)
  paw.keymap.feed("<leader>la")
  eq(paw.pick.state().matches[1]:find("Move C7 to C6", 1, true) ~= nil, true, "the fix is offered")
  paw.keymap.feed("<CR>")
  eq(clip:notes()[2].pitch, 84, "and applied")
  paw.lsp.stop()
end)

test("lsp: a server speaking Content-Length headers works the same", function()
  if not python() then return "no python3" end
  start()
  local clip = flute()
  paw.lsp.config("range", { cmd = { python(), SERVER, "--headers" }, framing = "headers" })
  paw.lsp.enable("range")
  until_(function() return #paw.diagnostic.get(clip.id) == 1 end, "the range diagnostic")
  paw.lsp.stop()
end)

test("lsp: hover shows what the server says about the note", function()
  if not python() then return "no python3" end
  start()
  local clip = flute()
  range()
  until_(function() return #paw.diagnostic.get(clip.id) == 1 end, "the server to answer")
  local got
  paw.lsp.hover(clip.id, 96, 1, function(sections) got = sections end)
  until_(function() return got end, "the hover")
  eq(got[1].client, "range", "from the server")
  eq(got[1].lines[1], "C7 in range-lint's eyes", "what it said")
  paw.ui.views:get("pianoroll"):set(96, 1)
  paw.ui.focus("pianoroll")
  paw.keymap.feed("gK")
  until_(function() return paw.ui.float and paw.ui.float.name == "pager" end, "the float")
  local screen = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(screen:find("C7 in range-lint's eyes", 1, true) ~= nil, true, "the float shows the hover")
  eq(screen:find("C7 is outside C3-C6", 1, true) ~= nil, true, "and the diagnostic about the note")
  paw.ui.close()
  paw.lsp.stop()
end)

test("lsp: a server's suggestions come back as completion items", function()
  if not python() then return "no python3" end
  start()
  local clip = flute()
  range()
  until_(function() return status("range") == "running" end, "the server")
  local items
  paw.lsp.complete({ clip = clip.id, at = 2, trigger = "manual" }, function(list) items = list or {} end)
  until_(function() return items end, "the suggestions")
  eq(#items, 1, "one item")
  eq(items[1].source, "range", "from the server")
  local n = items[1].notes[1]
  eq(string.format("%d %g %g %d", n.pitch, n.start, n.length, n.velocity), "60 2 1 90", "a note in the clip's beats")
  paw.lsp.stop()
end)

test("lsp: settings that change are sent to the server, and what it says follows", function()
  if not python() then return "no python3" end
  start()
  local clip = flute()
  range()
  until_(function() return #paw.diagnostic.get(clip.id) == 1 end, "the range diagnostic")
  paw.lsp.config("range", { settings = { hi = 100 } })
  until_(function() return #paw.diagnostic.get(clip.id) == 0 end, "the wider range")
  paw.lsp.stop()
end)

test("lsp: attach filters which clips a server is sent", function()
  if not python() then return "no python3" end
  start()
  local clip = flute()
  range({ attach = { tracks = { "Violin*" } } })
  until_(function() return status("range") == "running" end, "the server")
  eq(paw.lsp.settle(), true, "settled")
  eq(#paw.lsp.clients()[1].documents, 0, "a flute is not sent to a server for violins")
  eq(#paw.diagnostic.get(clip.id), 0, "so nothing is said about it")
  paw.lsp.stop()
end)

test("lsp: a server that dies is restarted as its config allows, and its diagnostics go", function()
  if not python() then return "no python3" end
  start()
  flute()
  paw.lsp.config("range", { cmd = { python(), SERVER, "--crash" }, restart = { max = 1, within_s = 60 } })
  paw.lsp.enable("range")
  local function deaths()
    local n = 0
    for _, line in ipairs(paw.lsp.log) do
      if line:find("^range dead") then n = n + 1 end
    end
    return n
  end
  T.advance_until(function() return deaths() == 2 end, "a death, a restart and a second death", 10000)
  paw.wait(700)
  eq(deaths(), 2, "not restarted a second time")
  eq(status("range"), "dead", "left dead")
  eq(#paw.diagnostic.get(), 0, "nothing said")
  local info = table.concat(
    (function()
      local out = {}
      for _, l in ipairs(paw.lsp.info_lines()) do
        out[#out + 1] = type(l) == "table" and l.text or l
      end
      return out
    end)(),
    "\n"
  )
  eq(info:find("range  dead", 1, true) ~= nil, true, ":lsp info says so")
  paw.lsp.stop()
end)

test("lsp: a server that cannot be started is said to be dead, with the reason", function()
  start()
  paw.lsp.config("nothing", { cmd = { "/nonexistent/server" } })
  paw.lsp.enable("nothing")
  eq(status("nothing"), "dead", "dead")
  eq(paw.lsp.clients()[1].error:find("/nonexistent/server", 1, true) ~= nil, true, "with the reason")
  paw.cmd("lsp", { "info" })
  eq(paw.ui.float and paw.ui.float.name, "pager", ":lsp info opens")
  paw.ui.close()
  paw.lsp.stop()
end)
