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
local api = paw.api
local plugstate = require("plugstate")
local juce = require("plugstate.juce")
local bytes = require("plugstate.bytes")
local J = require("plugstate.jsonspan")

local M = {}

M.LV2 = "urn:soundshed:guitar"

function M.matches(d)
  local p = d.plugin
  if not p then return false end
  if p.format == "lv2" then return p.id == M.LV2 end
  return p.format == "vst3" and (p.name or ""):lower() == "soundshed guitar"
end

-- --- the state ----------------------------------------------------------------

--- The plugin's JSON in a state, its tree of places, and a function that
--- gives the state with other JSON.
function M.open(state64, format)
  local data, close = juce.open(state64, format)
  local at = data:find("{", 1, true)
  if not at then error("not a state of Soundshed Guitar", 0) end
  local root = J.parse(data, at)
  local text = data:sub(at, root.e)
  return text, J.parse(text), function(new)
    return close(data:sub(1, at - 1) .. new .. data:sub(root.e + 1))
  end
end

--- The scene that plays: its node, and the graph's node.
function M.scene(text, root)
  local preset = J.at(root, "preset")
  if not preset then return nil end
  local scenes = J.at(preset, "scenes")
  local active = root.fields.activeSceneId and J.value(text, root.fields.activeSceneId)
  for i, sc in ipairs(scenes and scenes.items or {}) do
    if J.value(text, J.at(sc, "id")) == active or (not active and i == 1) then return sc, J.at(sc, "graph"), i end
  end
  return nil, J.at(preset, "graph")
end

local KINDS = {
  ["2eb53b40-6139-4696-8820-387ac56ffa91"] = "nam", -- NAM amp
  ["49ea214c-91e6-41f9-bd27-ad6eec0ae90a"] = "nam", -- NAM amp, optimized
  ["c3263344-65e4-4b7e-b102-ea625700e12f"] = "nam", -- NAM effect
  ["94fa2577-e904-43b8-968b-9c569c511160"] = "ir", -- cabinet IR
}

--- The blocks of the scene that play a file: `{ key, label, node, type,
--- resource }` (`resource`: the node of its first file, if any).
function M.blocks(text, root)
  local _, graph = M.scene(text, root)
  local out, count = {}, {}
  for _, node in ipairs(J.at(graph, "nodes") and J.at(graph, "nodes").items or {}) do
    local res = J.at(node, "resources")
    local first = res and res.items[1]
    local kind = first and first.fields.resourceType and J.value(text, first.fields.resourceType)
    kind = kind or KINDS[node.fields.type and J.value(text, node.fields.type) or ""]
    if kind == "nam" or kind == "ir" then
      local category = node.fields.category and J.value(text, node.fields.category) or kind
      count[category] = (count[category] or 0) + 1
      out[#out + 1] = {
        key = category .. count[category],
        label = node.fields.label and J.value(text, node.fields.label) or category,
        node = node, type = kind, resource = first,
      }
    end
  end
  return out
end

--- Where the plugin keeps its files: `~/.config/Soundshed Guitar/data/v1`
--- (JUCE's folder of application data; it does not read XDG_CONFIG_HOME).
function M.data_dir()
  return (os.getenv("HOME") or "") .. "/.config/Soundshed Guitar/data/v1"
end

--- A name for a file the library names by id: the plugin's copy of a
--- pack's file is `<id>-<name>.<ext>`.
local function library_name(id)
  local pack, hash = id:match("^(.-)__(%x+)$")
  if not hash then return id end
  local dir = M.data_dir() .. "/resources/content/factory-archives/" .. pack
  for _, e in ipairs(api.read_dir(dir)) do
    if e.name:sub(1, #hash) == hash then return (plugstate.stem(e.name:sub(#hash + 2))) end
  end
  return hash:sub(1, 8)
end

function M.resource_value(text, resource)
  if not resource then return nil end
  local f = resource.fields
  if f.filePath then return J.value(text, f.filePath) end
  if f.resourceId then return library_name(J.value(text, f.resourceId)) end
end

-- --- presets and packs -------------------------------------------------------

M.PACK = "%.soundshed%.presets$"

--- The presets in a file: a pack gives each of its presets, a .json file
--- its one preset. `{ path = "<file>#<id>", name, folder }`.
local packs = {} -- path -> { size, presets } : a pack is read once while it stays the same

--- The decoded presets.json of a pack, or nil.
function M.pack_list(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  local known = packs[path]
  if known and known.size == size then return known.list end
  local ok, entries = pcall(function() return assert(paw.zip.read(assert(bytes.read_file(path)))) end)
  local list = ok and entries["presets.json"] and paw.json.decode(entries["presets.json"]) or nil
  packs[path] = { size = size, list = list }
  return list
end

function M.presets_in(path, folder)
  local out = {}
  if path:lower():match(M.PACK) then
    local list = M.pack_list(path)
    for _, p in ipairs(type(list) == "table" and list.presets or {}) do
      out[#out + 1] = { path = path .. "#" .. p.id, name = p.name or p.id, folder = folder or "", preset = p }
    end
  else
    local text = bytes.read_file(path)
    local p = text and paw.json.decode(text)
    if type(p) == "table" and p.scenes then
      out[#out + 1] = { path = path, name = p.name or plugstate.stem(path), folder = folder or "", preset = p }
    end
  end
  return out
end

--- The folders with presets and packs: the library folders, and the
--- factory packs that come with the plugin.
function M.preset_folders()
  local dirs = {}
  for _, dir in ipairs(plugstate.share_dirs("soundshed-guitar/resources/ui/presets/factory")) do dirs[#dirs + 1] = dir end
  return dirs
end

function M.list_presets(roots)
  if not roots then
    roots = plugstate.roots()
    for i, dir in ipairs(M.preset_folders()) do table.insert(roots, i, dir) end
  end
  local out = {}
  for _, root in ipairs(roots) do
    for _, f in ipairs(plugstate.files({ types = { "presets", "json" } }, { root })) do
      for _, p in ipairs(M.presets_in(f.path, f.folder)) do out[#out + 1] = p end
    end
  end
  return out
end

--- The text of a preset (`<file>#<id>` or a .json file), with the files of
--- a pack copied to paw's data folder and named by their path.
function M.preset_text(ref)
  local file, id = ref:match("^(.-)#(.+)$")
  file = file or ref
  local data, err = bytes.read_file(file)
  if not data then error("there is no file " .. file .. " (" .. tostring(err) .. ")", 0) end
  if not id then
    local root = J.parse(data)
    if root.kind ~= "object" or not root.fields.scenes then error(file .. " is not a Soundshed preset", 0) end
    return data:sub(root.s, root.e), root
  end
  local entries = assert(paw.zip.read(data))
  local list = entries["presets.json"] or error(file .. " has no presets.json", 0)
  local root = J.parse(list)
  local text
  for _, p in ipairs(J.at(root, "presets").items) do
    if J.value(list, p.fields.id) == id then text = list:sub(p.s, p.e) end
  end
  if not text then error("no preset " .. id .. " in " .. file, 0) end
  -- The pack's files: id -> the name in the zip.
  local files = {}
  for _, r in ipairs(paw.json.decode(list).resources or {}) do files[r.id] = r.fileName end
  local pack = plugstate.stem(file):gsub("%.soundshed$", "")
  local dir = (os.getenv("XDG_DATA_HOME") or ((os.getenv("HOME") or ".") .. "/.local/share")) .. "/paw/plugstate/" .. pack
  local edits = {}
  local function walk(text_, node)
    if node.kind == "object" then
      local res = node.fields.resources
      if res and res.kind == "array" then
        local items = {}
        for _, r in ipairs(res.items) do
          local rid = r.fields.resourceId and J.value(text_, r.fields.resourceId)
          local name = rid and files[rid]
          local kind = r.fields.resourceType and J.value(text_, r.fields.resourceType) or "nam"
          if name and entries["resources/" .. name] then
            local path = dir .. "/" .. name
            if not io.open(path, "rb") then
              os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'")
              local f = assert(io.open(path, "wb"))
              f:write(entries["resources/" .. name])
              f:close()
            end
            items[#items + 1] = paw.json.encode({ resourceType = kind, type = kind, filePath = path })
          else
            items[#items + 1] = text_:sub(r.s, r.e)
          end
        end
        edits[#edits + 1] = { res, "[" .. table.concat(items, ",") .. "]" }
      end
      for _, k in ipairs(node.keys) do if k ~= "resources" then walk(text_, node.fields[k]) end end
    elseif node.kind == "array" then
      for _, v in ipairs(node.items) do walk(text_, v) end
    end
  end
  local proot = J.parse(text)
  walk(text, proot)
  text = J.edit(text, edits)
  return text, J.parse(text)
end

--- The state's JSON with another preset in it, its first scene playing.
function M.with_preset(text, root, ptext, proot)
  local id = J.value(ptext, proot.fields.id)
  local scenes = proot.fields.scenes
  local first = scenes and scenes.items[1] and J.at(scenes.items[1], "id")
  local edits = { { root.fields.preset, ptext } }
  if root.fields.presetId then edits[#edits + 1] = { root.fields.presetId, paw.json.encode(id) } end
  -- The mixer plays the presets it names, from their data in it or else
  -- from the plugin's library: it names the new one, with its data.
  local mixer = root.fields.mixer
  if mixer and mixer.kind == "object" then
    local name = proot.fields.name and J.value(ptext, proot.fields.name) or id
    local key = paw.json.encode(id)
    local m = text:sub(mixer.s, mixer.e)
    local mroot = J.parse(m)
    local medits = {}
    if mroot.fields.activePresetIds then medits[#medits + 1] = { mroot.fields.activePresetIds, "[" .. key .. "]" } end
    if mroot.fields.presets then
      medits[#medits + 1] = { mroot.fields.presets, "{" .. key .. ":" .. paw.json.encode({ mix = 1, mute = false, name = name, pan = 0, solo = false }) .. "}" }
    end
    if mroot.fields.presetData then medits[#medits + 1] = { mroot.fields.presetData, "{" .. key .. ":" .. ptext .. "}" } end
    edits[#edits + 1] = { mixer, J.edit(m, medits) }
  end
  if first and root.fields.activeSceneId then edits[#edits + 1] = { root.fields.activeSceneId, ptext:sub(first.s, first.e) } end
  return J.edit(text, edits)
end

-- --- the adapter --------------------------------------------------------------

function M.slots(id, d)
  local text, root = M.open(api.device_state(id), d.plugin.format)
  local preset = root.fields.preset
  local name = preset and preset.fields.name and J.value(text, preset.fields.name)
  local scene = M.scene(text, root)
  local scenes = {}
  for _, sc in ipairs(J.at(root, "preset", "scenes") and J.at(root, "preset", "scenes").items or {}) do
    scenes[#scenes + 1] = sc.fields.title and J.value(text, sc.fields.title) or J.value(text, sc.fields.id)
  end
  -- The preset in the library with the id that plays. The plugin puts the
  -- pack's name before the id of a preset it takes from a pack.
  local pid = root.fields.presetId and J.value(text, root.fields.presetId)
  local value = name
  if type(pid) == "string" then
    for _, p in ipairs(M.list_presets()) do
      local own = p.path:match("#(.+)$") or p.preset.id
      if own and (pid == own or pid:sub(-#own - 2) == "__" .. own) then value = p.path break end
    end
  end
  local slots = {
    { key = "preset", label = "Preset", what = "preset", kind = "file", types = { "presets", "json" },
      list = M.list_presets, value = value },
    { key = "scene", label = "Scene", what = "scene", kind = "text", choices = scenes,
      value = scene and scene.fields.title and J.value(text, scene.fields.title) or nil },
  }
  for _, b in ipairs(M.blocks(text, root)) do
    slots[#slots + 1] = {
      key = b.key, label = b.label, what = b.type == "nam" and "model" or "impulse response", kind = "file",
      types = b.type == "nam" and { "nam" } or { "wav" }, value = M.resource_value(text, b.resource),
    }
  end
  return slots
end

function M.load(id, d, slot, value)
  local text, root, close = M.open(api.device_state(id), d.plugin.format)
  if slot.key == "preset" then
    local ptext, proot = M.preset_text(value)
    local name = proot.fields.name and J.value(ptext, proot.fields.name)
    return { state = close(M.with_preset(text, root, ptext, proot)), name = name, params = {} }
  end
  if slot.key == "scene" then
    local scenes = J.at(root, "preset", "scenes")
    local want = tostring(value):lower()
    for i, sc in ipairs(scenes and scenes.items or {}) do
      local title = sc.fields.title and J.value(text, sc.fields.title) or ""
      if tostring(i) == want or title:lower() == want or J.value(text, sc.fields.id) == want then
        return { state = close(J.edit(text, { { root.fields.activeSceneId, text:sub(sc.fields.id.s, sc.fields.id.e) } })), name = title }
      end
    end
    error("no scene " .. tostring(value) .. " (the scenes: " .. table.concat(slot.choices or {}, ", ") .. ")", 0)
  end
  for _, b in ipairs(M.blocks(text, root)) do
    if b.key == slot.key then
      local f = io.open(value, "rb")
      if not f then error("there is no file " .. value, 0) end
      f:close()
      local ext = (value:match("%.([%w]+)$") or ""):lower()
      if (b.type == "nam") ~= (ext == "nam") then
        error(b.label .. " takes " .. (b.type == "nam" and ".nam models" or ".wav impulse responses"), 0)
      end
      local ref = paw.json.encode({ resourceType = b.type, type = b.type, filePath = value })
      local res = b.node.fields.resources
      local new
      if res and res.items[1] then
        new = J.edit(text, { { res.items[1], ref } })
      else
        new = J.with_field(text, b.node, "resources", "[" .. ref .. "]")
      end
      return { state = close(new) }
    end
  end
  error("Soundshed Guitar has no " .. slot.key .. " in this scene", 0)
end

--- The preset (decoded) a reference names, from the list.
function M.find(ref)
  local file = ref:match("^(.-)#") or ref
  for _, p in ipairs(M.presets_in(file)) do
    if p.path == ref then return p end
  end
end

function M.describe(path)
  if path:match("#") or path:lower():match("%.json$") then
    local found = M.find(path)
    if not found then return nil end
    local words = {}
    local p = found.preset
    if p.description then words[#words + 1] = p.description end
    local titles = {}
    for _, sc in ipairs(p.scenes or {}) do titles[#titles + 1] = sc.title end
    if #titles > 0 then words[#words + 1] = "scenes: " .. table.concat(titles, ", ") end
    return table.concat(words, " · ")
  end
  if path:lower():match("%.nam$") then return require("plugstate.adapters").nam_words(path) end
end

plugstate.adapter({
  name = "soundshed",
  desc = "Soundshed Guitar: its presets (packs and .json), scenes, and the model or impulse response of each block, written into its state",
  matches = M.matches,
  slots = M.slots,
  load = M.load,
  describe = M.describe,
  name_of = function(ref)
    local p = ref:find("#", 1, true) and M.find(ref)
    return p and p.name or plugstate.stem(ref)
  end,
})

return M
