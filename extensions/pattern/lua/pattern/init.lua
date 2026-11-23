-- `require("pattern")`: patterns in the manner of TidalCycles' mini-notation,
-- and MIDI clips whose notes follow one. See README.md beside the extension.
local parser = require("pattern.parse")
local eval = require("pattern.eval")
local names = require("pattern.names")
local core = require("pattern.core")

local api = paw.api
local M = {
  drums = names.drums, -- word -> General MIDI note, for the drum names
  chords = names.chords, -- chord name -> semitones above the root
  scales = names.scales, -- scale name -> semitones, for degrees
  params = parser.params, -- the `# name` parameters and how their values read
  core = core,
}

--- Parse pattern text. Returns a tree, or nil and an error with `message`,
--- `pos` (1-based column) and `text`; `tostring(err)` is "col 5: message".
function M.parse(text) return parser.parse(text) end

--- The error's text with a caret line under its column.
M.caret = parser.caret

--- Parse and evaluate. `seed` picks the random choices (default 0).
--- Returns a compiled pattern, or nil and the error.
function M.compile(text, seed)
  if type(text) == "table" and text.main and text.main.query then return text end
  local tree, err = parser.parse(text)
  if not tree then return nil, err end
  return eval.compile(tree, seed or 0)
end

local function compiled_or_error(text, seed)
  local compiled, err = M.compile(text, seed)
  if not compiled then error("pattern: " .. tostring(err), 3) end
  return compiled
end

--- The events of `cycles` cycles (default 1), from cycle 0, in order. Each
--- is { start, stop } in cycles, `text` (the word as written), `pitches`,
--- and `params` (the `#` values at its start).
---   pattern.events("bd [sn sn]", 1)
function M.events(text, cycles, opts)
  opts = opts or {}
  local compiled = compiled_or_error(text, opts.seed)
  return eval.events(compiled, opts.from or 0, (opts.from or 0) + (cycles or 1))
end

--- Notes for `cycles` cycles of `beats` beats each (default: one bar each),
--- as a clip holds them: { pitch, start, length, velocity, meta }.
--- opts: `seed`, `beats`, `length` (in beats, instead of `cycles`), `velocity`.
function M.notes(text, cycles, opts)
  opts = opts or {}
  local compiled = compiled_or_error(text, opts.seed)
  local beats = opts.beats or paw.time.bar()
  return eval.notes(compiled, {
    beats = beats,
    length = opts.length or (cycles or 1) * beats,
    velocity = opts.velocity or paw.opt.velocity,
  })
end

M.pitches = eval.pitches
M.bjorklund = core.bjorklund

-- Clips --------------------------------------------------------------------------
-- A clip follows a pattern while `clip.meta.pattern` holds one:
--   { text, seed, beats (per cycle; nil for one bar), digest, name }
-- `digest` is a checksum of the notes the pattern last wrote. When the clip's
-- notes no longer match it, they were edited by other means, and the clip lets
-- go of the pattern (see `refresh`).

local function clip_id(clip) return type(clip) == "table" and clip.id or clip end

local function digest(notes)
  local h1, h2 = 5381, 0
  local parts = {}
  for i, n in ipairs(notes) do
    parts[i] =
      string.format("%d:%.6f:%.6f:%d:%s", n.pitch, n.start, n.length, n.velocity or 0, n.meta and n.meta.channel or "")
  end
  table.sort(parts)
  local text = table.concat(parts, ";")
  for i = 1, #text do
    local b = text:byte(i)
    h1 = (h1 * 33 + b) % 4294967291
    h2 = (h2 * 31 + b * i) % 2147483629
  end
  return string.format("%d/%08x%08x", #notes, h1, h2)
end
M.digest = digest

local function cycle_beats(pm) return tonumber(pm.beats) or paw.time.bar() end

--- The pattern a clip follows: { text, seed, beats, ... } or nil.
function M.get(clip)
  local c = api.clip_get(clip_id(clip))
  local pm = c.meta and c.meta.pattern
  if type(pm) == "table" and type(pm.text) == "string" then return pm end
end

--- The text a clip last followed before it was detached, if any.
function M.detached(clip)
  local c = api.clip_get(clip_id(clip))
  return c.meta and c.meta.pattern_detached
end

local function write_meta(id, pm, extra)
  local meta = api.clip_get(id).meta or {}
  if type(meta) ~= "table" then meta = {} end
  meta.pattern = pm
  for k, v in pairs(extra or {}) do
    if v == false then
      meta[k] = nil
    else
      meta[k] = v
    end
  end
  api.clip_set(id, "meta", meta)
end

-- A name for the clip in the arrange view: the pattern text.
local function label(text) return "≈ " .. text end
M.label = label

local function rename(id, pm, c)
  if not paw.opt.pattern_names then return end
  local want = label(pm.text)
  -- Only a name we gave it, or the default one, is ours to change.
  if c.name == want then
    pm.name = want
    return
  end
  if c.name == pm.name or c.name == "midi" or c.name == "pattern" or c.name == "" then
    api.clip_set(id, "name", want)
    pm.name = want
  end
end

--- Evaluate a clip's pattern over its length and write the notes. Returns
--- the notes, or nil and the error when the text does not parse.
local function apply(id, pm)
  local compiled, err = M.compile(pm.text, pm.seed)
  if not compiled then return nil, err end
  local c = api.clip_get(id)
  local ok, notes = pcall(eval.notes, compiled, {
    beats = cycle_beats(pm),
    length = c.length,
    velocity = paw.opt.velocity,
  })
  if not ok then return nil, setmetatable({ message = tostring(notes), pos = 1, text = pm.text }, parser.Error) end
  local fresh = digest(notes)
  if fresh ~= digest(api.clip_notes(id)) then paw.clip(id):set_notes(notes) end
  local before = c.meta and c.meta.pattern or {}
  local stale = c.meta and c.meta.pattern_detached ~= nil
  pm.digest = digest(api.clip_notes(id))
  rename(id, pm, c)
  -- Writing the meta is itself a change, so only write when something differs.
  for _, key in ipairs({ "text", "seed", "beats", "digest", "name" }) do
    if before[key] ~= pm[key] then stale = true end
  end
  if stale then write_meta(id, pm, { pattern_detached = false }) end
  return notes
end

--- Make a clip follow a pattern, replacing its notes. `opts`: `seed`,
--- `beats` (per cycle; false for one bar). Keeps the clip's seed and cycle
--- unless given. Returns the notes, or nil and the error, leaving the clip
--- as it was.
---   pattern.set(clip, "bd*2 [~ sn] # vel 1 0.7")
function M.set(clip, text, opts)
  opts = opts or {}
  local id = clip_id(clip)
  local c = api.clip_get(id)
  if c.kind ~= "midi" then
    return nil, setmetatable({ message = "not a MIDI clip", pos = 1, text = text }, parser.Error)
  end
  local old = M.get(id) or {}
  local pm = {
    text = text,
    seed = opts.seed or old.seed or 0,
    beats = old.beats,
    name = old.name,
  }
  if opts.beats == false then
    pm.beats = nil
  elseif opts.beats then
    pm.beats = opts.beats
  end
  return apply(id, pm)
end

--- Stop a clip following its pattern; its notes stay as they are. The text
--- is kept in `meta.pattern_detached`, for `pattern.edit` to offer.
function M.detach(clip, why)
  local id = clip_id(clip)
  local pm = M.get(id)
  if not pm then return false end
  write_meta(id, nil, { pattern_detached = pm.text })
  if why then paw.notify("pattern detached: " .. why .. " (`:pattern.edit` brings it back)", "warn") end
  return true
end

--- Bring a clip up to date with its pattern after a change: re-evaluate when
--- its length, the bar or the text changed, and detach it when its notes were
--- edited by other means. Called on every `clip.changed`.
function M.refresh(clip)
  local id = clip_id(clip)
  local ok, c = pcall(api.clip_get, id)
  if not ok or c.kind ~= "midi" then return end
  local pm = c.meta and c.meta.pattern
  if type(pm) ~= "table" or type(pm.text) ~= "string" then return end
  local current = digest(api.clip_notes(id))
  if pm.digest and current ~= pm.digest then
    -- Edited by hand, unless the notes are what the pattern gives anyway
    -- (a split cuts them where the shorter pattern does).
    local compiled = M.compile(pm.text, pm.seed)
    local fresh = compiled
      and digest(eval.notes(compiled, {
        beats = cycle_beats(pm),
        length = c.length,
        velocity = paw.opt.velocity,
      }))
    if fresh ~= current then return M.detach(id, "the notes of `" .. c.name .. "` were edited") end
  end
  local _, err = apply(id, pm)
  if err then paw.notify("pattern: " .. tostring(err), "error") end
end

--- Every clip that follows a pattern, as clip ids.
function M.clips()
  local out = {}
  for _, part in ipairs(api.part_list()) do
    for _, clip in ipairs(api.clip_list(part)) do
      local pm = clip.meta and clip.meta.pattern
      if type(pm) == "table" and type(pm.text) == "string" then out[#out + 1] = clip.id end
    end
  end
  return out
end

--- Re-evaluate every pattern clip, for instance after changing `drums`.
function M.refresh_all()
  for _, id in ipairs(M.clips()) do
    M.refresh(id)
  end
end

return M
