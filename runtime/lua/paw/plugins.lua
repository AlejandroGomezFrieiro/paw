-- `paw.plugins`: plugins an extension ships, and what plugins call their keys.
--
--   paw.plugins.add_dir(dir)        -- look for CLAP and VST3 plugins in `dir` too
--   paw.plugins.remove_dir(dir)     -- and no more
--   paw.plugins.attach(path)        -- a native library that can take each plugin (ARA)
--   paw.plugins.from["clap:dev.paw.sampler"]   -- "sampler": who added it
--   paw.plugins.note_names(device)  -- { [36] = "Kick", ... } (CLAP note-name)
--   paw.plugins.key_names(track)    -- the same for a track's devices together
local api = paw.api

local M = {}

--- Which extension (or directory) each device kind added by `add_dir`
--- came from, by kind.
M.from = {}

--- The directories added, by path: `{ dir, kinds, ext }`, the device kinds
--- found there and the extension that added it. A directory that goes
--- (`remove_dir`, or the unload of its extension) is searched no more, and
--- its device kinds are offered no more.
M.dirs = require("paw.registry").new("plugin_dirs", "plugin directories", {
  changed = function(_, dir, old)
    if dir or not old then return end
    for _, kind in ipairs(old.kinds) do
      M.from[kind] = nil
    end
    api.plugins_remove_dir(old.dir, old.kinds)
  end,
})

--- How long a device's key names are kept before it is asked again, in
--- milliseconds: an instrument may load another sound and name its keys anew.
M.names_ttl = 2000

--- Find CLAP and VST3 plugins in `dir` and in the usual plugin folders, for
--- the rest of the session. Register the plugins in `dir` now. paw makes
--- the devices of these plugins that a project contains and that paw could
--- not make before. The list shows them as from `name` (by default the extension
--- whose directory contains `dir`, or `dir`). It also works with
--- `--no-plugins`. Returns `{ kinds, notes }`: the device kinds found and
--- the files that paw cannot use. Returns nil where paw cannot find plugins.
---   paw.plugins.add_dir(here .. "/result/lib/clap")   -- `here`: the extension's directory
function M.add_dir(dir, name)
  dir = tostring(dir)
  local found = api.plugins_add_dir(dir)
  if not found then return nil end
  local by = paw.commands.owner()
  name = name or by or dir:match("extensions/([^/]+)") or dir
  local added = {}
  for _, kind in ipairs(found.kinds) do
    M.from[kind] = name
    added[kind] = true
  end
  M.dirs:put(dir, { dir = dir, kinds = found.kinds, ext = by })
  for _, note in ipairs(found.notes) do
    api.log("plugin scan: " .. note)
  end
  for _, id in ipairs(api.track_list({ all = true })) do
    for _, device in ipairs(api.track_get(id).devices) do
      local d = api.device_get(device)
      if added[d.kind] and d.missing then pcall(api.device_restart, device) end
    end
  end
  paw.emit("plugins.scanned", { notes = found.notes, dir = dir, kinds = found.kinds })
  return found
end

--- Load an attachment: a native library that an extension ships, which
--- can take each CLAP plugin that paw makes from now on, and reach the
--- extensions of the plugin (ARA). The library implements
--- `crates/paw-plugins/include/paw_attach.h`. Returns the name of the
--- attachment, or nil and the reason when paw cannot load it.
---   paw.plugins.attach(here .. "/lib/paw-ara.so")   -- "ara"
function M.attach(path)
  local ok, name = pcall(api.plugins_attach, tostring(path))
  if not ok then return nil, tostring(name):gsub("^.-: ", "", 1) end
  M.attached[name] = tostring(path)
  return name
end

--- The attachments loaded, by name: the path of each.
M.attached = {}

--- Stop to find plugins in `dir`, and stop to offer the devices found
--- there. The devices that exist continue to work.
function M.remove_dir(dir) M.dirs:remove(tostring(dir)) end

local names = {}

--- What the built-in devices call their keys, by kind: the pieces of the
--- `drums` kit on the General MIDI drum notes (crates/paw-engine/src/devices/drums.rs).
M.builtin_names = {
  drums = {
    [35] = "Kick 2",
    [36] = "Kick",
    [37] = "Rim",
    [38] = "Snare",
    [39] = "Clap",
    [40] = "Snare 2",
    [41] = "Floor tom",
    [42] = "Closed hat",
    [43] = "Floor tom 2",
    [44] = "Pedal hat",
    [45] = "Low tom",
    [46] = "Open hat",
    [47] = "Mid tom",
    [48] = "High-mid tom",
    [49] = "Crash",
    [50] = "High tom",
    [51] = "Ride",
    [52] = "China",
    [53] = "Ride bell",
    [54] = "Tambourine",
    [55] = "Splash",
    [56] = "Cowbell",
    [57] = "Crash 2",
    [59] = "Ride 2",
  },
}

--- What a device calls its keys, by pitch: a plugin that implements CLAP's
--- `note-name` (a drum kit's drums, a sampler's keyswitches), or a built-in
--- device of `M.builtin_names` (the `drums` kit). Empty for the rest. Asked
--- again after `M.names_ttl`.
function M.note_names(device)
  local now = api.now()
  local known = names[device]
  if known and (known.builtin or now - known.at < M.names_ttl) then return known.names end
  -- A device keeps its kind: a built-in one is looked at once.
  local ok_kind, d = pcall(api.device_get, device)
  local builtin = ok_kind and d and M.builtin_names[d.kind]
  if builtin then
    names[device] = { at = now, names = builtin, builtin = true }
    return builtin
  end
  local ok, list = pcall(api.device_note_names, device)
  names[device] = { at = now, names = ok and list or {} }
  return names[device].names
end

--- The key names of all the devices of a track. When two devices name a
--- key, the first in the chain wins.
--- @type function(track: integer): {integer:string}
function M.key_names(track)
  local ok, t = pcall(api.track_get, track)
  local out = {}
  if not ok then return out end
  for i = #t.devices, 1, -1 do
    for pitch, name in pairs(M.note_names(t.devices[i])) do
      out[pitch] = name
    end
  end
  return out
end

paw.on("device.removed", function(e)
  if e and e.id then names[e.id] = nil end
end)
paw.on("device.changed", function(e)
  if e and e.id then names[e.id] = nil end
end)

return M
