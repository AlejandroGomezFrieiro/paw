-- The notation view's paint, timed: what `tools/paintbench.lua` prints. A clip of `bars` bars of random melody with some
-- chords is opened as notation and painted at 1053 x 1215 px.
local api = paw.api
local M = {}

local W, H = 1053, 1215

--- Notes for `bars` bars, the same every time.
function M.notes(bars)
  local notes = {}
  local scale = { 60, 62, 64, 65, 67, 69, 71, 72, 74, 76 }
  local seed = 7
  local function rnd(n)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed % n
  end
  for bar = 0, bars - 1 do
    local t = 0
    while t < 4 do
      local len = ({ 0.25, 0.5, 0.5, 1, 1, 2 })[rnd(6) + 1]
      if t + len > 4 then len = 4 - t end
      local p = scale[rnd(#scale) + 1]
      notes[#notes + 1] = { pitch = p, start = bar * 4 + t, length = len, velocity = 90 }
      if rnd(4) == 0 then
        notes[#notes + 1] = { pitch = p - 12 - rnd(8), start = bar * 4 + t, length = len, velocity = 80 }
      end
      t = t + len
    end
  end
  return notes
end

local function median(list)
  table.sort(list)
  return list[math.floor(#list / 2) + 1]
end

--- Time the paint. `opts` are `paw.canvas.paint`'s. Returns the times in
--- ms (`first`, `same`, `cursor`, `edit`, `relayout`, medians) and the
--- drawing's size (`ops`, `kinds`, `json` bytes). With `how.notation`
--- the edit is made in notation (the note sharpened there: its score
--- changed and written back as MIDI), and `edit` is the edit itself and
--- the paint after it; else the note is changed in the clip and `edit` is
--- the paint after it.
function M.run(bars, opts, rounds, how)
  rounds = rounds or 20
  how = how or {}
  local view = require("notation")
  local notes = M.notes(bars)
  local track = api.track_add({ name = "Bench" })
  local id = api.clip_add(track, { start = 0, length = bars * 4, notes = notes })
  paw.flush()
  view:edit(id)
  local function paint() return paw.canvas.paint("notation", W, H, opts) end
  local function time(fn)
    local t = api.now()
    local r = fn()
    return api.now() - t, r
  end
  local out = {}
  local drawing
  out.first, drawing = time(paint)
  local same, cursor, edit, relayout = {}, {}, {}, {}
  for i = 1, rounds do
    same[i] = time(paint)
  end
  for i = 1, rounds do
    view:move(view:entry_length() * (i % 2 == 0 and -1 or 1), 0)
    cursor[i] = time(paint)
  end
  local clip = view:clip()
  for i = 1, rounds do
    -- A note of a bar in the middle up a step, as an edit does.
    local at = math.floor(#notes / 2)
    local n = clip:notes()[at]
    if how.notation then
      -- The cursor on the note, then the edit as the key makes it.
      for _, ev in ipairs(require("notation.model").events(view:layout())) do
        for _, w in ipairs(ev.notes or {}) do
          if w.index == at and not w.tied then
            view.beat, view.step = ev.start, w.step
          end
        end
      end
      edit[i] = time(function()
        view:inflect(i % 2 == 0 and -1 or 1)
        return paint()
      end)
    else
      clip:set_note(at, { pitch = n.pitch + (i % 2 == 0 and -1 or 1) })
      edit[i] = time(paint)
    end
  end
  for i = 1, rounds do
    view.cache = nil
    relayout[i] = time(paint)
  end
  out.same, out.cursor, out.edit, out.relayout = median(same), median(cursor), median(edit), median(relayout)
  local kinds = {}
  for _, op in ipairs(drawing.ops) do
    kinds[op[1]] = (kinds[op[1]] or 0) + 1
  end
  out.ops, out.kinds, out.json, out.bars, out.notes = #drawing.ops, kinds, #api.json_encode(drawing.ops), bars, #notes
  api.clip_remove(id)
  return out
end

--- A notation edit against a MIDI edit, each with the paint after it, one
--- after the other on one clip of `bars` bars, `rounds` times: so that a
--- busy machine slows both alike. Returns the medians in ms (`plain`,
--- `notation`) and the median of each round's ratio of the two (`ratio`).
function M.pair(bars, opts, rounds)
  local view = require("notation")
  local model = require("notation.model")
  local notes = M.notes(bars)
  local track = api.track_add({ name = "Bench" })
  local id = api.clip_add(track, { start = 0, length = bars * 4, notes = notes })
  paw.flush()
  view:edit(id)
  local function paint() return paw.canvas.paint("notation", W, H, opts) end
  -- Each from a clean heap, so that neither pays for the other's garbage.
  local function time(fn)
    collectgarbage()
    local t = api.now()
    fn()
    return api.now() - t
  end
  paint()
  local clip = view:clip()
  local at = math.floor(#notes / 2)
  local plain, notation, ratio = {}, {}, {}
  for i = 1, rounds do
    local n = clip:notes()[at]
    plain[i] = time(function()
      clip:set_note(at, { pitch = n.pitch + 1 })
      paint()
    end)
    for _, ev in ipairs(model.events(view:layout())) do
      for _, w in ipairs(ev.notes or {}) do
        if w.index == at and not w.tied then
          view.beat, view.step = ev.start, w.step
        end
      end
    end
    notation[i] = time(function()
      view:inflect(-1)
      paint()
    end)
    ratio[i] = notation[i] / math.max(0.01, plain[i])
  end
  api.clip_remove(id)
  return { plain = median(plain), notation = median(notation), ratio = median(ratio) }
end

function M.format(r)
  local kinds = {}
  for k, v in pairs(r.kinds) do
    kinds[#kinds + 1] = k .. "=" .. v
  end
  table.sort(kinds)
  return string.format(
    "bars=%d notes=%d ops=%d (%s) json=%d bytes\n"
      .. "paint first=%.2fms same=%.2fms cursor move=%.2fms edit=%.2fms relayout=%.2fms",
    r.bars,
    r.notes,
    r.ops,
    table.concat(kinds, " "),
    r.json,
    r.first,
    r.same,
    r.cursor,
    r.edit,
    r.relayout
  )
end

return M
