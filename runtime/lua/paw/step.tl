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
-- The controls of the controller: a key, pad or pedal does an action of
-- the target (a rest, a tie, a note value) in place of a key of the
-- computer. They are the user's, not the song's: `:step.learn` keeps them
-- in `state_dir/step-controls.json`, and `paw.step.bind` in init.lua keeps
-- them for the session. While a target listens, a mapped control enters
-- no note, does not sound and does not record (`api.engine_midi_filter`).
--
--   paw.step.bind({ port = "nanoPAD", note = 36 }, "rest")
--   paw.step.bind({ cc = 64 }, { down = "rest", held = "tie" })   -- the default of the pedal
--   paw.step.bind({ port = "Keystation", note = 23 }, { keys = "=8t" })
--   paw.step.unbind({ cc = 64 }); paw.step.bindings()
--   paw.step.action("accent", function(count) end)                -- a new action
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
local type KeymapModule = require("paw.keymap")
local type CursorModule = require("paw.cursor")
local type UiModule = require("paw.ui")
local type PickModule = require("paw.pick")

--- The part of `paw.audio` (paw/audio.lua) that step input calls.
local record Audio
  pick: function(track: integer, groups?: {string})
end

local record Paw is partial.Paw
  keymap: KeymapModule
  audio: Audio
  cursor: CursorModule
  ui: UiModule
  pick: PickModule
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
  --- Where the controls are kept: `state_dir/step-controls.json`; nil
  --- with --clean (`M.use`).
  file: string
  --- The action that `:step.learn` waits to bind, or nil.
  learning: string
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

-- Controls of the controller --------------------------------------------------

local type Source = contracts.StepSource
local type Binding = contracts.StepBinding
local type Action = contracts.StepAction

-- The actions of a target, in the order `Tab` gives them.
local BUILTIN: {string} = {
  "rest",
  "tie",
  "back",
  "erase",
  "again",
  "legato",
  "dur.1",
  "dur.2",
  "dur.4",
  "dur.8",
  "dur.16",
  "dur.32",
  "dot",
  "triplet",
  "octave.up",
  "octave.down",
  "chord",
  "finish",
}
-- The actions that extensions added (`M.action`), for any target.
local extra: {string: Action} = {}
local bindings: {Binding} = {}
-- The controls pressed now, by `key_of` their source: the action each did.
local pressed: {string: string} = {}
-- The `chord` control is held: the keys join one chord across releases.
local chording = false
-- The engine keeps the controls from the tracks (`filter`).
local filtering = false
-- What a control did last, for the title, and until when.
local said: string
local said_until = 0.0

local env = api.env()
local function default_file(): string
  return not env.clean and (env.state_dir .. "/step-controls.json") or nil
end
M.file = default_file()

local function key_of(s: Source): string
  local what = s.note and ("note " .. s.note) or ("cc " .. tostring(s.cc))
  return (s.port or "") .. "|" .. tostring(s.channel or "") .. "|" .. what
end

local function known(name: string): boolean
  if extra[name] then
    return true
  end
  for _, b in ipairs(BUILTIN) do
    if b == name then
      return true
    end
  end
  return false
end

--- Every action that a control can do: the core's, then the actions of
--- extensions (`M.action`).
function M.actions(): {string}
  local out: {string} = {}
  for i, name in ipairs(BUILTIN) do
    out[i] = name
  end
  local added: {string} = {}
  for name in pairs(extra) do
    added[#added + 1] = name
  end
  table.sort(added)
  for _, name in ipairs(added) do
    out[#out + 1] = name
  end
  return out
end

--- A control in words: "Test Pads C2 (note 36)", "cc 64 (pedal)".
function M.source_text(s: contracts.StepSource): string
  local parts: {string} = {}
  if s.port then
    parts[#parts + 1] = s.port
  end
  if s.channel then
    parts[#parts + 1] = "ch " .. s.channel
  end
  if s.note then
    parts[#parts + 1] = music.name(s.note) .. " (note " .. s.note .. ")"
  else
    parts[#parts + 1] = "cc " .. tostring(s.cc) .. (s.cc == 64 and " (pedal)" or "")
  end
  return table.concat(parts, " ")
end

--- What a control does, in words: "rest", "keys =8t", "rest, tie while
--- keys are held".
function M.action_text(b: contracts.StepBinding): string
  if b.keys then
    return "keys " .. b.keys
  elseif b.action then
    return b.action
  end
  return (b.down or "nothing") .. ", " .. (b.held or "nothing") .. " while keys are held"
end

local function check_byte(v: integer, what: string, low: integer, top: integer)
  if v ~= nil and (math.type(v) ~= "integer" or v < low or v > top) then
    error("paw.step.bind: " .. what .. " is " .. low .. " to " .. top, 4)
  end
end

local function valid_source(s: Source): Source
  if type(s) ~= "table" or (s.note == nil) == (s.cc == nil) then
    error("paw.step.bind: a control is { note = N } or { cc = N }, with a port and a channel if you like", 3)
  end
  check_byte(s.note, "note", 0, 127)
  check_byte(s.cc, "cc", 0, 127)
  check_byte(s.channel, "channel", 1, 16)
  return {port = s.port, channel = s.channel, note = s.note, cc = s.cc}
end

local function check_action(name: string)
  if name ~= nil and not known(name) then
    error("paw.step.bind: no action " .. tostring(name) .. " (paw.step.actions() lists them)", 4)
  end
end

-- While a target listens, the engine keeps the controls from the tracks:
-- they do not sound and do not record. With none listening, the tracks
-- get them again.
local function filter(on: boolean)
  if seats.current ~= 0 then
    return
  end
  if on and #bindings > 0 then
    local rules: {types.MidiFilterRule} = {}
    for i, b in ipairs(bindings) do
      local s = b.source
      rules[i] = {port = s.port, channel = s.channel, note = s.note, cc = s.cc}
    end
    api.engine_midi_filter("step", rules)
    filtering = true
  elseif filtering then
    api.engine_midi_filter("step", nil)
    filtering = false
  end
end

local function add(source: Source, action: string | contracts.StepDo, saved: boolean): Binding
  local s = valid_source(source)
  local b: Binding = {source = s, saved = saved}
  if action is string then
    check_action(action)
    b.action = action
  elseif type(action) == "table" and (action.keys or action.down or action.held) then
    check_action(action.down)
    check_action(action.held)
    b.keys, b.down, b.held = action.keys, action.down, action.held
  else
    error('paw.step.bind: an action is a name, { keys = "=8" } or { down = "rest", held = "tie" }', 3)
  end
  local key = key_of(s)
  for i, other in ipairs(bindings) do
    if key_of(other.source) == key then
      bindings[i] = b
      return b
    end
  end
  bindings[#bindings + 1] = b
  return b
end

local function remove(source: Source): boolean
  local key = key_of(source)
  for i, b in ipairs(bindings) do
    if key_of(b.source) == key then
      table.remove(bindings, i)
      pressed[key] = nil
      return true
    end
  end
  return false
end

-- The file of the controls keeps what `:step.learn` bound, and the default
-- of the pedal while the user keeps it.
local record Saved
  port: string
  channel: integer
  note: integer
  cc: integer
  action: string
  keys: string
  down: string
  held: string
end
local record SavedFile
  bindings: {Saved}
end

local function write()
  if not M.file then
    return
  end
  local list: {Saved} = {}
  for _, b in ipairs(bindings) do
    if b.saved then
      local s = b.source
      list[#list + 1] = {
        port = s.port,
        channel = s.channel,
        note = s.note,
        cc = s.cc,
        action = b.action,
        keys = b.keys,
        down = b.down,
        held = b.held,
      }
    end
  end
  local data: SavedFile = {bindings = list}
  pcall(api.fs_mkdir, M.file:match("^(.*)/[^/]*$") or ".")
  local handle = io.open(M.file .. ".tmp", "wb")
  if not handle then
    return paw.notify("step controls: cannot write " .. M.file, "warn")
  end
  handle:write(api.json_encode(data, true))
  handle:close()
  os.rename(M.file .. ".tmp", M.file)
end

local function read(): {Saved}
  local handle = M.file and io.open(M.file, "rb")
  if not handle then
    return nil
  end
  local text = handle:read("*a")
  handle:close()
  local ok, data = pcall(api.json_decode, text) as (boolean, SavedFile)
  if not ok or type(data) ~= "table" or type(data.bindings) ~= "table" then
    paw.notify("step controls: " .. M.file .. " is not a list of controls, so paw uses the default", "warn")
    return nil
  end
  return data.bindings
end

--- Read the file of the controls again: what it keeps replaces what it
--- kept before. With no file, the default of the pedal. The controls from
--- Lua (`M.bind`) stay as they are.
function M.load()
  local from_lua: {string: boolean} = {}
  local kept: {Binding} = {}
  for _, b in ipairs(bindings) do
    if not b.saved then
      kept[#kept + 1] = b
      from_lua[key_of(b.source)] = true
    end
  end
  bindings = kept
  local list = read()
  if not list then
    if not from_lua[key_of({cc = 64})] then
      add({cc = 64}, {down = "rest", held = "tie"}, true)
    end
  else
    for _, e in ipairs(list) do
      if type(e) == "table" then
        local source: Source = {port = e.port, channel = e.channel, note = e.note, cc = e.cc}
        local what: string | contracts.StepDo = e.action or {keys = e.keys, down = e.down, held = e.held}
        local ok, err = pcall(add, source, what, true) as (boolean, string)
        if not ok then
          paw.notify("step controls: " .. tostring(err), "warn")
        end
      end
    end
  end
  filter(filtering)
end

--- Keep the controls in `file`, for tests; with no file, where paw keeps
--- them (nowhere with --clean). Then read them from there.
function M.use(file?: string)
  M.file = file or default_file()
  M.load()
end

--- Let a control of the controller do an action while a target listens.
--- `source` is `{ port, channel, note | cc }`; `port` and `channel` may be
--- left out. `action` is a name (`paw.step.actions()`), `{ keys = "=8t" }`
--- (types those keys in the view), or `{ down = "rest", held = "tie" }`
--- (the first with no key held, the second while keys are held). It
--- replaces the control of the same source, for this session:
--- `:step.learn` keeps a control in the file.
function M.bind(source: contracts.StepSource, action: string | contracts.StepDo)
  add(source, action, false)
  filter(filtering)
end

--- Take away the control of `source`: `paw.step.unbind({ cc = 64 })` lets
--- the pedal sustain again. True if there was one.
function M.unbind(source: contracts.StepSource): boolean
  local gone = remove(valid_source(source))
  filter(filtering)
  return gone
end

--- The controls, each `{ source, action, keys, down, held, saved }`.
function M.bindings(): {contracts.StepBinding}
  local out: {Binding} = {}
  for i, b in ipairs(bindings) do
    local s = b.source
    out[i] = {
      source = {port = s.port, channel = s.channel, note = s.note, cc = s.cc},
      action = b.action,
      keys = b.keys,
      down = b.down,
      held = b.held,
      saved = b.saved,
    }
  end
  return out
end

--- A new action for the controls: `fn(count)` runs in a target that has
--- no action of that name itself.
---   paw.step.action("accent", function(count) ... end)
function M.action(name: string, fn: contracts.StepAction)
  if type(name) ~= "string" or type(fn) ~= "function" then
    error("usage: paw.step.action(name, function(count) end)", 2)
  end
  extra[name] = fn
end

--- What a control did a moment ago ("rest", "back"), for the title; nil
--- after a moment.
function M.said(): string
  if said and api.now() < said_until then
    return said
  end
  return nil
end

local function say(text: string)
  said, said_until = text, api.now() + 1500
  paw.defer(function() api.ui_redraw() end, 1600)
end

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
    held, order, chording, pressed = {}, {}, false, {}
  end
  filter(t ~= nil)
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

-- True when a control is pressed (a key or pad, a controller at half or
-- more), false when it is let go, nil when the event is not a control.
local function down_of(e: types.MidiEvent): boolean
  if e.type == "note_on" and e.pitch then
    return (e.velocity or 0) > 0
  elseif e.type == "note_off" and e.pitch then
    return false
  elseif e.type == "cc" and e.number then
    return (e.value or 0) >= 0.5
  end
  return nil
end

-- The control of an event: the one that names the most (port, channel).
local function find(e: types.MidiEvent): Binding
  local best: Binding
  local score = -1
  for _, b in ipairs(bindings) do
    local s = b.source
    local hit = s.note ~= nil and (e.type == "note_on" or e.type == "note_off") and e.pitch == s.note
      or s.cc ~= nil and e.type == "cc" and e.number == s.cc
    if hit and (not s.port or s.port == e.port) and (not s.channel or s.channel == e.channel) then
      local points = (s.port and 2 or 0) + (s.channel and 1 or 0)
      if points > score then
        best, score = b, points
      end
    end
  end
  return best
end

-- The keys played while the `chord` control is held: true once the first
-- of them started the chord.
local chord_open = false

local function run(name: string, t: contracts.StepTarget)
  if name == "chord" then
    chording, chord_open = true, false
    return say("chord")
  end
  local fn = t.actions and t.actions[name] or extra[name]
  if not fn then
    return paw.notify("not here: " .. name, "warn")
  end
  say(name)
  fn(1)
end

-- A control of the controller while `t` listens: true when the event is
-- one (it enters no note).
local function control(e: types.MidiEvent, t: contracts.StepTarget): boolean
  local b = find(e)
  if not b then
    return false
  end
  local key = key_of(b.source)
  local down = down_of(e)
  local was = pressed[key]
  if down == (was ~= nil) then
    return true
  end
  if not down then
    pressed[key] = nil
    if was == "chord" then
      chording = false
      if next(held) == nil then
        t.release()
      end
    end
    return true
  end
  if M.paused() then
    return true
  end
  if b.keys then
    pressed[key] = "keys"
    say(b.keys)
    paw.keymap.feed(b.keys)
  else
    local name = b.action or (next(held) ~= nil and b.held or b.down)
    pressed[key] = name or ""
    if name then
      run(name, t)
    end
  end
  api.ui_redraw()
  return true
end

-- The wait of `:step.learn`: the next key, pad or pedal pressed is bound,
-- by its port, channel and note or cc. True when it took the event.
local function learned(e: types.MidiEvent): boolean
  if not M.learning or e.filtered then
    return false
  end
  if not down_of(e) then
    return false
  end
  local action = M.learning
  local source: Source = {port = e.port, channel = e.channel}
  if e.type == "cc" then
    source.cc = e.number
  else
    source.note = e.pitch
  end
  M.learning = nil
  if paw.ui.grabber then
    paw.ui.grabber = nil
  end
  local ok, err = pcall(add, source, action, true) as (boolean, string)
  if not ok then
    paw.notify("step.learn: " .. tostring(err), "error")
    return true
  end
  write()
  if current() then
    pressed[key_of(source)] = action
  end
  filter(filtering)
  paw.notify(M.source_text(source) .. " now does " .. action .. " in step input")
  api.ui_redraw()
  return true
end

--- A key from the controller: for the target that listens now, if it came
--- from the input of its track and the transport is stopped.
local function heard(e: types.MidiEvent)
  if learned(e) then
    return
  end
  local _, t = current()
  if t and control(e, t) then
    return
  end
  -- A control that a filter maps (`api.engine_midi_filter`) enters nothing.
  if e.type ~= "note_on" and e.type ~= "note_off" or not e.pitch or e.filtered then
    return
  end
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
    local chord = next(held) ~= nil or (chording and chord_open)
    chord_open = chording
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
    -- While the `chord` control is held, the chord stays open.
    if next(held) == nil then
      order = {}
      if not chording then
        t.release()
      end
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

--- Stop the wait of `:step.learn`.
function M.learn_cancel()
  if not M.learning then
    return
  end
  M.learning = nil
  paw.ui.grabber = nil
  paw.notify("step.learn: stopped")
  api.ui_redraw()
end

-- While `:step.learn` waits, the keys of the computer wait too: Esc stops.
local function waiting(key: string)
  if key == "<Esc>" or key == "<C-c>" then
    return M.learn_cancel()
  end
  paw.notify("step.learn: press a key, pad or pedal of the controller for " .. M.learning .. " (Esc stops)")
end

--- Wait for the next key, pad or pedal of the controller, and bind it to
--- `action` by its port, channel and note or cc, in the file of the controls.
function M.learn(action: string)
  if not known(action) then
    return paw.notify("step.learn: no action " .. tostring(action) .. " (Tab lists them)", "error")
  end
  M.learning = action
  paw.ui.grabber = waiting
  paw.notify("step.learn: press a key, pad or pedal of the controller for " .. action .. " (Esc stops)")
  api.ui_redraw()
end

commands.define(
  "step.learn",
  function(ctx: Context): Result
    local action = ctx.args[1]
    if not (action is string) then
      return paw.notify("usage: step.learn {action}: " .. table.concat(M.actions(), " "), "warn")
    end
    M.learn(action)
  end,
  {
    desc = "Bind the next key, pad or pedal of the MIDI controller to an action of step input: `step.learn rest`",
    complete = function(_: string): {string | contracts.CompleteCandidate}
      local out: {string | contracts.CompleteCandidate} = {}
      for i, name in ipairs(M.actions()) do
        out[i] = name
      end
      return out
    end,
  }
)

--- A line of `:step.controls`.
local record ControlLine
  text: string
  source: Source
end

local controls: contracts.PickSource<ControlLine> = {
  title = "Step input controls",
  desc = "The controls of the MIDI controller in step input",
  empty = "No control is bound: :step.learn rest binds one.",
  items = function(): {ControlLine}
    local out: {ControlLine} = {}
    for i, b in ipairs(bindings) do
      out[i] = {
        text = string.format(
          "%-28s %s%s", M.source_text(b.source), M.action_text(b), b.saved and "" or "  (from Lua)"
        ),
        source = b.source,
      }
    end
    return out
  end,
  on_choose = function(item: ControlLine) paw.notify(item.text) end,
  delete = function(items: {ControlLine})
    for _, item in ipairs(items) do
      remove(item.source)
    end
    write()
    filter(filtering)
  end,
}
paw.pick.sources:put("step.controls", controls)

commands.define(
  "step.controls",
  function(_: Context): Result paw.pick("step.controls") end,
  {desc = "List the controls of step input; Alt-d removes one"}
)

M.load()

return M
