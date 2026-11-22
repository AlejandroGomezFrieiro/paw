-- Importing OpenUtau (.ustx), UTAU (.ust) and other singing projects.
--
-- OpenUtau's own readers do the parsing: `paw-utau-engine --convert` loads
-- the file and writes it out as a Lua table, which becomes vocal tracks here.
local api = paw.api
local engine = require("utau.engine")
local utau = require("utau")

local M = {}

--- What `paw-utau-engine --convert` makes of a file, as a table.
function M.read(path)
  local out = engine.tmp(".lua")
  local code, log = engine.tool({ "--convert", path, "--out", out }, 120)
  local chunk = code == 0 and loadfile(out)
  os.remove(out)
  if not chunk then
    error(
      "could not read " .. path .. ": " .. (log:match("paw%-utau%-engine: ([^\n]+)") or "see the engine's output"),
      0
    )
  end
  return setfenv(chunk, {})()
end

local CURVES = {}
for _, abbr in ipairs(utau.CURVES) do
  CURVES[abbr] = true
end

--- Add the tracks of a converted project after the existing ones. Returns the
--- new tracks' ids.
function M.add(project, opts)
  opts = opts or {}
  local resolution = project.resolution or 480
  local offset = opts.at or 0
  if project.tempos and project.tempos[1] then
    -- Tempo changes at ticks of the file, as steps; at the import's offset
    -- when it goes into a song that has its own.
    if offset == 0 then
      local points = {}
      for i, t in ipairs(project.tempos) do
        points[i] = { beat = (t.pos or 0) / resolution, bpm = t.bpm }
      end
      local sigs = {}
      for i, s in ipairs(project.timesigs or {}) do
        sigs[i] = {
          beat = 0,
          num = s.beatPerBar or s.num or 4,
          den = s.beatUnit or s.den or 4,
          bar = s.barPosition or s.bar or 0,
        }
      end
      paw.tempo.set_points(points, nil)
      -- Signatures are by bar in the file: place each where its bar starts.
      for _, s in ipairs(sigs) do
        paw.api.signature_set(paw.tempo.bar_start(s.bar + 1), s.num, s.den)
      end
    else
      paw.project.tempo = project.tempos[1].bpm
      if #project.tempos > 1 then
        paw.notify("utau: imported away from the start, only the file's first tempo is used", "warn")
      end
    end
  end
  local added = {}
  for _, t in ipairs(project.tracks or {}) do
    local track = api.track_add({ name = t.name ~= "" and t.name or "Vocal" })
    local device = api.device_add(track, "utau", {})
    added[#added + 1] = track
    local config = {}
    if t.singer ~= "" then config.singer = t.singer end
    if t.phonemizer ~= "" then config.phonemizer = t.phonemizer end
    if t.renderer ~= "" then config.renderer = t.renderer end
    if next(config) then utau.configure(track, config) end
    if t.mute then api.track_set(track, "mute", true) end
    local lanes = {}
    for _, part in ipairs(t.parts or {}) do
      local start = offset + part.pos / resolution
      local notes = {}
      for _, n in ipairs(part.notes or {}) do
        local props = {}
        for _, key in ipairs({ "tu", "po", "vb", "pp", "ex", "ph" }) do
          props[key] = n[key]
        end
        notes[#notes + 1] = {
          pitch = n.tone,
          start = n.pos / resolution,
          length = n.dur / resolution,
          velocity = 100,
          meta = { lyric = n.lyric, utau = next(props) and props or nil },
        }
      end
      api.clip_add(track, {
        name = part.name ~= "" and part.name or t.name,
        start = start,
        length = math.max(part.dur / resolution, 1 / resolution),
        notes = notes,
      })
      for _, curve in ipairs(part.curves or {}) do
        if CURVES[curve.abbr] then
          local points = lanes[curve.abbr] or {}
          lanes[curve.abbr] = points
          for i, x in ipairs(curve.xs) do
            points[#points + 1] = { start + x / resolution, curve.ys[i] }
          end
        end
      end
    end
    for abbr, points in pairs(lanes) do
      table.sort(points, function(a, b) return a[1] < b[1] end)
      api.lane_add(track, { target = "param", device = device, param = abbr, points = points })
    end
  end
  return added
end

--- Read a file and add its tracks.
function M.file(path, opts) return M.add(M.read(path), opts) end

return M
