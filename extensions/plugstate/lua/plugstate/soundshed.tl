-- Soundshed Guitar (VST3, LV2): its presets, its scenes, and the amp
-- model or impulse response of each block, without its window.
--
-- Soundshed Guitar keeps its whole state as JSON (inside JUCE's VST3 and
-- LV2 forms): the preset that plays (`preset`, `presetId`), the scene of
-- the preset that plays (`activeSceneId`), and settings. A preset has up
-- to four scenes, each a graph of blocks (`nodes`). A block that plays a
-- model or an impulse response names it in `resources`: by an id in the
-- plugin's library (`resourceId`) or by a file (`filePath`).
--
-- This adapter changes the JSON in place and leaves the rest as it was: a
-- preset goes into `preset`; a file goes into the block as `filePath`
-- (with no library id, which the plugin would try first); a scene sets
-- `activeSceneId`. A preset of a pack (.soundshed.presets, a zip with
-- presets.json and the files) names files by their id in the pack: paw
-- copies those files into its data folder and names them by path.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local plugstate = require("plugstate")
local juce = require("plugstate.juce")
local bytes = require("plugstate.bytes")
local J = require("plugstate.jsonspan")
local type types = require("paw.types")

local api = paw.api

local type Node = J.Node
local type Slot = plugstate.Slot
local type SlotValue = plugstate.SlotValue

local record M
  --- A scene of a preset, as its JSON has it.
  record Scene
    id: string
    title: string
  end

  --- A preset of Soundshed Guitar, as its JSON has it (what paw reads).
  record Preset
    id: string
    name: string
    description: string
    scenes: {Scene}
  end

  --- A preset to choose: in a pack (`<file>#<id>`) or a .json file.
  record PresetFile is plugstate.File
    preset: Preset
  end

  --- A file of a pack: its id and its name in the zip (`resources/`).
  record PackFile
    id: string
    fileName: string
  end

  --- The presets.json of a pack.
  record PackList
    presets: {Preset}
    resources: {PackFile}
  end

  --- A block of the scene that plays a file: its key ("nam1", "ir1"), its
  --- label, its node, its type ("nam" or "ir") and the node of its first
  --- file, if any.
  record Block
    key: string
    label: string
    node: Node
    type: string
    resource: Node
  end

  LV2: string
  PACK: string
end

M.LV2 = "urn:soundshed:guitar"

function M.matches(d: types.Device): boolean
  local p = d.plugin
  if not p then
    return false
  end
  if p.format == "lv2" then
    return p.id == M.LV2
  end
  return p.format == "vst3" and (p.name or ""):lower() == "soundshed guitar"
end

-- --- the state ----------------------------------------------------------------

--- The plugin's JSON in a state, its tree of places, and a function that
--- gives the state with other JSON.
function M.open(state64: string, format: string): string, Node, function(new: string): string
  local data, close = juce.open(state64, format)
  local at = data:find("{", 1, true)
  if not at then
    error("not a state of Soundshed Guitar", 0)
  end
  local root = J.parse(data, at)
  local text = data:sub(at, root.e)
  return text,
    J.parse(text),
    function(new: string): string return close(data:sub(1, at - 1) .. new .. data:sub(root.e + 1)) end
end

--- The scene that plays: its node, the graph's node, and its place.
function M.scene(text: string, root: Node): Node, Node, integer
  local preset = J.at(root, "preset")
  if not preset then
    return nil
  end
  local scenes = J.at(preset, "scenes")
  local active = root.fields.activeSceneId and J.value(text, root.fields.activeSceneId)
  for i, sc in ipairs(scenes and scenes.items or {}) do
    if J.value(text, J.at(sc, "id")) == active or (not active and i == 1) then
      return sc, J.at(sc, "graph"), i
    end
  end
  return nil, J.at(preset, "graph")
end

local KINDS: {string: string} = {
  ["2eb53b40-6139-4696-8820-387ac56ffa91"] = "nam", -- NAM amp
  ["49ea214c-91e6-41f9-bd27-ad6eec0ae90a"] = "nam", -- NAM amp, optimized
  ["c3263344-65e4-4b7e-b102-ea625700e12f"] = "nam", -- NAM effect
  ["94fa2577-e904-43b8-968b-9c569c511160"] = "ir", -- cabinet IR
}

--- The blocks of the scene that play a file: `{ key, label, node, type,
--- resource }` (`resource`: the node of its first file, if any).
function M.blocks(text: string, root: Node): {M.Block}
  local _, graph = M.scene(text, root)
  local out: {M.Block} = {}
  local count: {string: integer} = {}
  local nodes = J.at(graph, "nodes")
  for _, node in ipairs(nodes and nodes.items or {}) do
    local res = J.at(node, "resources")
    local first = res and res.items[1]
    local kind = first and J.text(text, first.fields.resourceType)
    kind = kind or KINDS[J.text(text, node.fields.type) or ""]
    if kind == "nam" or kind == "ir" then
      local category = J.text(text, node.fields.category) or kind
      count[category] = (count[category] or 0) + 1
      out[#out + 1] = {
        key = category .. count[category],
        label = J.text(text, node.fields.label) or category,
        node = node,
        type = kind,
        resource = first,
      }
    end
  end
  return out
end

--- Where the plugin keeps its files: `~/.config/Soundshed Guitar/data/v1`
--- (JUCE's folder of application data; it does not read XDG_CONFIG_HOME).
function M.data_dir(): string
  return (os.getenv("HOME") or "") .. "/.config/Soundshed Guitar/data/v1"
end

--- A name for a file the library names by id: the plugin's copy of a
--- pack's file is `<id>-<name>.<ext>`.
local function library_name(id: string): string
  local pack, hash = id:match("^(.-)__(%x+)$")
  if not hash then
    return id
  end
  local dir = M.data_dir() .. "/resources/content/factory-archives/" .. pack
  for _, e in ipairs(api.read_dir(dir)) do
    if e.name:sub(1, #hash) == hash then
      return (plugstate.stem(e.name:sub(#hash + 2)))
    end
  end
  return hash:sub(1, 8)
end

--- The file a resource of a block names: its path, or the name of a file
--- of the library.
function M.resource_value(text: string, resource: Node): string
  if not resource then
    return nil
  end
  local f = resource.fields
  if f.filePath then
    return J.text(text, f.filePath)
  end
  if f.resourceId then
    return library_name(J.text(text, f.resourceId))
  end
end

-- --- presets and packs -------------------------------------------------------

M.PACK = "%.soundshed%.presets$"

--- A pack read once while it stays the same: its size, and its list.
local record Pack
  size: integer
  list: M.PackList
end

local packs: {string: Pack} = {}

--- The decoded presets.json of a pack, or nil.
function M.pack_list(path: string): M.PackList
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local size = f:seek("end")
  f:close()
  local known = packs[path]
  if known and known.size == size then
    return known.list
  end
  local ok, entries = pcall(
    function(): {string: string} return (assert(paw.zip.read(assert(bytes.read_file(path))))) end
  ) as (boolean, {string: string})
  local list = ok and entries["presets.json"] and api.json_decode(entries["presets.json"]) as M.PackList or nil
  packs[path] = {size = size, list = list}
  return list
end

--- The presets in a file: a pack gives each of its presets, a .json file
--- its one preset. `{ path = "<file>#<id>", name, folder }`.
function M.presets_in(path: string, folder?: string): {M.PresetFile}
  local out: {M.PresetFile} = {}
  if path:lower():match(M.PACK) then
    local list = M.pack_list(path)
    for _, p in ipairs(type(list) == "table" and list.presets or {}) do
      out[#out + 1] = {path = path .. "#" .. p.id, name = p.name or p.id, folder = folder or "", preset = p}
    end
  else
    local text = bytes.read_file(path)
    local p = text and api.json_decode(text) as M.Preset
    if type(p) == "table" and p.scenes then
      out[#out + 1] = {path = path, name = p.name or plugstate.stem(path), folder = folder or "", preset = p}
    end
  end
  return out
end

--- The folders with presets and packs: the library folders, and the
--- factory packs that come with the plugin.
function M.preset_folders(): {string}
  local dirs: {string} = {}
  for _, dir in ipairs(plugstate.share_dirs("soundshed-guitar/resources/ui/presets/factory")) do
    dirs[#dirs + 1] = dir
  end
  return dirs
end

--- The presets of the packs and .json files under `roots` (default: the
--- folders of presets and the library).
function M.list_presets(roots?: {string}): {M.PresetFile}
  if not roots then
    roots = plugstate.roots()
    for i, dir in ipairs(M.preset_folders()) do
      table.insert(roots, i, dir)
    end
  end
  local out: {M.PresetFile} = {}
  for _, root in ipairs(roots) do
    for _, f in ipairs(plugstate.files({types = {"presets", "json"}}, {root})) do
      for _, p in ipairs(M.presets_in(f.path, f.folder)) do
        out[#out + 1] = p
      end
    end
  end
  return out
end

-- A file of a pack copied into paw's data folder (once), and its path.
local function unpack_file(dir: string, name: string, data: string): string
  local path = dir .. "/" .. name
  if not io.open(path, "rb") then
    pcall(api.fs_mkdir, dir)
    local f = assert(io.open(path, "wb"))
    f:write(data)
    f:close()
  end
  return path
end

-- The edits that make each resource of a pack's file in `node` (and the
-- nodes under it) name the file by its path in `dir`.
local function pack_edits(
  text: string, node: Node, files: {string: string}, entries: {string: string}, dir: string, edits: {J.Edit}
)
  if node.kind == "object" then
    local res = node.fields.resources
    if res and res.kind == "array" then
      local items: {string} = {}
      for _, r in ipairs(res.items) do
        local rid = J.text(text, r.fields.resourceId)
        local name = rid and files[rid]
        local kind = J.text(text, r.fields.resourceType) or "nam"
        if name and entries["resources/" .. name] then
          local path = unpack_file(dir, name, entries["resources/" .. name])
          items[#items + 1] = api.json_encode({resourceType = kind, type = kind, filePath = path})
        else
          items[#items + 1] = text:sub(r.s, r.e)
        end
      end
      edits[#edits + 1] = {res, "[" .. table.concat(items, ",") .. "]"}
    end
    for _, k in ipairs(node.keys) do
      if k ~= "resources" then
        pack_edits(text, node.fields[k], files, entries, dir, edits)
      end
    end
  elseif node.kind == "array" then
    for _, v in ipairs(node.items) do
      pack_edits(text, v, files, entries, dir, edits)
    end
  end
end

--- The text of a preset (`<file>#<id>` or a .json file), with the files of
--- a pack copied to paw's data folder and named by their path.
function M.preset_text(ref: string): string, Node
  local file, id = ref:match("^(.-)#(.+)$")
  file = file or ref
  local data, err = bytes.read_file(file)
  if not data then
    error("there is no file " .. file .. " (" .. tostring(err) .. ")", 0)
  end
  if not id then
    local root = J.parse(data)
    if root.kind ~= "object" or not root.fields.scenes then
      error(file .. " is not a Soundshed preset", 0)
    end
    return data:sub(root.s, root.e), root
  end
  local entries = assert(paw.zip.read(data))
  local list = entries["presets.json"] or error(file .. " has no presets.json", 0)
  local root = J.parse(list)
  local text: string
  for _, p in ipairs(J.at(root, "presets").items) do
    if J.value(list, p.fields.id) == id then
      text = list:sub(p.s, p.e)
    end
  end
  if not text then
    error("no preset " .. id .. " in " .. file, 0)
  end
  -- The pack's files: id -> the name in the zip.
  local files: {string: string} = {}
  for _, r in ipairs((api.json_decode(list) as M.PackList).resources or {}) do
    files[r.id] = r.fileName
  end
  local pack = plugstate.stem(file):gsub("%.soundshed$", "")
  local dir = (os.getenv("XDG_DATA_HOME") or ((os.getenv("HOME") or ".") .. "/.local/share"))
    .. "/paw/plugstate/"
    .. pack
  local edits: {J.Edit} = {}
  pack_edits(text, J.parse(text), files, entries, dir, edits)
  text = J.edit(text, edits)
  return text, J.parse(text)
end

--- What the mixer holds of a preset.
local record MixerPreset
  mix: number
  mute: boolean
  name: string
  pan: number
  solo: boolean
end

-- The mixer's JSON naming the new preset (`key`, its id in JSON), with
-- its data: the mixer plays the presets it names, from their data in it
-- or else from the plugin's library.
local function mixer_with(m: string, key: string, name: string, ptext: string): string
  local mroot = J.parse(m)
  local medits: {J.Edit} = {}
  if mroot.fields.activePresetIds then
    medits[#medits + 1] = {mroot.fields.activePresetIds, "[" .. key .. "]"}
  end
  if mroot.fields.presets then
    local entry: MixerPreset = {mix = 1, mute = false, name = name, pan = 0, solo = false}
    medits[#medits + 1] = {mroot.fields.presets, "{" .. key .. ":" .. api.json_encode(entry) .. "}"}
  end
  if mroot.fields.presetData then
    medits[#medits + 1] = {mroot.fields.presetData, "{" .. key .. ":" .. ptext .. "}"}
  end
  return J.edit(m, medits)
end

--- The state's JSON with another preset in it, its first scene playing.
function M.with_preset(text: string, root: Node, ptext: string, proot: Node): string
  local id = J.value(ptext, proot.fields.id)
  local scenes = proot.fields.scenes
  local first = scenes and scenes.items[1] and J.at(scenes.items[1], "id")
  local edits: {J.Edit} = {{root.fields.preset, ptext}}
  if root.fields.presetId then
    edits[#edits + 1] = {root.fields.presetId, api.json_encode(id)}
  end
  local mixer = root.fields.mixer
  if mixer and mixer.kind == "object" then
    local name = J.text(ptext, proot.fields.name) or tostring(id)
    local m = text:sub(mixer.s, mixer.e)
    edits[#edits + 1] = {mixer, mixer_with(m, api.json_encode(id), name, ptext)}
  end
  if first and root.fields.activeSceneId then
    edits[#edits + 1] = {root.fields.activeSceneId, ptext:sub(first.s, first.e)}
  end
  return J.edit(text, edits)
end

-- --- the adapter --------------------------------------------------------------

-- The preset in the library with the id that plays, or nil. The plugin
-- puts the pack's name before the id of a preset it takes from a pack.
local function library_preset(pid: string): string
  for _, p in ipairs(M.list_presets()) do
    local own = p.path:match("#(.+)$") or p.preset.id
    if own and (pid == own or pid:sub(-#own - 2) == "__" .. own) then
      return p.path
    end
  end
  return nil
end

local function list_presets(roots?: {string}): {plugstate.File}
  local out: {plugstate.File} = {}
  for i, p in ipairs(M.list_presets(roots)) do
    out[i] = p
  end
  return out
end

function M.slots(id: integer, d: types.Device): {Slot}
  local text, root = M.open(api.device_state(id), d.plugin.format)
  local preset = root.fields.preset
  local name = preset and J.text(text, preset.fields.name)
  local scene = M.scene(text, root)
  local scenes: {string} = {}
  local list = J.at(root, "preset", "scenes")
  for _, sc in ipairs(list and list.items or {}) do
    scenes[#scenes + 1] = J.text(text, sc.fields.title) or tostring(J.value(text, sc.fields.id))
  end
  local pid = J.text(text, root.fields.presetId)
  local slots: {Slot} = {
    {
      key = "preset",
      label = "Preset",
      what = "preset",
      kind = "file",
      types = {"presets", "json"},
      list = list_presets,
      value = pid and library_preset(pid) or name,
    },
    {
      key = "scene",
      label = "Scene",
      what = "scene",
      kind = "text",
      choices = scenes,
      value = scene and J.text(text, scene.fields.title) or nil,
    },
  }
  for _, b in ipairs(M.blocks(text, root)) do
    slots[#slots + 1] = {
      key = b.key,
      label = b.label,
      what = b.type == "nam" and "model" or "impulse response",
      kind = "file",
      types = b.type == "nam" and {"nam"} or {"wav"},
      value = M.resource_value(text, b.resource),
    }
  end
  return slots
end

-- The state with the scene `value` playing: by its place, its title or its id.
local function load_scene(
  text: string, root: Node, close: function(string): string, slot: Slot, value: SlotValue
): types.PresetLoad
  local scenes = J.at(root, "preset", "scenes")
  local want = tostring(value):lower()
  for i, sc in ipairs(scenes and scenes.items or {}) do
    local title = J.text(text, sc.fields.title) or ""
    if tostring(i) == want or title:lower() == want or J.value(text, sc.fields.id) == want then
      return {
        state = close(J.edit(text, {{root.fields.activeSceneId, text:sub(sc.fields.id.s, sc.fields.id.e)}})),
        name = title,
      }
    end
  end
  error("no scene " .. tostring(value) .. " (the scenes: " .. table.concat(slot.choices or {}, ", ") .. ")", 0)
end

-- The state with a block playing the file `value`.
local function load_file(text: string, close: function(string): string, b: M.Block, value: string): types.PresetLoad
  local f = io.open(value, "rb")
  if not f then
    error("there is no file " .. value, 0)
  end
  f:close()
  local ext = (value:match("%.([%w]+)$") or ""):lower()
  if (b.type == "nam") ~= (ext == "nam") then
    error(b.label .. " takes " .. (b.type == "nam" and ".nam models" or ".wav impulse responses"), 0)
  end
  local ref = api.json_encode({resourceType = b.type, type = b.type, filePath = value})
  local res = b.node.fields.resources
  local new: string
  if res and res.items[1] then
    new = J.edit(text, {{res.items[1], ref}})
  else
    new = J.with_field(text, b.node, "resources", "[" .. ref .. "]")
  end
  return {state = close(new)}
end

function M.load(id: integer, d: types.Device, slot: Slot, value: SlotValue): types.PresetLoad
  local text, root, close = M.open(api.device_state(id), d.plugin.format)
  if slot.key == "preset" then
    local ptext, proot = M.preset_text(tostring(value))
    local name = J.text(ptext, proot.fields.name)
    return {state = close(M.with_preset(text, root, ptext, proot)), name = name, params = {}}
  end
  if slot.key == "scene" then
    return load_scene(text, root, close, slot, value)
  end
  for _, b in ipairs(M.blocks(text, root)) do
    if b.key == slot.key then
      return load_file(text, close, b, tostring(value))
    end
  end
  error("Soundshed Guitar has no " .. slot.key .. " in this scene", 0)
end

--- The preset (decoded) a reference names, from the list.
function M.find(ref: string): M.PresetFile
  local file = ref:match("^(.-)#") or ref
  for _, p in ipairs(M.presets_in(file)) do
    if p.path == ref then
      return p
    end
  end
end

function M.describe(path: string): string
  if path:match("#") or path:lower():match("%.json$") then
    local found = M.find(path)
    if not found then
      return nil
    end
    local words: {string} = {}
    local p = found.preset
    if p.description then
      words[#words + 1] = p.description
    end
    local titles: {string} = {}
    for _, sc in ipairs(p.scenes or {}) do
      titles[#titles + 1] = sc.title
    end
    if #titles > 0 then
      words[#words + 1] = "scenes: " .. table.concat(titles, ", ")
    end
    return table.concat(words, " · ")
  end
  if path:lower():match("%.nam$") then
    return require("plugstate.adapters").nam_words(path)
  end
end

plugstate.adapter(
  {
    name = "soundshed",
    desc = "Soundshed Guitar: its presets (packs and .json), scenes, and the model or impulse response of each block, written into its state",
    matches = M.matches,
    slots = M.slots,
    load = M.load,
    describe = M.describe,
    name_of = function(ref: string): string
      local p = ref:find("#", 1, true) and M.find(ref)
      return p and p.name or plugstate.stem(ref)
    end,
  }
)

return M
