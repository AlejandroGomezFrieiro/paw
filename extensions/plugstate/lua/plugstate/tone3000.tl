-- TONE3000 (CLAP, VST3, LV2): its presets, and the amp model or impulse
-- response of each block of its chain, without its window.
--
-- TONE3000 keeps no file names in parameters. Its state is a JUCE tree
-- after "T3KB": `TONE3000State` with the parameters (`PARAMETERS`), the
-- MIDI map and the chain (`ChainSnapshot`). The chain has two rows of five
-- blocks (`ChainBlocks`, `RightChainBlocks`). A block that plays a tone
-- has its tone as JSON (`toneJson`, its models), the model that plays
-- (`activeModelId`) and the bytes of its models (`ModelCache`). A preset
-- file (.t3kpreset) is "T3KH", the length of a header tree, the header
-- (`id`, `name`) and a `T3KPreset` tree with a `ChainSnapshot` and the
-- values of its parameters (`Params`).
--
-- So this adapter writes the state: a preset puts its chain and values in
-- place; a file makes a block a local tone, as a file dropped on the block
-- in the window does, with the bytes in the block's cache. When the cache
-- has the model, the plugin loads it from there and asks the network for
-- nothing.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local plugstate = require("plugstate")
local juce = require("plugstate.juce")
local jucestate = require("plugstate.jucestate")
local bytes = require("plugstate.bytes")
local type types = require("paw.types")
local type util = require("paw.util")

local api = paw.api

local type Tree = juce.Tree
local type Slot = plugstate.Slot
local type SlotValue = plugstate.SlotValue

local record M
  --- The header of a preset: its id and its name.
  record Header
    id: string
    name: string
  end

  --- A block of the chain: its key ("block1", "right2"), its tree, its row
  --- and its place in the row.
  record Block
    key: string
    block: Tree
    row: string
    n: integer
  end

  --- What a block plays: its type, the title of its tone, the model that
  --- plays (its id and name), the models of the tone and those in the
  --- block's cache, and for a local tone the file.
  record BlockInfo
    type: string
    title: string
    model: juce.Value
    model_name: string
    models: {plugstate.Model}
    cached: {juce.Value: boolean}
    is_local: boolean
    path: string
  end

  IDS: {string: string}
  ROWS: {{string, string}}
  desc: jucestate.Desc
end

--- A model in the JSON of a tone. `paw_path`: the file the user chose,
--- for paw; the plugin keeps the tone's JSON as it is.
local record ModelJson
  id: integer
  name: string
  model_url: string
  paw_path: string
end

--- The JSON of a tone (`toneJson`). Its field `local` (a word of Lua) is
--- read and written through the table.
local record ToneJson
  id: integer
  title: string
  format: string
  models: {ModelJson}
end

M.IDS = {clap = "com.tone3000.plugin", lv2 = "https://www.tone3000.com/plugin"}

function M.matches(d: types.Device): boolean
  local p = d.plugin
  if not p then
    return false
  end
  if p.format == "vst3" then
    return (p.name or ""):lower() == "tone3000"
  end
  return M.IDS[p.format] == p.id
end

-- --- the state ----------------------------------------------------------------

-- The description for the JUCE layer: a tree after "T3KB" in each format.
M.desc = jucestate.plugin(
  {
    name = "tone3000",
    title = "TONE3000",
    prefix = "T3KB",
    root = "TONE3000State",
    ids = {clap = M.IDS.clap, lv2 = M.IDS.lv2, vst3 = "TONE3000"},
    params = "/TONE3000State/PARAMETERS",
    paths = {preset = "/TONE3000State@activePresetName", preset_id = "/TONE3000State@activePresetId"},
  }
)

--- The plugin's tree in a state (paw's base64) and a function that gives
--- the state with another tree.
function M.open(state64: string, format: string): Tree, function(tree: Tree): string
  local ok, doc = pcall(jucestate.open, state64, format, {desc = M.desc}) as (boolean, jucestate.Doc)
  if not ok then
    error("not a state of TONE3000 (" .. tostring(doc) .. ")", 0)
  end
  return doc.root, function(tree: Tree): string doc.root, doc.changed = tree, true; return doc:write() end
end

-- A value of a header as text, or nil.
local function text_of(v: juce.Value): string
  return v ~= nil and tostring(v) or nil
end

-- The `T3KPreset` tree of the bytes of a preset file, and its header tree.
local function parse_preset(data: string): Tree, Tree
  if data:sub(1, 4) == "T3KH" then
    local head, after = juce.parse(data, 9)
    return (juce.parse(data, after)), head
  elseif data:sub(1, 4) == "T3KB" then
    return (juce.parse(data, 5)), nil
  end
  error("not a TONE3000 preset", 0)
end

--- The `T3KPreset` tree of a preset file and its header (`id`, `name`), or
--- nil and why.
function M.read_preset(path: string): Tree, M.Header | string
  local data, err = bytes.read_file(path)
  if not data then
    return nil, err
  end
  local ok, preset, header = pcall(parse_preset, data) as (boolean, Tree, Tree)
  if not ok then
    return nil, path .. ": " .. tostring(preset)
  end
  if preset.type ~= "T3KPreset" then
    return nil, path .. ": not a TONE3000 preset"
  end
  header = header or preset
  return preset,
    {
      id = text_of(juce.get(header, "id")),
      name = text_of(juce.get(header, "name")) or plugstate.stem(path),
    }
end

--- Only the header of a preset file: `{ id, name }` (a preset can be
--- megabytes; the header is in its first bytes).
function M.preset_header(path: string): M.Header
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local head = f:read(65536) or ""
  f:close()
  if head:sub(1, 4) ~= "T3KH" then
    return nil
  end
  local ok, tree = pcall(juce.parse, head, 9) as (boolean, Tree)
  if not ok then
    return nil
  end
  return {id = text_of(juce.get(tree, "id")), name = text_of(juce.get(tree, "name"))}
end

--- Put a preset into a state tree: its chain, the values of its
--- parameters, its id and name.
function M.apply_preset(root: Tree, preset: Tree, header: M.Header)
  local chain = juce.child(preset, "ChainSnapshot")
  if not chain then
    error("the preset has no chain", 0)
  end
  local _, at = juce.child(root, "ChainSnapshot")
  if at then
    root.children[at] = chain
  else
    root.children[#root.children + 1] = chain
  end
  local params = juce.child(root, "PARAMETERS")
  local values = juce.child(preset, "Params")
  if params and values then
    local by_id: {juce.Value: Tree} = {}
    for _, p in ipairs(params.children) do
      local id = juce.get(p, "id")
      if id ~= nil then
        by_id[id] = p
      end
    end
    for _, v in ipairs(values.children) do
      local id = juce.get(v, "id")
      local p = id ~= nil and by_id[id]
      if p then
        juce.set(p, "value", juce.get(v, "value"))
      end
    end
  end
  juce.set(root, "activePresetId", header.id or "")
  juce.set(root, "activePresetName", header.name or "")
end

-- --- blocks -------------------------------------------------------------------

M.ROWS = {{"ChainBlocks", "block"}, {"RightChainBlocks", "right"}}

--- The blocks of a state tree: `{ key, block, row, n }`.
function M.blocks(root: Tree): {M.Block}
  local out: {M.Block} = {}
  local chain = juce.child(root, "ChainSnapshot")
  if not chain then
    return out
  end
  for _, row in ipairs(M.ROWS) do
    local list = juce.child(chain, row[1])
    for n, block in ipairs(list and list.children or {}) do
      out[#out + 1] = {key = row[2] .. n, block = block, row = row[1], n = n}
    end
  end
  return out
end

--- What a block plays: `{ type, title, model, models = { { id, name } },
--- cached = { [id] = true }, path }` (`path`: the file of a local tone).
function M.block_info(block: Tree): M.BlockInfo
  local kind = juce.get(block, "type")
  local info: M.BlockInfo = {type = kind is string and kind or "insert", models = {}, cached = {}}
  local tone = juce.get(block, "toneJson")
  local ok, json = pcall(api.json_decode, tone is string and tone or "") as (boolean, ToneJson)
  if ok and type(json) == "table" then
    info.title = json.title
    info.is_local = (json as {string: util.Data})["local"] == true
    for _, m in ipairs(type(json.models) == "table" and json.models or {}) do
      info.models[#info.models + 1] = {id = m.id, name = m.name, url = m.model_url, path = m.paw_path}
    end
  end
  info.model = juce.get(block, "activeModelId")
  local cache = juce.child(block, "ModelCache")
  for _, c in ipairs(cache and cache.children or {}) do
    local id = juce.get(c, "modelId")
    if id ~= nil then
      info.cached[id] = true
    end
  end
  for _, m in ipairs(info.models) do
    if m.id == info.model then
      info.model_name = m.name
      if info.is_local then
        info.path = m.path
      end
    end
  end
  return info
end

--- Where TONE3000 keeps its files: `~/.config/TONE3000` (JUCE's folder of
--- application data; it does not read XDG_CONFIG_HOME).
function M.root(): string
  return (os.getenv("HOME") or "") .. "/.config/TONE3000"
end

local EQ_BANDS: {{string, number, number}} = {
  {"lowshelf", 100, 0.71},
  {"bell", 250, 1},
  {"bell", 650, 1},
  {"bell", 1600, 1},
  {"bell", 3500, 1.4},
  {"highshelf", 8000, 0.71},
}

local function flat_eq(): Tree
  local bands: {Tree} = {}
  for i, b in ipairs(EQ_BANDS) do
    bands[i] = juce.tree("Band", {{"type", b[1]}, {"freqHz", b[2]}, {"gainDb", 0}, {"q", b[3]}})
  end
  return juce.tree("Eq", {{"enabled", true}, {"pre", false}}, bands)
end

--- Make a block play a .nam model or a .wav impulse response from a file,
--- as a local tone with the file's bytes in its cache.
function M.set_file(block: Tree, path: string)
  local ext = (path:match("%.([%w]+)$") or ""):lower()
  if ext ~= "nam" and ext ~= "wav" then
    error("TONE3000 takes .nam models and .wav impulse responses", 0)
  end
  local data, err = bytes.read_file(path)
  if not data then
    error("there is no file " .. path .. " (" .. tostring(err) .. ")", 0)
  end
  -- The plugin names what it keeps of a file by FNV-1a of its bytes.
  local hex, mod = bytes.fnv1a64(data, 0x7ffffffe)
  local id = mod + 1
  local stash = string.format("%s/LocalModels/%s-%d.%s", M.root(), (hex:gsub("^0+", "")), #data, ext)
  local stem = plugstate.stem(path)
  local tone: ToneJson = {
    id = 0,
    title = stem,
    format = ext == "nam" and "nam" or "ir",
    models = {{id = id, name = stem, model_url = "file://" .. stash, paw_path = path}},
  }
  local fields = tone as {string: util.Data}
  fields["local"] = true
  juce.set(block, "type", ext == "nam" and "nam" or "ir")
  juce.set(block, "enabled", true)
  juce.set(block, "toneId", 0, "int")
  juce.set(block, "toneJson", api.json_encode(tone))
  juce.set(block, "activeModelId", id, "int")
  local kept: {Tree} = {}
  for _, c in ipairs(block.children) do
    if c.type ~= "ModelCache" then
      kept[#kept + 1] = c
    end
  end
  if not juce.child(block, "Eq") then
    table.insert(kept, 1, flat_eq())
  end
  kept[#kept + 1] = juce.tree(
    "ModelCache",
    nil,
    {
      juce.tree("CachedModel", {{"modelId", id, "int"}, {"data", data, "binary"}}),
    }
  )
  block.children = kept
end

--- Make a block play another of the models its tone holds, by name or a
--- part of it. The model's bytes must be in the block.
function M.set_model(block: Tree, words: string): plugstate.Model
  local info = M.block_info(block)
  local lower = words:lower()
  for _, m in ipairs(info.models) do
    if (m.name or ""):lower():find(lower, 1, true) then
      if not info.cached[m.id] then
        error("the model " .. m.name .. " is not in the block (open the window to get it)", 0)
      end
      juce.set(block, "activeModelId", m.id, "int")
      return m
    end
  end
  error("no model with “" .. words .. "” in " .. (info.title or "the block"), 0)
end

-- --- the library --------------------------------------------------------------

--- The folders of presets: the plugin's own (`Presets` and `Presets/Factory`
--- under its folder), and the factory presets that come with it.
function M.preset_folders(): {string}
  local dirs = {M.root() .. "/Presets"}
  for _, dir in ipairs(plugstate.share_dirs("tone3000/factory-presets")) do
    dirs[#dirs + 1] = dir
  end
  return dirs
end

-- --- the adapter --------------------------------------------------------------

-- The preset file with the id (else, without an id, the name), or nil.
local function preset_path(id: string, name: string): string
  local no_id = not id or id == ""
  for _, dir in ipairs(M.preset_folders()) do
    for _, f in ipairs(plugstate.files({types = {"t3kpreset"}}, {dir})) do
      local head = M.preset_header(f.path)
      if head and ((not no_id and head.id == id) or (no_id and head.name == name)) then
        return f.path
      end
    end
  end
  return nil
end

function M.slots(id: integer, d: types.Device): {Slot}
  local root = M.open(api.device_state(id), d.plugin.format)
  local name = text_of(juce.get(root, "activePresetName"))
  local slots: {Slot} = {
    {
      key = "preset",
      label = "Preset",
      what = "preset",
      kind = "file",
      types = {"t3kpreset"},
      folders = M.preset_folders(),
      value = preset_path(text_of(juce.get(root, "activePresetId")), name) or (name ~= "" and name or nil),
    },
  }
  for _, b in ipairs(M.blocks(root)) do
    local info = M.block_info(b.block)
    local what = info.type == "nam" and "model"
      or (info.type == "ir" and "impulse response" or "model or impulse response")
    local label = (b.row == "ChainBlocks" and "Block " or "Right block ") .. b.n
    if info.title then
      label = label .. " (" .. info.title .. ")"
    end
    slots[#slots + 1] = {
      key = b.key,
      label = label,
      what = what,
      kind = "file",
      types = {"nam", "wav"},
      value = info.path or info.model_name or info.title,
      models = info.models,
    }
  end
  return slots
end

function M.load(id: integer, d: types.Device, slot: Slot, value: SlotValue): types.PresetLoad
  local root, close = M.open(api.device_state(id), d.plugin.format)
  local file = tostring(value)
  if slot.key == "preset" then
    local preset, header = M.read_preset(file)
    if not preset then
      error(header, 0)
    end
    local h = header as M.Header
    M.apply_preset(root, preset, h)
    -- The preset sets the parameters: the plugin's values after the state
    -- are the ones that count, not the ones the project had.
    return {state = close(root), name = h.name, params = {}}
  end
  local target: Tree
  for _, b in ipairs(M.blocks(root)) do
    if b.key == slot.key then
      target = b.block
    end
  end
  if not target then
    error("TONE3000 has no " .. slot.key, 0)
  end
  local f = io.open(file, "rb")
  if f then
    f:close()
    M.set_file(target, file)
  else
    if file:find("/", 1, true) then
      error("there is no file " .. file, 0)
    end
    M.set_model(target, file)
  end
  return {state = close(root)}
end

function M.describe(path: string): string
  if path:lower():match("%.t3kpreset$") then
    local preset, header = M.read_preset(path)
    if not preset then
      return nil
    end
    local titles: {string} = {}
    for _, b in ipairs(M.blocks(preset)) do
      local info = M.block_info(b.block)
      if info.title then
        titles[#titles + 1] = info.title
      end
    end
    return (header as M.Header).name .. (#titles > 0 and (": " .. table.concat(titles, " → ")) or "")
  end
  if path:lower():match("%.nam$") then
    return require("plugstate.adapters").nam_words(path)
  end
end

plugstate.adapter(
  {
    name = "tone3000",
    desc = "TONE3000: its presets (.t3kpreset) and the model or impulse response of each block, written into its state",
    matches = M.matches,
    slots = M.slots,
    load = M.load,
    describe = M.describe,
  }
)

return M
