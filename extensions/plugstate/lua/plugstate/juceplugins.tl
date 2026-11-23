-- The state of plugins as trees in paw: the descriptions of some JUCE
-- plugins, one adapter for every described plugin, one adapter (a
-- fallback) for every plugin whose state a framework reader opens, and the
-- commands that show and change the state of any plugin (`:plugstate.tree`,
-- `.mark`, `.changes`, `.path`, `.preset_write`). See
-- `plugstate.frameworks` and `plugstate.jucestate` for the layers.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local plugstate = require("plugstate")
local jucestate = require("plugstate.jucestate")
local frameworks = require("plugstate.frameworks")
local juce = require("plugstate.juce")
local type types = require("paw.types")
local type contracts = require("paw.contracts")

local api = paw.api
local command = paw.command

local type Doc = jucestate.Doc
local type Slot = plugstate.Slot
local type SlotValue = plugstate.SlotValue

local record M
  --- The states kept by `:plugstate.mark`, by device (not in the project).
  marks: {integer: string}
end

M.marks = {}

-- --- descriptions -------------------------------------------------------------------

-- Surge XT: its own patch ("sub3", the size of the XML, the sizes of its
-- wavetables, the XML, the wavetables) in a JUCE wrapper.
jucestate.plugin(
  {
    name = "surge-xt",
    title = "Surge XT",
    ids = {
      clap = "org.surge-synth-team.surge-xt",
      vst3 = "Surge XT",
      lv2 = "https://surge-synthesizer.github.io/lv2/surge-xt",
    },
    header = {magic = "sub3", size = 5, skip = 32},
    root = "patch",
    ignore = {"/patch/dawExtraState"}, -- the window's state, not the sound
    paths = {
      name = "/patch/meta@name", category = "/patch/meta@category", octave = "/patch/parameters/a_octave@value"
    },
    slots = {
      {key = "name", label = "Patch name", path = "name"},
      {key = "octave", label = "Octave of scene A", path = "octave"},
    },
  }
)

-- Musio (Cinesamples): `copyXmlToBinary` of a `PluginState`. The
-- instrument, its articulations and its mic mix are in `MusioFile`, which
-- is empty until an instrument is loaded (with a login).
jucestate.plugin(
  {
    name = "musio",
    title = "Musio",
    ids = {vst3 = "Musio"},
    root = "PluginState",
    paths = {
      reverb = "/PluginState@studioReverb",
      room = "/PluginState@studioReverbRoom",
      reverb_amount = "/PluginState@studioReverbAmount",
      file = "/PluginState/MusioFile",
      file_version = "/PluginState/MusioFile@FileVersion",
    },
    slots = {
      {key = "reverb", label = "Studio reverb (on, off)", path = "reverb"},
      {key = "room", label = "Studio reverb room", path = "room"},
      {key = "reverb_amount", label = "Studio reverb amount (0 to 1)", path = "reverb_amount"},
    },
  }
)

-- DecentSampler: `copyXmlToBinary` of a `DecentSampler` element. Its
-- attributes name the sample library that it plays. No slots: a library
-- needs its files, so the names are for `:plugstate.path` and the tree.
jucestate.plugin(
  {
    name = "decent-sampler",
    title = "DecentSampler",
    ids = {vst3 = "DecentSampler"},
    root = "DecentSampler",
    paths = {
      preset_name = "/DecentSampler@_presetName",
      sample_path = "/DecentSampler@_samplePath",
      library_url = "/DecentSampler@_libraryUrl",
      tuning = "/DecentSampler@_tuningA69Frequency",
    },
  }
)

-- --- presets of path edits ------------------------------------------------------------

-- The slot of a preset of path edits: every adapter here has one.
local function preset_slot(): Slot
  return {key = "preset", label = "Preset", what = "preset", kind = "file", types = {"jucepreset"}}
end

-- The preset a file holds, or an error with why.
local function preset_of(value: SlotValue): jucestate.Preset, string
  local file = tostring(value)
  local preset, err = jucestate.read_preset(file)
  if not preset then
    error(err, 0)
  end
  return preset, preset.name or (plugstate.stem(file):gsub("%.jucepreset$", ""))
end

-- A few words on a preset file: what it is for, and how many changes it has.
local function describe_preset(path: string, owner: function(p: jucestate.Preset): string): string
  local preset = path:match("%.jucepreset$") and jucestate.read_preset(path)
  if preset then
    return string.format("%s preset, %d changes", owner(preset), #(preset.edits or {}))
  end
end

-- --- the adapter of described plugins ---------------------------------------------------

local function doc_of(id: integer, d?: types.Device): Doc
  d = d or api.device_get(id)
  return jucestate.open(api.device_state(id), d.plugin.format, {desc = jucestate.plugin_of(d)})
end

plugstate.adapter(
  {
    name = "juce",
    desc = "JUCE plugins with a description (Surge XT, Musio): presets of path edits (.jucepreset), and the values that the description names",
    matches = function(d: types.Device): boolean
      local desc = jucestate.plugin_of(d)
      return desc ~= nil and desc.slots ~= nil
    end,
    slots = function(id: integer, d: types.Device): {Slot}
      local desc = jucestate.plugin_of(d)
      local doc = doc_of(id, d)
      local slots = {preset_slot()}
      for _, s in ipairs(desc.slots) do
        local v = doc:get(s.path)
        slots[#slots + 1] = {
          key = s.key,
          label = s.label,
          what = s.what or s.key,
          kind = "text",
          path = s.path,
          value = v ~= nil and tostring(v) or nil,
        }
      end
      return slots
    end,
    load = function(id: integer, d: types.Device, slot: Slot, value: SlotValue): types.PresetLoad
      -- The plugin's values after the state count, not those of the project
      -- before it: the state holds them.
      if slot.key == "preset" then
        local preset, name = preset_of(value)
        local state = jucestate.generate(preset, d.plugin.format, api.device_state(id), {uri = d.plugin.id})
        return {state = state, name = name, params = {}}
      end
      local doc = doc_of(id, d)
      doc:set(slot.path, tostring(value), "string", {make = true})
      return {state = doc:write(), name = d.meta and d.meta.preset as string or nil, params = {}}
    end,
    describe = function(path: string): string
      return describe_preset(path, function(p: jucestate.Preset): string return p.plugin or "JUCE" end)
    end,
  }
)

-- --- the adapter of every other plugin ---------------------------------------------------
-- Asked after all the others: a plugin whose state a framework reader
-- opens takes a preset of path edits (`.jucepreset`), on its state lane too.

plugstate.adapter(
  {
    name = "state",
    fallback = true,
    desc = "every other plugin whose saved state plugstate reads (JUCE, DPF, iPlug2, LSP, LV2, nih-plug and other JSON, or its bytes): presets of path edits (.jucepreset)",
    matches = function(d: types.Device): boolean return d.plugin ~= nil and not d.missing end,
    slots = function(): {Slot} return {preset_slot()} end,
    load = function(id: integer, d: types.Device, _: Slot, value: SlotValue): types.PresetLoad
      local preset, name = preset_of(value)
      local hint = frameworks.markers(frameworks.binary_of(d.plugin))
      local state = frameworks.generate(
        preset, d.plugin.format, api.device_state(id), {uri = d.plugin.id, param_info = d.param_info, hint = hint}
      )
      return {state = state, name = name, params = {}}
    end,
    describe = function(path: string): string
      return describe_preset(
        path, function(p: jucestate.Preset): string return p.framework or p.plugin or "plugstate" end
      )
    end,
  }
)

-- --- commands for any plugin ----------------------------------------------------------------

--- The plugin device the commands act on: the one of the device panel's
--- row, else the first plugin of the cursor track.
function M.target(): integer, string
  local selected = plugstate.panel_device()
  if selected and api.device_get(selected).plugin then
    return selected
  end
  local track = paw.cursor.track_id()
  for _, id in ipairs(track and api.track_get(track).devices or {}) do
    if api.device_get(id).plugin then
      return id
    end
  end
  return nil, "no plugin here: put the row of the device panel on one"
end

--- The state of a device as a document of its framework, or nil and why.
function M.open(id: integer, state64?: string): Doc, string
  local d = api.device_get(id)
  if not d.plugin then
    return nil, d.name .. " is not a plugin"
  end
  local ok, doc = pcall(frameworks.open_device, id, state64) as (boolean, Doc)
  if not ok then
    return nil, d.name .. ": " .. tostring(doc)
  end
  return doc
end

local function target(): integer
  local id, why = M.target()
  if not id then
    paw.notify(why, "warn")
  end
  return id
end

local function opened(id: integer): Doc
  local doc, why = M.open(id)
  if not doc then
    paw.notify(why, "warn")
  end
  return doc
end

--- Keep the state of a device now, to compare with later (`changes`).
function M.mark(id: integer)
  M.marks[id] = api.device_state(id)
end

-- Whether a path is under one of the prefixes.
local function ignored(path: string, prefixes: {string}): boolean
  for _, prefix in ipairs(prefixes) do
    if path:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

--- What changed in the state of a device since `mark`: the changes of
--- `juce.diff`, or nil and why.
function M.changes(id: integer): {juce.Change}, string
  local before = M.marks[id]
  if not before then
    return nil, "no mark: `:plugstate.mark` keeps the state first"
  end
  local a, why = M.open(id, before)
  if not a then
    return nil, why
  end
  local b, why2 = M.open(id)
  if not b then
    return nil, why2
  end
  local out: {juce.Change} = {}
  -- What the description says is not the sound (the state of the window).
  local ignore = a.plugin and a.plugin.ignore or {}
  for _, c in ipairs(juce.diff(a.root, b.root)) do
    if not ignored(c.path, ignore) then
      out[#out + 1] = c
    end
  end
  return out
end

--- The edits of a preset from changes: sets, nodes added (as trees) and
--- what was taken away.
function M.edits_of(changes: {juce.Change}): {jucestate.Edit}
  local edits: {jucestate.Edit} = {}
  for _, c in ipairs(changes) do
    local after = c.after
    if c.op == "remove" then
      edits[#edits + 1] = {path = c.path, remove = true}
    elseif after is string then
      edits[#edits + 1] = {path = c.path, value = juce.value(after), kind = juce.kind(after), make = true}
    elseif after then
      local parent = c.path:match("^(.*)/[^/]*$")
      edits[#edits + 1] = {path = parent, insert = after}
    end
  end
  return edits
end

-- The device's name, for the messages.
local function name_of(id: integer): string
  return api.device_get(id).name
end

command(
  "plugstate.tree",
  function(ctx: contracts.CommandContext)
    local id = target()
    if not id then
      return
    end
    local doc = opened(id)
    if not doc then
      return
    end
    local words: {string} = {}
    for i, a in ipairs(ctx.args) do
      words[i] = tostring(a)
    end
    local path = table.concat(words, " ")
    local found = path ~= "" and doc:get(path) or doc.root
    local node = juce.tree_of(found)
    if not node then
      paw.notify(path .. " = " .. tostring(found))
      return
    end
    local lines = {
      name_of(id)
        .. " · "
        .. (doc.title or doc.framework or "JUCE")
        .. " · "
        .. table.concat(doc:layer_names(), " › "),
    }
    for _, note in ipairs(doc.notes or {}) do
      lines[#lines + 1] = "(" .. note .. ")"
    end
    for _, l in ipairs(juce.dump(node, {depth = ctx.count or 3, max = 40})) do
      lines[#lines + 1] = l
    end
    paw.notify(table.concat(lines, "\n"))
  end,
  {
    desc = "Show the saved state of a plugin as a tree, in the form of its framework (JUCE, DPF, iPlug2, LSP, LV2, JSON): `plugstate.tree /PluginState/MusioFile` shows a part (a count: how deep)",
  }
)

command(
  "plugstate.mark",
  function()
    local id = target()
    if not id or not opened(id) then
      return
    end
    M.mark(id)
    paw.notify(name_of(id) .. ": state kept. Change the plugin, then `:plugstate.changes`")
  end,
  {desc = "Keep the saved state of a plugin now, to see later what a change in its window changed"}
)

command(
  "plugstate.changes",
  function()
    local id = target()
    if not id then
      return
    end
    local changes, why = M.changes(id)
    if not changes then
      paw.notify(why, "warn")
      return
    end
    if #changes == 0 then
      paw.notify(name_of(id) .. ": no change since the mark")
      return
    end
    local lines = {name_of(id) .. ": " .. #changes .. " changes since the mark"}
    for _, l in ipairs(juce.diff_text(changes, 40)) do
      lines[#lines + 1] = l
    end
    paw.notify(table.concat(lines, "\n"))
  end,
  {desc = "List the paths of the saved state of a plugin that changed since `:plugstate.mark`"}
)

-- The value that `:plugstate.path` sets, and its kind. A number stays a
-- number, except in a JUCE state (its XML is text) or in quotes.
local function path_value(doc: Doc, path: string, text: string, quoted: boolean): juce.Value, juce.Kind
  local now = doc:get(path)
  local number = tonumber(text)
  if not quoted and doc.framework ~= "juce" and doc.framework ~= "hise" and now is number and number then
    return number, nil
  end
  return text, "string"
end

command(
  "plugstate.path",
  function(ctx: contracts.CommandContext)
    local id = target()
    if not id then
      return
    end
    local doc = opened(id)
    if not doc then
      return
    end
    local path, value = tostring(ctx.args[1] or ""):match("^%s*(%S+)%s*(.-)%s*$")
    if not path then
      paw.notify("plugstate.path needs a path: `plugstate.path /PluginState@studioReverb off`", "warn")
      return
    end
    if value == "" then
      paw.notify(path .. " = " .. tostring((doc:get(path))))
      return
    end
    local quoted = value:match('^"(.*)"$')
    value = quoted or value
    local v, kind = path_value(doc, path, value, quoted ~= nil)
    local ok, err = pcall(doc.set, doc, path, v, kind, {make = true}) as (boolean, string)
    if not ok then
      paw.notify(name_of(id) .. ": " .. tostring(err), "error")
      return
    end
    local preset = api.device_get(id).meta.preset as string
    local fine, why = pcall(api.device_load, id, {name = preset, state = doc:write(), params = {}}) as (boolean, string)
    if not fine then
      paw.notify(name_of(id) .. ": " .. tostring(why), "error")
      return
    end
    paw.notify(name_of(id) .. ": " .. path .. " = " .. value)
  end,
  {
    raw = true,
    desc = "Show or set a value in the saved state of a plugin by its path: `plugstate.path /PluginState@studioReverb off`, `plugstate.path /DPF/Parameters@size 30` (one undo step)",
  }
)

command(
  "plugstate.preset_write",
  function(ctx: contracts.CommandContext)
    local id = target()
    if not id then
      return
    end
    local given = ctx.args[1]
    if not given then
      paw.notify("plugstate.preset_write needs a file name", "warn")
      return
    end
    local file = tostring(given):gsub("^~", os.getenv("HOME") or "~")
    if not file:match("%.jucepreset$") then
      file = file .. ".jucepreset"
    end
    local changes, why = M.changes(id)
    if not changes then
      paw.notify(why, "warn")
      return
    end
    local d = api.device_get(id)
    local desc = jucestate.plugin_of(d)
    local doc = M.open(id)
    jucestate.write_preset(
      file,
      {
        plugin = desc and desc.name,
        name = (plugstate.stem(file):gsub("%.jucepreset$", "")),
        framework = doc and doc.framework,
        edits = M.edits_of(changes),
      }
    )
    paw.notify(d.name .. ": " .. #changes .. " changes written to " .. file)
  end,
  {
    desc = "Write the changes since `:plugstate.mark` as a preset (.jucepreset) that `:plugstate.load` loads into the plugin (a JUCE preset into each format of it)",
    complete = "files",
  }
)

return M
