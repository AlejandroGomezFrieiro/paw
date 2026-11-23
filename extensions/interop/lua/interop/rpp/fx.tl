-- Plugins: REAPER's FX chain entries to paw's devices and back.
--
-- What maps, and how the state travels:
--   CLAP   `<CLAP "CLAP: Name (Vendor)" <id> ""` with a `<STATE` block that is
--          the plugin's own saved state, base64. paw keeps a CLAP's
--          state as the same bytes, so it is carried over as it is.
--   VST3   `<VST "VST3: Name (Vendor)" <file> 0 "" <n>{<class id>} ""`. The
--          base64 is three parts: REAPER's header (pins, sizes), the state,
--          and a trailer. The state part is
--            u32 component size, u32 1, component state,
--            u32 controller size, u32 0, controller state
--          and paw's is u32 size, component, u32 size, controller.
--          The sizes are checked against each other before anything is used.
--   LV2    `<LV2 "LV2: Name (Vendor)" <uri> ""` with `P symbol value` lines,
--          which are the plugin's control ports: paw's parameter keys
--          for an LV2 plugin are the same symbols. A `<STATE` block (state
--          beyond the ports) is not carried over.
-- Everything else (VST2, JSFX, AU, DX, containers) stays behind as a note.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local fmt = require("interop.rpp.format")
local interop = require("interop")
local type types = require("paw.types")

local b64 = paw.bytes
local api = paw.api

local record M
  --- What a plugin block is: its format, the text REAPER shows, and what
  --- finds it here (`kind` for CLAP and LV2, name, vendor and class for
  --- VST3).
  record Description
    tag: string
    display: string
    format: string
    kind: string
    id: string
    uri: string
    name: string
    vendor: string
    class: string
  end

  --- The three parts of a `<VST` block, decoded.
  record VstParts
    header: string
    data: string
    trailer: string
  end

  --- What a device keeps of its block in a REAPER project (`meta.rpp`),
  --- so that it is written back as it was read.
  record Meta
    header: {fmt.Token}
    quotes: {integer: string}
    --- A VST3 plugin: REAPER's header and trailer of its state, base64.
    vst_header: string
    vst_trailer: string
  end

  PLUGIN_BLOCKS: {string: boolean}
end

local type Description = M.Description

M.PLUGIN_BLOCKS = {
  VST = true, CLAP = true, LV2 = true, JS = true, DX = true, AU = true, VIDEO_EFFECT = true, CONTAINER = true
}

--- A note of REAPER's about channels after a plugin's vendor.
local function is_channels(s: string): boolean
  return s:match("^%d+ out$") ~= nil
    or s:match("^%d+ch$") ~= nil
    or s:match("^%d+%->%d+ch$") ~= nil
    or s == "Mono"
    or s == "Stereo"
end

--- "VST3i: SINE Player (Orchestral Tools)" -> "VST3i", "SINE Player", "Orchestral Tools"
function M.split_display(display: string): string, string, string
  local prefix, rest = display:match("^(%w+):%s*(.*)$")
  if not prefix then
    return nil, display
  end
  -- Trailing parentheses: the vendor, after which REAPER may add a channel
  -- note such as "(32 out)" or "(Mono)".
  local stripped = rest
  while true do
    local before, inside = stripped:match("^(.-)%s*%(([^()]*)%)$")
    if not before then
      return prefix, stripped, nil
    end
    if not is_channels(inside) then
      return prefix, before, inside
    end
    stripped = before
  end
end

-- VST3 state ------------------------------------------------------------------------

--- REAPER's state part of a VST3 chunk to paw's state, or nil and why.
function M.vst3_state_from_reaper(data: string): string, string
  local cs = b64.u32(data, 1)
  if not cs or 8 + cs + 8 > #data then
    return nil, "the state is shorter than its sizes say"
  end
  local comp = data:sub(9, 8 + cs)
  local ctrl_size = b64.u32(data, 9 + cs)
  if 16 + cs + ctrl_size ~= #data then
    return nil, "the state's sizes do not add up"
  end
  return b64.vst3_join(comp, data:sub(17 + cs, 16 + cs + ctrl_size))
end

--- paw's VST3 state to REAPER's state part.
function M.vst3_state_to_reaper(state: string): string
  local comp, ctrl = b64.vst3_split(state)
  if not comp then
    return nil
  end
  return b64.le32(#comp) .. b64.le32(1) .. comp .. b64.le32(#ctrl) .. b64.le32(0) .. ctrl
end

--- The three parts of a `<VST` block, decoded, with the header checked.
function M.vst_parts(block: fmt.Node): M.VstParts, string
  local groups = block:data_groups()
  if #groups < 2 then
    return nil, "the chunk does not have REAPER's three parts"
  end
  local ok, header = pcall(b64.unbase64, groups[1]) as (boolean, string)
  if not ok then
    return nil, "the chunk is not base64"
  end
  local magic = b64.u32(header, 5)
  if magic ~= 0xfeed5eee and magic ~= 0xfeed5eef then
    return nil, "the chunk header is not REAPER's"
  end
  local data = b64.unbase64(groups[2])
  local size = b64.u32(header, #header - 11)
  if size ~= #data then
    return nil, "the chunk header's size does not match its state"
  end
  return {header = header, data = data, trailer = groups[3] and b64.unbase64(groups[3]) or ""}
end

-- Import -----------------------------------------------------------------------------

--- Describe a plugin block: its format and display, and what finds it here.
function M.describe(block: fmt.Node): Description
  local tag = block:name()
  local d: Description = {tag = tag, display = block:arg(1) or tag}
  if tag == "CLAP" then
    d.format, d.id = "CLAP", block:arg(2)
    d.kind = d.id and ("clap:" .. d.id)
  elseif tag == "LV2" then
    d.format, d.uri = "LV2", block:arg(2)
    d.kind = d.uri and ("lv2:" .. d.uri)
  elseif tag == "VST" then
    local prefix, name, vendor = M.split_display(d.display)
    d.name, d.vendor = name, vendor
    d.format = prefix and prefix:match("^VST3") and "VST3" or "VST2"
    d.class = (block:arg(5) or ""):match("{(%x+)}")
  elseif tag == "JS" then
    d.format, d.display = "JSFX", "JS: " .. (block:arg(1) or "")
  else
    d.format = tag
  end
  return d
end

--- A device of a plugin on a track: what `import` adds, with the bypass of
--- REAPER's chain.
local record Adder
  track: integer
  bypass: boolean
end

--- Add a device of `kind`; nil and why when the plugin does not load here.
local function add_device(at: Adder, kind: string, opts?: types.DeviceOptions): integer, string
  local ok, id = pcall(api.device_add, at.track, kind, opts or {}) as (boolean, integer)
  if not ok then
    return nil, "could not load here: " .. tostring(id):gsub("\n.*", "")
  end
  if at.bypass then
    api.device_set(id, {bypass = true})
  end
  return id
end

local function import_clap(block: fmt.Node, d: Description, at: Adder, meta: M.Meta): integer, string
  if not interop.installed(d.kind) then
    return nil, "not installed here"
  end
  local state_block = block:child("STATE")
  local state = state_block and state_block:data()
  local id, why = add_device(at, d.kind, {state = state ~= "" and state or nil})
  if id then
    api.device_set(id, {meta = {rpp = meta}})
  end
  return id, why
end

--- An LV2 plugin with the values of its control ports (`P symbol value`).
local function import_lv2(block: fmt.Node, d: Description, at: Adder, meta: M.Meta, notes: {string}): integer, string
  if not interop.installed(d.kind) then
    return nil, "not installed here"
  end
  local id, why = add_device(at, d.kind)
  if not id then
    return nil, why
  end
  local unknown: {string} = {}
  for _, line in ipairs(block:all("P")) do
    for i = 1, #line.tokens - 2, 2 do
      local key, value = line:arg(i), line:argn(i + 1)
      if value and not pcall(api.device_set_param, id, key, value) then
        unknown[#unknown + 1] = key
      end
    end
  end
  if #unknown > 0 then
    notes[#notes + 1] = "parameters not found here: " .. table.concat(unknown, ", ")
  end
  local st = block:child("STATE")
  if st and #st.children > 0 then
    notes[#notes + 1] = "state beyond its parameters (<STATE>)"
  end
  api.device_set(id, {meta = {rpp = meta}})
  return id
end

--- A VST3 plugin with its state; with its defaults when the state does not
--- read or the plugin refuses it.
local function import_vst3(block: fmt.Node, d: Description, at: Adder, meta: M.Meta, notes: {string}): integer, string
  local t = d.name and interop.find_plugin({format = "vst3", id = d.class, name = d.name, vendor = d.vendor})
  if not t then
    return nil, "not installed here"
  end
  local parts, why = M.vst_parts(block)
  local state: string
  if parts then
    state, why = M.vst3_state_from_reaper(parts.data)
  end
  local id, err = add_device(at, t.kind, {state = state and b64.base64(state) or nil})
  if not id and state then
    -- The plugin refused the state: keep the plugin with its defaults.
    id, err = add_device(at, t.kind)
    why = why or "the plugin did not accept the state"
  end
  if not id then
    return nil, err
  end
  if not state then
    notes[#notes + 1] = "state not carried over (" .. tostring(why) .. "), defaults used"
  end
  if parts then
    meta.vst_header = b64.base64(parts.header)
    meta.vst_trailer = b64.base64(parts.trailer)
  end
  api.device_set(id, {meta = {rpp = meta}})
  return id
end

--- Add the plugin a block describes to a track. Returns the device id, or
--- nil and why it could not be carried over; `notes` gets a line for each
--- part that was left out although the plugin itself was added.
function M.import(block: fmt.Node, track: integer, bypass: boolean, notes: {string}): integer, string
  local d = M.describe(block)
  local at: Adder = {track = track, bypass = bypass}
  local meta: M.Meta = {header = block.tokens, quotes = block.quotes}
  if d.format == "CLAP" then
    return import_clap(block, d, at, meta)
  elseif d.format == "LV2" then
    return import_lv2(block, d, at, meta, notes)
  elseif d.format == "VST3" then
    return import_vst3(block, d, at, meta, notes)
  elseif d.format == "VST2" then
    return nil, "VST2 plugins are not hosted here"
  elseif d.format == "JSFX" then
    return nil, "JSFX are REAPER's own"
  end
  return nil, d.format .. " plugins are not hosted here"
end

-- Export -----------------------------------------------------------------------------

--- "CLAPi: Name (Vendor)": how REAPER shows a plugin of a format.
local function display_of(format: string, info: types.DeviceType): string
  return string.format(
    "%s%s: %s (%s)",
    format,
    info.category == "instrument" and "i" or "",
    info.name,
    info.vendor ~= "" and info.vendor or "unknown"
  )
end

--- The header of a block as it was read, when it was read from a block of
--- the same format.
local function keep_header(block: fmt.Node, meta: M.Meta, tag: string)
  if meta and meta.header and meta.header[1] == tag then
    block.tokens, block.quotes = meta.header, meta.quotes
  end
end

local function export_clap(d: types.Device, info: types.DeviceType, meta: M.Meta, state: string): fmt.Node
  local block = fmt.block("CLAP", display_of("CLAP", info), (d.kind:gsub("^clap:", "")), "")
  keep_header(block, meta, "CLAP")
  block:add(fmt.line("CFG", 4, 0, 0, ""))
  if state then
    block:add(fmt.block("STATE")):set_data(state)
  end
  return block
end

--- An LV2 plugin: its control ports as `P` lines of up to twelve each.
local function export_lv2(d: types.Device, info: types.DeviceType, meta: M.Meta, state: string): fmt.Node, string
  local block = fmt.block("LV2", display_of("LV2", info), (d.kind:gsub("^lv2:", "")), "")
  keep_header(block, meta, "LV2")
  block:add(fmt.line("CFG", 0, 0, 0, ""))
  local line: fmt.Node
  local n = 0
  local keys: {string} = {}
  for key in pairs(d.params or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    if not line or n >= 12 then
      line = block:add(fmt.line("P"))
      n = 0
    end
    line.tokens[#line.tokens + 1] = key
    line.tokens[#line.tokens + 1] = d.params[key]
    n = n + 1
  end
  return block, state and "LV2 plugins: state beyond the control ports is not written" or nil
end

--- A VST3 plugin, only when it came from a REAPER project: REAPER's header
--- is kept with the size of the new state.
local function export_vst3(meta: M.Meta, state: string): fmt.Node, string
  if not (meta and meta.vst_header and meta.header) then
    return nil, "a VST3 plugin is only written back when it came from a REAPER project (REAPER's id for it is unknown)"
  end
  local data = state and M.vst3_state_to_reaper(b64.unbase64(state))
  if not data then
    return nil, "its state could not be read"
  end
  local header = b64.unbase64(meta.vst_header)
  header = header:sub(1, #header - 12) .. b64.le32(#data) .. header:sub(#header - 7)
  local block = fmt.block()
  block.tokens, block.quotes = meta.header, meta.quotes
  block:set_data({b64.base64(header), b64.base64(data), meta.vst_trailer or "AAAAAAAA"})
  return block
end

--- A plugin block for a device, or nil and why there is none. The second
--- result of a block is a note of what was left out of it.
function M.export(device: integer, info: types.DeviceType): fmt.Node, string
  local d = api.device_get(device)
  local meta = d.meta and d.meta.rpp as M.Meta
  local state = api.device_state(device)
  local format = info and info.format or d.format
  if format == "clap" then
    return export_clap(d, info, meta, state)
  elseif format == "lv2" then
    return export_lv2(d, info, meta, state)
  elseif format == "vst3" then
    return export_vst3(meta, state)
  end
  return nil, "no REAPER equivalent"
end

return M
