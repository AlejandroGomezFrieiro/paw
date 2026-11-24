-- Working with devices the way one does all day: adding them by hand,
-- presets, favourites, wet/dry, controller learn. `paw.fx`.
local api = paw.api
local M = {}

paw.option.define("editor_on_add", true) -- a plugin added by hand opens its own window

-- Adding by hand ----------------------------------------------------------------

--- True if a person uses paw: a terminal UI is attached, or a graphical
--- frontend asked for the state recently. Scripts (`-l`) and a kernel that
--- nobody looks at do not count.
function M.interactive()
  if api.ui_attached() then return true end
  local polled = paw.frontend.polled
  return polled ~= nil and api.now() - polled < 5000
end

--- Add a device as a person does, from the device picker, the "Add a device"
--- box of the window or `:device.add`. It works as `part:add_device`. Then
--- a plugin with a window shows its window (`paw.opt.editor_on_add`), as
--- REAPER does. Some instruments make no sound until their window opens one time.
function M.add(part, kind, opts)
  local device = M.place(part, kind, opts)
  M.added(device, kind, opts)
  return device
end

--- The first half of `add`: the device on the part, set to the preset new
--- ones start from. What the device picker tries out before it is chosen.
function M.place(part, kind, opts)
  local device = part:add_device(kind, nil, { index = opts and opts.index })
  -- The preset the user marked as the one new instances start from.
  local default = M.default_preset(kind)
  if default then
    local ok, err = pcall(M.load, device, default)
    if not ok then
      paw.notify("the default preset `" .. default .. "` did not load: " .. tostring(err):match("^[^\n]*"), "warn")
    end
  end
  return device
end

--- The second half of `add`, once the device is there: remembered as used,
--- its window shown.
function M.added(device, kind, opts)
  M.note_used(kind, opts and opts.query)
  if paw.opt.editor_on_add and M.interactive() and device.editor == "closed" then
    local ok, err = pcall(api.device_editor, device.id, true)
    if not ok then paw.notify(tostring(err):match("^[^\n]*"), "warn") end
  end
  paw.emit("device.added_by_hand", { id = device.id, kind = kind })
  return device
end

-- Wet/dry and gain ----------------------------------------------------------------------
--
-- Every device has two parameters of the host's after its own: `fx_wet`, the
-- share of its output in percent (the rest is its input, held back by its
-- latency), and `fx_gain`, its output gain in dB. They are set, automated and
-- saved like any other parameter.

M.host_params = { fx_wet = true, fx_gain = true }

local function id_of(device) return type(device) == "number" and device or device.id end

--- How much of a device's effect is heard, in percent.
function M.set_wet(device, percent) api.device_set_param(id_of(device), "fx_wet", percent) end

--- A device's own gain after its effect, in dB.
function M.set_gain(device, db) api.device_set_param(id_of(device), "fx_gain", db) end

-- Parameters of large plugins -----------------------------------------------------------
--
-- A plugin may have a thousand parameters; the window's card shows sixteen.
-- The ones the user chose to show are kept with the device (`meta.shown`,
-- saved in the project) and come first, then the one last touched, then the
-- rest in the plugin's order.

--- The parameter last moved, in a plugin's own window or here:
--- `{ device = id, param = key, id = the device's own id, from = "editor" | "host" }`.
M.last_touched = nil

paw.on("param.touched", function(e)
  M.last_touched = { device = e.device, param = e.param, id = e.id, from = e.from }
  -- One moved in the plugin's own window shows itself in the device panel.
  if e.from == "editor" then
    local panel = paw.ui.views:get("devices")
    for i, row in ipairs(panel:rows()) do
      if row.param and row.device.id == e.device and row.param.key == e.param then panel.row = i end
    end
  end
end)

local function shown_of(d)
  local meta = type(d.meta) == "table" and d.meta or {}
  return type(meta.shown) == "table" and meta.shown or {}
end

--- The keys of the parameters the user chose to show for a device.
function M.shown(device) return shown_of(api.device_get(id_of(device))) end

--- Show a parameter first on the card of the device. The device keeps this setting.
function M.show_param(device, key)
  local d = api.device_get(id_of(device))
  local meta = type(d.meta) == "table" and d.meta or {}
  local list = { key }
  for _, k in ipairs(shown_of(d)) do
    if k ~= key then list[#list + 1] = k end
  end
  meta.shown = list
  api.device_set(d.id, "meta", meta)
end

--- Take a parameter off the device's card in the window.
function M.hide_param(device, key)
  local d = api.device_get(id_of(device))
  local meta = type(d.meta) == "table" and d.meta or {}
  local list = {}
  for _, k in ipairs(shown_of(d)) do
    if k ~= key then list[#list + 1] = k end
  end
  meta.shown = #list > 0 and list or nil
  api.device_set(d.id, "meta", meta)
end

--- A device's own parameters in the order its card shows them: the ones
--- chosen, the one last touched, then the rest. `d` is `api.device_get`'s.
function M.card_params(d)
  local by_key, out, seen = {}, {}, {}
  for _, p in ipairs(d.param_info) do
    if not M.host_params[p.key] then by_key[p.key] = p end
  end
  local function add(key)
    if by_key[key] and not seen[key] then
      seen[key] = true
      out[#out + 1] = by_key[key]
    end
  end
  for _, key in ipairs(shown_of(d)) do
    add(key)
  end
  local last = M.last_touched
  if last and last.device == d.id then add(last.param) end
  for _, p in ipairs(d.param_info) do
    add(p.key)
  end
  return out
end

--- Put the device panel's row on one parameter of a device.
function M.focus_param(id, key)
  local panel = paw.ui.views:get("devices")
  for i, row in ipairs(panel:rows()) do
    if row.param and row.device.id == id and row.param.key == key then panel.row = i end
  end
end

--- Select one of the parameters of the device: type a part of its name. It
--- shows first on the card of the window, and it is selected in the device panel.
function M.pick_param(device)
  device = device or M.target()
  if not device then return end
  local d = device:get()
  local items = {}
  local shown = {}
  for _, k in ipairs(shown_of(d)) do
    shown[k] = true
  end
  for _, p in ipairs(d.param_info) do
    items[#items + 1] = p
  end
  paw.pick({
    title = "Parameters · " .. d.name,
    items = items,
    format = function(p)
      return string.format(
        "%s %-34s %s",
        shown[p.key] and "●" or " ",
        p.name,
        paw.frontend.format_value(p, d.params[p.key])
      )
    end,
    on_choose = function(p)
      if not M.host_params[p.key] then M.show_param(d.id, p.key) end
      M.focus_param(d.id, p.key)
    end,
    actions = {
      ["<C-x>"] = {
        desc = "stop showing it first",
        fn = function(p)
          if p then M.hide_param(d.id, p.key) end
        end,
      },
    },
  })
end

-- Presets ---------------------------------------------------------------------------
--
-- A user preset is a JSON file, `<data dir>/presets/<kind>/<name>.json`, of
-- the device as `Device:snapshot()` gives it plus its name: the plugin's
-- state (base64) and every parameter's value. It loads into the same kind
-- of device in any project. Factory presets are the plugin's own (CLAP
-- preset discovery, `.vstpreset` files, LV2 presets) or, for built-in
-- devices, the tables in `paw/device_presets.lua` (also `paw.params.presets`).

M.factory = require("paw.device_presets") -- the built-in devices' presets, by kind
M.menu_size = 16 -- presets in the window's menu around the one loaded

--- Where presets are kept: `paw.opt.presets_dir`, or `presets` in the data directory.
function M.presets_dir()
  local dir = paw.opt.presets_dir
  if dir and dir ~= "" then return dir end
  return api.env().data_dir .. "/presets"
end

local function safe(text) return (tostring(text):gsub('[/\\:%*%?"<>|%c]', "_")) end

local function preset_name(name)
  local text = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then error("a preset needs a name", 3) end
  return text
end

local function kind_dir(kind) return M.presets_dir() .. "/" .. safe(kind) end

local function read_json(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local data = paw.json.decode(file:read("*a"))
  file:close()
  return data
end

local function write_json(path, data)
  pcall(paw.api.fs_mkdir, (path:match("^(.*)/[^/]*$")))
  local file = io.open(path, "w")
  if not file then error("cannot write " .. path, 3) end
  file:write(paw.json.encode(data, true), "\n")
  file:close()
end

local function as_device(device)
  if type(device) == "number" then return paw.device(device) end
  return device
end

--- The user's presets for a kind of device, by name: `{ name, path }`.
function M.user_presets(kind)
  local out = {}
  for _, entry in ipairs(api.read_dir(kind_dir(kind))) do
    if not entry.is_dir and entry.name:match("%.json$") then
      local data = read_json(kind_dir(kind) .. "/" .. entry.name)
      if data and data.kind == kind then
        out[#out + 1] = {
          name = data.name or entry.name:gsub("%.json$", ""),
          path = kind_dir(kind) .. "/" .. entry.name,
          user = true,
        }
      end
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

--- The device's own presets: a plugin's, or a built-in device's from
--- `paw.fx.factory`. `{ name, category, id }`, in the order the plugin gives.
function M.factory_presets(device)
  device = as_device(device)
  local d = device:get()
  if d.format == "builtin" or M.factory[d.kind] then
    local out = {}
    for i, p in ipairs(M.factory[d.kind] or {}) do
      out[i] = { name = p.name, params = p.params, category = p.category or "" }
    end
    return out
  end
  local ok, answer = pcall(api.device_call, d.id, "presets", "")
  if not ok then return {} end
  return paw.json.decode(answer) or {}
end

--- Every preset of the device: the user's first, then the factory's.
function M.presets(device)
  device = as_device(device)
  local out = {}
  for _, p in ipairs(M.user_presets(device.kind)) do
    out[#out + 1] = p
  end
  for _, p in ipairs(M.factory_presets(device)) do
    p.factory = true
    out[#out + 1] = p
  end
  return out
end

--- Save the device as it is now as a user preset. Returns the file's path.
function M.save(device, name)
  device = as_device(device)
  name = preset_name(name)
  local snap = device:snapshot()
  local path = kind_dir(snap.kind) .. "/" .. safe(name) .. ".json"
  local d = device:get()
  write_json(path, {
    version = 1,
    name = name,
    kind = snap.kind,
    state = snap.state,
    -- Every value, so the preset says what it sounds like even without the state.
    params = d.params,
    -- What the project set over the plugin's state, applied over it again.
    overrides = snap.state and d.overrides or nil,
  })
  -- What the device holds now is that preset.
  local meta = device:get().meta
  meta = type(meta) == "table" and meta or {}
  meta.preset = name
  api.device_set(device.id, "meta", meta)
  return path
end

--- Delete a preset of a kind of device, by name.
function M.delete(kind, name)
  local path = kind_dir(kind) .. "/" .. safe(preset_name(name)) .. ".json"
  local ok, err = os.remove(path)
  if not ok then error(err, 2) end
  if M.default_preset(kind) == name then M.set_default(kind, nil) end
end

--- Find a preset of the device by name, or take the one given.
local function find(device, preset)
  if type(preset) == "table" then return preset end
  for _, p in ipairs(M.presets(device)) do
    if p.name == preset then return p end
  end
  local wanted = tostring(preset):lower()
  for _, p in ipairs(M.presets(device)) do
    if p.name:lower():find(wanted, 1, true) then return p end
  end
end

--- Load a preset into the device by name (the user's first), or one from
--- `paw.fx.presets(device)`. One undo step.
function M.load(device, preset)
  device = as_device(device)
  local p = find(device, preset)
  if not p then error("no preset `" .. tostring(preset) .. "` for " .. device:get().name, 2) end
  local d = device:get()
  if p.user then
    local data = read_json(p.path)
    if not data then error("cannot read " .. p.path, 2) end
    -- A plugin's state says everything; its values are only for a device without one.
    api.device_load(
      d.id,
      { name = p.name, state = data.state, params = data.state and (data.overrides or {}) or data.params or {} }
    )
  elseif p.params then
    -- A built-in device's preset sets what it names; the rest stay where they are.
    local by_key, params = {}, {}
    for _, info in ipairs(d.param_info) do
      by_key[info.key] = info
    end
    for key, value in pairs(type(d.overrides) == "table" and d.overrides or {}) do
      params[key] = value
    end
    for key, value in pairs(p.params) do
      local info = by_key[key]
        or error("preset `" .. p.name .. "` sets `" .. key .. "`, which " .. d.kind .. " does not have", 2)
      params[key] = paw.params.preset_value(info, value)
    end
    api.device_load(d.id, { name = p.name, params = params })
  else
    api.device_load(d.id, { name = p.name, factory = p.id })
  end
  api.undo_label("preset " .. p.name)
  paw.emit("preset.loaded", { id = d.id, name = p.name })
  return p
end

--- The name of the preset the device was last set to, if any.
function M.current(device)
  device = as_device(device)
  local meta = device:get().meta
  return type(meta) == "table" and meta.preset or nil
end

--- Load the next (`step` 1) or previous (-1) preset of the device's list.
function M.step(device, step)
  device = as_device(device)
  local list = M.presets(device)
  if #list == 0 then error(device:get().name .. " has no presets", 2) end
  local now = M.current(device)
  local at = 0
  for i, p in ipairs(list) do
    if p.name == now then at = i end
  end
  local index = at == 0 and (step > 0 and 1 or #list) or ((at - 1 + step) % #list) + 1
  return M.load(device, list[index])
end

local function defaults_path() return M.presets_dir() .. "/defaults.json" end

--- The preset new instances of a kind start from, if the user marked one.
function M.default_preset(kind)
  local all = read_json(defaults_path())
  return type(all) == "table" and all[kind] or nil
end

--- Mark the preset that new instances of `kind` start from, or none.
function M.set_default(kind, name)
  local all = read_json(defaults_path())
  all = type(all) == "table" and all or {}
  all[kind] = name
  write_json(defaults_path(), all)
end

-- Finding a device among hundreds ------------------------------------------------------
--
-- Favourites, the devices used last, and what was chosen for what was typed
-- are kept in `<state dir>/devices.json`. Typed words starting with `@`
-- filter: `@instrument` `@effect`, `@clap` `@lv2` `@vst3` `@builtin`, `@fav`,
-- or the start of a vendor's name (`@surge`).

local library

local function library_path() return api.env().state_dir .. "/devices.json" end

--- What is kept about kinds of device across sessions (`favourites`), read once.
function M.library()
  if not library then
    local data = read_json(library_path())
    library = type(data) == "table" and data or {}
    library.favourites = type(library.favourites) == "table" and library.favourites or {}
    library.recent = type(library.recent) == "table" and library.recent or {}
    library.picks = type(library.picks) == "table" and library.picks or {}
  end
  return library
end

local function save_library() write_json(library_path(), M.library()) end

--- Forget what was read, for tests that change the file underneath.
function M.reload_library() library = nil end

--- True if a kind of device is a favorite.
function M.is_favourite(kind) return M.library().favourites[kind] == true end

--- Make a kind of device a favorite, or not. Returns true if it is a favorite now.
function M.toggle_favourite(kind)
  local fav = M.library().favourites
  fav[kind] = not fav[kind] or nil
  save_library()
  return fav[kind] == true
end

--- Note that a device was chosen, after `query` was typed if anything.
function M.note_used(kind, query)
  local lib = M.library()
  local recent = { kind }
  for _, k in ipairs(lib.recent) do
    if k ~= kind and #recent < 20 then recent[#recent + 1] = k end
  end
  lib.recent = recent
  query = query and query:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if query and query ~= "" then lib.picks[query] = kind end
  save_library()
end

--- Every device that can be added: favourites first, then the ones used
--- last, newest first, then the rest (the kind `wanted` first, see
--- `preferred`; built-in ones first, by name).
function M.device_list(wanted)
  local lib = M.library()
  local recency = {}
  for i, kind in ipairs(lib.recent) do
    recency[kind] = i
  end
  local out = paw.device_types()
  for _, info in ipairs(out) do
    info.favourite = lib.favourites[info.kind] == true
    info.recent = recency[info.kind]
  end
  local function group(info) return info.favourite and 0 or info.recent and 1 or 2 end
  table.sort(out, function(a, b)
    if group(a) ~= group(b) then return group(a) < group(b) end
    if a.recent and b.recent and a.recent ~= b.recent then return a.recent < b.recent end
    if wanted and group(a) == 2 and (a.category == wanted) ~= (b.category == wanted) then
      return a.category == wanted
    end
    if (a.format == "builtin") ~= (b.format == "builtin") then return a.format == "builtin" end
    return a.name:lower() < b.name:lower()
  end)
  return out
end

--- The line that lists a device: a star for a favorite, then its name and
--- vendor. Then the extension that it came with, if any, its format, and
--- if it is an instrument or an effect.
function M.device_line(info)
  return string.format(
    "%s %-28s %-14s %s%s %s",
    info.favourite and "★" or " ",
    info.name,
    info.vendor ~= "" and info.vendor or "—",
    info.from and ("[" .. info.from .. "] ") or "",
    info.format,
    info.category
  )
end

--- Whether a device passes one `@` filter word.
local function passes(info, tag)
  if tag == "" then return true end
  local function starts(text) return text ~= nil and text:lower():sub(1, #tag) == tag end
  if tag == "fav" or tag == "favourite" or tag == "favorite" then return info.favourite end
  if starts(info.format) or starts(info.category) or starts(info.from) then return true end
  if tag == "instr" or tag == "inst" then return info.category == "instrument" end
  if tag == "fx" then return info.category == "effect" end
  for word in (info.vendor or ""):gmatch("%S+") do
    if starts(word) then return true end
  end
  return false
end

--- The kind of device that a part probably needs next. "instrument" is
--- for a part that makes sound from MIDI and has no instrument yet.
--- "effect" is for the other parts (a part with an instrument, the
--- master, a part of audio).
function M.preferred(part_id)
  if not part_id or part_id == 0 then return "effect" end
  local part = paw.part(part_id)
  if not part then return "effect" end
  local category = {}
  for _, info in ipairs(paw.device_types()) do
    category[info.kind] = info.category
  end
  for _, device in ipairs(part:devices()) do
    if category[device:get().kind] == "instrument" then return "effect" end
  end
  for _, clip in ipairs(api.clip_list(part_id)) do
    if clip.kind ~= "midi" then return "effect" end
  end
  return "instrument"
end

--- How well a device matches the typed text, or nil when it does not match.
--- The `@` words filter. The other words must match the whole line. A match
--- in the name alone counts for more than a match that needs the vendor.
--- The device selected last time for the same words comes first. A device
--- of the category `wanted` (see `preferred`) comes before the others.
function M.rank(info, query, line, wanted)
  local words = {}
  for word in query:gmatch("%S+") do
    local tag = word:match("^@(.*)$")
    if tag then
      if not passes(info, tag:lower()) then return nil end
    else
      words[#words + 1] = word
    end
  end
  local rest = table.concat(words, " ")
  local score = 0
  if rest ~= "" then
    score = paw.pick.match(rest, line or M.device_line(info), false)
    if not score then return nil end
    local in_name = paw.pick.match(rest, info.name, false)
    if in_name then score = score + 1000 + in_name end
    -- The whole name, or its start, typed: that one first.
    local name, typed = info.name:lower(), rest:lower()
    if name == typed then
      score = score + 5000
    elseif name:sub(1, #typed) == typed then
      score = score + 2000
    end
  end
  if info.favourite then score = score + 10 end
  if wanted and info.category == wanted then score = score + 5 end
  local q = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if q ~= "" and M.library().picks[q] == info.kind then score = score + 100000 end
  return score
end

--- The devices that match `query`, best first, at most `limit`. The "Add a
--- device" box of the window shows this list.
function M.search(query, limit, wanted)
  local out = {}
  for _, info in ipairs(M.device_list(wanted)) do
    local score = M.rank(info, query or "", nil, wanted)
    if score then out[#out + 1] = { info = info, score = score } end
  end
  if query and query:match("%S") then
    table.sort(out, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      return #a.info.name < #b.info.name
    end)
  end
  local list = {}
  for i = 1, math.min(limit or 40, #out) do
    list[i] = out[i].info
  end
  return list
end

-- Commands, keys, the picker ---------------------------------------------------------

local function clean(err) return (tostring(err):gsub("^[^:]*:%d+: ", ""):match("^[^\n]*")) end

--- The device the preset commands act on: the one selected in the device
--- panel (its row stays where it was when another view has the keys).
function M.target()
  local device = paw.ui.views:get("devices"):selected()
  if not device then paw.notify("no device here: add one with `a` in the device panel", "warn") end
  return device
end

--- A line of the preset picker.
local function preset_line(p, current, default)
  local mark = p.name == default and "★" or " "
  local now = p.name == current and "●" or " "
  local source = p.user and "user" or "factory"
  local category = p.category and p.category ~= "" and "  " .. p.category or ""
  return string.format("%s%s %-32s %s%s", now, mark, p.name, source, category)
end

--- Choose a preset of the device in a picker and load it.
function M.pick(device)
  device = as_device(device) or M.target()
  if not device then return end
  local d = device:get()
  local list = M.presets(device)
  local current, default = M.current(device), M.default_preset(d.kind)
  paw.pick({
    title = "Presets · " .. d.name,
    items = list,
    empty = "No presets for " .. d.name .. " yet. `:preset.save <name>` keeps how it is now.",
    format = function(p) return preset_line(p, current, default) end,
    on_choose = function(p)
      local ok, err = pcall(M.load, device, p)
      if not ok then return paw.notify(clean(err), "error") end
      paw.notify(d.name .. ": " .. p.name)
    end,
    -- Loaded as a trial and heard with what the part plays around the
    -- cursor; Escape puts the device back as it was.
    audition_key = "presets",
    audition = function(p)
      paw.audition.try(function() M.load(device, p) end)
      return {
        label = p.name .. " · " .. paw.audition.through(d.part),
        keep = function() paw.notify(d.name .. ": " .. p.name) end,
      }
    end,
    actions = {
      ["<C-s>"] = {
        desc = "default for new ones",
        fn = function(p)
          if not p then return end
          M.set_default(d.kind, p.name)
          paw.notify(p.name .. " is what new " .. d.name .. " devices start from")
        end,
      },
    },
    preview = function(p)
      local lines =
        { { text = p.name, style = "Title" }, "", p.user and ("user preset  " .. p.path) or "factory preset" }
      if p.category and p.category ~= "" then lines[#lines + 1] = "in " .. p.category end
      if p.name == default then lines[#lines + 1] = "new " .. d.name .. " devices start from it" end
      return lines
    end,
  })
end

--- Define the commands for devices. The runtime calls this once at start.
function M.setup()
  local command = paw.command
  local function with_device(fn)
    return function(ctx)
      local device = M.target()
      if not device then return end
      local ok, err = pcall(fn, device, ctx)
      if not ok then paw.notify(clean(err), "error") end
    end
  end
  command(
    "preset",
    with_device(function(device, ctx)
      local name = ctx.args[1] and table.concat(ctx.args, " ")
      if not name then return M.pick(device) end
      local p = M.load(device, name)
      paw.notify(device:get().name .. ": " .. p.name)
    end),
    {
      desc = "Load a preset into the device: `preset Soft pad`; with no name, choose in a picker (yours first, then the factory's)",
    }
  )
  command(
    "preset.save",
    with_device(function(device, ctx)
      local function save(name)
        if not name or name == "" then return end
        local ok, path = pcall(M.save, device, name)
        if not ok then return paw.notify(clean(path), "error") end
        paw.notify("saved the preset “" .. name .. "” (" .. path .. ")")
      end
      if ctx.args[1] then return save(table.concat(ctx.args, " ")) end
      paw.ui.input({ prompt = "Preset name: ", text = M.current(device) or "" }, save)
    end),
    { desc = "Save the device as it is now as a preset of yours: `preset.save Warm`" }
  )
  command(
    "preset.next",
    with_device(function(device, ctx)
      local p = M.step(device, ctx.count or 1)
      paw.notify(device:get().name .. ": " .. p.name)
    end),
    { desc = "Load the device's next preset" }
  )
  command(
    "preset.prev",
    with_device(function(device, ctx)
      local p = M.step(device, -(ctx.count or 1))
      paw.notify(device:get().name .. ": " .. p.name)
    end),
    { desc = "Load the device's previous preset" }
  )
  command(
    "preset.default",
    with_device(function(device, ctx)
      local kind, name = device.kind, ctx.args[1] and table.concat(ctx.args, " ") or M.current(device)
      if name == "none" then
        M.set_default(kind, nil)
        return paw.notify("new " .. device:get().name .. " devices start as the plugin makes them")
      end
      if not name then
        -- Nothing loaded yet: keep the device as it is, and start from that.
        name = "Default"
        M.save(device, name)
      end
      M.set_default(kind, name)
      paw.notify("new " .. device:get().name .. " devices start from “" .. name .. "”")
    end),
    { desc = "New devices of this kind start from this preset (or the one named); `preset.default none` stops that" }
  )
  command(
    "preset.delete",
    with_device(function(device, ctx)
      local name = ctx.args[1] and table.concat(ctx.args, " ") or M.current(device)
      if not name then return paw.notify("usage: preset.delete <name>", "warn") end
      M.delete(device.kind, name)
      paw.notify("deleted the preset “" .. name .. "”")
    end),
    { desc = "Delete one of your presets of this device: `preset.delete Warm`" }
  )

  command(
    "param",
    with_device(function(device) M.pick_param(device) end),
    { desc = "Find a parameter of the device by name, and show it first on its card" }
  )
  command("param.last", function(ctx)
    local last = M.last_touched
    if not (last and pcall(api.device_get, last.device)) then
      return paw.notify("no parameter touched yet: move one in a plugin's window, or here", "warn")
    end
    local d = api.device_get(last.device)
    paw.cursor.set_part(d.part)
    paw.ui.focus("devices")
    M.focus_param(last.device, last.param)
    local what = ctx.args[1]
    if what == "automate" then
      paw.device(last.device):automate(last.param)
      paw.notify("automating " .. d.name .. " · " .. last.param)
    elseif what == "learn" and M.learn then
      M.learn(last.device, last.param)
    elseif what == "show" then
      M.show_param(last.device, last.param)
    end
  end, {
    desc = "Go to the parameter last touched; `param.last automate`, `param.last learn` or `param.last show` act on it",
  })

  local function dmap(lhs, rhs, desc) paw.keymap.set(lhs, rhs, { view = "devices", desc = desc }) end
  dmap("f", "param", "Find a parameter by name")
  dmap("t", "param.last", "The parameter last touched")

  --- A part by name, by its place in the list, or by id.
  local function part_named(text)
    local n = tonumber(text)
    local rows = paw.groups.rows()
    if n and rows[n] then return paw.part(rows[n]) end
    return paw.part(text)
  end
  local function to_part(copy)
    return function(ctx)
      local device = M.target()
      if not device then return end
      local name = table.concat(ctx.args, " ")
      local part = name ~= "" and part_named(name)
      if not part then
        return paw.notify("usage: device." .. (copy and "copy_to" or "move_to") .. " <part name or number>", "warn")
      end
      if copy then
        paw.restore_device(device:snapshot(), part)
      else
        device:move(#part:devices() + 1, part)
      end
      paw.notify(device:get().name .. (copy and " copied to " or " moved to ") .. part.name)
    end
  end
  command(
    "device.copy_to",
    to_part(true),
    { desc = "Copy the device, with its state, to the end of another part: `device.copy_to Bass`, `device.copy_to 3`" }
  )
  command(
    "device.move_to",
    to_part(false),
    { desc = "Move the device to the end of another part: `device.move_to Bass`" }
  )

  -- What the window's device card does: the same, for the device clicked.
  local A = paw.frontend.act
  --- A card dropped on a part's header: the device moves there, or with
  --- Ctrl a copy of it goes there.
  function A.drop_device(id, part, copy)
    local device = paw.device(id)
    local d = device:get()
    local target = paw.part(part)
    if copy then
      paw.restore_device(device:snapshot(), target)
    elseif d.part ~= part then
      device:move(#target:devices() + 1, target)
    end
  end
  --- A card dropped in the list: before the card at `index` (from 1; one
  --- past the end for last), or a copy there with Ctrl.
  function A.place_device(id, index, copy)
    local device = paw.device(id)
    local d = device:get()
    if copy then
      paw.restore_device(device:snapshot(), d.part, index)
    else
      device:move(d.index < index and index - 1 or index)
    end
  end
  local A = paw.frontend.act
  function A.preset_step(id, step)
    local ok, err = pcall(M.step, id, step)
    if not ok then paw.notify(clean(err), "warn") end
  end
  --- The names in the card's preset menu: the user's presets and those
  --- around the one loaded, at most `menu_size`, then "All presets…" when
  --- there are more (a plugin may have thousands).
  local menu_map = {}
  function A.preset_menu(id)
    local device = paw.device(id)
    local current, default = M.current(device), M.default_preset(device.kind)
    local list = M.presets(device)
    local at = 1
    for i, p in ipairs(list) do
      if p.name == current then at = i end
    end
    local first = math.max(1, math.min(at - math.floor(M.menu_size / 2), #list - M.menu_size + 1))
    local out = {}
    menu_map = {}
    for i, p in ipairs(list) do
      if p.user or (i >= first and i < first + M.menu_size) then
        out[#out + 1] = (p.name == current and "● " or "")
          .. p.name
          .. (p.user and "" or "  · factory")
          .. (p.name == default and "  ★" or "")
        menu_map[#out] = i
      end
    end
    if #out < #list then
      out[#out + 1] = "All " .. #list .. " presets…"
      menu_map[#out] = "all"
    end
    return out
  end
  function A.preset_choose(id, index)
    local at = menu_map[index] or index
    if at == "all" then
      M.select(id)
      return M.pick(id)
    end
    local p = M.presets(id)[at]
    if not p then return end
    local ok, err = pcall(M.load, id, p)
    if not ok then paw.notify(clean(err), "error") end
  end
  --- The window's "Add a device" box: the devices matching what is typed,
  --- each as the line to show and its kind.
  function A.search_devices(query)
    local out = {}
    for i, info in ipairs(M.search(query, 40, M.preferred(paw.cursor.part_id()))) do
      out[i] = {
        kind = info.kind,
        line = (info.favourite and "★ " or "")
          .. info.name
          .. (info.vendor ~= "" and "  · " .. info.vendor or "")
          .. "  · "
          .. info.format
          .. " "
          .. info.category,
      }
    end
    return out
  end
  function A.toggle_favourite(kind) return M.toggle_favourite(kind) end
  --- A preset command, on the device clicked: it is selected in the panel first.
  function A.device_command(id, line)
    M.select(id)
    paw.commands.exec(line)
  end
end

--- Put the device panel's row on a device of the cursor part.
function M.select(id)
  local panel = paw.ui.views:get("devices")
  for i, row in ipairs(panel:rows()) do
    if row.device.id == id and not row.param and not row.picture then panel.row = i end
  end
end

return M
