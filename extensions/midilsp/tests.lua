-- Tests for extensions/midilsp, run by tests/suite.lua with its helpers.
-- Those that need MIDI LSP's engine run when one is found (paw.opt.midilsp_cmd,
-- $MIDI_LSP_ENGINE or reaper-midi-lsp on the PATH) and are skipped otherwise.
local T = ...
local eq, fresh = T.eq, T.fresh

-- Each test leaves things as the next expects them: no servers, no
-- diagnostics, the piano roll closed, whether it passed or not.
local function test(name, fn)
  T.test(name, function()
    local result = { xpcall(fn, debug.traceback) }
    paw.lsp.stop()
    paw.diagnostic.reset()
    while paw.ui.float do paw.ui.close() end
    paw.ui.views.pianoroll.clip_id = nil
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
    if not result[1] then error(result[2], 0) end
    return result[2]
  end)
end
local api = paw.api

local midilsp

local function load()
  if not midilsp then
    paw.opt.midilsp_autostart = false
    paw.ext.load("extensions/midilsp")
    midilsp = require("midilsp")
  end
  return midilsp
end

local until_ = T.until_

local function start()
  fresh()
  load()
  paw.lsp.stop()
  paw.diagnostic.reset()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do paw.ui.close() end
  paw.ui.focus("arrange")
end

local function running(name)
  for _, c in ipairs(paw.lsp.clients()) do
    if c.name == name then return c.status == "running" end
  end
end

--- Two voices moving in parallel fifths, C5 over F4 then D5 over G4, with
--- the upper one open in the piano roll.
local function fifths()
  local upper = paw.add_track({ name = "Upper" }):add_clip({ start = 0, length = 4,
    notes = { { pitch = 72, start = 0, length = 1 }, { pitch = 74, start = 1, length = 1 } } })
  paw.add_track({ name = "Lower" }):add_clip({ start = 0, length = 4,
    notes = { { pitch = 65, start = 0, length = 1 }, { pitch = 67, start = 1, length = 1 } } })
  paw.ui.views.pianoroll:edit(upper)
  return upper
end

test("midilsp: the engine is found from the option, then the environment", function()
  start()
  local saved = paw.opt.midilsp_cmd
  paw.opt.midilsp_cmd = "/opt/engine --rules /r"
  eq(table.concat(midilsp.engine(), " "), "/opt/engine --rules /r", "the option, as words")
  midilsp.configure()
  eq(table.concat(paw.lsp.configs["midi-lsp"].cmd(), " "), "/opt/engine --rules /r --stdio", "the language role on stdio")
  eq(table.concat(paw.lsp.configs["midi-lsp-suggest"].cmd(), " "), "/opt/engine --rules /r --role suggest --stdio", "and the suggestion role")
  paw.opt.midilsp_cmd = saved
  local text = {}
  for _, line in ipairs(midilsp.info_lines()) do text[#text + 1] = type(line) == "table" and line.text or line end
  eq(table.concat(text, "\n"):find("preset default", 1, true) ~= nil, true, ":midilsp shows the settings")
end)

test("midilsp: settings are kept with the project and sent as the engine takes them", function()
  start()
  midilsp.set_rule("parallel-perfect", false)
  eq(api.project_get().meta.midilsp.rules["parallel-perfect"], false, "kept in the project")
  local s = paw.lsp.configs["midi-lsp"].settings
  eq(s.preset .. " " .. tostring(s.rules["parallel-perfect"].enabled), "default false", "as the engine's configuration")
  midilsp.set_preset("strict-counterpoint")
  eq(midilsp.settings().preset, "strict-counterpoint", "a preset")
end)

test("midilsp: Problems lists every namespace's diagnostics with their fixes, and applies one", function()
  start()
  local clip = paw.add_track({ name = "Oboe" }):add_clip({ start = 0, length = 4, notes = { { pitch = 100, start = 0, length = 1 } } })
  paw.diagnostic.set("lint", clip, { { notes = { 1 }, message = "too high", fixes = { { title = "Down an octave", edits = { { note = 1, pitch = 88 } } } } } })
  paw.cmd("problems")
  local state = paw.pick.state()
  eq(#state.matches, 2, "the diagnostic and its fix")
  eq(state.matches[2]:find("fix: Down an octave", 1, true) ~= nil, true, "the fix")
  paw.keymap.feed("<C-n><CR>")
  eq(clip:notes()[1].pitch, 88, "applied")
end)

-- MIDI LSP's dialect, without the engine: the tests' range lint speaking it.
test("midilsp: any server speaking MIDI LSP's dialect works through its adapter", function()
  local python = io.popen("command -v python3 2>/dev/null"):read("*l")
  if not python or python == "" then return "no python3" end
  start()
  local clip = paw.add_track({ name = "Flute" }):add_clip({ start = 0, length = 4,
    notes = { { pitch = 60, start = 0, length = 1 }, { pitch = 96, start = 1, length = 1 } } })
  paw.ui.views.pianoroll:edit(clip)
  paw.lsp.config("range-midi", { cmd = { python, "tests/fixtures/range_lint.py", "--midi" }, adapter = "midi-lsp" })
  paw.lsp.enable("range-midi")
  until_(function() return #paw.diagnostic.get(clip.id) == 1 end, "the range diagnostic")
  local d = paw.diagnostic.get(clip.id)[1]
  eq(d.notes[1], 2, "on the second note, by its id")
  eq(d.at .. " " .. d.length, "1 1", "where, from its ticks")
  eq(paw.diagnostic.actions(clip.id, 2)[1].title, "Move C7 to C6", "its fix")
  local hover
  paw.lsp.hover(clip.id, 96, 1, function(s) hover = s end)
  until_(function() return hover end, "the hover")
  eq(hover[1].lines[1], "C7 in range-lint's eyes", "midi/hover")
  local items
  paw.lsp.complete({ clip = clip.id, at = 2 }, function(list) items = list or {} end)
  until_(function() return items end, "the suggestions")
  eq(items[1].notes[1].pitch .. " " .. items[1].notes[1].start, "60 2", "midi/completion, in the clip's beats")
  paw.lsp.stop()
end)

-- With the real engine ----------------------------------------------------------

local function engine_or_skip()
  if not load().engine() then return "no MIDI LSP engine: set $MIDI_LSP_ENGINE to run these" end
end

test("midilsp: the engine marks a parallel fifth, and its fix is one undo step", function()
  local skip = engine_or_skip()
  if skip then return skip end
  start()
  local clip = fifths()
  midilsp.start(true)
  until_(function() return #paw.diagnostic.get(clip.id, { namespace = "midi-lsp" }) > 0 end, "the engine's diagnostics")
  local d
  for _, x in ipairs(paw.diagnostic.get(clip.id)) do
    if x.rule == "parallel-perfect" then d = x end
  end
  eq(d ~= nil, true, "a parallel-perfect diagnostic")
  eq(d.message:find("Parallel fifths", 1, true) ~= nil, true, "it says so: " .. d.message)
  eq(table.concat(d.notes, ","), "1,2", "on both notes")
  eq(d.source, "midi-lsp", "from the engine")
  local marks = paw.diagnostic.roll_marks(clip.id)
  eq(#marks, 2, "the window is told to mark both")
  api.undo_checkpoint()
  local actions = paw.diagnostic.actions(clip.id, 2)
  eq(actions[1].title, "Change D5 to C5", "the engine's fix, in the key paw.harmony reads and sends")
  actions[1].run()
  paw.flush()
  api.undo_checkpoint()
  eq(clip:notes()[2].pitch, 72, "applied")
  until_(function()
    for _, x in ipairs(paw.diagnostic.get(clip.id)) do
      if x.rule == "parallel-perfect" then return false end
    end
    return true
  end, "the fifths to be gone")
  paw.undo()
  eq(clip:notes()[2].pitch, 74, "one undo takes it back")
  until_(function() return #paw.diagnostic.get(clip.id, { namespace = "midi-lsp" }) > 0 end, "the diagnostic again")
  -- The chords it hears.
  until_(function() return paw.lsp.analysis[clip.id] end, "the analysis")
  local chords = {}
  for _, c in ipairs(paw.lsp.analysis[clip.id].chords) do chords[#chords + 1] = c.name .. "@" .. c.at end
  eq(table.concat(chords, " "), "F@0 G@1", "the chords, in project beats")
  -- Switching the rule off is sent at once.
  midilsp.set_rule("parallel-perfect", false)
  until_(function()
    for _, x in ipairs(paw.diagnostic.get(clip.id)) do
      if x.rule == "parallel-perfect" then return false end
    end
    return true
  end, "the rule to be off")
  paw.lsp.stop()
end)

test("midilsp: the engine's hover and suggestions come back", function()
  local skip = engine_or_skip()
  if skip then return skip end
  start()
  local clip = fifths()
  midilsp.start(true)
  until_(function() return running("midi-lsp") and running("midi-lsp-suggest") end, "both roles")
  local hover
  paw.lsp.hover(clip.id, 74, 1, function(sections) hover = sections end)
  until_(function() return hover end, "the hover")
  eq(hover[1].client, "midi-lsp", "the language role hovers")
  local text = table.concat(hover[1].lines, "\n")
  eq(text:find("chord  G", 1, true) ~= nil and text:find("note   D5", 1, true) ~= nil, true, "the note and the chord:\n" .. text)
  local items
  paw.lsp.complete({ clip = clip.id, at = 2, trigger = "manual" }, function(list) items = list or {} end)
  until_(function() return items end, "the suggestions")
  eq(#items > 0, true, "something suggested")
  eq(items[1].source, "midi-lsp-suggest", "by the suggestion role")
  eq(#items[1].notes > 0 and items[1].notes[1].start >= 2, true, "notes from where it was asked, in the clip's beats")
  paw.lsp.stop()
end)

test("midilsp: in the terminal, a parallel fifth is marked, gone to, explained and fixed", function()
  local skip = engine_or_skip()
  if skip then return skip end
  start()
  local clip = fifths()
  local roll = paw.ui.views.pianoroll
  midilsp.start(true)
  until_(function() return #paw.diagnostic.get(clip.id, { namespace = "midi-lsp" }) > 0 end, "the engine's diagnostics")
  until_(function() return running("midi-lsp") and running("midi-lsp-suggest") and paw.lsp.settle() end, "both roles")
  roll:set(74, 0)
  -- The playhead's cap would sit where the mark is.
  paw.transport.seek(20)
  local function screen() return table.concat(api.ui_snapshot(120, 40), "\n") end
  local lines = api.ui_snapshot(120, 40)
  local text = table.concat(lines, "\n")
  -- The message after the last note it is about, on D5's row.
  local row
  for i, line in ipairs(lines) do
    if line:find("Parallel fifths between Upper and Lower", 1, true) then row = i end
  end
  eq(row ~= nil and lines[row]:find("D5", 1, true) ~= nil, true, "the message on D5's row:\n" .. text)
  -- A mark on the ruler where it starts, at the clip's first column.
  local marked = false
  for _, line in ipairs(lines) do
    if line:find("^     " .. paw.draw.g.mark) then marked = true end
  end
  eq(marked, true, "a mark on the ruler:\n" .. text)
  eq(text:find("W1", 1, true) ~= nil, true, "the status line counts it")
  -- ]d goes to its first note, [d comes round to it again.
  roll:set(60, 3)
  paw.keymap.feed("]d")
  eq(roll.pitch .. " " .. roll.beat, "72 0", "]d: the diagnostic's first note")
  paw.keymap.feed("[d")
  eq(roll.pitch .. " " .. roll.beat, "72 0", "[d: the only one, round again")
  -- gK on D5: the diagnostic and what the engine hears there.
  roll:set(74, 1)
  paw.keymap.feed("gK")
  until_(function() return paw.ui.float and paw.ui.float.name == "pager" end, "the hover float")
  text = screen()
  eq(text:find("parallel-perfect", 1, true) ~= nil and text:find("chord  G", 1, true) ~= nil, true, "the float:\n" .. text)
  paw.ui.close()
  -- :diagnostics lists it.
  paw.cmd("diagnostics")
  eq(paw.pick.state().matches[2]:find("Parallel fifths", 1, true) ~= nil, true, ":diagnostics lists it")
  while paw.ui.float do paw.ui.close() end
  -- :lsp info shows both roles running.
  paw.cmd("lsp", { "info" })
  text = screen()
  eq(text:find("midi-lsp  running", 1, true) ~= nil and text:find("midi-lsp-suggest  running", 1, true) ~= nil, true, ":lsp info:\n" .. text)
  paw.ui.close()
  -- ,ca on D5 offers the engine's fixes; Enter applies the first as one undo step.
  paw.ui.focus("pianoroll")
  roll:set(74, 1)
  api.undo_checkpoint()
  paw.keymap.feed(",ca")
  text = screen()
  eq(text:find("Change D5 to C5", 1, true) ~= nil, true, "the fixes, in the picker:\n" .. text)
  paw.keymap.feed("<CR>")
  api.undo_checkpoint()
  eq(clip:notes()[2].pitch, 72, "fixed")
  until_(function() return #paw.diagnostic.get(clip.id, { namespace = "midi-lsp" }) == 0 end, "the mark to go")
  -- (The message line may still say what ]d went to.)
  local still = false
  for _, line in ipairs(api.ui_snapshot(120, 40)) do
    if line:find("Parallel fifths", 1, true) and not line:find("warning", 1, true) then still = true end
  end
  eq(still, false, "and it is gone from the roll")
  eq(screen():find("W1", 1, true), nil, "and from the status line")
  paw.undo()
  eq(clip:notes()[2].pitch, 74, "one undo brings it back")
end)

test("midilsp: the engine's delivery and settings checks look at every render of the demo song", function()
  local skip = engine_or_skip()
  if skip then return skip end
  start()
  local checks = require("midilsp.checks")
  dofile("examples/demo-song.lua")
  paw.flush()
  checks.start()
  local path = T.scratch .. "/demo-master.wav"
  paw.render(path, { bits = 16, tail = 1 })
  local uri = paw.address.render(path)
  local function rules(ns)
    local out = {}
    for _, d in ipairs(paw.diagnostic.get(uri, { namespace = ns })) do out[d.rule] = d end
    return out
  end
  until_(function() return next(rules("midilsp-delivery")) and next(rules("midilsp-settings")) end, "both checks", 120000)
  local delivery = rules("midilsp-delivery")
  eq(delivery["delivery.integrated"] ~= nil, true, "the delivery check measured the master's loudness")
  eq(delivery["delivery.integrated"].message:find("LUFS", 1, true) ~= nil, true, delivery["delivery.integrated"].message)
  local dither = rules("midilsp-settings")["render.no_dither"]
  eq(dither ~= nil, true, "the settings check: 16 bits without dither")
  eq(dither.fixes[1].title, "Render it again with dither", "with a fix")
  -- The terminal lists them under the render.
  paw.cmd("diagnostics")
  local text = table.concat(paw.pick.state().matches, "\n")
  eq(text:find("── Renders", 1, true) ~= nil and text:find("demo-master.wav", 1, true) ~= nil, true, text)
  while paw.ui.float do paw.ui.close() end
  -- Rendered again with dither, the settings check has nothing to say about it.
  paw.diagnostic.apply(dither)
  until_(function()
    return paw.address.renders[path].opts.dither == true and next(rules("midilsp-delivery")) and rules("midilsp-settings")["render.no_dither"] == nil
  end, "the render again, checked", 120000)
  checks.stop()
end)
