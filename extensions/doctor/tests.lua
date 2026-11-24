-- Tests of the doctor; tests/suite.lua runs them. Everything runs on the null
-- backend, whose test input gives two channels of tone and whose test MIDI
-- port is played with `paw.midi.inject`. The real hardware is out of reach
-- of tests: what they check is that the checks run, measure what arrives,
-- ask, report, and leave nothing behind.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local api = paw.api

local doctor, loaded

local function load()
  if not loaded then
    paw.ext.load("extensions/doctor")
    loaded = true
  end
  doctor = require("doctor")
  paw.opt.doctor_dir = T.scratch .. "/doctor"
  paw.opt.doctor_plugins = {}
  return doctor
end

--- The engine with no device (the null backend, or the stepped one of the
--- suite) with a test input and the MIDI port "Keys A", until
--- the test ends.
local function null_backend()
  api.engine_restart({
    test_input = { frequency = 440, level = -12, channels = 2 },
    test_midi = { "Keys A" },
  })
  T.after(function() api.engine_restart({}) end)
end

--- Short runs: a quarter-second tone, a second of dropouts, and so on.
local quick = {
  tone = 0.2,
  seconds = 1,
  record_seconds = 1,
  input_seconds = 0.6,
  wait_seconds = 0.4,
  round_trips = 1,
  plugin_seconds = 0.5,
  voices = 3,
}

local function run(opts)
  local o = {}
  for k, v in pairs(quick) do
    o[k] = v
  end
  for k, v in pairs(opts or {}) do
    o[k] = v
  end
  return doctor.run_to_end(o, 120)
end

local function result(r, id)
  for _, x in ipairs(r.done) do
    if x.id == id then return x end
  end
  error("no result for " .. id)
end

local function text(path)
  local file = assert(io.open(path, "r"))
  local out = file:read("*a")
  file:close()
  return out
end

--- Everything about the open project that a check must leave alone.
local function state()
  local project = api.project_get()
  project.edits = nil
  local parts = {}
  for _, id in ipairs(api.part_list()) do
    local t = api.part_get(id)
    t.clip_list = api.clip_list(id)
    parts[#parts + 1] = t
  end
  return paw.json.encode({
    project = project,
    tree = api.undo_tree(),
    parts = parts,
    transport = { position = api.transport_get().position, loop = api.transport_get().loop_enabled },
  })
end

local function listing(dir)
  local names = {}
  for _, e in ipairs(api.read_dir(dir)) do
    names[#names + 1] = e.name
  end
  return table.concat(names, ",")
end

test("the doctor lists nine checks, and another extension can add one", function()
  load()
  null_backend()
  fresh()
  eq(#doctor.checks >= 9, true, "the checks that come with it")
  eq(doctor.checks[1].id, "system", "the sound system first")
  table.insert(doctor.checks, {
    name = "Mine",
    unattended = true,
    run = function(ctx)
      ctx:fact("answer", 42)
      return "ok", "it works"
    end,
  })
  local r = run({ only = { "mine" } })
  eq(#r.done, 1, "one check ran")
  eq(r.done[1].status, "ok", "the check's own verdict")
  eq(r.done[1].summary, "it works", "and its sentence")
  eq(r.done[1].facts.answer, 42, "and what it found")
  table.remove(doctor.checks)
end)

test("the doctor's sound system check reads the engine and warns about the null backend", function()
  load()
  null_backend()
  fresh()
  local r = run({ only = { "system" }, unattended = true })
  local c = result(r, "system")
  eq(c.status, "warn", "the null backend is a warning")
  eq(c.facts.backend, api.engine_get().backend, "the backend")
  eq(c.facts.sample_rate, 48000, "the rate")
  local joined = table.concat(c.lines, "\n")
  eq(joined:find("null backend", 1, true) ~= nil, true, "the warning says why")
  eq(joined:find("latency reported", 1, true) ~= nil, true, "the latencies are listed")
end)

test("the doctor's input check sees both channels of the test input", function()
  load()
  null_backend()
  fresh()
  local r = run({ only = { "input" }, unattended = true })
  local c = result(r, "input")
  eq(c.status, "ok", c.summary)
  eq(c.facts.channels, 2, "two channels")
  eq(c.facts.silent_channels, "none", "none silent")
  eq(c.measures.peak_1:find("%-1[0-9]%.%d dBFS") ~= nil, true, "a tone at about -12 dB: " .. c.measures.peak_1)
end)

test("the doctor's recording check records the test tone and takes it away", function()
  load()
  null_backend()
  fresh()
  local before = listing(api.env().data_dir .. "/recordings")
  local r = run({ only = { "recording" }, unattended = true })
  local c = result(r, "recording")
  eq(c.status, "ok", c.summary)
  eq(c.facts.take_format, "2 channels, 48000 Hz", "a stereo take")
  eq(c.measures.peak_1:find("%-1[0-9]%.%d dBFS") ~= nil, true, "the tone is in it: " .. c.measures.peak_1)
  eq(c.measures.playback_peak ~= "-120.0 dBFS", true, "and it was played back")
  eq(listing(api.env().data_dir .. "/recordings"), before, "the file is gone")
  eq(api.project_shelved(), false, "the scratch project is closed")
end)

test("the doctor's MIDI check records the port, channel, note and controller that arrived", function()
  load()
  null_backend()
  fresh()
  local sent = {}
  local r = run({
    only = { "midi" },
    auto = function(prompt)
      if sent[prompt.question] then return nil end
      sent[prompt.question] = true
      if prompt.question:find("key", 1, true) then
        paw.midi.inject({ type = "note_on", pitch = 62, velocity = 99, channel = 3, port = "Keys A" })
      else
        paw.midi.inject({ type = "cc", number = 74, value = 0.5, channel = 3, port = "Keys A" })
      end
    end,
  })
  local c = result(r, "midi")
  eq(c.status, "ok", c.summary)
  local joined = table.concat(c.lines, "\n")
  eq(joined:find("“Keys A”, channel 3, note 62, velocity 99", 1, true) ~= nil, true, joined)
  eq(joined:find("controller 74", 1, true) ~= nil, true, joined)
  eq(c.facts.note_port, "Keys A", "the port is a fact")
end)

test("the doctor's MIDI check fails when nothing arrives, without hanging", function()
  load()
  null_backend()
  fresh()
  local r = run({ only = { "midi" } })
  eq(result(r, "midi").status, "fail", "nothing was played")
end)

test("midi.in names the port a message came from", function()
  null_backend()
  fresh()
  local seen
  local handler = paw.on("midi.in", function(event) seen = event end)
  paw.midi.inject({ type = "note_on", pitch = 60, velocity = 100, port = "Keys A" })
  paw.flush()
  paw.off(handler)
  eq(seen.port, "Keys A", "the port")
  eq(seen.pitch, 60, "and the note")
end)

test("a project put aside comes back with its undo tree, and the scratch one is empty", function()
  load()
  null_backend()
  fresh()
  local t = paw.add_part({ name = "Mine" })
  paw.flush()
  api.undo_checkpoint()
  t:add_clip({ start = 0, length = 4, notes = { { pitch = "C4", start = 0, length = 1 } } })
  paw.flush()
  api.undo_checkpoint()
  local before = state()
  api.project_shelve()
  eq(api.project_shelved(), true, "put aside")
  eq(#api.part_list(), 0, "an empty project in its place")
  paw.add_part({ name = "scratch" })
  paw.flush()
  api.project_unshelve()
  paw.flush()
  eq(api.project_shelved(), false, "back")
  eq(state(), before, "exactly as it was, undo tree and all")
  eq(api.part_get(api.part_list()[1]).name, "Mine", "the part")
  api.undo()
  eq(#api.part_list(), 1, "undo goes back to the project's own earlier step, not the scratch one's")
end)

test("a whole doctor run leaves the open project exactly as it was, and nothing behind", function()
  load()
  null_backend()
  fresh()
  local t = paw.add_part({ name = "Keep" })
  t:add_device("synth")
  t:add_clip({
    start = 0,
    length = 4,
    notes = { { pitch = "C4", start = 0, length = 1 }, { pitch = "E4", start = 1, length = 1 } },
  })
  paw.add_part({ name = "Other" })
  paw.flush()
  api.undo_checkpoint()
  paw.transport.seek(6)
  local before = state()
  local recordings = listing(api.env().data_dir .. "/recordings")
  local streamed = paw.opt.media_stream
  paw.opt.media_stream = 2
  local autosave = paw.opt.autosave
  paw.opt.autosave = 30

  local asked, during = {}, nil
  local r = run({
    auto = function(prompt, check)
      during = paw.opt.autosave
      asked[#asked + 1] = prompt.question
      for _, choice in ipairs(prompt.choices) do
        if choice[1] == "y" then return "y" end
      end
      return "d"
    end,
  })
  paw.opt.media_stream = streamed
  eq(during, 0, "autosave was turned off while the doctor ran")
  eq(paw.opt.autosave, 30, "and put back")
  paw.opt.autosave = autosave
  eq(#r.done >= 9, true, "every check ran")
  eq(r.running, false, "the run is over")
  eq(api.project_shelved(), false, "the person's project is back")
  eq(state(), before, "and is exactly as it was: parts, clips, undo history, playhead")
  eq(listing(api.env().data_dir .. "/recordings"), recordings, "the recordings directory is as it was")
  eq(listing(T.scratch .. "/doctor"):find("tmp-", 1, true), nil, "the run's own files are gone")
  eq(listing(T.scratch .. "/doctor"):find("open-project", 1, true), nil, "and the safety copy of the project")
  eq(#asked > 0, true, "the person was asked things")
  eq(paw.transport.recording, false, "not recording")
  eq(paw.transport.playing, false, "not playing")
end)

test("the doctor's dropout check runs, reports its numbers and takes its file away", function()
  load()
  null_backend()
  fresh()
  local streamed = paw.opt.media_stream
  paw.opt.media_stream = 2
  local r = run({ only = { "dropouts" }, unattended = true })
  paw.opt.media_stream = streamed
  local c = result(r, "dropouts")
  eq(c.status ~= "fail", true, c.summary)
  local joined = table.concat(c.lines, "\n")
  eq(joined:find("synth voices alone: %d+ xruns") ~= nil, true, joined)
  eq(
    joined:find("read from the disk: %d+ xruns") ~= nil,
    true,
    "the second run was with a file read from the disk: " .. joined
  )
  eq(c.measures.disk_cpu_max_percent ~= nil, true, "the CPU load")
  eq(listing(T.scratch .. "/doctor"):find("tmp-", 1, true), nil, "the long file is gone")
end, { live = "the check measures dropouts and the processor over seconds of real time" })

test("a doctor check that raises an error fails, and what it added is taken away", function()
  load()
  null_backend()
  fresh()
  local seen
  table.insert(doctor.checks, {
    id = "bad",
    name = "Bad",
    run = function(ctx)
      ctx:part({ name = "left behind" })
      ctx:file(ctx:dir() .. "/x.wav")
      io.open(ctx:dir() .. "/x.wav", "w"):close()
      error("something broke")
    end,
  })
  table.insert(doctor.checks, {
    id = "after",
    name = "After",
    run = function(ctx)
      ctx:scratch()
      seen = #api.part_list()
      return "ok", "looked"
    end,
  })
  local r = run({ only = { "bad", "after" } })
  table.remove(doctor.checks)
  table.remove(doctor.checks)
  eq(result(r, "bad").status, "fail", "the check failed")
  eq(result(r, "bad").summary:find("something broke", 1, true) ~= nil, true, result(r, "bad").summary)
  eq(result(r, "after").status, "ok", "the next one ran")
  eq(seen, 0, "the part the first one added was removed")
end)

test("a doctor check that waits too long is stopped at its limit", function()
  load()
  null_backend()
  fresh()
  table.insert(doctor.checks, { id = "slow", name = "Slow", limit = 0.4, run = function(ctx) ctx:sleep(60000) end })
  local r = run({ only = { "slow" } })
  table.remove(doctor.checks)
  eq(result(r, "slow").status, "fail", "stopped")
  eq(result(r, "slow").summary:find("did not finish", 1, true) ~= nil, true, result(r, "slow").summary)
end)

test("cancelling a doctor run mid-question ends it, cleans up and writes the report", function()
  load()
  null_backend()
  fresh()
  paw.add_part({ name = "Keep" })
  paw.flush()
  api.undo_checkpoint()
  local before = state()
  table.insert(doctor.checks, {
    id = "asks",
    name = "Asks",
    run = function(ctx)
      ctx:part({ name = "temporary" })
      ctx:ask("Will you answer?")
      return "ok", "answered"
    end,
  })
  table.insert(doctor.checks, { id = "never", name = "Never", run = function() return "ok", "ran" end })
  local started = doctor.start({ only = { "asks", "never" } })
  T.advance_until(function() return started.prompt end, "the question to be shown", 5000)
  eq(doctor.answer("x"), false, "a key that is not an answer is not one")
  eq(doctor.cancel(), true, "cancelled")
  T.advance_until(function() return not started.running end, "the run to end", 5000)
  table.remove(doctor.checks)
  table.remove(doctor.checks)
  eq(started.running, false, "ended")
  eq(result(started, "asks").status, "skip", "the question was not answered")
  eq(result(started, "never").summary, "cancelled", "the rest were not run")
  eq(started.report ~= nil, true, "the report was written")
  eq(text(started.report):find("cancelled", 1, true) ~= nil, true, "and says so")
  eq(state(), before, "the project is as it was")
end)

test("the doctor's report holds each check, the machine, and what changed since the last one", function()
  load()
  null_backend()
  fresh()
  local value = "one"
  table.insert(doctor.checks, {
    id = "drifting",
    name = "Drifting",
    unattended = true,
    run = function(ctx)
      ctx:fact("setting", value)
      return value == "one" and "ok" or "warn", "setting is " .. value
    end,
  })
  os.execute("rm -rf '" .. T.scratch .. "/doctor'")
  local first = run({ only = { "system", "drifting" }, unattended = true })
  eq(first.report ~= nil, true, "a report path")
  eq(first.report:find(T.scratch .. "/doctor/", 1, true), 1, "in the doctor's directory")
  local body = text(first.report)
  eq(body:find("## This machine", 1, true) ~= nil, true, "the machine")
  eq(body:find("The sound system", 1, true) ~= nil, true, "the first check")
  eq(body:find("Drifting", 1, true) ~= nil, true, "the second")
  eq(body:find("Changed since", 1, true), nil, "nothing to compare with the first time")
  value = "two"
  os.execute("sleep 1")
  local second = run({ only = { "system", "drifting" }, unattended = true })
  table.remove(doctor.checks)
  local again = text(second.report)
  eq(again:find("## Changed since the report of", 1, true) ~= nil, true, "the second compares")
  eq(again:find("Drifting, setting: one → two", 1, true) ~= nil, true, again)
  eq(again:find("Drifting: ok → WARN", 1, true) ~= nil, true, "and the verdict")
  eq(second.report ~= first.report, true, "a file of its own")
end)

test("the doctor's round trip measures a click and says when the signal is no loop-back", function()
  load()
  local path = T.scratch .. "/click-test.wav"
  local read = paw.api.sound_envelope
  -- A click 1.0123 s into a take that begins 0.004 s after it was played.
  local function make(at)
    doctor.write_sound(path, 48000, 2, 48000 * 3, function(f)
      local t = f / 48000 - at
      return (t >= 0 and t < 0.003) and 0.5 or 0
    end)
    return read(path)
  end
  local found = doctor.round_trip(make(2.0123), 1.0, 0.004)
  near(found.round_trip, 1012.3, 0.1, "the round trip in milliseconds")
  near(found.residual, 1008.3, 0.1, "what the program does not take off yet")
  local none = doctor.round_trip(read(path), 1.0, 0)
  eq(none ~= nil, true, "the same file at another place")
  doctor.write_sound(path, 48000, 2, 48000 * 3, function(f) return 0.3 * math.sin(f / 20) end)
  local tone, problem = doctor.round_trip(read(path), 1.0, 0)
  eq(tone, nil, "a tone is not a click")
  eq(problem:find("not a loop-back", 1, true) ~= nil, true, problem)
  doctor.write_sound(path, 48000, 2, 48000, function() return 0 end)
  local quiet, silence = doctor.round_trip(read(path), 1.0, 0)
  eq(quiet, nil, "silence")
  eq(silence:find("no click came back", 1, true) ~= nil, true, silence)
  os.remove(path)
end)

test("the doctor's page lists the checks and the question being asked", function()
  load()
  null_backend()
  fresh()
  paw.ui.open("doctor", { title = "Doctor", width = 100, height = 30 })
  paw.flush()
  local screen = table.concat(api.ui_snapshot(110, 34), "\n")
  eq(screen:find("The sound system", 1, true) ~= nil, true, "the list is on the page")
  eq(screen:find("Plugins", 1, true) ~= nil, true, "all of it")
  paw.ui.close()
  paw.cmd("doctor")
  eq(paw.ui.focused, "doctor", "with no terminal, the page has the keyboard")
  eq(
    paw.ui.visible("doctor") and require("paw.canvas").titles.doctor,
    "Doctor",
    "docked for a graphical frontend, under its title"
  )
  paw.cmd("doctor.close")
  paw.flush()
  eq(paw.ui.float, nil, "closed")
  eq(paw.ui.focused, "arrange", "the keyboard is back")
  eq(require("paw.canvas").open_views.doctor, nil, "and the window with it")
end)

test("paw doctor runs from the shell without the extension in the configuration", function()
  local out = T.scratch .. "/shell-out.txt"
  local state = T.scratch .. "/shell-state"
  os.execute("mkdir -p '" .. state .. "'")
  local pipe = io.popen("readlink /proc/" .. api.env().pid .. "/exe")
  local binary = pipe:read("*l")
  pipe:close()
  local code = os.execute(
    string.format(
      "XDG_STATE_HOME='%s' XDG_CONFIG_HOME='%s/none' '"
        .. binary
        .. "' doctor --clean --no-plugins --audio null --only system,environment > '%s' 2>/dev/null",
      state,
      state,
      out
    )
  )
  local report = text(out)
  eq(code == 0 or code == true, true, "it exits with 0 when nothing failed")
  eq(report:find("# paw doctor", 1, true) ~= nil, true, "a report on the standard output")
  eq(report:find("The sound system", 1, true) ~= nil, true, "with the checks asked for")
  eq(report:find("Round trip", 1, true), nil, "and none that needs a person")
  eq(listing(state .. "/paw/doctor"):find(".md", 1, true) ~= nil, true, "and one written to the state directory")
end)

test("the doctor's window paints the checks and its buttons answer the question", function()
  load()
  null_backend()
  fresh()
  paw.cmd("doctor")
  local canvas = require("paw.canvas")
  local words = {}
  for _, op in ipairs(canvas.paint("doctor", 900, 560).ops) do
    if op[1] == "t" then words[#words + 1] = op[4] end
  end
  eq(table.concat(words, "\n"):find("The sound system", 1, true) ~= nil, true, "the list")
  eq(table.concat(words, "\n"):find("Run all", 1, true) ~= nil, true, "and the button")
  table.insert(
    doctor.checks,
    { id = "asks", name = "Asks", run = function(ctx) return ctx:ask("Heard it?") == "y" and "ok" or "fail", "" end }
  )
  local started = doctor.start({ only = { "asks" } })
  T.advance_until(function() return started.prompt end, "the question to be shown", 5000)
  local at
  for _, op in ipairs(canvas.paint("doctor", 900, 560).ops) do
    if op[1] == "t" and op[4]:find("yes  (y)", 1, true) then at = op end
  end
  eq(at ~= nil, true, "a button for yes")
  canvas.pointer("doctor", { kind = "down", button = "left", x = at[2] + 2, y = at[3] + 2 })
  T.advance_until(function() return not started.running end, "the run to end", 5000)
  table.remove(doctor.checks)
  eq(result(started, "asks").status, "ok", "a click on the button answered")
  paw.cmd("doctor.close")
end)
