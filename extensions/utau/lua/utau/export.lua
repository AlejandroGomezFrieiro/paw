-- Getting the singing out: OpenUtau's `.ustx`, UTAU's `.ust` and MIDI with
-- lyrics, and opening a track in OpenUtau.
--
-- The vocal tracks are described as JSON (notes with the
-- payload the engine sings from, curves as knots in OpenUtau's ticks and
-- units) and `paw-utau-engine --export` builds the OpenUtau project with the
-- same mapping the live engine uses, then saves it with OpenUtau's own
-- writers. The format follows the file's extension; a `.ust` holds one part,
-- so a second part goes to `name-2.ust`, and so on.
local api = paw.api
local utau = require("utau")
local engine = require("utau.engine")
local json = require("utau.json")

local M = {}

M.FORMATS = { ustx = true, ust = true, mid = true, midi = true }

--- The vocal tracks to export as the engine's JSON description. `opts`:
--- `tracks` (track ids; all vocal tracks when absent), `clip` (one clip).
function M.describe(opts)
  opts = opts or {}
  local snap = utau.snapshot()
  api.project_get()
  local wanted
  if opts.tracks then
    wanted = {}
    for _, id in ipairs(opts.tracks) do wanted[tostring(id)] = true end
  end
  if opts.clip then wanted = { [tostring(api.clip_get(opts.clip).track)] = true } end
  local desc = {
    tempos = json.array((function()
      local out = {}
      for i, t in ipairs(snap.tempos) do out[i] = { pos = t.tick, bpm = t.bpm } end
      return out
    end)()),
    timesigs = json.array((function()
      local out = {}
      for i, s in ipairs(snap.sigs) do out[i] = { bar = s.bar, num = s.num, den = s.den } end
      return out
    end)()),
    tracks = json.array(),
  }
  for _, t in ipairs(snap.tracks) do
    if not wanted or wanted[t.id] then
      local track = {
        name = t.name ~= "" and t.name or "Vocal", singer = t.config.singer or "",
        phonemizer = t.config.phonemizer or "", renderer = t.config.renderer or "",
        mute = t.muted and true or false, parts = json.array(),
      }
      for _, p in ipairs(snap.parts) do
        if p.track == t.id and (not opts.clip or p.clip == opts.clip) then
          local part = { name = p.name or "", pos = p.pos, dur = p.dur, notes = json.array(), curves = json.array() }
          for _, n in ipairs(p.notes) do
            part.notes[#part.notes + 1] = { pos = n.pos, dur = n.dur, tone = n.tone, payload = paw.api.base64_encode(n.payload, { url = true, pad = false }) }  -- as the engine's `--export` reads it
          end
          for _, c in ipairs(p.curves) do
            if #c.knots > 0 then
              local knots = json.array()
              for i, k in ipairs(c.knots) do knots[i] = { k[1], k[2], k[3] or 1, k[4] or 0 } end
              part.curves[#part.curves + 1] = { abbr = c.abbr, knots = knots }
            end
          end
          track.parts[#track.parts + 1] = part
        end
      end
      desc.tracks[#desc.tracks + 1] = track
    end
  end
  return desc
end

--- Write `path` (`.ustx`, `.ust` or `.mid`). Returns the files written.
function M.write(path, opts)
  if path:sub(1, 1) ~= "/" then path = (os.getenv("PWD") or ".") .. "/" .. path end
  local ext = (path:match("%.(%w+)$") or ""):lower()
  if not M.FORMATS[ext] then error("export to .ustx, .ust or .mid, not `" .. path .. "`", 0) end
  local desc = M.describe(opts)
  if #desc.tracks == 0 then error("no vocal track to export", 0) end
  local input = engine.tmp(".json")
  local file = assert(io.open(input, "wb"))
  file:write(json.encode(desc))
  file:close()
  local dir = path:match("^(.*)/[^/]*$")
  if dir and dir ~= "" then pcall(paw.api.fs_mkdir, dir) end
  local code, out = engine.tool({ "--export", input, "--out", path }, 120)
  os.remove(input)
  local files = {}
  for line in out:gmatch("[^\n]+") do
    if line:sub(1, 1) == "/" or line == path then
      local f = io.open(line, "rb")
      if f then
        f:close()
        files[#files + 1] = line
      end
    end
  end
  if code ~= 0 or #files == 0 then
    error("export failed: " .. (out:match("paw%-utau%-engine: ([^\n]+)") or ("exit code " .. tostring(code))), 0)
  end
  return files
end

-- Opening in OpenUtau -------------------------------------------------------------

--- Where `open` writes: beside the project file, named after it; in the
--- program's data directory for a project that is not saved yet.
function M.open_path()
  local project = api.project_get()
  local dir, stem
  if project.path and project.path ~= "" then
    dir, stem = project.path:match("^(.*)/([^/]-)%.?[^./]*$")
  end
  if not dir or dir == "" then
    dir = api.env().data_dir .. "/utau/openutau"
    stem = (project.name ~= "" and project.name or "untitled"):gsub("[^%w%-_ ]", "_")
  end
  return string.format("%s/%s.ustx", dir, stem)
end

--- What starts OpenUtau on a file: `paw.opt.utau_openutau`, else
--- `$PAW_UTAU_OPENUTAU`, else `OpenUtau` on the PATH.
function M.open_command(path)
  local command = paw.opt.utau_openutau
  if not command or command == "" then command = os.getenv("PAW_UTAU_OPENUTAU") end
  if not command or command == "" then command = "OpenUtau" end
  local argv = {}
  for word in command:gmatch("%S+") do argv[#argv + 1] = word end
  argv[#argv + 1] = path
  return argv
end

--- Export the vocal tracks to a `.ustx` beside the project and start
--- OpenUtau on it, unless `opts.dry`. Returns the file and the command.
function M.open(opts)
  opts = opts or {}
  local path = opts.path or M.open_path()
  M.write(path, { tracks = opts.tracks })
  local argv = M.open_command(path)
  if not opts.dry then api.proc_spawn(argv, { log = engine.log_path() }) end
  return path, argv
end

return M
