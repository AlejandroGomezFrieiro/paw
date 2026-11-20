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
local fmt = require("rpp.format")
local b64 = paw.bytes
local M = {}

local PLUGIN_BLOCKS = { VST = true, CLAP = true, LV2 = true, JS = true, DX = true, AU = true, VIDEO_EFFECT = true, CONTAINER = true }
M.PLUGIN_BLOCKS = PLUGIN_BLOCKS

--- "VST3i: SINE Player (Orchestral Tools)" -> "VST3i", "SINE Player", "Orchestral Tools"
function M.split_display(display)
  local prefix, rest = display:match("^(%w+):%s*(.*)$")
  if not prefix then return nil, display end
  -- Trailing parentheses: the vendor, after which REAPER may add a channel
  -- note such as "(32 out)" or "(Mono)".
  local function is_channels(s)
    return s:match("^%d+ out$") or s:match("^%d+ch$") or s:match("^%d+%->%d+ch$") or s == "Mono" or s == "Stereo"
  end
  local stripped = rest
  while true do
    local before, inside = stripped:match("^(.-)%s*%(([^()]*)%)$")
    if not before then return prefix, stripped, nil end
    if not is_channels(inside) then return prefix, before, inside end
    stripped = before
  end
end

-- VST3 state ------------------------------------------------------------------------

--- REAPER's state part of a VST3 chunk to paw's state, or nil and why.
function M.vst3_state_from_reaper(data)
  local cs = b64.u32(data, 1)
  if not cs or 8 + cs + 8 > #data then return nil, "the state is shorter than its sizes say" end
  local comp = data:sub(9, 8 + cs)
  local ctrl_size = b64.u32(data, 9 + cs)
  if 16 + cs + ctrl_size ~= #data then return nil, "the state's sizes do not add up" end
  local ctrl = data:sub(17 + cs, 16 + cs + ctrl_size)
  return b64.le32(#comp) .. comp .. b64.le32(#ctrl) .. ctrl
end

--- paw's VST3 state to REAPER's state part.
function M.vst3_state_to_reaper(state)
  local cs = b64.u32(state, 1)
  if not cs or 4 + cs + 4 > #state then return nil end
  local comp = state:sub(5, 4 + cs)
  local ctrl_size = b64.u32(state, 5 + cs) or 0
  local ctrl = state:sub(9 + cs, 8 + cs + ctrl_size)
  return b64.le32(#comp) .. b64.le32(1) .. comp .. b64.le32(#ctrl) .. b64.le32(0) .. ctrl
end

--- The three parts of a `<VST` block, decoded, with the header checked.
function M.vst_parts(block)
  local groups = block:data_groups()
  if #groups < 2 then return nil, "the chunk does not have REAPER's three parts" end
  local ok, header = pcall(b64.unbase64, groups[1])
  if not ok then return nil, "the chunk is not base64" end
  local magic = b64.u32(header, 5)
  if magic ~= 0xfeed5eee and magic ~= 0xfeed5eef then return nil, "the chunk header is not REAPER's" end
  local data = b64.unbase64(groups[2])
  local size = b64.u32(header, #header - 11)
  if size ~= #data then return nil, "the chunk header's size does not match its state" end
  return { header = header, data = data, trailer = groups[3] and b64.unbase64(groups[3]) or "" }
end

-- Import -----------------------------------------------------------------------------

local function installed(kind) return paw.api.device_find({ kind = kind }) end

--- The VST3 plugin installed here: by its class id (`{...}` in REAPER's
--- line), else by name and vendor.
local function find_vst3(name, vendor, class)
  return paw.api.device_find({ format = "vst3", id = class, name = name, vendor = vendor })
end

--- Describe a plugin block: { format, display, kind (if it can map), ... }.
function M.describe(block)
  local tag = block.tokens[1]
  local d = { tag = tag, display = block.tokens[2] or tag }
  if tag == "CLAP" then
    d.format, d.id = "CLAP", block.tokens[3]
    d.kind = d.id and ("clap:" .. d.id)
  elseif tag == "LV2" then
    d.format, d.uri = "LV2", block.tokens[3]
    d.kind = d.uri and ("lv2:" .. d.uri)
  elseif tag == "VST" then
    local prefix, name, vendor = M.split_display(d.display)
    d.name, d.vendor = name, vendor
    d.format = prefix and prefix:match("^VST3") and "VST3" or "VST2"
    d.class = tostring(block.tokens[6] or ""):match("{(%x+)}")
  elseif tag == "JS" then
    d.format, d.display = "JSFX", "JS: " .. (block.tokens[2] or "")
  else
    d.format = tag
  end
  return d
end

--- Add the plugin a block describes to a track. Returns the device id, or
--- nil and why it could not be carried over; `notes` gets a line for each
--- part that was left out although the plugin itself was added.
function M.import(block, track, bypass, notes)
  local d = M.describe(block)
  local api = paw.api
  local function add(kind, opts)
    local ok, id = pcall(api.device_add, track, kind, opts or {})
    if not ok then return nil, "could not load here: " .. tostring(id):gsub("\n.*", "") end
    if bypass then api.device_set(id, "bypass", true) end
    return id
  end
  local meta = { header = block.tokens, quotes = block.quotes }
  if d.format == "CLAP" then
    if not installed(d.kind) then return nil, "not installed here" end
    local state_block = block:child("STATE")
    local state = state_block and state_block:data()
    local id, why = add(d.kind, { state = state ~= "" and state or nil })
    if id then api.device_set(id, "meta", { rpp = meta }) end
    return id, why
  elseif d.format == "LV2" then
    if not installed(d.kind) then return nil, "not installed here" end
    local id, why = add(d.kind)
    if not id then return nil, why end
    local unknown = {}
    for _, line in ipairs(block:all("P")) do
      for i = 2, #line.tokens - 1, 2 do
        local key, value = line.tokens[i], tonumber(line.tokens[i + 1])
        if value and not pcall(api.device_set_param, id, key, value) then unknown[#unknown + 1] = key end
      end
    end
    if #unknown > 0 then notes[#notes + 1] = "parameters not found here: " .. table.concat(unknown, ", ") end
    local st = block:child("STATE")
    if st and #st.children > 0 then notes[#notes + 1] = "state beyond its parameters (<STATE>)" end
    api.device_set(id, "meta", { rpp = meta })
    return id
  elseif d.format == "VST3" then
    local t = d.name and find_vst3(d.name, d.vendor, d.class)
    if not t then return nil, "not installed here" end
    local parts, why = M.vst_parts(block)
    local state
    if parts then state, why = M.vst3_state_from_reaper(parts.data) end
    local id, err = add(t.kind, { state = state and b64.base64(state) or nil })
    if not id and state then
      -- The plugin refused the state: keep the plugin with its defaults.
      id, err = add(t.kind)
      why = why or "the plugin did not accept the state"
    end
    if not id then return nil, err end
    if not state then notes[#notes + 1] = "state not carried over (" .. tostring(why) .. "), defaults used" end
    if parts then
      meta.vst_header = b64.base64(parts.header)
      meta.vst_trailer = b64.base64(parts.trailer)
    end
    api.device_set(id, "meta", { rpp = meta })
    return id
  elseif d.format == "VST2" then
    return nil, "VST2 plugins are not hosted here"
  elseif d.format == "JSFX" then
    return nil, "JSFX are REAPER's own"
  end
  return nil, d.format .. " plugins are not hosted here"
end

-- Export -----------------------------------------------------------------------------

--- A plugin block for a device, or nil and why there is none.
function M.export(device, info)
  local api = paw.api
  local d = api.device_get(device)
  local meta = d.meta and d.meta.rpp
  local state = api.device_state(device)
  local format = info and info.format or d.format
  if format == "clap" then
    local display = string.format("CLAP%s: %s (%s)", info.category == "instrument" and "i" or "", info.name, info.vendor ~= "" and info.vendor or "unknown")
    local block = fmt.block("CLAP", display, (d.kind:gsub("^clap:", "")), "")
    if meta and meta.header and meta.header[1] == "CLAP" then
      block.tokens, block.quotes = meta.header, meta.quotes
    end
    block:add(fmt.line("CFG", 4, 0, 0, ""))
    if state then block:add(fmt.block("STATE")):set_data(state) end
    return block
  elseif format == "lv2" then
    local display = string.format("LV2%s: %s (%s)", info.category == "instrument" and "i" or "", info.name, info.vendor ~= "" and info.vendor or "unknown")
    local block = fmt.block("LV2", display, (d.kind:gsub("^lv2:", "")), "")
    if meta and meta.header and meta.header[1] == "LV2" then
      block.tokens, block.quotes = meta.header, meta.quotes
    end
    block:add(fmt.line("CFG", 0, 0, 0, ""))
    local line, n = nil, 0
    local keys = {}
    for key in pairs(d.params or {}) do keys[#keys + 1] = key end
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
  elseif format == "vst3" then
    if not (meta and meta.vst_header and meta.header) then
      return nil, "a VST3 plugin is only written back when it came from a REAPER project (REAPER's id for it is unknown)"
    end
    local data = state and M.vst3_state_to_reaper(b64.unbase64(state))
    if not data then return nil, "its state could not be read" end
    local header = b64.unbase64(meta.vst_header)
    header = header:sub(1, #header - 12) .. b64.le32(#data) .. header:sub(#header - 7)
    local block = fmt.block()
    block.tokens, block.quotes = meta.header, meta.quotes
    block:set_data({ b64.base64(header), b64.base64(data), meta.vst_trailer or "AAAAAAAA" })
    return block
  end
  return nil, "no REAPER equivalent"
end

return M
