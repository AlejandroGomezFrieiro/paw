-- Real time tests.
local T = ...
local test, after, eq, fresh, tone, until_, next_block = T.test, T.after, T.eq, T.fresh, T.tone, T.until_, T.next_block
local paw = require("paw")
local api = paw.api

test("the transport plays, seeks, loops and stops", function()
  fresh()
  local t = paw.add_track()
  t:add_device("synth")
  local notes = {}
  for beat = 0, 7 do
    notes[#notes + 1] = { pitch = "A3", start = beat, length = 1 }
  end
  t:add_clip({ start = 0, length = 8, notes = notes })
  paw.project.tempo = 240 -- four beats a second
  eq(paw.transport.playing, false, "starts stopped")
  paw.transport.seek(2)
  eq(paw.transport.position, 2, "seek is visible at once")
  local began = api.now()
  paw.transport.play()
  until_(function() return paw.transport.position > 2.6 end, "the transport to advance")
  -- Not faster than real time: four beats a second. (A loaded machine may
  -- make it later, not sooner.)
  local pos = paw.transport.position
  eq(
    api.now() - began >= (pos - 2) * 250 * 0.8,
    true,
    "advanced in real time, got " .. pos .. " after " .. (api.now() - began) .. " ms"
  )
  until_(function() return select(1, t:meter()) > 0.01 end, "the meter to move")
  paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 1, true
  paw.transport.seek(0)
  -- Round the loop twice: it goes back to its start, never past its end.
  local before, wraps = paw.transport.position, 0
  until_(function()
    local now = paw.transport.position
    eq(now < 1, true, "stays inside the loop")
    if now < before then wraps = wraps + 1 end
    before = now
    return wraps >= 2
  end, "the loop to go round twice")
  paw.transport.stop()
  local stopped = paw.transport.position
  next_block(5)
  eq(paw.transport.position, stopped, "holds still when stopped")
end)

test("the engine counts the blocks it ran, and the blocks each device ran", function()
  fresh()
  local sleep = api.engine_get().device_sleep
  after(function() api.engine_set_sleep(sleep) end)
  api.engine_set_sleep(true)
  local t = paw.add_track()
  local synth = t:add_device("synth", { attack = 0.001, release = 0.01 })
  next_block()
  local first = api.blocks()
  next_block(3)
  eq(api.blocks() - first >= 4, true, "next_block(3) waits for three whole blocks after the one under way")
  eq(api.blocks(987654), nil, "nil for a device the engine does not have")
  -- A synth with no note sleeps: its count stays.
  until_(function()
    local ran = api.blocks(synth.id)
    next_block(3)
    return api.blocks(synth.id) == ran
  end, "the synth to sleep")
  t:note_on("C4", 100)
  local ran = api.blocks(synth.id)
  next_block(2, synth.id)
  eq(api.blocks(synth.id) - ran >= 3, true, "a device that plays counts its blocks")
  t:note_off("C4")
end)

test("a lane wins over the fader while playing, and lets go when it is turned off", function()
  fresh()
  local t = tone("held", 64)
  paw.project.tempo = 240
  local lane = t:automate("volume")
  lane:add(0, -60)
  paw.transport.play()
  next_block(10)
  eq(select(1, t:meter()) < 0.003, true, "the lane holds the track down")
  t.volume = 6
  next_block(10)
  eq(select(1, t:meter()) < 0.003, true, "moving the fader does not override it")
  lane.enabled = false
  until_(function() return select(1, t:meter()) > 0.05 end, "turning the lane off to return to the fader")
  paw.transport.stop()
end)

test("live notes sound without the transport", function()
  fresh()
  local t = paw.add_track()
  t:add_device("synth")
  t:note_on("C4", 110)
  until_(function() return select(1, t:meter()) > 0.01 end, "the note to sound")
  t:note_off("C4")
  until_(function() return select(1, t:meter()) < 0.005 end, "the note to be released and the meter to fall back")
end)
