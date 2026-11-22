-- Virtual inputs: what they are, and where they are kept.
--
-- A virtual input is a chain that ends in a MIDI port of the program's own
-- (`paw.midi.open_port`), so a track takes it like any other MIDI port, by
-- its name. What feeds the port is its `kind`: a table in `kinds` that says
-- which stages the chain has, which settings each stage has, and how to run
-- the program that does the work. `kinds.gdi2m` turns a guitar into MIDI.
--
--   local vinput = require("vinput")
--   vinput.add({ name = "Guitar", source = "Input 2", gain = 1.2 })
--   vinput.set("Guitar", "threshold", 0.8)
--   track.midi_input = { port = "Guitar" }
--
-- The inputs belong to the machine, not to a project: they name audio ports
-- of this computer. They are kept in a file in the program's state
-- directory and are there again at the next start.
local api = paw.api
local util = paw.util

local M = {
  kinds = {}, -- by name: { title, stages, defaults(), argv(input), ... }
  inputs = {}, -- in the order they were made
}

--- The settings of a kind, in the order of its stages: each is
--- `{ key, name, type, min, max, step, default, unit, help, stage }`.
function M.settings(kind)
  local out = {}
  for _, stage in ipairs((M.kinds[kind] or {}).stages or {}) do
    for _, setting in ipairs(stage.settings or {}) do
      out[#out + 1] = util.merge(setting, { stage = stage.key })
    end
  end
  return out
end

function M.setting(kind, key)
  for _, setting in ipairs(M.settings(kind)) do
    if setting.key == key then return setting end
  end
end

function M.get(name)
  for index, input in ipairs(M.inputs) do
    if input.name == name then return input, index end
  end
end

--- A value as the setting takes it: a number within its range, a switch as
--- true or false, text trimmed. Nil and the reason when it cannot be.
function M.coerce(setting, value)
  if setting.type == "number" then
    local n = tonumber(value)
    if not n then return nil, setting.name .. " is a number" end
    n = util.clamp(n, setting.min, setting.max)
    if setting.whole then n = math.floor(n + 0.5) end
    return n
  elseif setting.type == "switch" then
    if value == "on" or value == "true" or value == "1" or value == "yes" then return true end
    if value == "off" or value == "false" or value == "0" or value == "no" then return false end
    return value and true or false
  end
  local text = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if setting.check then
    local ok, why = setting.check(text)
    if not ok then return nil, why end
  end
  return text
end

local function unique(name)
  if not M.get(name) then return name end
  local n = 2
  while M.get(name .. " " .. n) do
    n = n + 1
  end
  return name .. " " .. n
end

local function clean_name(name)
  -- The name is a MIDI port's, and part of a file's.
  local text = tostring(name or ""):gsub("[%c/\\:]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

-- Keeping them between runs ------------------------------------------------------

--- The file the inputs are kept in, or nil when they are not kept: a clean
--- start (`--clean`) neither reads nor writes the user's own, unless
--- `paw.opt.vinput_file` names a file.
function M.path()
  local file = paw.opt.vinput_file
  if file and file ~= "" then return file end
  local env = api.env()
  if env.clean then return nil end
  return env.state_dir .. "/vinput.json"
end

local made_dir, pending = {}, nil

--- Write the inputs to their file now.
function M.save()
  if pending then
    paw.cancel(pending)
    pending = nil
  end
  local path = M.path()
  if not path then return end
  local dir = path:match("^(.*)/[^/]*$")
  if dir and not made_dir[dir] then
    pcall(paw.api.fs_mkdir, dir)
    made_dir[dir] = true
  end
  local file = io.open(path, "w")
  if not file then return paw.notify("virtual inputs: cannot write " .. path, "warn") end
  file:write(paw.json.encode({ version = 1, inputs = M.inputs }, true), "\n")
  file:close()
end

--- A change was made: keep it (soon: a slider that is dragged changes many
--- times a second), let the trackers follow, draw again.
local function changed()
  if not pending then pending = paw.defer(function()
    pending = nil
    M.save()
  end, 300) end
  require("vinput.run").sync()
  api.ui_redraw()
  paw.emit("vinput.changed", {})
end

paw.on("exit", function()
  if pending then M.save() end
end)

--- Read the inputs kept from earlier runs and open their ports.
function M.load()
  local run = require("vinput.run")
  for _, input in ipairs(M.inputs) do
    paw.midi.close_port(input.name)
  end
  M.inputs = {}
  local path = M.path()
  local file = path and io.open(path, "r")
  if file then
    local data, why = paw.json.decode(file:read("*a"))
    file:close()
    if not data then
      paw.notify("virtual inputs: " .. path .. " is not readable: " .. tostring(why), "warn")
    else
      for _, saved in ipairs(type(data.inputs) == "table" and data.inputs or {}) do
        if
          type(saved) == "table"
          and M.kinds[saved.kind]
          and clean_name(saved.name) ~= ""
          and not M.get(saved.name)
        then
          local input = M.kinds[saved.kind].defaults()
          input.kind, input.name, input.on = saved.kind, clean_name(saved.name), saved.on ~= false
          for _, setting in ipairs(M.settings(saved.kind)) do
            if saved[setting.key] ~= nil then
              local value = M.coerce(setting, saved[setting.key])
              if value ~= nil then input[setting.key] = value end
            end
          end
          M.inputs[#M.inputs + 1] = input
          paw.midi.open_port(input.name)
        end
      end
    end
  end
  run.sync()
end

-- Making and changing ---------------------------------------------------------------

--- A new input: `spec.kind` ("gdi2m"), `spec.name`, and any of the kind's
--- settings. An input of that name that is there already is changed instead.
function M.add(spec)
  spec = spec or {}
  local kind = spec.kind or "gdi2m"
  local def = M.kinds[kind]
  if not def then error("no kind of virtual input `" .. tostring(kind) .. "`", 2) end
  local name = clean_name(spec.name)
  local input = name ~= "" and M.get(name)
  if not input then
    input = def.defaults()
    input.kind, input.on = kind, true
    input.name = unique(name ~= "" and name or def.name)
    M.inputs[#M.inputs + 1] = input
    paw.midi.open_port(input.name)
  end
  if spec.on ~= nil then input.on = spec.on and true or false end
  for _, setting in ipairs(M.settings(kind)) do
    if spec[setting.key] ~= nil then
      local value, why = M.coerce(setting, spec[setting.key])
      if value == nil then error(why, 2) end
      input[setting.key] = value
    end
  end
  changed()
  return input
end

--- Change one setting of an input; `name` renames it, `on` turns it on or
--- off. Tracks that take the input follow a new name.
function M.set(name, key, value)
  local input = M.get(name)
  if not input then error("no virtual input `" .. tostring(name) .. "`", 2) end
  if key == "on" then
    input.on = value and true or false
  elseif key == "name" then
    local new = clean_name(value)
    if new == "" then error("an input needs a name", 2) end
    if new ~= input.name then
      if M.get(new) then error("there is an input `" .. new .. "` already", 2) end
      local old = input.name
      require("vinput.run").stop(old)
      paw.midi.close_port(old)
      input.name = new
      paw.midi.open_port(new)
      for _, id in ipairs(api.track_list()) do
        local midi = api.track_get(id, "midi_input")
        if midi and midi.port == old then api.track_set(id, "midi_input", { port = new, channel = midi.channel }) end
      end
    end
  else
    local setting = M.setting(input.kind, key)
    if not setting then error("a " .. input.kind .. " input has no setting `" .. tostring(key) .. "`", 2) end
    local coerced, why = M.coerce(setting, value)
    if coerced == nil then error(why, 2) end
    input[key] = coerced
  end
  changed()
  return input
end

--- Move a number setting by `steps` of its step; a switch is flipped.
function M.nudge(name, key, steps)
  local input = M.get(name)
  local setting = input and M.setting(input.kind, key)
  if not setting then return end
  if setting.type == "switch" then return M.set(name, key, not input[key]) end
  if setting.type ~= "number" then return end
  return M.set(name, key, util.round(input[key] + steps * setting.step, setting.step))
end

function M.remove(name)
  local input, index = M.get(name)
  if not input then return false end
  require("vinput.run").stop(name)
  paw.midi.close_port(name)
  table.remove(M.inputs, index)
  changed()
  return true
end

--- A track that takes the input and plays it: an instrument, the input
--- chosen, and monitoring on by being armed.
function M.make_track(name, instrument)
  local input = M.get(name)
  if not input then error("no virtual input `" .. tostring(name) .. "`", 2) end
  local track = paw.add_track({ name = input.name, index = paw.cursor.index() and paw.cursor.index() + 1 or nil })
  track:add_device(instrument or "synth")
  track.midi_input = { port = input.name }
  track.armed = true
  paw.cursor.set_track(track.id)
  return track
end

--- What an input is doing: `{ state, text, level, notes, load, advice }`.
function M.status(name) return require("vinput.run").status(name) end

--- A setting's value in words.
function M.format(setting, value)
  if setting.format then return setting.format(value) end
  if setting.type == "switch" then return value and "on" or "off" end
  if setting.type == "number" then
    local text = setting.whole and string.format("%d", value)
      or string.format("%." .. (setting.digits or 2) .. "f", value)
    return setting.unit and (text .. " " .. setting.unit) or text
  end
  return value == "" and (setting.empty or "none") or tostring(value)
end

package.loaded["vinput"] = M
return M
