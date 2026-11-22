-- What the pickers' preview pane draws of a clip: a small piano roll of a
-- MIDI clip's notes, a waveform of an audio clip's sound, as lines of text
-- for `preview(item)` to return (`paw.pick.preview`).
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local theme = require("paw.theme")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type objects = require("paw.objects")
local type MusicModule = require("paw.music")
local type AuditionModule = require("paw.audition")

local record Paw is partial.Paw
  time: objects.Time
  music: MusicModule
  audition: AuditionModule
end
local paw = (_G as {string: Paw}).paw

local type Line = contracts.PageLine

local record M
end

local EPS = 1e-9

--- A MIDI clip's notes as `height` lines `width` columns wide: a row a
--- pitch (or a few, when they do not fit), the pitch's name on the left,
--- a column a stretch of beats, a bar line `▏` where a bar starts. The note
--- `focus` (its id) is drawn `▓`, the others `█`. A long clip is shown from
--- the bar the focus is in, as many bars as fit at a column a 16th.
function M.roll(clip_id: integer, width: integer, height: integer, focus?: integer): {Line}
  local ok, c = pcall(api.clip_get, clip_id) as (boolean, types.Clip)
  if not ok or c.kind ~= "midi" then
    return {}
  end
  local notes = api.clip_notes(clip_id)
  local cols = math.max(8, width - 5)
  height = math.max(3, height)
  -- The stretch shown: the whole clip, or from the focus's bar.
  local from: number = 0
  local span = c.length
  local per = span / cols
  if per < 0.25 - EPS then
    per = 0.25
  end
  if span / per > cols then
    local f: types.Note
    for _, n in ipairs(notes) do
      if n.id == focus then
        f = n
      end
    end
    if f then
      from = paw.time.bar_start(paw.time.bar_of(c.start + f.start)) - c.start
    end
    span = cols * per
  end
  local lo, hi = 127, 0
  for _, n in ipairs(notes) do
    if n.start + n.length > from and n.start < from + span then
      lo, hi = math.min(lo, n.pitch), math.max(hi, n.pitch)
    end
  end
  if lo > hi then
    return {{text = "no notes here", style = "Dim"}}
  end
  lo, hi = math.max(0, lo - 1), math.min(127, hi + 1)
  local step = math.max(1, math.ceil((hi - lo + 1) / height))
  local rows = math.ceil((hi - lo + 1) / step)
  local grid: {{string}} = {}
  for r = 1, rows do
    grid[r] = {}
    for x = 1, cols do
      grid[r][x] = " "
    end
  end
  -- Bar lines, on the left edge of the column a bar starts in.
  local bar = paw.time.bar_of(c.start + from)
  while true do
    local b = paw.time.bar_start(bar) - c.start
    if b >= from + span - EPS then
      break
    end
    local x = math.floor((b - from) / per + EPS) + 1
    if x >= 1 and x <= cols then
      for r = 1, rows do
        grid[r][x] = "▏"
      end
    end
    bar = bar + 1
  end
  for _, n in ipairs(notes) do
    local r = rows - math.floor((n.pitch - lo) / step)
    local x0 = math.floor((n.start - from) / per + EPS) + 1
    local x1 = math.max(x0, math.ceil((n.start + n.length - from) / per - EPS))
    local ch = n.id ~= nil and n.id == focus and "▓" or "█"
    for x = math.max(1, x0), math.min(cols, x1) do
      grid[r][x] = ch
    end
  end
  local out: {Line} = {}
  for r = 1, rows do
    local pitch = lo + (rows - r) * step
    local name = (pitch % 12 == 0 or r == 1 or r == rows) and paw.music.name(pitch) or ""
    out[r] = {text = string.format("%-4s ", name) .. table.concat(grid[r]), style = "PickRoll"}
  end
  out[#out + 1] = {
    text = string.format("     %s, %g beats from %s", c.name, span, paw.time.format(c.start + from)), style = "Dim"
  }
  return out
end

--- An audio clip's sound as `rows` lines `width` columns wide.
function M.wave(clip_id: integer, width: integer, rows?: integer): {Line}
  local ok, peaks = pcall(api.clip_peaks, clip_id, math.max(1, math.min(width, 512))) as (boolean, {types.Peak})
  if not ok or #peaks == 0 then
    return {}
  end
  local outline: {number} = {}
  for i, p in ipairs(peaks) do
    outline[i] = math.max(math.abs(p[1] or 0), math.abs(p[2] or 0))
  end
  local out: {Line} = {}
  for _, row in ipairs(paw.audition.outline_lines(outline, width, rows or 4)) do
    out[#out + 1] = {text = row.text, style = "PickWave"}
  end
  return out
end

--- A clip drawn as `M.roll` or `M.wave` draws it, whichever it is.
function M.clip(clip_id: integer, width: integer, height: integer, focus?: integer): {Line}
  local ok, c = pcall(api.clip_get, clip_id) as (boolean, types.Clip)
  if not ok then
    return {}
  end
  if c.kind == "midi" then
    return M.roll(clip_id, width, height, focus)
  end
  return M.wave(clip_id, width, math.min(height, 6))
end

--- The width of the preview pane of a picker as wide as `paw.pick.open`
--- makes one, for previews that draw to fit.
function M.width(): integer
  local w = api.ui_size()
  return math.max(20, math.floor(math.min(120, w - 4) * 0.4) - 2)
end

api.hl_set("PickRoll", {fg = theme.palette.green})

return M
