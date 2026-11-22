-- `paw.step`: step input from a MIDI controller. A view that takes step
-- input registers a target (`paw.step.target`). paw hears the controller,
-- keeps the keys that are held, and tells the target that listens now of
-- each key and of the release of the last one. The piano roll's target is
-- in paw/roll_draw.tl (`I`); notation and the vocal editor bring their own.
--
-- Step input listens to the MIDI input of the target's track (its port
-- and channel), else to every port, as recording does. Nothing is
-- recorded, and nothing enters while the transport plays: the keys only
-- sound then. While a target listens, its track plays the controller.
--
--   paw.step.target("myview", { active = ..., track = ..., note = function(e) end, release = function() end })
--   paw.step.active()   -- the name of the target that listens now, or nil
--   paw.step.input(id)  -- what step input listens to for a track, or nil and why not
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local commands = require("paw.commands")
local options = require("paw.options")
local seats = require("paw.seats")
local music = require("paw.music")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type CursorModule = require("paw.cursor")

--- The part of `paw.audio` (paw/audio.lua) that step input calls.
local record Audio
  pick: function(track: integer, groups?: {string})
end

local record Paw is partial.Paw
  audio: Audio
  cursor: CursorModule
end
local paw = (_G as {string: Paw}).paw

--- What step input listens to: the port (nil for every port) and the
--- channel (nil for every channel) of the MIDI input of `track`.
local record Listen
  track: integer
  port: string
  channel: integer
end

local record M
  type Listen = Listen
end

-- The velocity of the notes that step input enters: "key", the velocity of
-- the key played, or a number from 1 to 127 for all of them.
local step_velocity = options.define(
  "step_velocity",
  "key" as integer | string,
  {type = {"number", "string"}, min = 1, max = 127, integer = true, values = {"key"}}
)

local record Entry
  name: string
  spec: contracts.StepTarget
end
local targets: {Entry} = {}
-- The pitches held now, and the order they came in.
local held: {integer: boolean} = {}
local order: {integer} = {}
-- The track that plays the controller for step input, nil when none listens
-- (`api.engine_follow_always`).
local sounding: integer

--- Let a view take step input: `spec` as `paw.contracts.StepTarget` says.
--- The first target whose `active()` is true listens. A second call with
--- the same name replaces the target.
function M.target(name: string, spec: contracts.StepTarget)
  for _, e in ipairs(targets) do
    if e.name == name then
      e.spec = spec
      return
    end
  end
  targets[#targets + 1] = {name = name, spec = spec}
end

--- Remove the target of a view (its extension unloaded).
function M.untarget(name: string)
  for i, e in ipairs(targets) do
    if e.name == name then
      table.remove(targets, i)
      return
    end
  end
end

local function current(): string, contracts.StepTarget
  for _, e in ipairs(targets) do
    if e.spec.active() then
      return e.name, e.spec
    end
  end
end

--- The name of the target that listens now, or nil.
function M.active(): string
  return (current())
end

--- The pitches held now on the controller, in the order they were played.
function M.held(): {integer}
  local out: {integer} = {}
  for _, p in ipairs(order) do
    if held[p] then
      out[#out + 1] = p
    end
  end
  return out
end

--- Why the keys only sound now: "playing" or "recording", or nil.
function M.paused(): string
  local t = api.transport_get()
  if t.playing then
    return t.recording and "recording" or "playing"
  end
  return nil
end

--- What step input listens to for `track`: its MIDI input's port and
--- channel, or every port. Nil and why not when paw hears no MIDI: no port
--- is listed or open, or the track's port is not connected.
function M.input(track: integer): Listen, string
  local midi: types.MidiInput = track and api.track_get(track).midi_input or nil
  local listen: Listen = {track = track, port = midi and midi.port, channel = midi and midi.channel}
  local ports = api.midi_inputs()
  if #ports == 0 then
    if api.engine_get().backend == "null" then
      return nil, "no MIDI port is open: the engine runs without an audio device"
    end
    return nil, "no MIDI port is connected"
  end
  local open = false
  for _, p in ipairs(ports) do
    if listen.port and p.name == listen.port then
      if not p.open then
        return nil, "the track's port " .. listen.port .. " is not open"
      end
      return listen
    end
    open = open or p.open
  end
  if listen.port then
    return nil, "the track's port " .. listen.port .. " is missing"
  end
  if not open then
    return nil, "no MIDI port is open"
  end
  return listen
end

--- The port that step input listens to for `track`, in a few words:
--- `"Keystation 49"`, `"Keystation 49 · ch 2"`, `"all ports"`, or nil with no input.
function M.source(track: integer): string
  local listen = M.input(track)
  if not listen then
    return nil
  end
  local port = listen.port or "all ports"
  return listen.channel and (port .. " · ch " .. listen.channel) or port
end

--- Say that step input has no MIDI input for `track`, and why, and open
--- the MIDI part of the track's list of inputs. True if it had to.
function M.ask_input(track: integer): boolean
  local listen, why = M.input(track)
  if listen then
    return false
  end
  paw.notify(
    "step input: no MIDI input ("
      .. why
      .. "). Connect a keyboard, or choose one: :track.midi (I on the track lists the inputs)",
    "warn"
  )
  if track then
    paw.audio.pick(track, {"midi", "channel"})
  end
  return true
end

--- Look again at which target listens: its track plays the controller,
--- and with none the held keys are forgotten. A target calls it when it
--- starts or stops listening.
function M.refresh()
  local _, t = current()
  local track = t and t.track and t.track() or nil
  if not t then
    held, order = {}, {}
  end
  if track ~= sounding and seats.current == 0 then
    sounding = track
    -- That track plays the controller, also while another track is armed
    -- (and in place of the selected track while it is set).
    api.engine_follow_always(track)
  end
end

local function release_all(t: contracts.StepTarget)
  local any = next(held) ~= nil
  held, order = {}, {}
  if any and t then
    t.release()
  end
end

--- A key from the controller: for the target that listens now, if it came
--- from the input of its track and the transport is stopped.
local function heard(e: types.MidiEvent)
  -- A control that a filter maps (`api.engine_midi_filter`) enters nothing.
  if e.type ~= "note_on" and e.type ~= "note_off" or not e.pitch or e.filtered then
    return
  end
  local _, t = current()
  if not t then
    held, order = {}, {}
    return
  end
  local track = t.track and t.track() or nil
  local midi: types.MidiInput = track and api.track_get(track).midi_input or nil
  if midi and midi.port and e.port ~= midi.port then
    return
  end
  if midi and midi.channel and e.channel ~= midi.channel then
    return
  end
  if M.paused() then
    held, order = {}, {}
    return
  end
  if e.type == "note_on" and (e.velocity or 0) > 0 then
    local chord = next(held) ~= nil
    held[e.pitch] = true
    order[#order + 1] = e.pitch
    local fixed = step_velocity:get()
    local velocity = fixed is integer and fixed or math.floor((e.velocity or 0) + 0.5)
    t.note(
      {
        pitch = e.pitch,
        velocity = math.max(1, math.min(127, velocity)),
        attr = e.attr,
        channel = e.channel,
        port = e.port,
        chord = chord,
      }
    )
  elseif held[e.pitch] then
    held[e.pitch] = nil
    if next(held) == nil then
      order = {}
      t.release()
    end
  end
  api.ui_redraw()
end
events.on(kernel.midi_in, heard)

-- A port that goes away lets go of the keys held on it: the chord is closed.
events.on(kernel.midi_lost, function(_: kernel.MidiPort) local _, t = current(); release_all(t) end)

--- The velocity of the notes entered, in words: "key", or a number.
function M.velocity(): string
  return tostring(step_velocity:get())
end

--- The pitches held, in words: "C4 E4".
function M.held_text(): string
  local names: {string} = {}
  for i, p in ipairs(M.held()) do
    names[i] = music.name(p)
  end
  return table.concat(names, " ")
end

local type Context = commands.Context
local type Result = commands.Result
commands.define(
  "step.input",
  function(_: Context): Result
    local _, t = current()
    local track = t and t.track and t.track() or paw.cursor.track_id()
    if track == 0 then
      track = nil
    end
    if M.ask_input(track) then
      return
    end
    local name = track and api.track_get(track).name or "no track"
    paw.notify("step input listens to " .. M.source(track) .. " (the MIDI input of " .. name .. ")")
    if track then
      paw.audio.pick(track, {"midi", "channel"})
    end
  end,
  {desc = "Say what step input listens to: the MIDI input of the track of the active clip, and open its list"}
)

return M
