-- The checks that come with the doctor, in the order they are listed.
local api = paw.api
local ffi = require("ffi")
local dsp = require("paw.dsp")

local SILENT = 1e-3 -- about -60 dBFS: below that nothing was played

local function db(level) return string.format("%.1f dBFS", math.max(-120, dsp.db(level))) end

--- Write a 16-bit WAV of `frames` frames. `sample(frame, channel)` gives each
--- sample from -1 to 1, with `frame` counting from 0 and `channel` from 1.
local function write_sound(path, rate, channels, frames, sample)
  local buf = ffi.new("float[?]", rate * channels)
  api.sound_write(path, { rate = rate, channels = channels, bits = 16 }, function(at, n)
    n = math.min(n, frames - at)
    if n <= 0 then return nil end
    for i = 0, n - 1 do
      for ch = 1, channels do buf[i * channels + ch - 1] = sample(at + i, ch) end
    end
    return ffi.string(buf, n * channels * 4)
  end)
end

--- The device in a list that has this name.
local function entry(list, name)
  for _, d in ipairs(list or {}) do
    if d.name == name then return d end
  end
end

local function bluetooth(device)
  local text = ((device.name or "") .. " " .. (device.id or "")):lower()
  return text:find("bluez", 1, true) or text:find("bluetooth", 1, true) or text:find("a2dp", 1, true)
end

local function interface(device)
  local text = (device.name or ""):lower()
  return text:find("ur22", 1, true) or text:find("steinberg", 1, true)
end

--- The track's peak over `ms`, read as often as the runner wakes.
local function listen(ctx, track, ms)
  local peak, to = 0, api.now() + ms
  while api.now() < to do
    local l, r = track:meter()
    peak = math.max(peak, l or 0, r or 0)
    ctx:sleep(20)
  end
  return peak
end

--- Record `seconds` on an armed track from the position `from` (in seconds).
--- Returns the clip that came of it, and its file's name.
local function record(ctx, track, from, seconds)
  local started = api.now()
  paw.transport.seek(paw.time.to_beat(from))
  ctx:cleanup(function() ctx:stop() end)
  paw.transport.record()
  local dropped = 0
  while api.now() - started < seconds * 1000 do
    dropped = math.max(dropped, api.engine_get().record_dropped)
    ctx:sleep(50)
  end
  paw.transport.stop()
  local got = ctx:wait_for(function() return #track:clips() > 0 end, 3000)
  if not got then return nil, nil, dropped end
  local clip = track:clips()[1]
  return clip, clip:get().file, dropped
end

--- The input a recording check takes: the first two channels, or the one.
local function first_input()
  local n = api.engine_get().input_channels
  if n >= 2 then return "1/2", 2 end
  if n == 1 then return "1", 1 end
end

return function(M)
  M.write_sound = write_sound
  local checks = M.checks

  -- 1. The sound system ------------------------------------------------------------

  table.insert(checks, {
    id = "system",
    name = "The sound system",
    help = "Nothing from you.",
    unattended = true,
    run = function(ctx)
      local e = api.engine_get()
      local list = paw.audio.devices()
      ctx:fact("backend", e.backend)
      ctx:fact("output", e.device)
      ctx:fact("input", e.input_device)
      ctx:fact("sample_rate", e.sample_rate)
      ctx:fact("outputs_found", #list.outputs)
      ctx:fact("inputs_found", #list.inputs)
      ctx:measure("block", e.block)
      ctx:measure("input_latency_ms", string.format("%.1f", e.input_latency))
      ctx:measure("output_latency_ms", string.format("%.1f", e.output_latency))
      ctx:log(string.format("sound system %s, sample rate %d Hz, block %s frames (asked for %s)", e.backend, e.sample_rate,
        e.block > 0 and e.block or "not known yet", e.buffer_size > 0 and e.buffer_size or "the device's own"))
      ctx:log(string.format("output: %s%s; input: %s", e.device, (e.device_id == "" and e.backend ~= "null") and " (the system's default)" or "", e.input_device))
      ctx:log(string.format("latency reported: input %.1f ms, output %.1f ms", e.input_latency, e.output_latency))
      for _, d in ipairs(list.outputs) do
        ctx:log(string.format("%s output: %s, %d channels, %s Hz", d.name == list.output and "chosen" or "found", d.name, d.channels, d.sample_rate or "?"))
      end
      for _, d in ipairs(list.inputs) do
        ctx:log(string.format("%s input: %s, %d channels, %s Hz", d.name == list.input and "chosen" or "found", d.name, d.channels, d.sample_rate or "?"))
      end
      if e.lost then return "fail", "the audio device was lost: " .. tostring(e.lost.device) end
      if e.backend == "null" then
        ctx:warn("the null backend is running: there is no sound device, nothing can be heard or recorded")
      else
        local chosen = entry(list.outputs, list.output) or {}
        if bluetooth({ name = e.device, id = e.device_id }) or bluetooth(chosen) then
          ctx:warn("the output is a Bluetooth device (" .. e.device .. "): its latency is high, and playing along or recording against it is late. "
            .. "Choose the interface with `:audio.output`, or set it in `init.lua` with `paw.audio.use`.")
        end
        if e.output_latency > 80 then
          ctx:warn(string.format("the output latency is %.0f ms, too much to play along with", e.output_latency))
        end
        local found
        for _, d in ipairs(list.outputs) do
          if interface(d) then found = d end
        end
        if found and found.name ~= list.output then
          ctx:warn("the interface (" .. found.name .. ") is connected but is not the output in use")
        end
        local said = {}
        for _, d in ipairs({ entry(list.outputs, list.output) or {}, entry(list.inputs, list.input) or {}, found or {} }) do
          if d.sample_rate and d.sample_rate ~= e.sample_rate and not said[d.name] then
            said[d.name] = true
            ctx:warn(string.format("%s runs at %d Hz and the program at %d Hz: sound is converted, and PipeWire may retune the device. `:audio.rate` sets one rate for both",
              d.name, d.sample_rate, e.sample_rate))
          end
        end
        if e.input_channels == 0 then ctx:warn("no input is open: nothing can be recorded") end
      end
      local ms = e.block * 1000 / e.sample_rate
      if e.block >= 2048 or ms > 25 then
        ctx:warn(string.format("the block is %d frames (%.0f ms): very large, notes played live will be late. `:audio.buffer 128` asks for less", e.block, ms))
      end
      return "ok", string.format("%s, %s -> %s, %g kHz, %s", e.backend, e.input_device, e.device, e.sample_rate / 1000,
        e.block > 0 and (e.block .. " frames") or "block not known")
    end,
  })

  -- 2. Output ----------------------------------------------------------------------

  --- The test tone: -18 dB, one segment of `tone` seconds each on the left, the
  --- right and both, a third of a second apart.
  function M.tone_file(path, rate, tone)
    local seg, gap = math.floor(tone * rate), math.floor(0.3 * rate)
    local amp, fade = dsp.gain(-18), math.floor(0.02 * rate)
    local frames = 3 * seg + 2 * gap
    write_sound(path, rate, 2, frames, function(f, ch)
      local at = f
      for _, side in ipairs({ { true, false }, { false, true }, { true, true } }) do
        if at >= 0 and at < seg then
          if not side[ch] then return 0 end
          local edge = math.min(at, seg - at, fade) / fade
          return amp * edge * math.sin(2 * math.pi * 440 * at / rate)
        end
        at = at - seg - gap
      end
      return 0
    end)
    return (3 * seg + 2 * gap) / rate
  end

  table.insert(checks, {
    id = "output",
    name = "Output",
    help = "Listen: a gentle tone, left, then right, then both, a second each. Say whether you heard it and where.",
    limit = 180,
    run = function(ctx)
      local e = api.engine_get()
      local path = ctx:file(ctx:dir() .. "/tone.wav")
      local total = paw.limit.unhurried(M.tone_file, path, e.sample_rate, ctx.settings.tone)
      local track = ctx:track({ name = "doctor tone" })
      track:add_clip({ start = 0, file = path })
      if e.backend == "null" then
        ctx:play(0, 0.3)
        return "skip", "the null backend makes no sound to listen to"
      end
      while true do
        ctx:say("playing a tone: left, right, both")
        ctx:play(0, total + 0.3)
        local answer = ctx:ask("Did you hear the tone on the left, then the right, then both?",
          { { "y", "heard it" }, { "n", "did not" }, { "w", "heard it, in the wrong places" }, { "r", "play it again" }, { "s", "skip" } })
        if answer == "y" then
          ctx:fact("heard", "left, right and both")
          return "ok", "the tone was heard on the left, the right and both"
        elseif answer == "w" then
          ctx:fact("heard", "in the wrong places")
          return "fail", "the tone was heard, but not where it should be (the channels may be swapped)"
        elseif answer == "n" then
          local which = ctx:ask("Which did you miss?",
            { { "l", "the left" }, { "r", "the right" }, { "b", "both" }, { "a", "all of it" }, { "s", "skip" } })
          local said = { l = "the left", r = "the right", b = "both", a = "all of it" }
          if which == "skip" or which == "s" then return "fail", "the tone was not heard" end
          ctx:fact("heard", "missed " .. said[which])
          return "fail", "not heard: " .. said[which] .. ". Check the cable, the speaker and `:audio.output`"
        elseif answer ~= "r" then
          return "skip", "not answered"
        end
      end
    end,
  })

  -- 3. Input ----------------------------------------------------------------------

  table.insert(checks, {
    id = "input",
    name = "Input levels",
    help = "Play or speak into each input in turn; the level of each channel is shown. Press d when done.",
    unattended = true,
    limit = 120,
    run = function(ctx)
      local e = api.engine_get()
      if e.input_channels == 0 then return "skip", "no input is open" end
      local n = e.input_channels
      local peaks = {}
      for ch = 1, n do peaks[ch] = 0 end
      local function sample()
        local levels = paw.audio.levels()
        for ch = 1, n do peaks[ch] = math.max(peaks[ch], levels[ch] or 0) end
        ctx.run.meters = levels
        api.ui_redraw()
      end
      ctx.run.meters = {}
      local seconds = ctx.settings.input_seconds
      if ctx:attended() then
        ctx:say("play or speak into each input")
        local answer = ctx:ask("Play or speak into each input; the level of each channel is shown. Press d when done.",
          { { "d", "done" }, { "s", "skip" } }, { timeout = seconds, each = sample, default = "d" })
        if answer == "skip" or answer == "s" then ctx.run.meters = nil return "skip", "skipped" end
      else
        local to = api.now() + math.min(seconds, 3) * 1000
        while api.now() < to do sample() ctx:sleep(40) end
      end
      ctx.run.meters = nil
      local active, silent, clipped = {}, {}, {}
      for ch = 1, n do
        ctx:measure("peak_" .. ch, db(peaks[ch]))
        if peaks[ch] < SILENT then
          silent[#silent + 1] = ch
          ctx:log(string.format("channel %d stayed silent (peak %s)", ch, db(peaks[ch])))
        else
          active[#active + 1] = ch
          ctx:log(string.format("channel %d: peak %s", ch, db(peaks[ch])))
          if peaks[ch] >= 0.99 then clipped[#clipped + 1] = ch end
        end
      end
      ctx:fact("channels", n)
      ctx:fact("silent_channels", #silent > 0 and table.concat(silent, ",") or "none")
      if #clipped > 0 then ctx:warn("channel " .. table.concat(clipped, ", ") .. " reached full scale: turn the input gain down") end
      if #active == 0 then
        return ctx:attended() and "fail" or "warn", "nothing arrived on any of the " .. n .. " channels"
      end
      local text = string.format("signal on channel %s", table.concat(active, ", "))
      if #silent > 0 then text = text .. "; silent: channel " .. table.concat(silent, ", ") end
      return "ok", text
    end,
  })

  -- 4. Round trip ------------------------------------------------------------------

  --- A click: a few milliseconds of a 2 kHz tone that dies away, in both channels.
  local function click_file(path, rate)
    local frames = math.floor(0.2 * rate)
    write_sound(path, rate, 2, frames, function(f)
      local t = f / rate
      return t < 0.005 and 0.5 * math.sin(2 * math.pi * 2000 * t) * (1 - t / 0.005) or 0
    end)
  end

  --- What a recording says of the round trip. `info` is the recorded file read
  --- by `paw.api.sound_envelope`, `click_at` the second of the take the
  --- click was played at,
  --- `applied` the seconds the program already takes off the start of a take.
  --- Gives `{ round_trip, residual }` in milliseconds, or nil and why.
  function M.round_trip(info, click_at, applied)
    local peak = 0
    for _, p in ipairs(info.peaks) do peak = math.max(peak, p) end
    if peak < 0.01 then return nil, "no click came back (the loudest sample was " .. db(peak) .. ")" end
    local onset = info.onset(peak * 0.2)
    if onset < click_at - 0.05 then
      return nil, string.format("the signal was there %.2f s before the click was played: this is not a loop-back, but a tone or noise", click_at - onset)
    end
    local trip = (onset - click_at) * 1000
    return { round_trip = trip, residual = trip - applied * 1000 }
  end

  table.insert(checks, {
    id = "roundtrip",
    name = "Round trip latency",
    help = "Needs a cable from an output of the interface to an input (or a microphone that hears the speakers, with the volume low). Measures the delay of a click and offers to set the recording offset.",
    limit = 180,
    run = function(ctx)
      local e = api.engine_get()
      local spec = first_input()
      if not spec then return "skip", "no input is open" end
      if ctx:ask("Is an output connected to the input (a cable, or a microphone near the speakers, volume low)? The click is loud.",
        { { "y", "yes, measure" }, { "s", "skip" } }) ~= "y" then
        return "skip", "no loop-back to measure with"
      end
      local path = ctx:file(ctx:dir() .. "/click.wav")
      click_file(path, e.sample_rate)
      local rec_from, click_at = 2, 1
      local click = ctx:track({ name = "doctor click" })
      click:add_clip({ start = paw.time.to_beat(rec_from + click_at), file = path })
      local capture = ctx:track({ name = "doctor capture", volume = -120 })
      -- Armed, a track is heard: a loop-back must not hear itself.
      capture.mute = true
      capture.input = spec
      capture.armed = true
      local trips, residuals = {}, {}
      for run = 1, ctx.settings.round_trips do
        ctx:say(string.format("measuring %d of %d", run, ctx.settings.round_trips))
        local clip, file = record(ctx, capture, rec_from, click_at + 1.2)
        if not clip then return "fail", "nothing was recorded" end
        ctx:file(file)
        local ok, info = pcall(api.sound_envelope, file)
        if not ok then return "fail", "the take cannot be read: " .. tostring(info) end
        local applied = clip:get().offset or 0
        local found, problem = M.round_trip(info, click_at, applied)
        clip:remove()
        os.remove(file)
        if not found then return "fail", problem end
        trips[#trips + 1], residuals[#residuals + 1] = found.round_trip, found.residual
        ctx:log(string.format("measurement %d: %.2f ms (%.2f ms left after what the program takes off)", run, found.round_trip, found.residual))
      end
      table.sort(trips)
      table.sort(residuals)
      local trip, residual = trips[math.ceil(#trips / 2)], residuals[math.ceil(#residuals / 2)]
      local spread = trips[#trips] - trips[1]
      ctx:measure("round_trip_ms", string.format("%.2f", trip))
      ctx:measure("spread_ms", string.format("%.2f", spread))
      local now = paw.transport.record_offset or 0
      local wanted = now + residual
      ctx:fact("record_offset_ms", string.format("%.1f", now))
      ctx:log(string.format("the recording offset is %.1f ms; %.1f ms would put a take where it was played", now, wanted))
      if spread > 2 then ctx:warn(string.format("the measurements differ by %.1f ms: something else is using the device, or the loop is not steady", spread)) end
      if math.abs(residual) >= 1 then
        local set = ctx:ask(string.format("Set the recording offset to %.1f ms (now %.1f)?", wanted, now))
        if set == "y" then
          paw.transport.record_offset = wanted
          ctx:fact("record_offset_ms", string.format("%.1f", wanted))
          ctx:log(string.format("set for this session; to keep it, put `paw.transport.record_offset = %.1f` in init.lua", wanted))
        end
      end
      return "ok", string.format("round trip %.1f ms; the offset should be %.1f ms (it is %.1f)", trip, wanted, now)
    end,
  })

  -- 5. Dropouts --------------------------------------------------------------------

  --- Tracks that play a lot of synth voices: chords of six notes each beat, a
  --- chorus and a reverb on every track.
  local function heavy_song(ctx, tracks, beats)
    for i = 1, tracks do
      local track = ctx:track({ name = "doctor voices " .. i })
      track:add_device("synth", { release = 0.5 })
      track:add_device("chorus")
      track:add_device("reverb")
      local notes = {}
      for beat = 0, beats - 1 do
        for k = 0, 5 do
          notes[#notes + 1] = { pitch = 36 + i * 2 + k * 4, start = beat, length = 1.5, velocity = 80 }
        end
      end
      track:add_clip({ start = 0, length = beats, notes = notes })
    end
  end

  local function counters()
    local e = api.engine_get()
    return { xruns = e.xruns, late = e.late_blocks, midi = e.midi_dropped }
  end

  --- Play from the start for `seconds` and say what went wrong meanwhile.
  local function phase(ctx, label, seconds)
    ctx:say(label)
    api.engine_reset_stats()
    local before = counters()
    local cpu_max, cpu_sum, count, next_look = 0, 0, 0, 0
    ctx:play(0, seconds, function()
      if api.now() < next_look then return end
      next_look = api.now() + 250
      local cpu = api.engine_get().cpu
      cpu_max, cpu_sum, count = math.max(cpu_max, cpu), cpu_sum + cpu, count + 1
    end)
    local e = api.engine_get()
    local after = counters()
    return {
      xruns = after.xruns - before.xruns, late = after.late - before.late, midi = after.midi - before.midi,
      cpu_max = cpu_max, cpu_mean = count > 0 and cpu_sum / count or 0,
      p99 = e.blocks.p99, worst = e.blocks.max, budget = e.blocks.budget,
    }
  end

  local function report_phase(ctx, key, label, r)
    ctx:log(string.format("%s: %d xruns, %d late plugin blocks, %d MIDI events dropped; CPU %.0f%% on average, %.0f%% at most; "
      .. "a block took %.2f ms at the 99th percentile and %.2f ms at worst, of %.2f ms available",
      label, r.xruns, r.late, r.midi, r.cpu_mean * 100, r.cpu_max * 100, r.p99, r.worst, r.budget))
    ctx:measure(key .. "_xruns", r.xruns)
    ctx:measure(key .. "_late_blocks", r.late)
    ctx:measure(key .. "_cpu_max_percent", string.format("%.0f", r.cpu_max * 100))
  end

  table.insert(checks, {
    id = "dropouts",
    name = "Dropouts",
    help = "Nothing from you. Plays a song of many synth voices for twenty seconds, then the same with a long sound file read from the disk, and counts the dropouts.",
    unattended = true,
    limit = function(s) return 4 * s.seconds + 240 end,
    run = function(ctx)
      local e = api.engine_get()
      local seconds = ctx.settings.seconds
      heavy_song(ctx, ctx.settings.voices, math.ceil(seconds * 2 * 2) + 4)
      local one = phase(ctx, "playing many voices", seconds)
      report_phase(ctx, "voices", "synth voices alone", one)

      -- A file past `media_stream` megabytes, once decoded, is read from the
      -- disk while it plays. Written here, a quiet tone, as long as it takes.
      local streamed = tonumber(paw.opt.media_stream) or 64
      local length = streamed > 0 and math.ceil(streamed * 1e6 / (8 * e.sample_rate) * 1.15) + 5 or 30
      local path = ctx:file(ctx:dir() .. "/long.wav")
      ctx:say(string.format("writing a sound file of %d s", length))
      paw.limit.unhurried(write_sound, path, e.sample_rate, 2, length * e.sample_rate, function(f)
        return 0.1 * math.sin(2 * math.pi * 220 * f / e.sample_rate)
      end)
      local disk = ctx:track({ name = "doctor disk" })
      ctx:say("bringing the file in")
      disk:add_clip({ start = 0, file = path })
      local on_disk
      for _, m in ipairs(paw.media.list()) do
        if m.path == path then on_disk = m.on_disk end
      end
      local two = phase(ctx, "playing many voices and a file from the disk", seconds)
      report_phase(ctx, "disk", on_disk and "with a file read from the disk" or "with a file held in memory", two)
      if not on_disk then
        ctx:log("the file was held in memory, not read from the disk (paw.opt.media_stream is " .. streamed .. "): the second run says nothing about disk reads")
      end
      ctx:fact("media_stream_mb", streamed)
      ctx:fact("voices", ctx.settings.voices)

      local total = one.xruns + one.late + two.xruns + two.late
      if two.xruns + two.late > one.xruns + one.late then
        ctx:warn("reading from the disk added dropouts: " .. (two.xruns + two.late - one.xruns - one.late))
      end
      local text = string.format("%d xruns and %d late blocks in all; CPU at most %.0f%%", one.xruns + two.xruns, one.late + two.late,
        math.max(one.cpu_max, two.cpu_max) * 100)
      if one.xruns + two.xruns >= 10 or math.max(one.cpu_max, two.cpu_max) > 0.95 then return "fail", text end
      if total > 0 then ctx:warn("there were dropouts: a larger block (`:audio.buffer 256`) may help") end
      return "ok", text
    end,
  })

  -- 6. MIDI in ---------------------------------------------------------------------

  table.insert(checks, {
    id = "midi",
    name = "MIDI input",
    help = "Press a key on your controller, then move a knob or fader. Which port, channel, note and controller arrived is recorded.",
    unattended = true,
    limit = 150,
    run = function(ctx)
      local ports = paw.midi.inputs()
      local names = {}
      for _, p in ipairs(ports) do
        names[#names + 1] = p.name
        ctx:log(string.format("port %s%s%s", p.name, p.open and "" or " (not open)", p.own and " (the program's own)" or ""))
      end
      ctx:fact("ports", #names > 0 and table.concat(names, ", ") or "none")
      if #ports == 0 then
        return ctx:attended() and "fail" or "warn", "no MIDI input ports: is the controller connected? (`:midi.select` may have left it out)"
      end
      if not ctx:attended() then return "ok", #ports .. (#ports == 1 and " port: " or " ports: ") .. table.concat(names, ", ") end

      local seen = { note = nil, cc = nil, count = 0 }
      local handler = paw.on("midi.in", function(event)
        seen.count = seen.count + 1
        if event.type == "note_on" and not seen.note then seen.note = event end
        if event.type == "cc" and not seen.cc then seen.cc = event end
      end)
      ctx:cleanup(function() paw.off(handler) end)
      local wait = ctx.settings.wait_seconds
      local function which(event)
        return string.format("port %s, channel %s", event.port and ("“" .. event.port .. "”") or "unknown", event.channel or "?")
      end

      ctx:say("press a key on the controller")
      ctx:ask("Press a key on your controller.", { { "s", "skip" } },
        { timeout = wait, done = function() return seen.note ~= nil end, default = "timeout" })
      if seen.note then
        ctx:log(string.format("a key arrived: %s, note %d, velocity %s", which(seen.note), seen.note.pitch, seen.note.velocity or "?"))
        ctx:fact("note_port", seen.note.port or "unknown")
      else
        ctx:log("no key was pressed in " .. wait .. " s")
      end
      ctx:ask("Now move a knob or a fader.", { { "s", "skip" } },
        { timeout = wait, done = function() return seen.cc ~= nil end, default = "timeout" })
      if seen.cc then
        ctx:log(string.format("a control arrived: %s, controller %s, value %.2f", which(seen.cc), seen.cc.number or "?", seen.cc.value or 0))
        ctx:fact("cc_port", seen.cc.port or "unknown")
      else
        ctx:log("no knob was moved in " .. wait .. " s")
      end
      if seen.note and seen.cc then return "ok", string.format("a key (note %d) and a control (%s) arrived", seen.note.pitch, tostring(seen.cc.number)) end
      if seen.note then return "warn", "a key arrived; no control was moved" end
      if seen.cc then return "warn", "a control arrived; no key was pressed" end
      return seen.count > 0 and "warn" or "fail", seen.count > 0 and "only other messages arrived" or "nothing arrived from any port in " .. wait .. " s"
    end,
  })

  -- 7. Recording -------------------------------------------------------------------

  table.insert(checks, {
    id = "recording",
    name = "Recording",
    help = "Play or speak into the input for four seconds while it records; then it is played back, and you say whether you heard it.",
    unattended = true,
    limit = 120,
    run = function(ctx)
      local spec = first_input()
      if not spec then return "skip", "no input is open" end
      local e = api.engine_get()
      local seconds = ctx.settings.record_seconds
      local track = ctx:track({ name = "doctor recording" })
      track.input = spec
      track.mute = true
      track.armed = true
      ctx:say(string.format("recording %d s from input %s: play or speak now", seconds, spec))
      local clip, file, dropped = record(ctx, track, 0, seconds)
      if not clip then return "fail", "no take came of the recording" end
      ctx:file(file)
      local ok, info = pcall(api.sound_envelope, file)
      if not ok then return "fail", "the take cannot be read: " .. tostring(info) end
      track.armed = false
      local peaks = {}
      for ch, p in ipairs(info.peaks) do
        peaks[#peaks + 1] = db(p)
        ctx:measure("peak_" .. ch, db(p))
      end
      local longest = 0
      for _, p in ipairs(info.peaks) do longest = math.max(longest, p) end
      ctx:log(string.format("recorded %.1f s, %d channel(s) at %d Hz; peak %s", info.frames / info.rate, info.channels, info.rate, table.concat(peaks, ", ")))
      ctx:fact("input", spec)
      ctx:fact("take_format", string.format("%d channels, %d Hz", info.channels, info.rate))
      if dropped > 0 then ctx:warn(dropped .. " frames of the take were lost to a slow disk") end
      if math.abs(info.frames / info.rate - seconds) > 1 then
        ctx:warn(string.format("the take is %.1f s long, not about %d s", info.frames / info.rate, seconds))
      end

      ctx:say("playing the take back")
      track.mute = false
      local played = 0
      ctx:play(0, seconds, function()
        local l, r = track:meter()
        played = math.max(played, l or 0, r or 0)
      end)
      ctx:measure("playback_peak", db(played))
      ctx:log("played back at " .. db(played))
      if played < SILENT and longest >= SILENT then ctx:warn("the take has sound in it, but nothing was heard at the track's meter on playback") end
      local heard
      if ctx:attended() and e.backend ~= "null" and longest >= SILENT then
        heard = ctx:ask("Did you hear the recording played back?")
        ctx:log("heard on playback: " .. (heard == "y" and "yes" or heard == "n" and "no" or "not answered"))
        if heard == "n" then return "fail", "the take has sound, but it was not heard on playback: check the output" end
      end
      if longest < SILENT then
        return ctx:attended() and "fail" or "warn", "the take is silent (peak " .. db(longest) .. "): nothing arrived on input " .. spec
      end
      return "ok", string.format("%.1f s from input %s, peak %s", info.frames / info.rate, spec, table.concat(peaks, ", "))
    end,
  })

  -- 8. Plugins ---------------------------------------------------------------------

  --- Plugins whose name or kind has `fragment` in it, instruments first.
  local function find_plugin(types, fragment)
    local wanted, found = fragment:lower(), nil
    for _, t in ipairs(types) do
      if t.format ~= "builtin" and ((t.name or ""):lower():find(wanted, 1, true) or t.kind:lower():find(wanted, 1, true)) then
        if not found or (t.category == "instrument" and found.category ~= "instrument") then found = t end
      end
    end
    return found
  end

  local function try_plugin(ctx, t)
    local track = ctx:track({ name = "doctor " .. t.name })
    local device = track:add_device(t.kind)
    ctx:say("waiting for " .. t.name .. " to load")
    ctx:wait_for(function() return device.status ~= "loading" end, 50000)
    if device.status ~= "running" then
      return "failed", t.name .. " did not start (" .. tostring(device.status) .. (device.stopped and (": " .. tostring(device.stopped)) or "") .. ")"
    end
    local function play_notes()
      local peak = 0
      for _, pitch in ipairs({ 36, 38, 42, 48, 60 }) do
        track:note_on(pitch, 110)
        peak = math.max(peak, listen(ctx, track, 200))
        track:note_off(pitch)
        peak = math.max(peak, listen(ctx, track, ctx.settings.plugin_seconds * 1000 / 5))
      end
      return peak
    end
    ctx:say("sending " .. t.name .. " a few notes")
    local peak = play_notes()
    if peak < 1e-4 and ctx:attended() and device.editor == "closed" then
      -- Some instruments make no sound until their own window has been open.
      local answer = ctx:ask(t.name .. " is silent. Some plugins make no sound until their editor has been opened once. Open it?")
      if answer == "y" then
        device:open_editor()
        ctx:ask("The editor is open. Press y when it has finished loading (load a sound there if it needs one).", { { "y", "try again" }, { "s", "skip" } },
          { timeout = 90 })
        peak = play_notes()
        if peak >= 1e-4 then ctx:log(t.name .. " sounded once its editor had been opened") end
      end
    end
    return peak >= 1e-4 and "sound" or "silent", peak
  end

  table.insert(checks, {
    id = "plugins",
    name = "Plugins",
    help = "Nothing from you, unless a plugin is silent: then it offers to open its editor. Plugins named in `paw.opt.doctor_plugins` are loaded and played.",
    unattended = true,
    limit = function(s) return 120 + 70 * #s.plugins end,
    run = function(ctx)
      local types = api.device_types()
      local counts, order = {}, {}
      for _, t in ipairs(types) do
        if not counts[t.format] then order[#order + 1] = t.format end
        counts[t.format] = (counts[t.format] or 0) + 1
      end
      table.sort(order)
      local found = 0
      for _, format in ipairs(order) do
        ctx:log(string.format("%s: %d", format, counts[format]))
        ctx:fact("count_" .. format, counts[format])
        if format ~= "builtin" then found = found + counts[format] end
      end
      local notes = {}
      for _, line in ipairs(api.log_get()) do
        local note = tostring(line):match("plugin scan: (.*)")
        if note then notes[#notes + 1] = note end
      end
      for _, note in ipairs(notes) do ctx:log("scan: " .. note) end
      ctx:fact("scan_notes", #notes)
      if found == 0 then
        ctx:warn("no CLAP, LV2 or VST3 plugin was found (plugins not scanned with --no-plugins? look in ~/.vst3, ~/.clap, ~/.lv2, or CLAP_PATH, LV2_PATH, VST3_PATH)")
      end
      if #notes > 0 then ctx:warn(#notes .. " scan note(s) about files that could not be used: see above, and `:plugins.rescan`") end

      local silent, failed = {}, {}
      for _, fragment in ipairs(ctx.settings.plugins) do
        local t = find_plugin(types, fragment)
        if not t then
          failed[#failed + 1] = fragment
          ctx:log(string.format("“%s”: no plugin has that in its name (%d found)", fragment, found))
          ctx:fact("plugin " .. fragment, "not installed")
        else
          local verdict, detail = try_plugin(ctx, t)
          if verdict == "sound" then
            ctx:log(string.format("%s (%s): sound, peak %s", t.name, t.format, db(detail)))
          elseif verdict == "silent" then
            silent[#silent + 1] = t.name
            ctx:warn(string.format("%s (%s) made no sound for the notes it was sent. Some plugins need their editor opened once before they sound (`ge` on its track), "
              .. "or a sound loaded in it; an effect makes none", t.name, t.format))
          else
            failed[#failed + 1] = t.name
            ctx:log(detail)
          end
          ctx:fact("plugin " .. fragment, verdict)
        end
      end
      local summary = string.format("%d plugins found (%s)", found, (function()
        local parts = {}
        for _, format in ipairs(order) do if format ~= "builtin" then parts[#parts + 1] = format .. " " .. counts[format] end end
        return #parts > 0 and table.concat(parts, ", ") or "none"
      end)())
      if #ctx.settings.plugins > 0 then
        summary = summary .. string.format("; of %d tried, %d silent, %d failed", #ctx.settings.plugins, #silent, #failed)
      end
      if #failed > 0 then return "fail", summary end
      return "ok", summary
    end,
  })

  -- 9. The environment ----------------------------------------------------------------

  table.insert(checks, {
    id = "environment",
    name = "The environment",
    help = "Nothing from you.",
    unattended = true,
    run = function(ctx)
      local e = api.engine_get()
      local env = api.env()
      -- What the program itself sees, after it has put right a display
      -- name that is older than the display (`repair_display_env`).
      local display, wayland, auth = os.getenv("DISPLAY"), os.getenv("WAYLAND_DISPLAY"), os.getenv("XAUTHORITY")
      ctx:fact("DISPLAY", display or "unset")
      ctx:fact("WAYLAND_DISPLAY", wayland or "unset")
      ctx:fact("XAUTHORITY", auth or "unset")
      ctx:log(string.format("DISPLAY=%s WAYLAND_DISPLAY=%s XAUTHORITY=%s", display or "unset", wayland or "unset", auth or "unset"))
      if display then
        local n = display:match("^:(%d+)")
        if n and not api.fs_exists("/tmp/.X11-unix/X" .. n) then
          ctx:warn("DISPLAY is " .. display .. " but there is no X socket for it: plugin editors cannot open")
        end
        if auth and not api.fs_exists(auth) then ctx:warn("XAUTHORITY names a file that is not there (" .. auth .. "): the display will refuse the program") end
      elseif not wayland then
        ctx:warn("neither DISPLAY nor WAYLAND_DISPLAY is set: plugin windows cannot open")
      end
      if wayland then
        local runtime = os.getenv("XDG_RUNTIME_DIR")
        if runtime and not api.fs_exists(runtime .. "/" .. wayland) then
          ctx:warn("WAYLAND_DISPLAY is " .. wayland .. " but its socket is not in XDG_RUNTIME_DIR")
        end
      end

      local where = env.data_dir .. "/recordings"
      local probe = where
      while probe ~= "/" and not api.fs_exists(probe) do probe = probe:match("^(.*)/[^/]*$") or "/" end
      if probe == "" then probe = "/" end
      local space = select(2, pcall(api.fs_space, probe))
      local free = type(space) == "table" and space.free / 1024 or nil
      local status = "ok"
      if free then
        local gb = free / 1048576
        ctx:log(string.format("%.1f GB free where recordings go (%s)", gb, where))
        ctx:measure("free_disk_gb", string.format("%.1f", gb))
        -- Stereo float at 48 kHz is about 22 MB a minute.
        if gb < 0.5 then status = "fail" ctx:warn(string.format("only %.2f GB free where recordings go", gb))
        elseif gb < 5 then ctx:warn(string.format("%.1f GB free where recordings go: about %d minutes of stereo", gb, math.floor(free / 22000))) end
      else
        ctx:warn("the free space where recordings go could not be read")
      end

      local gdi2m = paw.opt.vinput_gdi2m
      for _, program in ipairs({ "ffmpeg", "gdi2m" }) do
        local path = api.which(program)
        if not path and program == "gdi2m" and type(gdi2m) == "string" and gdi2m ~= "" and api.fs_exists(gdi2m) then path = gdi2m end
        ctx:fact("program_" .. program, path or "missing")
        ctx:log(program .. ": " .. (path or "not found in PATH"))
        if not path then
          ctx:warn(program == "ffmpeg" and "ffmpeg is not on the PATH: sound files that need it cannot be read or written"
            or "gdi2m is not on the PATH: a guitar cannot be heard as MIDI (`extensions/vinput`)")
        end
      end

      ctx:fact("limit_async", api.limit_async == true)
      ctx:fact("threads", e.threads)
      ctx:log(string.format("LuaJIT can stop runaway Lua from outside (limit_async): %s; the engine uses %d threads (asked for %d)",
        tostring(api.limit_async == true), e.threads, e.threads_wanted))
      if api.limit_async ~= true then
        ctx:warn("limit_async is false: this build was made without LUAJIT_ENABLE_CHECKHOOK (`.cargo/config.toml`), so runaway Lua is caught more slowly")
      end
      ctx:measure("leaked", e.leaked)
      ctx:log(string.format("plugin processes stopped: %d; sound files in memory: %d; MIDI open: %s", e.devices_stopped, e.audio_files, tostring(e.midi)))
      if e.devices_stopped > 0 then ctx:warn(e.devices_stopped .. " device(s) have stopped working") end
      return status, string.format("display %s, %s", display or wayland or "none", free and string.format("%.0f GB free", free / 1048576) or "disk unknown")
    end,
  })
end
