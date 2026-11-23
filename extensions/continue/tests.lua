-- Tests for the continue extension, run by tests/suite.lua.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api
local roll = paw.ui.views:get("pianoroll")

local function ext()
  paw.ext.load("extensions/continue")
  return require("continue")
end

local function n(pitch, start, length) return { pitch = pitch, start = start, length = length or 1 } end

local function list(notes)
  local out = {}
  for i, x in ipairs(notes) do
    out[i] = string.format("%d@%g", x.pitch, x.start)
  end
  return table.concat(out, " ")
end

--- A bar of C major (C D E G), open in the piano roll with the cursor after
--- it; the source is taken away again when `fn` ends.
local function with_bar(fn)
  local continue = ext()
  -- Only this source suggests: the snippets of an earlier test are a
  -- source too. The sources come back with their owners: a register from
  -- this file would make the core's snippets a source of this extension,
  -- which its unload takes away.
  local saved = paw.complete.sources:save()
  T.after(function() paw.complete.sources:restore(saved) end)
  for _, source in ipairs(paw.complete.list()) do
    if source.name ~= "continue" then paw.complete.unregister(source.name) end
  end
  T.fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  local t = paw.add_part({ name = "Lead" })
  local clip = t:add_clip({ start = 0, length = 4, notes = { n(60, 0), n(62, 1), n(64, 2), n(67, 3) } })
  roll:edit(clip)
  roll:set(67, 4)
  paw.flush()
  api.undo_checkpoint()
  paw.opt.complete_auto = false
  local ok, err = xpcall(fn, debug.traceback, continue, clip)
  paw.complete.dismiss()
  paw.complete.unregister("continue")
  paw.opt.complete_auto = true
  paw.opt.complete_idle_ms = 1200
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.hide("pianoroll")
  paw.ui.focus("arrange")
  if not ok then error(err, 0) end
end

test("continue guesses the key from how long each pitch sounds", function()
  local continue = ext()
  paw.complete.unregister("continue")
  eq(continue.guess_key({ n(60, 0), n(64, 1), n(67, 2), n(62, 3), n(65, 4) }).name, "C major", "C major")
  eq(continue.guess_key({ n(57, 0, 3), n(60, 3), n(64, 4), n(62, 5), n(59, 6) }).name, "A minor", "A minor")
  local tune = {
    n(60, 0),
    n(62, 1),
    n(64, 2),
    n(67, 3),
    n(65, 4),
    n(64, 5),
    n(62, 6),
    n(60, 7),
    n(62, 8),
    n(64, 9),
    n(65, 10),
    n(69, 11),
    n(67, 12),
    n(65, 13),
    n(64, 14),
    n(62, 15),
  }
  eq(continue.guess_key(tune).name, "C major", "a tune that starts on C and leans on F is still in C")
  eq(continue.shift(64, 1, { tonic = 0, mode = "major" }), 65, "E a step up in C is F")
  eq(continue.shift(71, 1, { tonic = 0, mode = "major" }), 72, "B a step up is C, an octave on")
  eq(continue.shift(60, -1, { tonic = 0, mode = "major" }), 59, "C a step down is B below")
  eq(continue.shift(61, 1, { tonic = 0, mode = "major" }), 63, "a note outside the key keeps its distance")
end)

test("continue offers the bar again, a step higher and lower in the key, and the motif rising", function()
  with_bar(function(continue)
    local items = continue.suggest({ notes = paw.clip(roll.clip_id):notes(), at = 4, bar = 4 })
    local got = {}
    for i, item in ipairs(items) do
      got[i] = item.label .. ": " .. list(item.notes)
    end
    eq(got[1], "the bar again: 60@4 62@5 64@6 67@7", "the bar again")
    eq(got[2], "a step higher: 62@4 64@5 65@6 69@7", "in the key, not by a semitone")
    eq(got[3], "a step lower: 59@4 60@5 62@6 65@7", "and lower")
    eq(got[4], "the motif, rising: 65@4 69@5 67@6 71@7", "the last half bar, a step up each time")
    eq(#continue.suggest({ notes = {}, at = 4, bar = 4 }), 0, "nothing to go on from: nothing")
  end)
end)

test("continue's suggestion is accepted with tab in insert mode as one undo step", function()
  with_bar(function(_, clip)
    paw.keymap.feed("i<C-Space>")
    local cur = paw.complete.current()
    eq(cur and #cur.items, 4, "four alternatives")
    eq(cur.item.source, "continue", "from this source")
    paw.keymap.feed("<C-n>")
    T.keys("<Tab>")
    eq(
      T.melody(clip),
      "60@0+1 62@1+1 64@2+1 67@3+1 62@4+1 64@5+1 65@6+1 69@7+1",
      "the sequence a step higher is written"
    )
    eq(roll.beat, 8, "the cursor goes on after it, to enter more")
    eq(paw.keymap.mode, "i", "still entering notes")
    paw.keymap.feed("<Esc>")
    paw.undo()
    eq(T.melody(clip), "60@0+1 62@1+1 64@2+1 67@3+1", "one undo takes it away")
  end)
end)

test("continue suggests by itself after a pause, and again after what was accepted", function()
  with_bar(function(_, clip)
    paw.opt.complete_idle_ms = 30
    paw.opt.complete_auto = true
    clip:add_note(n(48, 0, 4))
    paw.flush()
    -- A suggestion comes after the pause.
    T.advance_until(function() return paw.complete.current() end, "a suggestion", 5000)
    paw.keymap.feed("<Tab>")
    paw.flush()
    local next = T.advance_until(function() return paw.complete.current() end, "a second suggestion", 5000)
    eq(next.item.notes[1].start, 8, "the next one goes on from there")
  end)
end)
