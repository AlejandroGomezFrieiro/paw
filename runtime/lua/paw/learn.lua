-- Controller learn: a knob, fader or wheel of a MIDI controller moves a
-- track's fader or pan, or a parameter of a device.
--
--   :learn                 -- for what was moved last: then move the controller
--   :learn volume          -- the selected track's fader (or `pan`, or a parameter's name)
--   :learn.list            -- what is bound; choose one to take it away
--   :learn.remove 2        -- take the second away
--   paw.learn.bind({ cc = 74, channel = 1 }, { track = t.id, target = "param", device = d.id, param = "cutoff" })
--
-- The bindings belong to the project (`project.meta.learn`): they name its
-- tracks and devices, are saved with it and undone like any edit. A move
-- from the controller is a move like any other: it writes automation when
-- the track's mode says so, and a sweep of it is one undo step.
--
-- A controller is where it was left, the song is not: so a control only
-- takes hold of its target once it has reached the target's value
-- (`paw.opt.learn_pickup`, on by default), instead of jumping it there.
local api = paw.api
local M = {}

paw.option.define("learn_pickup", true)

-- What is waiting for a controller: the target `:learn` was asked for.
M.learning = nil
-- What was moved last: { track, target, device, param }.
M.last = nil

-- Per binding, by `key`: the last position received and whether the control
-- has hold of its target.
local hold = {}

--- The bindings: { { source, channel, number, track, target, device, param }, ... }.
function M.bindings()
  local list = api.project_get().meta.learn
  return type(list) == "table" and list or {}
end

local function save(list)
  local meta = api.project_get().meta
  meta.learn = #list > 0 and list or nil
  api.project_set("meta", meta)
end

--- A controller as text: "CC 74 ch 1", "pitch wheel ch 2", "note 36 ch 10".
function M.source_name(b)
  local what = b.source == "cc" and ("CC " .. b.number)
    or b.source == "note" and ("note " .. b.number)
    or b.source == "bend" and "pitch wheel"
    or "pressure"
  return b.channel and (what .. " ch " .. b.channel) or what
end

-- What a button or a pad does rather than moves: kinds of target that
-- extensions add with `paw.learn.trigger` (the clip launcher adds `launch`,
-- `scene` and `stop`). A binding to a kind that no loaded extension adds
-- stays in the project and does nothing.
M.triggers = {}

--- Add a kind of target that a button or a pad presses: `spec` has
--- `press(binding, down)` (down is false when it is let go), `name(target)`
--- (the text of `:learn.list`), and optionally `check(target)` (an error for
--- a target that is not right), `words` (the words of `:learn` that name it),
--- `target_for(word, track)` (the target of a word, or nil) and
--- `under_cursor(focused)` (the target under the cursor of a view, or nil).
--- A target can keep a number in `slot`, such as a row.
function M.trigger(name, spec)
  assert(
    type(name) == "string" and type(spec) == "table" and type(spec.press) == "function",
    "paw.learn.trigger(name, { press = function(binding, down) ... end, name = ... })"
  )
  M.triggers[name] = spec
end

--- True if you press a target, and do not move it.
function M.is_trigger(target) return M.triggers[target.target] ~= nil end

--- What a binding moves, as text: "Lead › volume", "Lead › Filter › Cutoff".
function M.target_name(t)
  local trigger = M.triggers[t.target]
  if trigger then
    local ok, text = pcall(trigger.name, t)
    return ok and tostring(text) or "(" .. t.target .. ": " .. tostring(text) .. ")"
  end
  local ok, track = pcall(api.track_get, t.track)
  if not ok then return "(a track that is gone)" end
  if t.target ~= "volume" and t.target ~= "pan" and t.target ~= "param" then
    return track.name .. " › " .. t.target .. " (no loaded extension presses it)"
  end
  if t.target ~= "param" then return track.name .. " › " .. t.target end
  local found, device = pcall(api.device_get, t.device)
  if not found then return track.name .. " › (a device that is gone)" end
  for _, p in ipairs(device.param_info) do
    if p.key == t.param then return track.name .. " › " .. device.name .. " › " .. p.name end
  end
  return track.name .. " › " .. device.name .. " › " .. tostring(t.param)
end

local function same_target(a, b)
  return a.track == b.track
    and a.target == b.target
    and a.device == b.device
    and a.param == b.param
    and a.slot == b.slot
end

local function key(b)
  return table.concat(
    { b.source, b.number or "", b.channel or "", b.track or "", b.target, b.device or "", b.param or "", b.slot or "" },
    ":"
  )
end

--- The source of a `midi.in` event that can move something, or nil:
--- { source, number, channel, value } with the value from 0 to 1.
function M.source(event)
  if event.type == "cc" then
    return { source = "cc", number = event.number, channel = event.channel, value = event.value }
  elseif event.type == "bend" then
    return { source = "bend", channel = event.channel, value = (event.value + 1) / 2 }
  elseif event.type == "pressure" and not event.key then
    return { source = "pressure", channel = event.channel, value = event.value }
  elseif event.type == "note_on" or event.type == "note_off" then
    -- A key or a pad: pressed is 1, let go 0. Only buttons are bound to them.
    return { source = "note", number = event.pitch, channel = event.channel, value = event.type == "note_on" and 1 or 0 }
  end
end

local function check(target)
  assert(type(target) == "table", "a target is a table")
  if M.is_trigger(target) then
    if target.track then api.track_get(target.track) end
    local trigger = M.triggers[target.target]
    if trigger.check then trigger.check(target) end
    return
  end
  assert(target.track, "a target names its track")
  api.track_get(target.track)
  if target.target == "param" then
    local device = api.device_get(target.device)
    assert(device.track == target.track, "the device is not on that track")
    local found = false
    for _, p in ipairs(device.param_info) do
      found = found or p.key == target.param
    end
    assert(found, "the device has no parameter `" .. tostring(target.param) .. "`")
  elseif target.target ~= "volume" and target.target ~= "pan" then
    local names = {}
    for name in pairs(M.triggers) do
      names[#names + 1] = "`" .. name .. "`"
    end
    table.sort(names)
    error(
      "a controller moves `volume`, `pan` or a `param`"
        .. (#names > 0 and (", or presses " .. table.concat(names, ", ")) or ""),
      3
    )
  end
end

--- Bind a controller to a target, in place of whatever moved that target
--- before. `source` is { cc = 74 }, { bend = true } or { pressure = true },
--- or for a button { note = 36 }, with `channel` (1 to 16) or without for
--- any channel. Returns the binding.
function M.bind(source, target)
  check(target)
  local b = {
    source = source.cc and "cc"
      or source.note and "note"
      or source.bend and "bend"
      or source.pressure and "pressure"
      or source.source,
    number = source.cc or source.note or source.number,
    channel = source.channel,
    track = target.track,
    target = target.target or "volume",
    device = target.device,
    param = target.param,
    slot = target.slot,
  }
  assert(
    b.source == "cc" or b.source == "bend" or b.source == "pressure" or b.source == "note",
    "a controller is `cc`, `note`, `bend` or `pressure`"
  )
  assert(
    b.source ~= "note" or M.is_trigger(b),
    "a key or a pad presses a button (such as the clip launcher's); it moves nothing"
  )
  if b.source == "cc" or b.source == "note" then
    assert(
      type(b.number) == "number" and b.number >= 0 and b.number <= 127,
      "controller and note numbers go from 0 to 127"
    )
  end
  local list = {}
  for _, old in ipairs(M.bindings()) do
    if not same_target(old, b) then list[#list + 1] = old end
  end
  list[#list + 1] = b
  save(list)
  return b
end

--- Take a binding away: by its place in `bindings()`, or everything that
--- moves a target. Returns how many went.
function M.unbind(which)
  local list, gone = {}, 0
  for i, b in ipairs(M.bindings()) do
    local hit = type(which) == "number" and i == which or type(which) == "table" and same_target(b, which)
    if hit then
      gone = gone + 1
    else
      list[#list + 1] = b
    end
  end
  if gone > 0 then save(list) end
  return gone
end

--- Forget every controller binding.
function M.clear()
  if #M.bindings() > 0 then save({}) end
end

--- What moves a target: its binding, or nil.
function M.bound(target)
  for _, b in ipairs(M.bindings()) do
    if same_target(b, target) then return b end
  end
end

-- A fader's travel: silence at the bottom, then -60 dB to +6 dB.
local function fader_db(f) return f <= 0.001 and -120 or -60 + 66 * f end
local function fader_fraction(db) return db <= -60 and 0 or math.min(1, (db + 60) / 66) end

local function param_of(b)
  for _, p in ipairs(api.device_get(b.device).param_info) do
    if p.key == b.param then return p end
  end
end

--- Where a binding's target is now, 0 to 1.
local function position(b)
  if b.target == "volume" then return fader_fraction(api.track_get(b.track, "volume")) end
  if b.target == "pan" then return (api.track_get(b.track, "pan") + 1) / 2 end
  local p = param_of(b)
  return p and paw.params.fraction(p, api.device_get(b.device).params[b.param]) or 0
end

local function move(b, f)
  if b.target == "volume" then
    api.track_set(b.track, "volume", fader_db(f))
  elseif b.target == "pan" then
    local pan = f * 2 - 1
    -- The middle of a knob with 128 steps is not quite the middle.
    api.track_set(b.track, "pan", math.abs(pan) < 0.02 and 0 or pan)
  else
    local p = param_of(b)
    if p then api.device_set_param(b.device, b.param, paw.params.from_fraction(p, f)) end
  end
end

--- A controller moved to `f` (0 to 1): move what it is bound to.
local function apply(b, f)
  local state = hold[key(b)] or {}
  hold[key(b)] = state
  local now = position(b)
  -- Moved by something else since: the control has to catch it again.
  if state.set and math.abs(now - state.set) > 0.02 then state.held = false end
  if not state.held and paw.opt.learn_pickup then
    local reached = math.abs(f - now) <= 0.04 or (state.last and (state.last - now) * (f - now) <= 0)
    state.last = f
    if not reached then return false end
  end
  state.held, state.last = true, f
  move(b, f)
  state.set = position(b)
  return true
end

--- A button pressed (`f` 0.5 or more: a note on, a CC up) or let go: press
--- what it is bound to, once for each press.
local function press(b, f)
  local state = hold[key(b)] or {}
  hold[key(b)] = state
  local down = f >= 0.5
  if down == (state.down or false) then return end
  state.down = down
  M.triggers[b.target].press(b, down)
end

--- Wait for the next controller move and bind it to `target` (or to what
--- was moved last).
function M.start(target)
  target = target or M.last
  if not target then
    return paw.notify("learn: move a fader, a pan or a parameter first, or say which: `:learn volume`", "warn")
  end
  check(target)
  M.learning = target
  api.ui_redraw()
  paw.notify(
    "learn: move a knob or fader of the controller for " .. M.target_name(target) .. " (`:learn.cancel` gives up)"
  )
end

--- Stop the wait for a controller to learn.
function M.cancel()
  if M.learning then paw.notify("learn: given up") end
  M.learning = nil
  api.ui_redraw()
end

paw.on("midi.in", function(event)
  local source = M.source(event)
  if not source then return end
  if M.learning then
    local target = M.learning
    local trigger = M.is_trigger(target)
    -- A key binds only a button, and a button is learned from its press,
    -- not from its letting go.
    if (source.source == "note" and not trigger) or (trigger and source.value < 0.5) then return end
    M.learning = nil
    local ok, b = pcall(M.bind, source, target)
    if not ok then return paw.notify("learn: " .. tostring(b), "error") end
    -- It is where it is: no waiting for it to reach the target, and the
    -- press that taught it launches nothing.
    hold[key(b)] = { held = true, last = source.value, down = trigger or nil }
    paw.notify(M.source_name(b) .. " now moves " .. M.target_name(b))
    api.ui_redraw()
    return
  end
  for _, b in ipairs(M.bindings()) do
    if b.source == source.source and b.number == source.number and (not b.channel or b.channel == source.channel) then
      -- A target that is gone is passed over; `:learn.list` shows it.
      pcall(M.is_trigger(b) and press or apply, b, source.value)
    end
  end
end)

-- What was moved last, for `:learn` without a word. Parameters say so
-- themselves; a fader or pan is found by what changed on its track.
paw.on("param.touched", function(e)
  local ok, device = pcall(api.device_get, e.device)
  if ok then M.last = { track = device.track, target = "param", device = e.device, param = e.param } end
end)
local seen = {}
local function look(id)
  local ok, volume = pcall(api.track_get, id, "volume")
  if not ok then
    seen[id] = nil
    return
  end
  local was = seen[id]
  local t = { volume = volume, pan = api.track_get(id, "pan") }
  seen[id] = t
  if not was then return end
  if was.volume ~= t.volume then M.last = { track = id, target = "volume" } end
  if was.pan ~= t.pan then M.last = { track = id, target = "pan" } end
end
local function look_all()
  seen = {}
  for _, id in ipairs(api.track_list({ all = true })) do
    look(id)
  end
  look(0)
end
paw.on("track.changed", function(e)
  if e.id then look(e.id) end
end)
paw.on("track.added", function(e)
  if e.id then look(e.id) end
end)
paw.on("project.loaded", function()
  M.learning, M.last, hold = nil, nil, {}
  look_all()
end)
paw.on("startup", look_all)

--- The target a word names on the selected track: "volume", "pan", or a
--- parameter of one of its devices by key or name.
function M.target_for(word)
  local track = paw.cursor.track_id()
  word = tostring(word):lower()
  -- Buttons that extensions add.
  for _, trigger in pairs(M.triggers) do
    local target = trigger.target_for and trigger.target_for(word, track)
    if target then return target end
  end
  if not track then error("no track selected", 0) end
  if word == "volume" or word == "pan" then return { track = track, target = word } end
  for _, id in ipairs(api.track_get(track).devices) do
    for _, p in ipairs(api.device_get(id).param_info) do
      if p.key:lower() == word or p.name:lower() == word then
        return { track = track, target = "param", device = id, param = p.key }
      end
    end
  end
  error("the selected track has no parameter `" .. word .. "`", 0)
end

--- What the keyboard is on, if that is something a controller can move:
--- the parameter under the device panel's cursor, the mixer's fader.
function M.under_cursor()
  local ui = paw.ui
  if ui.focused == "devices" then
    local panel = ui.views.devices
    local row = panel:rows()[panel.row]
    if row and row.param then
      return {
        track = api.device_get(row.device.id).track,
        target = "param",
        device = row.device.id,
        param = row.param.key,
      }
    end
  elseif ui.focused == "mixer" then
    local track = paw.cursor.track_id()
    if track then return { track = track, target = "volume" } end
  end
  for _, trigger in pairs(M.triggers) do
    local target = trigger.under_cursor and trigger.under_cursor(ui.focused)
    if target then return target end
  end
end

paw.command("learn", function(ctx)
  local word = ctx.args[1] and table.concat(ctx.args, " ")
  M.start(word and M.target_for(word) or M.under_cursor() or M.last)
end, {
  desc = "Bind a MIDI controller: `learn` for what was moved last, `learn volume`, `learn pan`, `learn cutoff`, then move the controller or press the pad",
  complete = function()
    local words = { "volume", "pan" }
    for _, trigger in pairs(M.triggers) do
      for _, word in ipairs(trigger.words or {}) do
        words[#words + 1] = word
      end
    end
    local track = paw.cursor.track_id()
    for _, id in ipairs(track and api.track_get(track).devices or {}) do
      for _, p in ipairs(api.device_get(id).param_info) do
        words[#words + 1] = p.key
      end
    end
    return words
  end,
})
paw.command("learn.cancel", M.cancel, { desc = "Stop waiting for a controller" })
-- For a frontend's menus, which know the device and the parameter.
paw.command("learn.param", function(ctx)
  local device = tonumber(ctx.args[1])
  local d = device and api.device_get(device)
  M.start({ track = d.track, target = "param", device = device, param = tostring(ctx.args[2]) })
end, { desc = "Bind a MIDI controller to a parameter of a device, by their ids: `learn.param 12 cutoff`" })
-- `:param.last learn` (paw.fx) learns the parameter touched last.
--- Learn a controller for a device's parameter: the next one moved moves it.
paw.fx.learn = function(device, param)
  M.start({ track = api.device_get(device).track, target = "param", device = device, param = param })
end
paw.command(
  "learn.remove",
  function(ctx)
    local which = tonumber(ctx.args[1])
    if not which then
      local target = ctx.args[1] and M.target_for(table.concat(ctx.args, " ")) or M.under_cursor() or M.last
      if not target or M.unbind(target) == 0 then return paw.notify("learn: no controller moves that", "warn") end
      return paw.notify("learn: nothing moves " .. M.target_name(target) .. " now")
    end
    local b = M.bindings()[which]
    if not b then return paw.notify("learn: there are " .. #M.bindings() .. " bindings", "warn") end
    M.unbind(which)
    paw.notify("learn: " .. M.source_name(b) .. " no longer moves " .. M.target_name(b))
  end,
  { desc = "Take a controller binding away: `learn.remove 2` (as `learn.list` numbers them), `learn.remove volume`" }
)
paw.command("learn.clear", function()
  M.clear()
  paw.notify("learn: every controller binding is gone")
end, { desc = "Take every controller binding away" })
paw.command("learn.list", function()
  local list = M.bindings()
  if #list == 0 then return paw.notify("learn: no controller is bound; `:learn` binds one") end
  local items = {}
  for i, b in ipairs(list) do
    items[i] = { text = string.format("%d  %-18s → %s", i, M.source_name(b), M.target_name(b)), index = i }
  end
  paw.pick({
    title = "Controllers (Enter takes one away)",
    items = items,
    on_choose = function(item) paw.commands.run("learn.remove", { item.index }) end,
  })
end, { desc = "List the controller bindings; choosing one takes it away" })

return M
