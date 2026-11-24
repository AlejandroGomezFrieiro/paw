-- Batch edits and tuning presets for a vocal clip. Each runs as one edit, so one undo step.
local api = paw.api
local notes = require("utau.notes")
local kana = require("utau.kana")

local M = {}

local VIBRATO_ON = { 75, 175, 25, 10, 10, 0, 0, 0 }

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- A sung syllable, as opposed to a rest, an extender or a breath.
local function syllable(text)
  local t = trim(text)
  return t ~= "" and not notes.is_rest(t) and t ~= "+" and t ~= "-" and t ~= "+~" and t ~= "br"
end

local function lyric_op(fn)
  return function(text, params)
    if not syllable(text) then return nil end
    return fn(trim(text), params)
  end
end

local function replace(text, p)
  if not p or (p.find or "") == "" then return nil end
  if p.pattern then
    local ok, s = pcall(string.gsub, text, p.find, p.replace or "")
    return ok and s or nil
  end
  local out, i = {}, 1
  while true do
    local a, b = text:find(p.find, i, true)
    if not a then break end
    out[#out + 1] = text:sub(i, a - 1) .. (p.replace or "")
    i = b + 1
  end
  out[#out + 1] = text:sub(i)
  return table.concat(out)
end

--- Each op has `lyric(text, params)` returning a new lyric, `props(props,
--- note)` changing note properties and returning whether it did, or
--- `timing(list)` changing note starts and lengths.
M.OPS = {
  { id = "romaji_to_hiragana", name = "Romaji to hiragana", lyric = lyric_op(kana.to_hiragana) },
  { id = "kana_to_romaji", name = "Kana to romaji", lyric = lyric_op(kana.to_romaji) },
  {
    id = "vcv_to_cv",
    name = 'Japanese VCV to CV ("a ka" -> "ka")',
    lyric = function(text) return text:match("^%s*[aiueonN%-]%s+(%S.*)$") end,
  },
  {
    id = "remove_tone_suffix",
    name = 'Remove tone suffix ("ka_C4" -> "ka")',
    lyric = function(text)
      local s = text:gsub("[_%s]?[A-G]#?b?%-?%d$", "")
      if s ~= "" then return s end
    end,
  },
  {
    id = "remove_hint",
    name = 'Remove phonetic hints ("read[r iy d]" -> "read")',
    lyric = function(text)
      local s = trim(text:gsub("%b[]", ""))
      if s ~= "" then return s end
    end,
  },
  {
    id = "dash_to_plus",
    name = 'Dash to plus ("-" -> "+")',
    lyric = function(text)
      if trim(text) == "-" then return "+" end
    end,
  },
  { id = "lowercase", name = "Lowercase lyrics", lyric = function(text) return text:lower() end },
  { id = "replace", name = "Find and replace: `find=ka replace=ga [pattern=1]`", lyric = replace },
  {
    id = "reset_pitch",
    name = "Reset pitch transitions",
    props = function(p)
      if p.pp then
        p.pp = nil
        return true
      end
    end,
  },
  {
    id = "clear_vibrato",
    name = "Clear vibrato",
    props = function(p)
      if p.vb then
        p.vb = nil
        return true
      end
    end,
  },
  {
    id = "vibrato_long",
    name = "Add vibrato to long notes (1 beat or more)",
    props = function(p, note)
      if p.vb or note.length < 1 - 1e-6 or notes.is_rest(notes.lyric(note)) then return false end
      p.vb = notes.copy(VIBRATO_ON)
      return true
    end,
  },
  {
    id = "reset_exp",
    name = "Reset note expressions",
    props = function(p)
      if p.ex then
        p.ex = nil
        return true
      end
    end,
  },
  {
    id = "reset_phonemes",
    name = "Reset phoneme timing and overrides",
    props = function(p)
      if p.ph then
        p.ph = nil
        return true
      end
    end,
  },
  {
    id = "reset_po",
    name = "Reset phonemizer overrides",
    props = function(p)
      if p.po then
        p.po = nil
        return true
      end
    end,
  },
  {
    id = "reset_all",
    name = "Reset all note properties",
    props = function(p)
      local had = next(p) ~= nil
      for k in pairs(p) do
        p[k] = nil
      end
      return had
    end,
  },
  {
    id = "fix_overlap",
    name = "Fix overlaps (trim notes to the next one)",
    timing = function(list)
      local changed = 0
      for i = 1, #list - 1 do
        local a, b = list[i], list[i + 1]
        if b.start > a.start and a.start + a.length > b.start then
          a.length = b.start - a.start
          changed = changed + 1
        end
      end
      return changed
    end,
  },
  {
    id = "fill_gaps",
    name = "Close small gaps (up to an eighth note)",
    timing = function(list)
      local changed = 0
      for i = 1, #list - 1 do
        local a, b = list[i], list[i + 1]
        local gap = b.start - (a.start + a.length)
        if gap > 1e-9 and gap <= 0.5 + 1e-9 then
          a.length = b.start - a.start
          changed = changed + 1
        end
      end
      return changed
    end,
  },
}
M.BY_ID = {}
for _, op in ipairs(M.OPS) do
  M.BY_ID[op.id] = op
end

--- Run a batch edit on a clip's notes, or only those in `which` (index -> true).
--- Returns how many notes changed.
function M.run(id, clip_id, params, which)
  local op = M.BY_ID[id]
  if not op then error("no batch edit `" .. tostring(id) .. "`", 2) end
  if op.lyric then
    return notes.change(clip_id, function(note)
      local s = op.lyric(note.meta.lyric or "", params)
      if not s or s == "" or s == note.meta.lyric then return false end
      note.meta.lyric = s
      return true
    end, which)
  elseif op.props then
    return notes.change_props(clip_id, function(p, note) return op.props(p, note, params) end, which)
  end
  local list = api.clip_notes(clip_id)
  local chosen = {}
  for index, note in ipairs(list) do
    if not which or which[index] then chosen[#chosen + 1] = note end
  end
  local changed = op.timing(chosen, params)
  if changed > 0 then api.clip_set_notes(clip_id, list) end
  return changed
end

-- Tuning presets ---------------------------------------------------------------------

--- Ops: `{ curve, shape, value }` writes a curve under notes (shapes span,
--- attack, release, swell, by_pitch), `{ vibrato }` sets or (false) clears
--- vibrato, `{ exp, value }` sets a note expression, `{ transition }` shapes
--- the pitch into notes after a leap, `{ reset }` puts curves back.
M.PRESETS = {
  {
    id = "breath_in",
    name = "Breath at phrase starts",
    ops = { { curve = "brec", shape = "attack", value = 45, len_beats = 0.35, where = "phrase_start" } },
  },
  {
    id = "soft_endings",
    name = "Soft phrase endings",
    ops = {
      { curve = "dyn", shape = "release", value = -60, len = 0.4, where = "phrase_end" },
      { curve = "brec", shape = "release", value = 25, len = 0.4, where = "phrase_end" },
    },
  },
  {
    id = "swell",
    name = "Swell on long notes",
    ops = { { curve = "dyn", shape = "swell", value = 30, where = "long" } },
  },
  {
    id = "tension_high",
    name = "Tension on high notes",
    ops = { { curve = "tenc", shape = "by_pitch", value = 5, max = 60 } },
  },
  { id = "overshoot", name = "Overshoot on leaps", ops = { { transition = "overshoot", min_jump = 2 } } },
  { id = "preparation", name = "Preparation before leaps", ops = { { transition = "preparation", min_jump = 3 } } },
  { id = "crisp", name = "Crisp consonants", ops = { { exp = "vel", value = 140 } } },
  {
    id = "vib_gentle",
    name = "Vibrato: gentle, delayed",
    ops = { { vibrato = { 60, 180, 25, 35, 15, 0, 0, 0 }, min = 1 } },
  },
  {
    id = "vib_pop",
    name = "Vibrato: pop (fast, narrow)",
    ops = { { vibrato = { 50, 150, 18, 20, 10, 0, 0, 0 }, min = 0.75 } },
  },
  {
    id = "vib_opera",
    name = "Vibrato: operatic (wide, slow)",
    ops = { { vibrato = { 85, 210, 60, 15, 10, 0, 10, 10 }, min = 0.5 } },
  },
  { id = "vib_off", name = "No vibrato", ops = { { vibrato = false } } },
  {
    id = "raspy",
    name = "Harsh: raspy",
    ops = {
      { curve = "tenc", shape = "span", value = 40 },
      { curve = "brec", shape = "span", value = 20 },
      { curve = "voic", shape = "span", value = 88 },
      { curve = "grwc", shape = "span", value = 25 },
    },
  },
  {
    id = "scream",
    name = "Harsh: scream",
    ops = {
      { curve = "tenc", shape = "span", value = 80 },
      { curve = "brec", shape = "span", value = 35 },
      { curve = "voic", shape = "span", value = 72 },
      { curve = "genc", shape = "span", value = -10 },
      { curve = "grwc", shape = "span", value = 55 },
      { curve = "dyn", shape = "span", value = 20 },
      { vibrato = false },
      { exp = "vel", value = 150 },
    },
  },
  {
    id = "growl",
    name = "Harsh: death growl",
    ops = {
      { curve = "genc", shape = "span", value = -40 },
      { curve = "tenc", shape = "span", value = 70 },
      { curve = "brec", shape = "span", value = 45 },
      { curve = "voic", shape = "span", value = 58 },
      { curve = "grwc", shape = "span", value = 85 },
      { vibrato = false },
      { exp = "vel", value = 160 },
    },
  },
  {
    id = "fry",
    name = "Harsh: vocal fry onsets",
    ops = {
      { curve = "voic", shape = "attack", value = 40, len_beats = 0.2, base = 100 },
      { curve = "brec", shape = "attack", value = 55, len_beats = 0.2 },
    },
  },
  {
    id = "reset",
    name = "Reset tuning curves under the notes",
    ops = { { reset = { "dyn", "tenc", "brec", "genc", "voic", "grwc" } } },
  },
}
M.PRESET_BY_ID = {}
for _, p in ipairs(M.PRESETS) do
  M.PRESET_BY_ID[p.id] = p
end

--- Phrase starts and ends: a gap of a beat or a rest separates phrases.
local function phrases(list)
  local starts, ends = {}, {}
  for i, n in ipairs(list) do
    local prev, nxt = list[i - 1], list[i + 1]
    if not prev or n.start - (prev.start + prev.length) >= 1 - 1e-9 or notes.is_rest(notes.lyric(prev)) then
      starts[i] = true
    end
    if not nxt or nxt.start - (n.start + n.length) >= 1 - 1e-9 or notes.is_rest(notes.lyric(nxt)) then
      ends[i] = true
    end
  end
  return starts, ends
end

local function samples(op, a, b, base, pitch, avg)
  local len, v = b - a, op.value
  if op.shape == "attack" then
    local l = math.min(len, op.len_beats or len * (op.len or 0.3))
    if op.base then return { { a, v }, { a + l, op.base } } end
    return { { a, base + v }, { a + l, base } }
  elseif op.shape == "release" then
    local l = math.min(len, op.len_beats or len * (op.len or 0.3))
    return { { a, base }, { b - l, base }, { b, base + v } }
  elseif op.shape == "swell" then
    return { { a, base }, { a + len / 2, base + v }, { b, base } }
  elseif op.shape == "by_pitch" then
    local d = math.max(-(op.max or 100), math.min(op.max or 100, (pitch - avg) * v))
    if d <= 0 then return {} end
    return { { a, base + d }, { b, base + d } }
  end
  return {}
end

local function transition(kind, note, prev)
  local delta = (prev.pitch - note.pitch) * 10
  local dir = note.pitch > prev.pitch and 1 or -1
  if kind == "overshoot" then
    return { snap = true, pts = { { -40, delta, 0 }, { 25, 4 * dir, 0 }, { 90, 0, 0 } } }
  elseif kind == "preparation" then
    return { snap = true, pts = { { -110, delta, 0 }, { -60, delta - 3 * dir, 0 }, { 30, 0, 0 } } }
  end
end

--- Apply a tuning preset to a clip's notes, or those in `which`. Returns a
--- list of what it did.
function M.preset(id, clip_id, which)
  local preset = M.PRESET_BY_ID[id]
  if not preset then error("no tuning preset `" .. tostring(id) .. "`", 2) end
  local clip = api.clip_get(clip_id)
  local part = clip.part
  local device = require("utau").device_of(part)
  if not device then error("the clip is not on a vocal part", 2) end
  local list = api.clip_notes(clip_id)
  local chosen, avg = {}, 0
  for index, note in ipairs(list) do
    if not which or which[index] then
      chosen[#chosen + 1] = index
      avg = avg + note.pitch
    end
  end
  if #chosen == 0 then return {} end
  avg = avg / #chosen
  local starts, ends = phrases(list)
  local function wanted(op, index)
    if op.where == "phrase_start" then return starts[index] end
    if op.where == "phrase_end" then return ends[index] end
    if op.where == "long" then return list[index].length >= (op.min or 1) - 1e-9 end
    return true
  end
  local done = {}
  local selected = {}
  for _, index in ipairs(chosen) do
    selected[index] = true
  end
  for _, op in ipairs(preset.ops) do
    if op.curve then
      local base = notes.default(device, op.curve)
      local count = 0
      if op.shape == "span" then
        local first, last = list[chosen[1]], list[chosen[#chosen]]
        local a, b = clip.start + first.start, clip.start + last.start + last.length
        local _, min, max = notes.default(device, op.curve)
        local value = min == 0 and op.value or base + op.value
        value = math.max(min, math.min(max, value))
        notes.stroke(part, device, op.curve, { { a, value }, { b, value } })
        count = #chosen
      else
        for _, index in ipairs(chosen) do
          local n = list[index]
          if wanted(op, index) then
            local a = clip.start + n.start
            local s = samples(op, a, a + n.length, base, n.pitch, avg)
            if #s > 0 then
              notes.stroke(part, device, op.curve, s)
              count = count + 1
            end
          end
        end
      end
      done[#done + 1] = string.format("%s on %d notes", op.curve, count)
    elseif op.reset then
      for _, abbr in ipairs(op.reset) do
        for _, index in ipairs(chosen) do
          local n = list[index]
          notes.reset(part, device, abbr, clip.start + n.start, clip.start + n.start + n.length)
        end
      end
      done[#done + 1] = "curves reset"
    elseif op.vibrato ~= nil then
      local count = notes.change_props(clip_id, function(p, note)
        if op.vibrato == false then
          if not p.vb then return false end
          p.vb = nil
          return true
        end
        if note.length < (op.min or 0) - 1e-9 or notes.is_rest(notes.lyric(note)) then return false end
        p.vb = notes.copy(op.vibrato)
        return true
      end, selected)
      done[#done + 1] = string.format("vibrato on %d notes", count)
    elseif op.exp then
      local count = notes.change_props(clip_id, function(p)
        p.ex = p.ex or {}
        for _, e in ipairs(p.ex) do
          if e[1] == op.exp and (e[3] or -1) == -1 then
            if e[2] == op.value then return false end
            e[2] = op.value
            return true
          end
        end
        p.ex[#p.ex + 1] = { op.exp, op.value, -1 }
        return true
      end, selected)
      done[#done + 1] = string.format("%s = %s on %d notes", op.exp, op.value, count)
    elseif op.transition then
      local count = notes.change_props(clip_id, function(p, note, index)
        local prev = list[index - 1]
        if not prev or prev.start + prev.length < note.start - 0.25 then return false end
        if math.abs(note.pitch - prev.pitch) < (op.min_jump or 0) then return false end
        p.pp = transition(op.transition, note, prev)
        return true
      end, selected)
      done[#done + 1] = string.format("%s on %d notes", op.transition, count)
    end
  end
  return done
end

return M
