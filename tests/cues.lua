-- Tests of cues, the core's primitive under the clip launcher: a clip kept
-- off the timeline played on a track from a boundary, in place of the
-- track's timeline, until stopped. No extension is loaded here: the core
-- works without one. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fails, fresh, render = T.test, T.eq, T.near, T.fails, T.fresh, T.render
local api = paw.api

local function start()
  fresh()
  api.engine_restart({ backend = "null" })
end

local until_ = T.until_

local function state(track)
  for _, s in ipairs(api.cue_state()) do
    if s.track == track then return s end
  end
  return {}
end

--- A synth track with a clip off its timeline: one long note.
local function synth(name, pitch)
  local t = paw.add_track({ name = name })
  t:add_device("synth", { attack = 0.001, release = 0.01 })
  local id = api.clip_add(
    t.id,
    { cue = true, start = 8, length = 4, notes = { { pitch = pitch or 57, start = 0, length = 4 } } }
  )
  return t, id
end

test("cues: a clip off the timeline is kept apart, starts at 0, and is saved and undone with the project", function()
  start()
  local t, id = synth("Lead")
  eq(#api.clip_list(t.id), 0, "nothing on the timeline")
  local cues = api.cue_list(t.id)
  eq(#cues .. " " .. cues[1].start .. " " .. tostring(cues[1].cue), "1 0 true", "off the timeline, from 0")
  eq(api.clip_get(id).cue, true, "a clip's view says so")
  fails(function() api.clip_set(id, "start", 4) end, "starts at 0", "it has no place in time")
  local copy = api.clip_to_cues(t:add_clip({ start = 4, length = 2 }).id, t.id)
  eq(api.clip_get(copy).start .. " " .. #api.cue_list(t.id), "0 2", "a clip of the timeline copied off it")
  local other = paw.add_track({ name = "Other" })
  api.clip_set(copy, "track", other.id)
  eq(#api.cue_list(other.id), 1, "moved to another track")
  api.undo_checkpoint()
  local path = T.scratch .. "/cues.paw"
  api.project_save(path)
  paw.project.new()
  api.project_load(path)
  eq(#api.cue_list(api.track_list()[1]), 1, "saved and opened")
  api.clip_remove(api.cue_list(api.track_list()[1])[1].id)
  api.undo_checkpoint()
  api.undo()
  eq(#api.cue_list(api.track_list()[1]), 1, "undone")
end)

test("cues: a cue lands on its boundary in place of the timeline, then stops and goes back", function()
  start()
  local t, id = synth("Lead")
  t:add_clip({ start = 0, length = 64, notes = { { pitch = 45, start = 0, length = 64 } } })
  paw.transport.seek(0)
  paw.transport.play()
  until_(function() return paw.transport.position > 0.5 end, "the song to play", 10000)
  api.cue({ { track = t.id, clip = id } })
  until_(function() return state(t.id).clip == id end, "the clip to start", 10000)
  eq(state(t.id).since, 4, "on the next bar, the default")
  near(state(t.id).length, 4, 1e-9, "its loop")
  api.cue({ { track = t.id, stop = true, quantize = "1/4" } })
  until_(function() return state(t.id).stopped end, "the track to stop", 10000)
  eq(state(t.id).since % 1, 0, "on a beat")
  api.cue({ { track = t.id, timeline = true, quantize = "off" } })
  until_(function() return state(t.id).clip == nil and not state(t.id).stopped end, "the timeline again", 10000)
  fails(
    function() api.cue({ { track = t.id, clip = 999999 } }) end,
    "not off the timeline",
    "a clip that is not a cue clip"
  )
  fails(function() api.cue({ { track = t.id, clip = id, stop = true } }) end, "one of", "a cue names one thing")
  paw.transport.stop()
end)

test("cues: a clip that plays keeps playing while other clips off the timeline come and go", function()
  start()
  local t, first = synth("Lead", 60)
  local second = api.clip_add(t.id, { cue = true, length = 2, notes = { { pitch = 64, start = 0, length = 1 } } })
  paw.transport.play()
  api.cue({ { track = t.id, clip = second, quantize = "off" } })
  until_(function() return state(t.id).clip == second end, "the second clip to start", 5000)
  api.clip_remove(first)
  paw.flush()
  paw.wait(50)
  eq(state(t.id).clip, second, "the same clip plays on")
  api.clip_remove(second)
  paw.flush()
  until_(function() return state(t.id).stopped end, "a clip removed while it plays stops the track", 5000)
  paw.transport.stop()
  until_(function() return state(t.id).stopped == nil end, "stopping the song sends it back", 5000)
end)

test("cues: a render plays the timeline, not what is cued", function()
  start()
  local t, id = synth("Lead", 69)
  api.cue({ { track = t.id, clip = id, quantize = "off" } })
  until_(function() return state(t.id).clip == id end, "the clip to start", 5000)
  local info = render({ start = 0, ["end"] = 4, tail = 0, bits = 16 })
  eq(T.channel_peaks(info), 0, "the track has nothing on its timeline")
  paw.transport.stop()
end)

test("cues: a track folder from outside brings its clips off the timeline, with notes and ids of their own", function()
  start()
  local t = paw.add_track({ name = "Loop" })
  local id = api.clip_add(t.id, { cue = true, length = 4, notes = { { pitch = 62, start = 0, length = 1 } } })
  local path = T.scratch .. "/cues-outside"
  api.project_save(path)
  local folder
  for _, e in ipairs(api.read_dir(path .. "/tracks")) do
    folder = path .. "/tracks/" .. e.name
  end
  -- Another project, whose ids are the same as the first one's.
  paw.project.new()
  local other = paw.add_track({ name = "Here" })
  api.clip_add(other.id, { cue = true, length = 2 })
  local track = api.track_import_folder(folder)
  local cues = api.cue_list(track)
  eq(#cues, 1, "the clip off the timeline comes with the track")
  eq(api.clip_notes(cues[1].id)[1].pitch, 62, "with its notes, read from its file")
  eq(cues[1].id ~= api.cue_list(other.id)[1].id, true, "and an id of its own")
  local _ = id
end)
