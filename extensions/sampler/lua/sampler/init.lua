-- The sampler extension's state: where its plugin is, the sampler device
-- of a track, loading an instrument into it, what the instrument says of
-- itself (`describe`), and the instruments found in the library folders.
local api = paw.api

local M = {}

--- The plugin's kind of device.
M.KIND = "clap:dev.paw.sampler"
--- The files it reads.
M.FORMATS = { sfz = "SFZ", dspreset = "Decent Sampler" }

local exists = paw.api.fs_exists

--- Where `paw-sampler.clap` is: the `sampler_plugin_dir` option, else
--- `clap/` beside the extension (where its Nix package, and
--- `native/build.sh`, put it). Nil when neither has it.
function M.plugin_dir()
  local loaded = paw.ext.loaded.sampler
  for _, dir in ipairs({ paw.opt.sampler_plugin_dir or "", loaded and (loaded.path .. "/clap") or "" }) do
    if dir ~= "" and exists(dir .. "/paw-sampler.clap") then return dir end
  end
end

--- Whether the plugin can be made: it is among the device types.
function M.available() return api.device_find({ kind = M.KIND }) ~= nil end

--- The track's sampler device, or nil.
function M.device_of(track_id)
  local ok, track = pcall(api.track_get, track_id)
  if not ok then return nil end
  for _, id in ipairs(track.devices) do
    if api.device_get(id).kind == M.KIND then return id end
  end
end

-- What each device said of itself, by device: `{ path, value }`.
local described = {}

--- What the device's instrument says of itself (decoded `describe`):
--- name, format, path, range `{ lo, hi }`, keyswitches `{ pitch, name }`,
--- articulations `{ name, m2, keyswitch, default, custom }`, warnings,
--- params, and `error` when the file could not be read. Nil while the
--- device is not running.
function M.describe(device)
  local ok, text = pcall(api.device_call, device, "describe")
  if not ok then return nil end
  local value = paw.json.decode(text)
  described[device] = { path = value.path, value = value }
  return value
end

--- The last description of the device, asked for again only when it has none.
function M.known(device)
  local d = described[device]
  if d then return d.value end
  return M.describe(device)
end

--- Load an instrument file into the device, as one edit that undo takes
--- back (and a trial, inside `paw.audition.try`): the plugin's state, which
--- names the file, is kept in the project. Returns the instrument's
--- description, or nil and why.
function M.load(device, path)
  local name = path:match("([^/]+)$"):gsub("%.[%w]+$", "")
  local ok, err = pcall(api.device_load, device, { name = name, factory = "file:" .. path })
  described[device] = nil
  if not ok then return nil, (tostring(err):gsub("^.-: ", "")) end
  local d = M.describe(device)
  paw.emit("sampler.loaded", { device = device, path = path })
  return d
end

--- A few words on an instrument: "Violins · SFZ · 3 articulations".
function M.summary(d)
  if not d then return "not running" end
  if d.error then return "cannot read " .. (d.path ~= "" and d.path or "the instrument") end
  if not d.name or d.name == "" then return "no instrument yet" end
  local words = { d.name, M.FORMATS[d.format] or d.format }
  local arts = d.articulations and #d.articulations or 0
  if arts > 0 then words[#words + 1] = arts .. (arts == 1 and " articulation" or " articulations") end
  return table.concat(words, " · ")
end

--- The folders searched for instruments: the `sampler_libraries` option
--- (folders separated by `:`) and `instruments/` in paw's data folder.
function M.roots()
  local roots = {}
  for dir in (paw.opt.sampler_libraries or ""):gmatch("[^:]+") do
    roots[#roots + 1] = (dir:gsub("^~", os.getenv("HOME") or "~"))
  end
  local data = os.getenv("XDG_DATA_HOME") or ((os.getenv("HOME") or ".") .. "/.local/share")
  roots[#roots + 1] = data .. "/paw/instruments"
  return roots
end

--- Every instrument file under `roots` (default `M.roots()`), as `{ path,
--- name, format, folder }`, sorted by path. Looks six folders deep and at
--- most at 5000 files.
function M.instruments(roots)
  local found, seen = {}, 0
  local function walk(dir, depth, root)
    for _, entry in ipairs(api.read_dir(dir)) do
      seen = seen + 1
      if seen > 5000 then return end
      local path = dir .. "/" .. entry.name
      if entry.is_dir then
        if depth < 6 and not entry.name:match("^%.") then walk(path, depth + 1, root) end
      else
        local ext = entry.name:match("%.([%w]+)$")
        ext = ext and ext:lower()
        if ext and M.FORMATS[ext] then
          found[#found + 1] = {
            path = path,
            name = entry.name:gsub("%.[%w]+$", ""),
            format = ext,
            folder = dir:sub(#root + 2),
          }
        end
      end
    end
  end
  for _, root in ipairs(roots or M.roots()) do
    walk(root, 0, root)
  end
  table.sort(found, function(a, b) return a.path < b.path end)
  return found
end

--- A short phrase that shows an instrument off: a rising arpeggio in the
--- middle of its range, for the picker to play.
function M.phrase(d)
  local lo, hi = 48, 72
  if d and type(d.range) == "table" and d.range[1] then
    lo, hi = d.range[1], d.range[2]
  end
  local mid = math.floor((lo + hi) / 2)
  local root = math.max(lo, math.min(hi - 12, mid - 6))
  local notes = {}
  for i, step in ipairs({ 0, 4, 7, 12, 7, 4 }) do
    local pitch = math.min(hi, root + step)
    notes[i] = { pitch = pitch, start = (i - 1) * 0.5, length = i == 6 and 1.5 or 0.45, velocity = 96 }
  end
  return notes
end

return M
