-- The sound the engine sang, on its way to the vocal tracks' devices.
--
-- The `utau` device (devices/utau.lua, `lua:utau`) plays the phrases of the
-- voice its `voice` parameter names. Each phrase is written here to a file
-- of 32-bit floats, and what a voice holds is posted to every device of the
-- kind as the list of its files (`paw.api.device_post`): devices made later,
-- an offline render's among them, are given the same list before they play.
-- The devices map the files, so the sound is kept once, in the files.
--
-- Voices outlive tracks and projects, but not the program: the files are
-- under the cache, in a directory of this process's own, which goes when
-- it ends (or, if it ended without saying, when the next one starts).
local api = paw.api

local M = {
  DEVICE = "lua:utau",
  -- What the device was called when it was built into the program: projects
  -- saved then make it as the Lua device.
  OLD_DEVICE = "utau",
  -- voices[n][hash] = { start, rate, channels, quality, path }
  voices = {},
}

api.device_alias(M.OLD_DEVICE, M.DEVICE)

local seq = 0

local function cache_root()
  local base = os.getenv("XDG_CACHE_HOME")
  if not base or base == "" then base = (os.getenv("HOME") or "") .. "/.cache" end
  return base .. "/paw/utau-voices"
end

local dir

--- The directory this process keeps its phrases in, made the first time.
function M.dir()
  if dir then return dir end
  local root = cache_root()
  -- Directories left by programs that ended without saying.
  for _, item in ipairs(api.read_dir(root)) do
    local pid = tonumber(item.name)
    if item.is_dir and pid and #api.read_dir("/proc/" .. pid) == 0 then
      pcall(api.fs_remove, root .. "/" .. item.name)
    end
  end
  dir = root .. "/" .. api.env().pid
  pcall(paw.api.fs_mkdir, dir)
  return dir
end

paw.on("exit", function()
  if dir then pcall(api.fs_remove, dir) end
end)

--- A new file holding `raw`, named so that no file a device has mapped is
--- ever written over.
local function write(prefix, raw)
  seq = seq + 1
  local path = string.format("%s/%s-%d.f32", M.dir(), prefix, seq)
  local file = assert(io.open(path .. ".tmp", "wb"))
  file:write(raw)
  file:close()
  assert(os.rename(path .. ".tmp", path))
  return path
end

--- The voice a device plays, or nil when it has none yet.
function M.voice_of(device)
  local n = math.floor(api.device_get(device).params.voice or 0)
  if n >= 1 then return n end
end

--- Tell every device what voice `n` holds, then let go of `old` files.
local function post(n, old)
  local lines = {}
  for hash, p in pairs(M.voices[n] or {}) do
    lines[#lines + 1] = string.format("%s %.17g %d %d %d %s", hash, p.start, p.rate, p.channels, p.quality, p.path)
  end
  table.sort(lines)
  local refused = api.device_post(M.DEVICE, "voice." .. n, table.concat(lines, "\n"))
  for _, path in ipairs(old or {}) do os.remove(path) end
  if refused[1] then error("a vocal device did not take voice " .. n .. ": " .. refused[1].error, 0) end
end

--- Give the voice of `device` a phrase: `raw` is its samples as 32-bit
--- floats, interleaved when there are two channels; `start` in project
--- seconds; `quality` 0 for a draft, 1 for final. A phrase of the same hash
--- is replaced, unless it is of better quality.
function M.put(device, hash, start, rate, channels, quality, raw)
  local n = M.voice_of(device)
  if not n then error("the device has no voice: set its `voice` parameter first", 2) end
  if channels ~= 1 and channels ~= 2 or not (rate > 0) then
    error("phrases are mono or stereo, at a positive sample rate", 2)
  end
  if #raw % (4 * channels) ~= 0 then error("the samples do not fill whole frames", 2) end
  hash = tostring(hash)
  local voice = M.voices[n] or {}
  M.voices[n] = voice
  local before = voice[hash]
  if before and before.quality > quality then return end
  voice[hash] = { start = start, rate = rate, channels = channels, quality = quality,
    path = write("v" .. n .. "-" .. hash, raw) }
  post(n, before and { before.path })
end

--- Keep only the phrases of `device`'s voice whose hashes are listed.
function M.keep(device, hashes)
  local n = M.voice_of(device)
  if not n or not M.voices[n] then return end
  local wanted = {}
  for _, h in ipairs(hashes) do wanted[tostring(h)] = true end
  local old = {}
  for hash, p in pairs(M.voices[n]) do
    if not wanted[hash] then
      old[#old + 1] = p.path
      M.voices[n][hash] = nil
    end
  end
  if #old > 0 then post(n, old) end
end

--- Empty the voice of `device`.
function M.clear(device)
  local n = M.voice_of(device)
  if not n then return end
  local old = {}
  for _, p in pairs(M.voices[n] or {}) do old[#old + 1] = p.path end
  M.voices[n] = {}
  post(n, old)
end

local last_audition

--- Play a short clip on `device` at once, transport or not.
function M.audition(device, rate, channels, raw)
  local path = write("audition", raw)
  api.device_call(device, "audition", string.format("%d %d %s", rate, channels, path))
  if last_audition then os.remove(last_audition) end
  last_audition = path
end

--- What the device of voice `n` holds: `{ hash, start, seconds, quality }`
--- per phrase, by start, as the device itself says.
function M.list(device)
  local out = {}
  local text = api.device_call(device, "list", tostring(M.voice_of(device) or 0))
  for line in text:gmatch("[^\n]+") do
    local hash, start, seconds, quality = line:match("^(%S+) (%S+) (%S+) (%S+)$")
    out[#out + 1] = { hash = hash, start = tonumber(start), seconds = tonumber(seconds), quality = tonumber(quality) }
  end
  return out
end

return M
