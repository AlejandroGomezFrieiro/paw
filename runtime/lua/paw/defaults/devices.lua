-- The default commands and keys: devices. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local command = paw.command
local cursor = paw.cursor
local common = require("paw.defaults.common")
local need_part = common.need_part

--- Device kinds whose kind or name contains `text`, built-in ones first.
local function device_kinds(text)
  local wanted, out = text:lower(), {}
  for _, info in ipairs(paw.device_types()) do
    if info.kind:lower():find(wanted, 1, true) or info.name:lower():find(wanted, 1, true) then out[#out + 1] = info end
  end
  table.sort(out, function(a, b)
    if (a.format == "builtin") ~= (b.format == "builtin") then return a.format == "builtin" end
    return a.kind < b.kind
  end)
  for i, info in ipairs(out) do
    out[i] = info.kind
  end
  return out
end

command("device.add", function(ctx)
  local part = need_part()
  if not part then return end
  local function add(text)
    if text == "" then return end
    -- An exact kind, or else the first device with `text` in its kind or name.
    local matches = device_kinds(text)
    local kind = matches[1]
    for _, match in ipairs(matches) do
      if match == text then kind = match end
    end
    if not kind then return paw.notify("no device matches `" .. text .. "`", "warn") end
    paw.fx.add(part, kind)
  end
  if ctx.args[1] then return add(table.concat(ctx.args, " ")) end
  paw.notify(#paw.device_types() .. " devices. Type part of a name and press Tab; `:devices` lists them all.")
  paw.ui.input({ prompt = "Add device: ", complete = device_kinds, history = "device" }, add)
end, { desc = "Add a device to the part: `device.add delay`, `device.add dragonfly hall`", complete = { "devices" } })
command("midi.inputs", function()
  local lines = {}
  for _, port in ipairs(paw.midi.inputs()) do
    lines[#lines + 1] = {
      text = string.format("%-8s %s %s", port.id, port.open and "open  " or "closed", port.name),
      style = port.open and "Normal" or "Dim",
    }
  end
  if #lines == 0 then lines[1] = "No MIDI input ports (they are only opened with an audio device)." end
  paw.ui.page("MIDI inputs", lines)
end, { desc = "List MIDI input ports" })
command("midi.select", function(ctx)
  local which = {}
  for _, arg in ipairs(ctx.args) do
    which[#which + 1] = tostring(arg)
  end
  if #which == 0 or which[1] == "all" then which = nil end
  paw.midi.select(which)
  paw.notify(which and "MIDI input from " .. table.concat(which, ", ") or "MIDI input from every port")
end, { desc = "Open only some MIDI ports by id or name, or all: `midi.select Keystation`, `midi.select all`" })
command("devices", function()
  local lines = {}
  for _, kind in ipairs(device_kinds("")) do
    lines[#lines + 1] = kind
  end
  paw.ui.page("Devices", lines)
end, { desc = "List every device that can be added" })
--- The device under the cursor of the devices view, or nil with a message
--- that says what the cursor is on and what the key `key` acts on.
local function device_here(key, what)
  local device = paw.ui.views:get("inspector"):selected()
  if device then return device end
  local place = paw.ui.views:get("inspector"):node()
  local on = place and ("; the cursor is on " .. place.node.name) or ""
  paw.notify("no device here: " .. key .. " " .. what .. on, "warn")
end

command("device.remove", function()
  local device = device_here("x", "removes a device")
  if device then device:remove() end
end, { desc = "Remove the device under the cursor of the devices view" })
command("device.restart", function()
  -- The device selected in the panel if it has stopped, else every device
  -- of the part that has.
  local chosen = (paw.ui.focused == "inspector" or paw.ui.focused == "devices")
      and paw.ui.views:get("inspector"):selected()
    or nil
  local part = need_part()
  local started, failed = 0, nil
  for _, device in ipairs(chosen and { chosen } or part and part:devices() or {}) do
    local d = device:get()
    if d.stopped or d.missing or chosen then
      local ok, err = pcall(device.restart, device)
      if ok then
        started = started + 1
      else
        failed = tostring(err):match("^[^\n]*")
      end
    end
  end
  if failed then return paw.notify(failed, "error") end
  paw.notify(
    started == 0 and "no device here has stopped"
      or started == 1 and "the device is running again"
      or started .. " devices are running again"
  )
end, { desc = "Start a plugin again that stopped working, with the state the project last had of it" })
command("device.bypass", function()
  local device = device_here("gcc", "bypasses a device")
  if device then device.bypass = not device.bypass end
end, { desc = "Bypass the device under the cursor of the devices view" })
command("device.editor", function()
  -- The device selected in the panel, else the part's first one with a window.
  local device = (paw.ui.focused == "inspector" or paw.ui.focused == "devices")
      and paw.ui.views:get("inspector"):selected()
    or paw.ui.focused == "mixer" and paw.mixer_rows.device()
    or nil
  if not (device and device.editor) then
    device = nil
    local part = need_part()
    for _, candidate in ipairs(part and part:devices() or {}) do
      if candidate.editor then
        device = candidate
        break
      end
    end
  end
  if not device then return paw.notify("no device with an editor window here", "warn") end
  api.device_editor(device.id)
end, { desc = "Show or hide the plugin's own window" })
command("device.set", function(ctx)
  local part = need_part()
  local device = part and part:device(ctx.args[1])
  if not device then return paw.notify("usage: device.set <kind> <param>=<value> ...", "warn") end
  for key, value in pairs(ctx.args) do
    if type(key) == "string" then device:set(key, value) end
  end
end, {
  desc = "Set parameters: `device.set synth cutoff=800 wave=2`",
  complete = function(_, info)
    if info.index == 1 then return paw.commands.completers:get("part_devices")() end
    local part = cursor.part()
    local device = part and part:device(info.words[1])
    local out = {}
    for _, p in ipairs(device and device:get().param_info or {}) do
      out[#out + 1] = { text = p.key .. "=", desc = p.name }
    end
    return out
  end,
})
