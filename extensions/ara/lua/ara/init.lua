-- ARA plugins on paw's tracks. The native part (native/bridge.cpp) is an
-- attachment that paw offers each CLAP plugin: it gives an ARA plugin the
-- track's audio clips and the tempo, and keeps the plugin's ARA archive
-- beside the device's state. This module finds the attachment, puts ARA
-- plugins on tracks and reads what they found in the clips.
local api = paw.api

local M = {}

local exists = paw.api.fs_exists

--- Where `paw-ara.so` is: the `ara_bridge` option, `lib/` beside the
--- extension (where its Nix package puts it), or `$PAW_ARA_BRIDGE`.
function M.bridge_path()
  local loaded = paw.ext.loaded and paw.ext.loaded.ara
  for _, path in ipairs({
    paw.opt.ara_bridge or "",
    loaded and (loaded.path .. "/lib/paw-ara.so") or "",
    os.getenv("PAW_ARA_BRIDGE") or "",
  }) do
    if path ~= "" and exists(path) then return path end
  end
end

--- Load the attachment. True when it is loaded; else nil and why.
function M.attach()
  if paw.plugins.attached.ara then return true end
  local path = M.bridge_path()
  if not path then return nil, "paw-ara.so not found" end
  local name, err = paw.plugins.attach(path)
  if not name then return nil, err end
  return true
end

--- Whether a kind of device says it is an ARA plugin (its CLAP features).
--- nil when paw does not know: a plugin file read by an older paw.
function M.is_ara_kind(kind, t)
  t = t or api.device_find({ kind = kind })
  if not t then return false end
  local features = t.features or {}
  if #features == 0 then return nil end
  for _, f in ipairs(features) do
    if f == "ara:supported" or f == "ara:required" then return true end
  end
  return false
end

--- The device kinds of the ARA plugins that paw knows.
function M.kinds()
  local out = {}
  for _, t in ipairs(api.device_find_all({ format = "clap" }) or {}) do
    if M.is_ara_kind(t.kind, t) then out[#out + 1] = t end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

--- What the plugin of a device says of its ARA document, or nil when the
--- device is not an ARA plugin: `{ plugin, manufacturer, clips, notes, ... }`.
function M.status(device)
  local ok, text = pcall(api.device_call, device, "ara.status", "")
  if not ok then return nil end
  local ok2, data = pcall(api.json_decode, text)
  return ok2 and data or nil
end

--- The ARA devices of a track, first to last.
function M.devices(track)
  local out = {}
  for _, id in ipairs(api.track_get(track).devices) do
    if M.status(id) then out[#out + 1] = id end
  end
  return out
end

--- Put an ARA plugin first on a track, so that it plays the track's clips.
--- Returns the device, or nil and why. A plugin that turns out not to be
--- an ARA plugin is taken away again, and leaves no undo step.
function M.add(track, kind)
  local ok, err = M.attach()
  if not ok then return nil, err end
  if M.is_ara_kind(kind) == false then return nil, kind .. " is not an ARA plugin" end
  local added, id = pcall(api.device_add, track, kind, { index = 1 })
  if not added then return nil, tostring(id) end
  if not M.status(id) then
    api.undo_discard()
    return nil, kind .. " is not an ARA plugin"
  end
  return id
end

--- The notes the plugin of a device found in the track's clips, in beats:
--- `{ { pitch, start, length, velocity } }`. While it is still at work:
--- nil and the part done (0 to 1).
function M.notes(device)
  local data = api.json_decode(api.device_call(device, "ara.notes", ""))
  if data.pending then return nil, data.progress or 0 end
  local notes = {}
  for _, n in ipairs(data.notes or {}) do
    local start = paw.tempo.seconds_to_beats(n.start)
    local stop = paw.tempo.seconds_to_beats(n.start + n.duration)
    local pitch = n.pitch
    if (pitch or -1) < 0 and (n.frequency or 0) > 0 then
      pitch = math.floor(69 + 12 * math.log(n.frequency / 440) / math.log(2) + 0.5)
    end
    -- A hit without a pitch (a drum) goes on one key.
    if (pitch or -1) < 0 then pitch = paw.opt.ara_unpitched_key end
    if pitch and pitch >= 0 and pitch <= 127 and stop > start then
      notes[#notes + 1] = {
        pitch = pitch,
        start = start,
        length = stop - start,
        velocity = math.max(1, math.min(127, math.floor((n.volume or 0.8) * 127 + 0.5))),
      }
    end
  end
  table.sort(notes, function(a, b) return a.start < b.start end)
  return notes
end

--- A one-line summary of an ARA device, for messages and `K`.
function M.summary(device)
  local s = M.status(device)
  if not s then return "not an ARA plugin" end
  local n = #(s.clips or {})
  local text = string.format("%s: %d clip%s on %s", s.plugin, n, n == 1 and "" or "s", s.track)
  if s.restored then text = text .. ", its edits restored from the project" end
  if s.error and s.error ~= "" then text = text .. " (" .. s.error .. ")" end
  return text
end

return M
