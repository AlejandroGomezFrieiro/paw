-- Tests of completion (`paw.complete`): sources, requests and their
-- deadlines, the ghost notes in the piano roll and the keys that take them.
-- The sources here are made for the tests: one that answers at once, one
-- that answers late, one that never does, ones that fail. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local eq = T.eq
local api = paw.api
local complete = paw.complete
local roll = paw.ui.views:get("pianoroll")

local log = {}

--- A test with only its own sources (the runtime's own, such as `paw.lsp`'s,
--- are put back after), that leaves the piano roll closed and the arrange
--- view focused, as the tests after it expect, however it ends.
local function test(name, fn)
  T.test(name, function()
    local others = {}
    for source_name, spec in pairs(complete.sources:entries()) do
      others[source_name] = spec
    end
    for source_name in pairs(others) do
      complete.unregister(source_name)
    end
    local ok, err = xpcall(fn, debug.traceback)
    for _, spec in pairs(others) do
      complete.register(spec)
    end
    complete.dismiss()
    paw.keymap.feed("<Esc><Esc>")
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
    if not ok then error(err, 0) end
  end)
end

local function n(pitch, start, length) return { pitch = pitch, start = start, length = length or 1 } end

--- A source that answers at once with `items` (a list, or a function of the context).
local function fixed(name, items, priority)
  return {
    name = name,
    priority = priority or 0,
    complete = function(ctx, done)
      log[#log + 1] = name .. " asked " .. ctx.trigger
      done(type(items) == "function" and items(ctx) or items)
    end,
  }
end

--- A source that answers after `ms`, and notes when it is cancelled.
local function slow(name, ms, items, priority)
  return {
    name = name,
    priority = priority or 0,
    complete = function(ctx, done)
      log[#log + 1] = name .. " asked " .. ctx.id
      paw.defer(function() done(type(items) == "function" and items(ctx) or items) end, ms)
    end,
    cancel = function(ctx) log[#log + 1] = name .. " cancelled " .. ctx.id end,
  }
end

--- A track with a clip of four notes open in the piano roll, the cursor
--- after them.
local function start()
  T.fresh()
  complete.dismiss()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  log = {}
  local t = paw.add_track({ name = "Lead" })
  local clip = t:add_clip({ start = 0, length = 4, notes = { n(60, 0), n(62, 1), n(64, 2), n(65, 3) } })
  roll:edit(clip)
  roll:set(65, 4)
  paw.flush()
  api.undo_checkpoint()
  return t, clip
end

--- Run `fn` with the sources registered and the options set, taking them
--- away afterwards whatever happens.
local function with(sources, opts, fn)
  local saved = {}
  for name, value in pairs(opts) do
    saved[name] = paw.opt[name]
  end
  paw.opt.complete_auto = false
  for name, value in pairs(opts) do
    paw.opt[name] = value
  end
  for _, s in ipairs(sources) do
    complete.register(s)
  end
  local ok, err = xpcall(fn, debug.traceback)
  for _, s in ipairs(sources) do
    complete.unregister(s.name)
  end
  complete.dismiss()
  paw.opt.complete_auto = true
  for name, value in pairs(saved) do
    paw.opt[name] = value
  end
  if not ok then error(err, 0) end
end

local function screen() return table.concat(api.ui_snapshot(120, 40), "\n") end

local function shown_notes()
  local cur = complete.current()
  if not cur then return "" end
  local out = {}
  for i, x in ipairs(cur.item.notes) do
    out[i] = string.format("%d@%g", x.pitch, x.start)
  end
  return table.concat(out, " ")
end

local next_bar =
  { { label = "rise", notes = { n(67, 4), n(69, 5) } }, { label = "fall", notes = { n(64, 4), n(62, 5) } } }

test("without a source nothing is suggested and the piano roll's keys are as they were", function()
  start()
  eq(complete.request("manual"), nil, "nobody to ask")
  eq(complete.current(), nil, "nothing shows")
  eq(roll:subscope(), nil, "no keys of its own")
  paw.keymap.feed("<Esc>")
  eq(paw.ui.focused, "pianoroll", "Escape stays in the piano roll, as in every view")
end)

test("a suggestion shows as ghost notes with its badge and changes nothing in the project", function()
  local _, clip = start()
  with({ fixed("fixed", next_bar) }, {}, function()
    local edits, before = api.project_get().edits, T.melody(clip)
    paw.keymap.feed("<C-Space>")
    eq(shown_notes(), "67@4 69@5", "the first alternative shows")
    eq(log[1], "fixed asked manual", "the source was asked by the key")
    local text = screen()
    eq(text:find("1/2 fixed: rise", 1, true) ~= nil, true, "the badge says which of how many, from where")
    eq(text:find("G4", 1, true) ~= nil, true, "the ghost notes are drawn with their names")
    local line = paw.ui.keybar.entries()
    eq(line[1] and line[1][1] .. " " .. line[1][2], "Tab accept", "the key line says how to take it")
    eq(#paw.ui.keybar.check(), 0, "and every key it shows is mapped")
    eq(T.melody(clip), before, "the clip is as it was")
    eq(api.project_get().edits, edits, "and nothing was edited")
  end)
end)

test("the terminal's piano roll draws ghost notes dashed on their rows, under a badge kept on screen", function()
  start()
  local function line_of(lines, text)
    for i, l in ipairs(lines) do
      if l:find(text, 1, true) then return i end
    end
  end
  with({ fixed("fixed", next_bar) }, {}, function()
    paw.keymap.feed("<C-Space>")
    local lines = api.ui_snapshot(120, 40)
    local g, a, badge = line_of(lines, "G4┄"), line_of(lines, "A4┄"), line_of(lines, "1/2 fixed: rise")
    eq(g ~= nil and a ~= nil, true, "both ghost notes, named and dashed")
    eq(g - a, 2, "each on its pitch's row: A4 two rows above G4")
    eq(badge, a - 1, "the badge on the row above the highest")
    paw.keymap.feed("<C-n>")
    lines = api.ui_snapshot(120, 40)
    eq(line_of(lines, "2/2 fixed: fall") ~= nil and line_of(lines, "E4┄") ~= nil, true, "Ctrl-n draws the other")
    paw.keymap.feed("<Esc>")
    eq(line_of(api.ui_snapshot(120, 40), "┄"), nil, "Esc takes it all away")
  end)
  with({ fixed("high", { { label = "high", notes = { n(120, 4) } } }) }, {}, function()
    complete.request()
    eq(screen():find("1/1 high", 1, true) ~= nil, true, "a badge for notes above the screen stays on it")
  end)
end)

test("tab accepts the whole suggestion as one undo step", function()
  local _, clip = start()
  with({ fixed("fixed", { { label = "on", notes = { n(67, 4), n(69, 5, 2), n(71, 7) } } }) }, {}, function()
    local before = T.melody(clip)
    paw.keymap.feed("<C-Space>")
    T.keys("<Tab>")
    eq(T.melody(clip), before .. " 67@4+1 69@5+2 71@7+1", "every note is written")
    eq(clip.length, 8, "the clip grew to hold them, by whole bars")
    eq(complete.current(), nil, "and the suggestion is gone")
    eq(roll.beat, 8, "the cursor is where they end")
    paw.undo()
    eq(T.melody(clip), before, "one undo takes all of it away")
    eq(clip.length, 4, "the clip's length too")
  end)
end)

test("ctrl-l accepts exactly the next onset, a chord or a note, and the rest stays", function()
  local _, clip = start()
  local item = { label = "on", notes = { n(62, 5), n(60, 4), n(64, 4), n(67, 4), n(65, 5.5) } }
  with({ fixed("fixed", { item, { label = "other", notes = { n(48, 4) } } }) }, {}, function()
    local before = T.melody(clip)
    paw.keymap.feed("<C-Space>")
    T.keys("<C-l>")
    eq(T.melody(clip), before .. " 60@4+1 64@4+1 67@4+1", "the chord that starts first, whole")
    eq(shown_notes(), "62@5 65@5.5", "the rest still shows")
    eq(#complete.current().items, 1, "alone, without the other alternatives")
    eq(roll.beat, 5, "the cursor waits where the rest begins")
    T.keys("<C-l>")
    eq(T.melody(clip), before .. " 60@4+1 64@4+1 67@4+1 62@5+1", "then one note")
    T.keys("<C-l>")
    eq(complete.current(), nil, "the last one ends the suggestion")
    paw.undo()
    eq(T.melody(clip), before .. " 60@4+1 64@4+1 67@4+1 62@5+1", "each part is an undo step of its own")
  end)
end)

test("alternatives are stepped through with ctrl-n and ctrl-p and picked with alt and a digit", function()
  start()
  local three = { next_bar[1], next_bar[2], { label = "stay", notes = { n(65, 4) } } }
  with({ fixed("fixed", three) }, {}, function()
    complete.request()
    paw.keymap.feed("<C-n>")
    eq(complete.current().index, 2, "the next")
    paw.keymap.feed("<C-n><C-n>")
    eq(complete.current().index, 1, "round past the last")
    paw.keymap.feed("<C-p>")
    eq(complete.current().index, 3, "and back past the first")
    paw.keymap.feed("<A-2>")
    eq(shown_notes(), "64@4 62@5", "Alt-2 shows the second")
    paw.keymap.feed("<A-9>")
    eq(complete.current().index, 2, "a digit with no alternative does nothing")
  end)
end)

test("escape dismisses the suggestion before it leaves insert mode", function()
  start()
  with({ fixed("fixed", next_bar) }, {}, function()
    paw.keymap.feed("i<C-Space>")
    eq(complete.current() ~= nil, true, "shows in insert mode")
    paw.keymap.feed("<Esc>")
    eq(complete.current(), nil, "the first Escape dismisses it")
    eq(paw.keymap.mode, "i", "and stays in insert mode")
    paw.keymap.feed("<Esc>")
    eq(paw.keymap.mode, "n", "the second leaves insert mode")
    paw.keymap.feed("<C-Space><C-e>")
    eq(complete.current(), nil, "Ctrl-e dismisses too")
    paw.keymap.feed("<C-Space><Esc>")
    eq(paw.ui.focused, "pianoroll", "in normal mode Escape dismisses first")
    paw.keymap.feed("<Esc>")
    eq(paw.ui.focused, "pianoroll", "and the next stays in the piano roll, as in every view")
  end)
end)

test("a request shows what came by the deadline and adds late answers at the end", function()
  start()
  local sizes = {}
  local id = paw.on("complete.changed", function()
    local cur = complete.current()
    sizes[#sizes + 1] = cur and #cur.items or 0
  end)
  with(
    { fixed("quick", { next_bar[1] }), slow("late", 900, { next_bar[2] }, 100) },
    { complete_deadline_ms = 200 },
    function()
      complete.request()
      eq(complete.current(), nil, "nothing before the deadline while one source is still out")
      eq(complete.pending(), true, "the request waits")
      T.advance_until(
        function() return complete.current() and #complete.current().items == 2 end,
        "the late answer to arrive",
        5000
      )
      eq(sizes[1], 1, "what came in time showed first")
      eq(sizes[#sizes], 2, "then the late one was added")
      eq(complete.current().items[2].source, "late", "at the end, though its source ranks higher")
      eq(complete.pending(), false, "nothing is owed any more")
    end
  )
  paw.off(id)
end)

test("answers that all come in time show at once, in the sources' order", function()
  start()
  with({ fixed("low", { next_bar[1] }, 1), fixed("high", { next_bar[2] }, 9) }, {}, function()
    complete.request()
    local cur = complete.current()
    eq(cur and #cur.items, 2, "both, without waiting for the deadline")
    eq(cur.items[1].source, "high", "the higher priority first")
  end)
end)

test("a source that never answers does not hold up the others", function()
  start()
  local never = {
    name = "never",
    complete = function() end,
    cancel = function(ctx) log[#log + 1] = "never cancelled " .. ctx.id end,
  }
  with({ never, fixed("quick", next_bar) }, { complete_deadline_ms = 50 }, function()
    local id = complete.request()
    T.advance_until(function() return complete.current() ~= nil end, "the others to show at the deadline", 5000)
    complete.dismiss()
    eq(log[#log], "never cancelled " .. id, "dismissing cancels what is still owed")
  end)
end)

test("a newer request cancels the older one and its late answer is dropped", function()
  start()
  local function labelled(ctx) return { { label = "for " .. ctx.id, notes = { n(67, 4) } } } end
  with({ slow("late", 150, labelled) }, { complete_deadline_ms = 1000 }, function()
    local first = complete.request()
    local second = complete.request()
    eq(log[#log - 1], "late cancelled " .. first, "the older one is cancelled")
    T.advance_until(function() return complete.current() ~= nil end, "the newer one to show", 5000)
    T.advance(300)
    eq(#complete.current().items, 1, "the older answer never joins it")
    eq(complete.current().item.label, "for " .. second, "it is the newer answer that shows")
  end)
end)

test("an edit of the clip dismisses the suggestion and cancels the request", function()
  local _, clip = start()
  with({ fixed("fixed", next_bar) }, {}, function()
    complete.request()
    clip:add_note(n(72, 0))
    paw.flush()
    eq(complete.current(), nil, "an edit dismisses what shows")
  end)
  with({ slow("late", 200, next_bar) }, {}, function()
    local id = complete.request()
    clip:add_note(n(74, 0))
    paw.flush()
    eq(log[#log], "late cancelled " .. id, "and cancels what is owed")
    T.advance(400)
    eq(complete.current(), nil, "whose answer is dropped")
  end)
end)

test("a source that fails or answers nonsense never breaks the piano roll", function()
  start()
  local crash = { name = "crash", complete = function() error("boom") end }
  local twice = {
    name = "twice",
    complete = function(_, done)
      done({ { label = "once", notes = { n(60, 4) } } })
      done({ { label = "again", notes = { n(61, 4) } } })
    end,
  }
  local nonsense = fixed("nonsense", {
    "not an item",
    { label = "empty" },
    { label = "broken", notes = { { pitch = 0 / 0, start = 4, length = 1 }, { pitch = 60, start = 4, length = -1 } } },
    { label = "half", notes = { { pitch = 61.6, at = 4, length = 1, velocity = 400 }, "x" } },
  })
  local garbage = fixed("garbage", "garbage")
  with({ crash, twice, nonsense, garbage, fixed("fine", next_bar) }, {}, function()
    complete.request()
    local labels = {}
    for i, item in ipairs(complete.current().items) do
      labels[i] = item.label
    end
    table.sort(labels)
    eq(table.concat(labels, " "), "fall half once rise", "what is usable shows, each source's first answer only")
    for _, item in ipairs(complete.current().items) do
      if item.label == "half" then
        eq(
          item.notes[1].pitch .. "@" .. item.notes[1].start .. " v" .. item.notes[1].velocity,
          "62@4 v127",
          "made whole"
        )
      end
    end
    roll.layer("broken", 45, function() error("layer boom") end, function() error("marks boom") end)
    local ok, text = pcall(screen)
    roll.layer("broken", 45, nil)
    eq(ok, true, "drawing goes on past a failing layer")
    eq(text:find("1/4", 1, true) ~= nil, true, "with the suggestion drawn")
  end)
  with({ crash }, {}, function()
    eq(complete.request() ~= nil, true, "a request to a failing source alone is still made")
    eq(complete.current(), nil, "and shows nothing")
    eq(complete.pending(), false, "and waits for nothing")
  end)
end)

test("suggestions come by themselves after an idle pause, never while playing or recording", function()
  local _, clip = start()
  api.engine_restart({})
  with({ fixed("fixed", next_bar) }, { complete_idle_ms = 30 }, function()
    complete.poke()
    T.advance(150)
    eq(complete.current(), nil, "not while automatic suggestions are off")
    paw.opt.complete_auto = true
    paw.transport.play()
    clip:add_note(n(72, 0))
    T.advance(200)
    eq(complete.current(), nil, "not while playing")
    eq(#log, 0, "the sources are not even asked")
    paw.transport.stop()
    paw.flush()
    complete.poke()
    T.advance_until(function() return complete.current() ~= nil end, "a suggestion after a pause when stopped", 5000)
    eq(log[1], "fixed asked auto", "asked as an automatic request")
    paw.transport.play()
    paw.flush()
    eq(complete.current(), nil, "and hidden when the transport starts")
    eq(roll:subscope(), nil, "its keys with it")
    paw.transport.stop()
    paw.flush()
  end)
end)

test("a source that only answers keys is not asked by itself", function()
  start()
  local manual = fixed("manual", next_bar)
  manual.auto = false
  with({ manual }, { complete_idle_ms = 20 }, function()
    paw.opt.complete_auto = true
    complete.poke()
    T.advance(150)
    eq(#log, 0, "not after a pause")
    complete.request()
    eq(complete.current() ~= nil, true, "but when asked")
  end)
end)

test("complete.show draws ghost notes for any module, with or without the keys", function()
  local _, clip = start()
  complete.show({ { label = "preview", notes = { n(70, 4) } } }, { keys = false })
  eq(shown_notes(), "70@4", "shown without a source")
  eq(roll:subscope(), nil, "a preview takes no keys")
  eq(screen():find("preview", 1, true) ~= nil, true, "it is drawn")
  complete.show({})
  eq(complete.current(), nil, "an empty list hides it")
  complete.show({ { label = "fix", notes = { n(70, 4) }, remove = { 4 }, velocities = { [1] = 40 } } })
  T.keys("<Tab>")
  eq(T.melody(clip), "60@0+1 62@1+1 64@2+1 70@4+1", "accepting writes it, replacing what it names")
  eq(clip:notes()[1].velocity, 40, "with its velocities")
end)

test(
  "the roll's row of tools has the switch, and a click on the suggestion's badge accepts it, in both frontends",
  function()
    local _, clip = start()
    with({ fixed("fixed", next_bar) }, {}, function()
      local tools = paw.ui.views:get("pianoroll"):toolbar()
      eq(tools[1] and tools[1].label, "Suggest", "the switch for automatic suggestions")
      eq(tools[1].on, false, "off here")
      paw.frontend.act[tools[1].act](clip.id)
      eq(paw.opt.complete_auto, true, "a click turns it on")
      paw.opt.complete_auto = false
      complete.request()
      paw.frontend.act.complete_badge(clip.id, 2)
      eq(complete.current().index, 2, "the second shown")
      -- The badge is a hit region of the scene a window is sent.
      api.scene_forget(0)
      paw.ui.render_scene("pianoroll", 120, 40, { w = 8, h = 16 })
      local patch = api.json_decode(api.scene_end(0, "complete"))
      api.scene_forget(0)
      local badge
      for _, n in ipairs(patch.set) do
        if n.hit and n.hit.kind == "act" and n.hit.act == "complete_badge" then badge = n end
      end
      eq(badge and badge.hit.arg, 2, "the badge, for the one showing")
      local before = T.melody(clip)
      paw.frontend.act[badge.hit.act](clip.id, badge.hit.arg)
      eq(T.melody(clip) ~= before, true, "a click on it accepts it")
    end)
  end
)

test("hearing a suggestion changes nothing in the project", function()
  local t, clip = start()
  t:add_device("synth")
  api.engine_restart({})
  with({ fixed("fixed", next_bar) }, {}, function()
    complete.request()
    local edits, before = api.project_get().edits, T.melody(clip)
    paw.keymap.feed("gh")
    T.advance(300)
    eq(T.melody(clip), before, "the clip is as it was")
    eq(api.project_get().edits, edits, "nothing was edited")
    eq(complete.current() ~= nil, true, "and the suggestion still shows")
    complete.dismiss()
  end)
end)

test("each seat has a suggestion of its own, and an edit from either makes both stale", function()
  local _, clip = start()
  local K = paw._kernel
  local function as(seat, fn)
    K.seat(seat)
    local ok, err = xpcall(fn, debug.traceback)
    K.seat(0)
    if not ok then error(err, 0) end
  end
  with({ fixed("fixed", next_bar) }, {}, function()
    K.seat_open(9, "terminal")
    local ok, err = pcall(function()
      as(9, function()
        roll:edit(clip)
        roll:set(65, 4)
        complete.request()
        eq(shown_notes(), "67@4 69@5", "the second seat sees its suggestion")
      end)
      eq(complete.current(), nil, "the instance's seat does not")
      complete.request()
      complete.select(2, true)
      as(9, function() eq(complete.current().index, 1, "nor shares which alternative shows") end)
      clip:add_note(n(72, 0))
      paw.flush()
      as(9, function() eq(complete.current(), nil, "an edit from another seat makes it stale") end)
    end)
    as(9, function() complete.dismiss() end)
    K.seat_close(9, "terminal")
    if not ok then error(err, 0) end
  end)
end)

-- With MIDI LSP's engine (skipped without one: $MIDI_LSP_ENGINE) ---------------

T.test(
  "the language server's suggestions show as ghost notes in the terminal's piano roll and are taken with Tab",
  function()
    paw.opt.midilsp_autostart = false
    if not paw.ext.loaded.midilsp then paw.ext.load("extensions/midilsp") end
    local midilsp = require("midilsp")
    if not midilsp.engine() then return "no MIDI LSP engine: set $MIDI_LSP_ENGINE to run this" end
    local ok, err = xpcall(function()
      T.fresh()
      paw.keymap.feed("<Esc><Esc>")
      local upper = paw
        .add_track({ name = "Upper" })
        :add_clip({ start = 0, length = 4, notes = { n(72, 0), n(74, 1), n(76, 2), n(77, 3) } })
      paw.add_track({ name = "Lower" }):add_clip({ start = 0, length = 4, notes = { n(60, 0, 2), n(67, 2, 2) } })
      roll:edit(upper)
      roll:set(77, 4)
      midilsp.start(true)
      T.advance_until(function()
        for _, c in ipairs(paw.lsp.clients()) do
          if c.name == "midi-lsp-suggest" and c.status == "running" then return paw.lsp.settle() end
        end
      end, "the engine's suggestion role to run", 30000)
      eq(complete.sources:get("lsp") ~= nil, true, "paw.lsp is a completion source")
      paw.opt.complete_deadline_ms = 3000
      paw.keymap.feed("<C-Space>")
      T.advance_until(function() return complete.current() ~= nil end, "the engine to answer", 30000)
      local cur = complete.current()
      eq(cur.item.source, "midi-lsp-suggest", "from the engine")
      eq(cur.item.notes[1].start >= 4 - 1e-6, true, "starting where it was asked, in the clip's beats")
      local text = table.concat(api.ui_snapshot(120, 40), "\n")
      eq(text:find("┄", 1, true) ~= nil, true, "drawn as ghost notes")
      eq(text:find("midi-lsp-suggest", 1, true) ~= nil, true, "under its badge")
      api.undo_checkpoint()
      local before = #upper:notes()
      T.keys("<Tab>")
      eq(#upper:notes(), before + #cur.item.notes, "Tab writes them")
      paw.undo()
      eq(#upper:notes(), before, "one undo takes them away")
    end, debug.traceback)
    paw.opt.complete_deadline_ms = 300
    complete.dismiss()
    paw.lsp.stop()
    paw.diagnostic.reset()
    paw.keymap.feed("<Esc><Esc>")
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
    if not ok then error(err, 0) end
  end
)
