-- The plugstate extension: what a plugin holds besides its parameters (the
-- model of an amp, an impulse response, an instrument file), read and set
-- through adapters, the files to choose from, and named snapshots of a
-- device's whole state.
--
-- An adapter knows one family of plugins:
--
--   plugstate.adapter({
--     name = "nam",
--     desc = "Neural Amp Modeler models",
--     matches = function(d) return ... end,          -- d = paw.api.device_get(id)
--     slots = function(id, d) return { slot, ... } end,
--     load = function(id, d, slot, value) return spec end,  -- for paw.api.device_load
--     describe = function(path) return "a few words" end,   -- optional
--   })
--
-- A slot is `{ key, label, what, types = { "nam" }, value }`: `what` names
-- the thing in the words of the user ("model"), `types` are the file name
-- extensions it takes (none: any file), `value` is the file now.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local type types = require("paw.types")
local type events = require("paw.events")

local api = paw.api

local record M
  --- What a slot holds: a file (its path), a text or a number.
  enum SlotKind
    "file"
    "text"
    "number"
  end

  --- The value of a slot: a path, a text, a number (an LV2 property can
  --- hold a boolean).
  type SlotValue = string | number | boolean

  --- A file to choose for a slot: its path, its name, and its folder
  --- under the root of the library it was found in.
  interface File
    path: string
    name: string
    folder: string
  end

  --- A model of a TONE3000 block: its id and name, the address of its
  --- file and the file the user chose.
  record Model
    id: integer
    name: string
    url: string
    path: string
  end

  --- What an adapter reads and sets of a plugin's state: `what` names it
  --- in the words of the user ("model"), `types` are the file name
  --- extensions it takes (none: any file), `value` is what it holds now.
  record Slot
    key: string
    label: string
    what: string
    kind: SlotKind
    types: {string}
    value: SlotValue
    --- An LV2 property: its URI.
    uri: string
    --- A value of a described JUCE plugin: the name of its path.
    path: string
    --- More folders to look in for files, before the library's.
    folders: {string}
    --- Choices that are not one file each (the presets in a pack): the
    --- slot lists them.
    list: function(roots?: {string}): {File}
    --- The values a text slot takes.
    choices: {string}
    --- The models of a TONE3000 block.
    models: {Model}
  end

  --- A family of plugins: which devices it knows (`matches`), what it
  --- sets of their state (`slots`), and how (`load`: what
  --- `paw.api.device_load` takes). `describe` says a few words of a file,
  --- `name_of` names one. An adapter with `fallback` is asked last.
  record Adapter
    name: string
    desc: string
    fallback: boolean
    matches: function(d: types.Device): boolean
    slots: function(id: integer, d: types.Device): {Slot}
    load: function(id: integer, d: types.Device, slot: Slot, value: SlotValue): types.PresetLoad
    describe: function(path: string): string
    name_of: function(path: string): string
  end

  --- The whole state of a device, kept with a name.
  record Snapshot
    name: string
    state: string
    params: {string: number}
  end

  --- What TONE3000 gave a slot (`tone3000_search`): the tone, the model,
  --- its author, license and address.
  record ToneRef
    tone_id: integer
    tone: string
    model_id: integer
    model: string
    author: string
    license: string
    url: string
  end

  --- What plugstate keeps in the meta of a device (`meta.plugstate`): the
  --- snapshots, the name of the one last recalled or kept, and what each
  --- slot holds from TONE3000.
  record Data
    snapshots: {Snapshot}
    current: string
    tone3000: {string: ToneRef}
  end

  --- The payload of `plugstate.loaded`.
  record Loaded
    device: integer
    slot: string
    value: SlotValue
  end

  --- The payload of `plugstate.recalled`.
  record Recalled
    device: integer
    name: string
  end

  adapters: {Adapter}
  --- Choose a file for a slot in a picker (`plugstate.commands` sets it).
  pick: function(id: integer, slot: Slot, query?: string)
  --- Choose a snapshot in a picker (`plugstate.commands` sets it).
  pick_snapshot: function(id: integer)
  --- The event `plugstate.loaded`: a slot of a device was set.
  loaded: events.Event<Loaded>
  --- The event `plugstate.recalled`: a snapshot was recalled.
  recalled: events.Event<Recalled>
end

local type Slot = M.Slot
local type SlotValue = M.SlotValue
local type Data = M.Data

M.adapters = {}
M.loaded = paw.events.event("plugstate.loaded")
M.recalled = paw.events.event("plugstate.recalled")
-- The folders of models and impulse responses, separated by `:`.
local folders = paw.option.define("plugstate_folders", "")

function M.basename(path: string): string
  return (path:match("([^/]+)$") or path)
end

function M.stem(path: string): string
  return (M.basename(path):gsub("%.[%w]+$", ""))
end

local function dirname(path: string): string
  return path:match("^(.*)/[^/]*$")
end

local stem = M.stem

-- The home folder for a path that starts with `~`.
local function expand(path: string): string
  return (path:gsub("^~", os.getenv("HOME") or "~"))
end

--- Add an adapter. Adapters added later are asked first, so one for a
--- particular plugin wins over a general one. An adapter with `fallback =
--- true` is asked after all the others.
function M.adapter(def: M.Adapter)
  assert(
    type(def.name) == "string" and def.matches and def.slots and def.load,
    "an adapter needs name, matches, slots and load"
  )
  for i, a in ipairs(M.adapters) do
    if a.name == def.name then
      table.remove(M.adapters, i)
      break
    end
  end
  table.insert(M.adapters, def.fallback and #M.adapters + 1 or 1, def)
end

--- The adapter for a device, and the device, or nil.
function M.adapter_of(id: integer): M.Adapter, types.Device
  local ok, d = pcall(api.device_get, id) as (boolean, types.Device)
  if not ok or not d then
    return nil
  end
  for _, a in ipairs(M.adapters) do
    local fine, yes = pcall(a.matches, d) as (boolean, boolean)
    if fine and yes then
      return a, d
    end
  end
end

--- The slots of a device (empty when no adapter knows it, or the plugin is
--- not running).
function M.slots(id: integer): {Slot}
  local a, d = M.adapter_of(id)
  if not a then
    return {}
  end
  local ok, slots = pcall(a.slots, id, d) as (boolean, {Slot})
  return ok and slots or {}
end

--- A slot of the device by key or label; the first one without `name`.
function M.slot(id: integer, name?: string): Slot
  local slots = M.slots(id)
  if not name or name == "" then
    return slots[1]
  end
  for _, s in ipairs(slots) do
    if s.key == name or (s.label or ""):lower() == name:lower() or (s.what or ""):lower() == name:lower() then
      return s
    end
  end
end

--- The device panel, as far as plugstate reads it.
local record DevicePanel
  selected: function(self: DevicePanel): paw.Device
end

--- The device on the row of the device panel, or nil.
function M.panel_device(): integer
  local panel = paw.ui.views.devices as DevicePanel
  local selected = panel and panel.selected and panel:selected()
  return selected and selected.id or nil
end

--- The device the commands act on: the one selected in the device panel
--- when an adapter knows it, else the first device of the cursor track that
--- one knows. Nil and a reason when there is none.
function M.target(): integer, string
  local selected = M.panel_device()
  if selected and M.adapter_of(selected) then
    return selected
  end
  local track = paw.cursor.track_id()
  if track then
    for _, id in ipairs(api.track_get(track).devices) do
      if M.adapter_of(id) then
        return id
      end
    end
  end
  return nil, "no device here holds a file that plugstate knows (`:plugstate.adapters` lists them)"
end

-- The error of a call that failed, without the place in the Lua source.
local function reason(err: string): string
  return (tostring(err):gsub("^.-:%d+: ", ""))
end

-- What `adapter.load` gives for a slot of a device set to `value` (`~`
-- names the home folder in a path), the adapter and the device. Nil and
-- why when no adapter knows the device or the value.
local function load_spec(
  id: integer, slot_key: string, value: SlotValue
): types.PresetLoad, string, M.Adapter, types.Device, SlotValue
  local a, d = M.adapter_of(id)
  if not a then
    return nil, "no adapter knows this device"
  end
  local slot = M.slot(id, slot_key)
  if not slot then
    return nil, "the device has no " .. (slot_key or "file") .. " to set"
  end
  if value is string and slot.kind ~= "text" then
    value = expand(value)
  end
  local ok, spec = pcall(a.load, id, d, slot, value) as (boolean, types.PresetLoad)
  if not ok then
    return nil, reason(tostring(spec))
  end
  return spec, slot.key, a, d, value
end

--- Set a slot of a device to a file (or value), as one undo step. The
--- device's parameters stay. Returns true, or nil and why.
function M.set(id: integer, slot_key: string, value: SlotValue): boolean, string
  local spec, key, _, d, v = load_spec(id, slot_key, value)
  if not spec then
    return nil, key
  end
  spec.name = spec.name or (v is string and stem(v)) or tostring(v)
  spec.params = spec.params or d.params
  local fine, err = pcall(api.device_load, id, spec) as (boolean, string)
  if not fine then
    return nil, (tostring(err):gsub("^runtime error: ", ""))
  end
  paw.emit(M.loaded, {device = id, slot = key, value = v})
  return true
end

-- --- the library -------------------------------------------------------------

--- The folders searched for files: the `plugstate_folders` option (folders
--- separated by `:`) and `models/` in paw's data folder.
function M.roots(): {string}
  local roots: {string} = {}
  for dir in (folders:get() or ""):gmatch("[^:]+") do
    roots[#roots + 1] = expand(dir)
  end
  local data = os.getenv("XDG_DATA_HOME") or ((os.getenv("HOME") or ".") .. "/.local/share")
  roots[#roots + 1] = data .. "/paw/models"
  return roots
end

--- The folders `share/<sub>` beside the plugin folders that paw looks in
--- (`paw.api.plugins_dirs`: `CLAP_PATH`, `VST3_PATH`, `LV2_PATH`, else the
--- usual folders), for what a plugin's package puts beside it: factory
--- presets, models. Only those that are there.
function M.share_dirs(sub: string): {string}
  local out: {string} = {}
  local seen: {string: boolean} = {}
  local function try(lib: string)
    local dir = lib:gsub("/+$", ""):gsub("/[^/]+$", "") -- lib/clap -> lib
    dir = dir:gsub("/[^/]+$", "") .. "/share/" .. sub -- lib -> the package
    if not seen[dir] and #api.read_dir(dir) > 0 then
      out[#out + 1] = dir
    end
    seen[dir] = true
  end
  local by_format = api.plugins_dirs() or {}
  for _, format in ipairs({"clap", "vst3", "lv2"}) do
    for _, dir in ipairs(by_format[format] or {}) do
      try(dir)
    end
  end
  return out
end

local function takes(slot: Slot, name: string): boolean
  if not slot.types or #slot.types == 0 then
    return true
  end
  local ext = name:match("%.([%w]+)$")
  ext = ext and ext:lower()
  for _, t in ipairs(slot.types) do
    if ext == t:lower() then
      return true
    end
  end
  return false
end

-- The folder of the slot's file now, when it is a path.
local function folder_of(slot: Slot): string
  local v = slot.value
  return v is string and v:find("/", 1, true) and dirname(v) or nil
end

local function by_path(x: M.File, y: M.File): boolean
  return x.path < y.path
end

--- Every file a slot takes under `roots` (default: `M.roots()` and the
--- folder of the slot's file now), as `{ path, name, folder }`, sorted by
--- path. Looks six folders deep and at most at 5000 entries.
function M.files(slot: Slot, roots?: {string}): {M.File}
  -- A slot whose choices are not one file each (the presets inside a
  -- pack) lists them itself.
  if slot.list then
    local found = slot.list(roots)
    table.sort(found, by_path)
    return found
  end
  if not roots then
    roots = M.roots()
    for i, dir in ipairs(slot.folders or {}) do
      table.insert(roots, i, dir)
    end
    local here = folder_of(slot)
    if here then
      table.insert(roots, 1, here)
    end
  end
  local found: {M.File} = {}
  local listed: {string: boolean} = {}
  local seen = 0
  local function walk(dir: string, depth: integer, root: string)
    for _, entry in ipairs(api.read_dir(dir)) do
      seen = seen + 1
      if seen > 5000 then
        return
      end
      local path = dir .. "/" .. entry.name
      if entry.is_dir then
        if depth < 6 and not entry.name:match("^%.") then
          walk(path, depth + 1, root)
        end
      elseif takes(slot, entry.name) and not listed[path] then
        listed[path] = true
        found[#found + 1] = {path = path, name = stem(entry.name), folder = dir:sub(#root + 2)}
      end
    end
  end
  for _, root in ipairs(roots) do
    walk(root, 0, root)
  end
  table.sort(found, by_path)
  return found
end

--- The files whose name or folder holds every word of `query`.
function M.search(slot: Slot, query?: string, roots?: {string}): {M.File}
  local words: {string} = {}
  for w in (query or ""):lower():gmatch("%S+") do
    words[#words + 1] = w
  end
  local out: {M.File} = {}
  for _, f in ipairs(M.files(slot, roots)) do
    local text = (f.name .. " " .. f.folder):lower()
    local all = true
    for _, w in ipairs(words) do
      if not text:find(w, 1, true) then
        all = false
        break
      end
    end
    if all then
      out[#out + 1] = f
    end
  end
  return out
end

--- The file `n` places after the slot's file now, among the files of its
--- folder (from the first file of the library when it has none). It goes
--- round at the ends.
function M.neighbour(slot: Slot, n: integer): M.File
  local here = folder_of(slot)
  local files = here and M.files(slot, {here}) or M.files(slot)
  if #files == 0 then
    return nil
  end
  for i, f in ipairs(files) do
    if f.path == slot.value then
      return files[(i - 1 + n) % #files + 1]
    end
  end
  return files[n > 0 and 1 or #files]
end

-- --- snapshots ---------------------------------------------------------------
-- A snapshot is the whole state of the device and its parameters, kept with
-- the device in the project (`meta.plugstate.snapshots`), so the project
-- keeps them without the extension.

--- What plugstate keeps in the meta of a device, and the meta.
function M.data_of(id: integer): Data, types.Meta
  local meta = api.device_get(id).meta or {}
  local data: Data = type(meta.plugstate) == "table" and meta.plugstate as Data or {}
  data.snapshots = data.snapshots or {}
  return data, meta
end

local data_of = M.data_of

--- The snapshots of a device: `{ name, state, params }`, in the order kept.
function M.snapshots(id: integer): {M.Snapshot}
  return (data_of(id)).snapshots
end

--- The name of the snapshot last recalled or kept, if the device still holds it.
function M.current(id: integer): string
  return (data_of(id)).current
end

-- The first free letter A, B, C... among the names of the snapshots.
local function free_name(data: Data): string
  local taken: {string: boolean} = {}
  for _, s in ipairs(data.snapshots) do
    taken[s.name] = true
  end
  for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):gmatch(".") do
    if not taken[c] then
      return c
    end
  end
  return "snapshot " .. (#data.snapshots + 1)
end

--- Keep the device's whole state now as a snapshot named `name` (one
--- undo step). A snapshot with that name is replaced. Without a name,
--- the next free letter: A, B, C...
function M.snapshot(id: integer, name?: string): string, boolean
  local data, meta = data_of(id)
  if not name or name == "" then
    name = free_name(data)
  end
  local d = api.device_get(id)
  local snap: M.Snapshot = {name = name, state = api.device_state(id), params = d.params}
  local replaced = false
  for i, s in ipairs(data.snapshots) do
    if s.name == name then
      data.snapshots[i], replaced = snap, true
    end
  end
  if not replaced then
    data.snapshots[#data.snapshots + 1] = snap
  end
  data.current = name
  meta.plugstate = data
  api.device_set(id, {meta = meta})
  return name, replaced
end

local function find_snapshot(data: Data, name: string): M.Snapshot, integer
  for i, s in ipairs(data.snapshots) do
    if s.name == name then
      return s, i
    end
  end
  local lower = name:lower()
  for i, s in ipairs(data.snapshots) do
    if s.name:lower():find(lower, 1, true) then
      return s, i
    end
  end
end

--- Bring back a snapshot: the plugin's state and the parameters, as one
--- undo step. Returns the snapshot, or nil and why.
function M.recall(id: integer, name: string): M.Snapshot, string
  local data, meta = data_of(id)
  local snap = find_snapshot(data, name)
  if not snap then
    return nil, "no snapshot `" .. name .. "`"
  end
  api.device_load(id, {name = snap.name, state = snap.state, params = snap.params or {}})
  -- The same undo step: both edits are made in this turn.
  meta = api.device_get(id).meta or meta
  data.current = snap.name
  meta.plugstate = data
  api.device_set(id, {meta = meta})
  paw.emit(M.recalled, {device = id, name = snap.name})
  return snap
end

--- The snapshot `n` places after the current one, going round.
function M.step(id: integer, n: integer): M.Snapshot, string
  local data = data_of(id)
  if #data.snapshots == 0 then
    return nil, "no snapshots: `:plugstate.snapshot` keeps one"
  end
  local _, at = find_snapshot(data, data.current or "")
  local i = at and ((at - 1 + n) % #data.snapshots + 1) or (n > 0 and 1 or #data.snapshots)
  return M.recall(id, data.snapshots[i].name)
end

--- Forget a snapshot (one undo step).
function M.forget(id: integer, name: string): M.Snapshot, string
  local data, meta = data_of(id)
  local snap, i = find_snapshot(data, name)
  if not snap then
    return nil, "no snapshot `" .. name .. "`"
  end
  table.remove(data.snapshots, i)
  if data.current == snap.name then
    data.current = nil
  end
  meta.plugstate = data
  api.device_set(id, {meta = meta})
  return snap
end

-- --- state lanes -------------------------------------------------------------
-- A choice of a slot or a snapshot as a state of the device's state lane
-- (a core lane: `paw.Device:automate_state`), so that it changes at a point
-- of the song. The lane keeps what the adapter gives: an LV2 property set
-- lands on the point's frame; a saved state is loaded there.

--- A slot set to `value` as a state lane takes it: `{ name, call }` or
--- `{ name, state, params }`. Nothing changes in the device. Nil and why
--- when no adapter knows the device or the value.
function M.lane_state(id: integer, slot_key: string, value: SlotValue): types.LaneState, string
  local spec, why, a, d, v = load_spec(id, slot_key, value)
  if not spec then
    return nil, why
  end
  local name = spec.name or (a.name_of and v is string and a.name_of(v)) or (v is string and stem(v)) or tostring(v)
  local state: types.LaneState = {name = name, call = spec.call, state = spec.state, params = spec.params}
  if state.state and not state.params then
    state.params = d.params
  end
  return state
end

--- A snapshot of the device as a state lane takes it.
function M.lane_snapshot(id: integer, name: string): types.LaneState, string
  local snap = find_snapshot((data_of(id)), name)
  if not snap then
    return nil, "no snapshot `" .. name .. "`"
  end
  return {name = snap.name, state = snap.state, params = snap.params or {}}
end

--- Give the device a state (from `lane_state` or `lane_snapshot`) from
--- `beat` on, on its state lane, made if it has none. One undo step.
function M.lane_point(id: integer, beat: number, state: types.LaneState): paw.Lane, integer
  local lane = paw.device(id):automate_state()
  local index = lane:add_state(state)
  lane:add(beat, index)
  return lane, index
end

return M
