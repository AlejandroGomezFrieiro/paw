-- The default commands and keys: transport. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local util = paw.util
local command = paw.command
local cursor, transport = paw.cursor, paw.transport
local keymap, edit = paw.keymap, paw.edit
local common = require("paw.defaults.common")
local need_clip = common.need_clip

-- Where play and record start. `paw.opt.play_from = "cursor"` (the
-- default): from the cursor of the view that has the keys, wherever the
-- playhead is. The cursor never moves by itself, and a stop leaves the
-- playhead where the song stopped. A playhead that the user placed on
-- purpose (`gs`, `gp`, a click on a ruler) stays for the next play, until the
-- cursor moves. `"playhead"` is the old way: play starts from the playhead.
local PIN_EPS = 1e-9
local pinned -- the cursor beat at the time the playhead was placed by hand

--- The song beat of the cursor of the view with the keys. A view with its
--- own cursor in a clip tells it with `view:play_beat()`.
local function cursor_beat()
  local view = paw.ui.views[paw.ui.focused]
  local beat = view and type(view.play_beat) == "function" and view:play_beat()
  return beat or cursor.beat
end
-- Emitted at once by `paw.transport.seek`, with the song stopped only.
paw.on("playhead.placed", function() pinned = not transport.playing and cursor_beat() or nil end)

--- Put the playhead where a start from a stop begins.
local function place()
  if paw.opt.play_from ~= "cursor" then return end
  local here, kept = cursor_beat(), pinned
  pinned = nil
  if kept and math.abs(kept - here) < PIN_EPS then return end
  transport.seek(here)
  pinned = nil
end

command("transport.toggle", function()
  if not transport.playing then place() end
  transport.toggle()
end, { desc = "Play (from the cursor, as `play_from` says) or stop" })
command("transport.play", function()
  if not transport.playing then place() end
  transport.play()
end, { desc = "Play from the cursor (`play_from`)" })
command("transport.stop", transport.stop, { desc = "Stop" })
command("transport.start", function() transport.seek(0) end, { desc = "Move the playhead to the start" })
command(
  "transport.to_cursor",
  function() transport.seek(cursor_beat()) end,
  { desc = "Move the playhead to the cursor" }
)
command("transport.play_cursor", function()
  transport.seek(cursor_beat())
  transport.play()
end, { desc = "Play from the cursor" })
command("transport.play_playhead", function() transport.play() end, { desc = "Play from the playhead" })
-- `<S-CR>` is the other start: the playhead when play starts at the cursor,
-- the cursor when play starts at the playhead.
command("transport.play_other", function()
  if paw.opt.play_from == "cursor" then
    transport.play()
  else
    transport.seek(cursor_beat())
    transport.play()
  end
end, { desc = "Play from the playhead (or, with play_from=playhead, from the cursor)" })
command(
  "transport.seek",
  function(ctx) transport.seek(paw.time.bar_start(tonumber(ctx.args[1]) or 1)) end,
  { desc = "Move the playhead to a bar: `transport.seek 5`" }
)
--- Set the playback loop to beats `from` up to `to`, turn looping on and
--- say so. `gl`, `:loop`, and the region and clip commands all come here.
local function set_loop(from, to, what)
  transport.loop_start, transport.loop_end, transport.loop_enabled = from, to, true
  local text = "loop: " .. paw.ruler.loop_text(from, to, true)
  paw.notify(what and (text .. " (" .. what .. ")") or text)
end

--- Turn looping on or off and say so.
local function switch_loop(on)
  transport.loop_enabled = on
  if not on then return paw.notify("loop: off") end
  if transport.loop_end > transport.loop_start then
    return paw.notify("loop: " .. paw.ruler.loop_text(transport.loop_start, transport.loop_end, true))
  end
  paw.notify("loop: on, but no range is set: select time and press gl", "warn")
end

command("transport.loop", function(ctx)
  local from, to = tonumber(ctx.args[1]), tonumber(ctx.args[2])
  if from and to then
    set_loop(paw.time.bar_start(from), paw.time.bar_start(to + 1))
  else
    switch_loop(not transport.loop_enabled)
  end
end, {
  desc = "Turn the playback loop on or off. The playback loop is the stretch of the song that repeats while it plays. `transport.loop 1 4` sets it to bars 1 to 4. It is not `clip.repeat`, which repeats the content of a clip",
})
command("transport.loop_beats", function(ctx)
  local from, to = tonumber(ctx.args[1]), tonumber(ctx.args[2])
  if not (from and to) or to <= from then
    return paw.notify("transport.loop_beats needs two beats, the start and the end", "warn")
  end
  set_loop(from, to, ctx.args[3])
end, {
  desc = "Set the playback loop to beats `from` to `to` and turn looping on: `transport.loop_beats 16 32`. `gl` does it for the selection",
})
command("loop", function(ctx)
  local r, word = ctx.range, ctx.args[1]
  if r and r.from and r.to and r.to > r.from then
    set_loop(r.from, r.to)
  elseif word == "off" then
    switch_loop(false)
  elseif word == "on" then
    switch_loop(true)
  elseif word == nil then
    switch_loop(not transport.loop_enabled)
  else
    paw.notify(
      "loop: use `:5,9loop` for bars 5 to 9, `:'<,'>loop`, `:loop on`, `:loop off`, or `:loop` to toggle",
      "warn"
    )
  end
end, {
  range = true,
  desc = "Set the playback loop to a range and turn looping on: `:5,9loop` (bars 5 to 9), `:'<,'>loop` (the selection). `:loop off` turns it off, `:loop on` turns it on, and `:loop` toggles it",
})
command("transport.loop_clip", function()
  local clip = need_clip()
  if not clip then return end
  local c = clip:get()
  set_loop(c.start, c.start + c.length, "the clip")
end, { desc = "Set the playback loop to the clip under the cursor and turn looping on" })
command("transport.record", function()
  if transport.recording then
    transport.recording = false
  else
    -- From a stop, the take starts where play starts (`play_from`: the
    -- cursor, or with "playhead" the cursor as before); while the song
    -- plays, it starts where the song is.
    if not transport.playing then
      if paw.opt.play_from == "cursor" then
        place()
      else
        transport.seek(cursor_beat())
      end
    end
    transport.record()
  end
end, { desc = "Record armed tracks from the cursor (or, while the song plays, from the playhead), or stop recording" })
-- The clip of event `e` when it is a take (its kind, a name that matches)
-- on an armed track, or nil. The track comes first, by one field: the clips
-- that an undo or a paste adds to a track that is not armed cost no read of
-- the whole clip (its notes).
local function armed(track)
  local ok, on = pcall(api.track_get, track, "armed")
  return ok and on == true
end
local function take_on_armed(e, kind, name)
  if e.track and not armed(e.track) then return end
  local ok, c = pcall(api.clip_get, e.id)
  if not ok or c.kind ~= kind or not tostring(c.name):match(name) then return end
  if not e.track and not armed(c.track) then return end
  return c
end
-- Sound recorded over sound clips becomes their newest take, in the step
-- that recorded it: the clips under it keep what they played as a take
-- (paw.takes.record_over), and only the new take plays.
paw.on("clip.added", function(e)
  if not take_on_armed(e, "audio", "^take %d+") then return end
  local step = api.undo_current()
  if paw.takes.record_over(e.id) > 0 then api.undo_join(step) end
end)
-- MIDI overdub (`paw.opt.midi_record = "merge"`): a MIDI take that lands
-- over clips joins its notes into them, in the step that recorded it. A
-- take round a loop stays a clip of takes, for comping.
paw.on("clip.added", function(e)
  if paw.opt.midi_record ~= "merge" then return end
  local c = take_on_armed(e, "midi", "^take %d+$")
  if not c then return end
  local track = e.track or c.track
  if paw.takes.count(e.id) > 1 then return end
  local from, to, over = c.start, c.start + c.length, { [e.id] = true }
  local any = false
  for _, other in ipairs(api.clip_list(track)) do
    if
      other.id ~= e.id
      and other.kind == "midi"
      and other.start < to - 1e-9
      and other.start + other.length > from + 1e-9
    then
      over[other.id], any = true, true
      from, to = math.min(from, other.start), math.max(to, other.start + other.length)
    end
  end
  if not any then return end
  local step = api.undo_current()
  edit.arrange.join(track, from, to, over)
  api.undo_join(step)
end)
command(
  "transport.metronome",
  function() transport.metronome = not transport.metronome end,
  { desc = "Toggle the metronome" }
)

-- The count-in is an option (`paw.opt.count_in`, bars) that the kernel is
-- told of: it counts before a take begun with the song stopped.
local function count_in_bars(value) return util.clamp(math.floor(tonumber(value) or 0), 0, 16) end
api.transport_set("count_in", count_in_bars(paw.opt.count_in))
paw.on("option.changed", function(e)
  if e.name == "count_in" then api.transport_set("count_in", count_in_bars(e.value)) end
end)
-- The metronome's level, accent and output are options the kernel is told
-- of: `paw.opt.click_level` (dB), `click_accent`, `click_output` (the first
-- output channel of a pair, 0 for with the song).
local function send_click()
  for _, name in ipairs({ "click_level", "click_accent", "click_output" }) do
    local ok, err = pcall(api.transport_set, name, paw.opt[name])
    if not ok then paw.notify(tostring(err):gsub("^[^:]*:%d+: ", ""), "warn") end
  end
end
send_click()
paw.on("option.changed", function(e)
  if e.name:match("^click_") then send_click() end
end)
local function click_said()
  local o = paw.opt
  return string.format(
    "click at %+g dB, %s, %s",
    o.click_level,
    o.click_accent and "the first beat higher" or "every beat the same",
    o.click_output > 0 and string.format("on outputs %d/%d", o.click_output, o.click_output + 1) or "with the song"
  )
end
command("click", function(ctx)
  local a = ctx.args
  local level = a.level ~= nil and tonumber(a.level) or nil
  if a.level ~= nil and not level then return paw.notify("click: level=-6, in dB", "warn") end
  local words = {
    on = true,
    yes = true,
    ["1"] = true,
    ["true"] = true,
    off = false,
    no = false,
    ["0"] = false,
    ["false"] = false,
  }
  local accent = a.accent
  if accent ~= nil and type(accent) ~= "boolean" then accent = words[tostring(accent)] end
  if a.accent ~= nil and accent == nil then return paw.notify("click: accent=on or accent=off", "warn") end
  local output = a.output
  if output == "song" or output == "mix" or output == "main" then output = 0 end
  if output ~= nil then output = tonumber((tostring(output):match("^(%d+)"))) end
  if a.output ~= nil and not output then
    return paw.notify("click: output=3 (outputs 3 and 4), or output=song", "warn")
  end
  local ok, err = pcall(function()
    if level then paw.opt.click_level = level end
    if accent ~= nil then paw.opt.click_accent = accent end
    if output then paw.opt.click_output = output end
  end)
  if not ok then return paw.notify((tostring(err):gsub("^[^:]*:%d+: ", "")), "warn") end
  paw.notify(click_said())
end, {
  desc = "The metronome's sound: `click level=-6`, `click accent=off`, `click output=3` (outputs 3 and 4, for headphones), `click output=song`; alone, what it is",
})
-- The selected track plays the MIDI keyboard while no track is armed
-- (`paw.opt.midi_follows_selection`): the kernel is told which track.
local function send_follow()
  if paw.seats.current ~= 0 then return end
  local id = paw.opt.midi_follows_selection and cursor.track_id() or nil
  api.engine_follow(id ~= 0 and id or nil)
end
paw.on("cursor.changed", send_follow)
paw.on("project.loaded", send_follow)
paw.on("option.changed", function(e)
  if e.name == "midi_follows_selection" then send_follow() end
end)
send_follow()
-- The undo history's limits are options the kernel is told of.
local function send_undo_limits() api.undo_limits(paw.opt.undo_steps, math.floor(paw.opt.undo_memory * 1024 * 1024)) end
send_undo_limits()
paw.on("option.changed", function(e)
  if e.name == "undo_steps" or e.name == "undo_memory" then send_undo_limits() end
end)
-- Esc while counting in calls the take off, as stopping does.
paw.on("escape", function()
  if (api.transport_get().counting or 0) > 0 then transport.stop() end
end)
local last_count = 1
command("countin", function(ctx)
  local word = ctx.args[1]
  local bars
  if word == "off" or word == "0" then
    bars = 0
  elseif tonumber(word) then
    bars = count_in_bars(word)
  elseif word == nil then
    bars = paw.opt.count_in > 0 and 0 or last_count
  else
    return paw.notify("countin: a number of bars, or `off`", "warn")
  end
  if bars > 0 then last_count = bars end
  paw.opt.count_in = bars
  paw.notify(
    bars > 0 and string.format("count-in: %d bar%s before a take", bars, bars == 1 and "" or "s") or "count-in off"
  )
end, { desc = "Count bars in before recording from a stop: `countin 1`, `countin off`, or toggle" })

-- The pre-roll is two options (`paw.opt.pre_roll` bars and
-- `paw.opt.pre_roll_seconds`) that the kernel is told of: a take punched in
-- from a stop starts playing that long before the punch in.
local function pre_roll_values()
  return util.clamp(math.floor(tonumber(paw.opt.pre_roll) or 0), 0, 16),
    util.clamp(tonumber(paw.opt.pre_roll_seconds) or 0, 0, 30)
end
local function send_pre_roll()
  local bars, seconds = pre_roll_values()
  api.transport_set("pre_roll", bars)
  api.transport_set("pre_roll_seconds", seconds)
end
send_pre_roll()
paw.on("option.changed", function(e)
  if e.name == "pre_roll" or e.name == "pre_roll_seconds" then send_pre_roll() end
end)
local last_pre_roll = 2
command("preroll", function(ctx)
  local word = ctx.args[1]
  local bars, seconds = 0, 0
  if word == "off" or word == "0" then
    bars = 0
  elseif word == nil then
    local now_bars, now_seconds = pre_roll_values()
    bars = (now_bars > 0 or now_seconds > 0) and 0 or last_pre_roll
  elseif tostring(word):match("^%d+%.?%d*s$") then
    seconds = tonumber(word:sub(1, -2))
  elseif tonumber(word) then
    bars = tonumber(word)
  else
    return paw.notify("preroll: a number of bars, `3s` for seconds, or `off`", "warn")
  end
  if bars > 16 or seconds > 30 then return paw.notify("preroll: up to 16 bars or 30 seconds", "warn") end
  bars = math.floor(bars)
  if bars > 0 then last_pre_roll = bars end
  paw.opt.pre_roll, paw.opt.pre_roll_seconds = bars, seconds
  if bars > 0 then
    paw.notify(string.format("pre-roll: %d bar%s before the punch in", bars, bars == 1 and "" or "s"))
  elseif seconds > 0 then
    paw.notify(string.format("pre-roll: %g seconds before the punch in", seconds))
  else
    paw.notify("pre-roll off")
  end
end, {
  desc = "Play bars (or `3s` seconds) before the punch in when recording from a stop: `preroll 2`, `preroll 3s`, `preroll off`, or toggle",
})

--- Punch in and out: record only between two points while the song plays.
--- The range is kept with the project, as the loop is.
local function punch_from_selection()
  local sel = keymap.selection()
  if sel and sel.kind ~= "line" and sel.c0 and sel.c1 and sel.c1 > sel.c0 then
    return sel.c0, sel.c1, "the selection"
  end
  if transport.loop_end > transport.loop_start then return transport.loop_start, transport.loop_end, "the loop" end
end
local function said_punch()
  local t = api.transport_get()
  if not t.punch_enabled then return paw.notify("punch off: recording takes in everything") end
  paw.notify(string.format("punch in at %s, out at %s", paw.time.format(t.punch_start), paw.time.format(t.punch_end)))
end
command("punch", function(ctx)
  local word = ctx.args[1]
  local from, to = tonumber(ctx.args[1]), tonumber(ctx.args[2])
  if from and to then
    transport.punch_start, transport.punch_end =
      paw.time.bar_start(math.min(from, to)), paw.time.bar_start(math.max(from, to) + 1)
    transport.punch_enabled = true
  elseif
    word == "selection"
    or (word == nil and not transport.punch_enabled and transport.punch_end <= transport.punch_start)
  then
    -- The first time, or when asked: the selection, else the loop.
    local a, b, what = punch_from_selection()
    if not a then return paw.notify("punch: select a stretch of time, or set the loop, or say `punch 5 8`", "warn") end
    transport.punch_start, transport.punch_end, transport.punch_enabled = a, b, true
    if keymap.mode == "x" then keymap.set_mode("n") end
    paw.notify(string.format("punch over %s: in at %s, out at %s", what, paw.time.format(a), paw.time.format(b)))
    return
  elseif word == "off" or word == "on" then
    transport.punch_enabled = word == "on" and transport.punch_end > transport.punch_start
  elseif word == nil then
    transport.punch_enabled = not transport.punch_enabled
  else
    return paw.notify("punch: `punch`, `punch 5 8` (bars), `punch selection`, `punch off`", "warn")
  end
  said_punch()
end, { desc = "Record only between two points: toggle, `punch 5 8` (bars), `punch selection` (or the loop)" })
-- `tempo`, `tempo.ramp`, `tempo.remove`, `tempo.list`, `tempo.tap`, `timesig`.
paw.tempo.commands(command)
-- `tempo.lane`, `tempo.move`.
paw.tempolane.commands(command)
