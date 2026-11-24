-- `paw.plugins`: plugins an extension ships, and what plugins call their keys.
--
--   paw.plugins.add_dir(dir)        -- look for CLAP and VST3 plugins in `dir` too
--   paw.plugins.remove_dir(dir)     -- and no more
--   paw.plugins.attach(path)        -- a native library that can take each plugin (ARA)
--   paw.plugins.from["clap:dev.paw.sampler"]   -- "sampler": who added it
--   paw.plugins.note_names(device)  -- { [36] = "Kick", ... } (CLAP note-name)
--   paw.plugins.key_names(part)    -- the same for a part's devices together
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local registry = require("paw.registry")
local type types = require("paw.types")
local type partial = require("paw.partial")
local type CommandsModule = require("paw.commands")

--- A directory of plugins that `add_dir` was given, with the device kinds
--- found there and the extension that added it.
local record Dir
  dir: string
  kinds: {string}
  ext: string
end

--- The payload of `plugins.scanned`: the notes of a scan (the files that
--- paw cannot use), and what it was about: a directory and the kinds
--- found there (`add_dir`), or the name given to `:plugins.rescan`.
local record Scanned
  notes: {string}
  dir: string
  kinds: {string}
  name: string
end

--- What a device called its keys, and when it was asked.
local record Names
  at: number
  names: {integer: string}
  builtin: boolean
end

local record Paw is partial.Paw
  commands: CommandsModule
end
local paw = (_G as {string: Paw}).paw

local record M
  type Dir = Dir
  type Scanned = Scanned

  --- Which extension (or directory) each device kind added by `add_dir`
  --- came from, by kind.
  from: {string: string}
  --- The directories added, by path: `{ dir, kinds, ext }`, the device kinds
  --- found there and the extension that added it. A directory that goes
  --- (`remove_dir`, or the unload of its extension) is searched no more, and
  --- its device kinds are offered no more.
  dirs: registry.Registry<Dir>
  --- The attachments loaded, by name: the path of each.
  attached: {string: string}
  --- How long a device's key names are kept before it is asked again, in
  --- milliseconds: an instrument may load another sound and name its keys anew.
  names_ttl: number
  --- What the built-in devices call their keys, by kind: the pieces of the
  --- `drums` kit on the General MIDI drum notes (crates/paw-engine/src/devices/drums.rs).
  builtin_names: {string: {integer: string}}
  --- The event `plugins.scanned`: a scan for plugins ended.
  scanned: events.Event<Scanned>
end

M.scanned = events.event("plugins.scanned")
M.from = {}
M.attached = {}
M.names_ttl = 2000

M.dirs = registry.new(
  "plugin_dirs",
  "plugin directories",
  {
    changed = function(_: string, dir: Dir, old: Dir)
      if dir or not old then
        return
      end
      for _, kind in ipairs(old.kinds) do
        M.from[kind] = nil
      end
      api.plugins_remove_dir(old.dir, old.kinds)
    end,
  }
)

--- Find CLAP and VST3 plugins in `dir` and in the usual plugin folders, for
--- the rest of the session. Register the plugins in `dir` now. paw makes
--- the devices of these plugins that a project contains and that paw could
--- not make before. The list shows them as from `name` (by default the extension
--- whose directory contains `dir`, or `dir`). It also works with
--- `--no-plugins`. Returns `{ kinds, notes }`: the device kinds found and
--- the files that paw cannot use. Returns nil where paw cannot find plugins.
---   paw.plugins.add_dir(here .. "/result/lib/clap")   -- `here`: the extension's directory
function M.add_dir(dir: string, name?: string): types.PluginDir
  dir = tostring(dir)
  local found = api.plugins_add_dir(dir)
  if not found then
    return nil
  end
  local by = paw.commands.owner()
  name = name or by or dir:match("extensions/([^/]+)") or dir
  local added: {string: boolean} = {}
  for _, kind in ipairs(found.kinds) do
    M.from[kind] = name
    added[kind] = true
  end
  M.dirs:put(dir, {dir = dir, kinds = found.kinds, ext = by})
  for _, note in ipairs(found.notes) do
    api.log("plugin scan: " .. note)
  end
  for _, id in ipairs(api.part_list({all = true})) do
    for _, device in ipairs(api.part_get(id).devices) do
      local d = api.device_get(device)
      if added[d.kind] and d.missing then
        pcall(api.device_restart, device)
      end
    end
  end
  events.emit(M.scanned, {notes = found.notes, dir = dir, kinds = found.kinds})
  return found
end

--- Load an attachment: a native library that an extension ships, which
--- can take each CLAP plugin that paw makes from now on, and reach the
--- extensions of the plugin (ARA). The library implements
--- `crates/paw-plugins/include/paw_attach.h`. Returns the name of the
--- attachment, or nil and the reason when paw cannot load it.
---   paw.plugins.attach(here .. "/lib/paw-ara.so")   -- "ara"
function M.attach(path: string): string, string
  local ok, name = pcall(api.plugins_attach, tostring(path)) as (boolean, string)
  if not ok then
    local reason = tostring(name):gsub("^.-: ", "", 1)
    return nil, reason
  end
  M.attached[name] = tostring(path)
  return name
end

--- Stop to find plugins in `dir`, and stop to offer the devices found
--- there. The devices that exist continue to work.
function M.remove_dir(dir: string)
  M.dirs:remove(tostring(dir))
end

local names: {integer: Names} = {}

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
function M.note_names(device: integer): {integer: string}
  local now = api.now()
  local known = names[device]
  if known and (known.builtin or now - known.at < M.names_ttl) then
    return known.names
  end
  -- A device keeps its kind: a built-in one is looked at once.
  local ok_kind, d = pcall(api.device_get, device) as (boolean, types.Device)
  local builtin = ok_kind and d and M.builtin_names[d.kind]
  if builtin then
    names[device] = {at = now, names = builtin, builtin = true}
    return builtin
  end
  local ok, list = pcall(api.device_note_names, device) as (boolean, {integer: string})
  names[device] = {at = now, names = ok and list or {}}
  return names[device].names
end

--- The key names of all the devices of a part. When two devices name a
--- key, the first in the chain wins.
function M.key_names(part: integer): {integer: string}
  local ok, t = pcall(api.part_get, part) as (boolean, types.Part)
  local out: {integer: string} = {}
  if not ok then
    return out
  end
  for i = #t.devices, 1, -1 do
    for pitch, name in pairs(M.note_names(t.devices[i])) do
      out[pitch] = name
    end
  end
  return out
end

events.on(
  kernel.device_removed,
  function(e: kernel.Item)
    if e and e.id then
      names[e.id] = nil
    end
  end
)
events.on(
  kernel.device_changed,
  function(e: kernel.Item)
    if e and e.id then
      names[e.id] = nil
    end
  end
)

return M
