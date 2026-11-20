-- Tests for the mix diagnostics, run by tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fresh, scratch = T.test, T.eq, T.near, T.fresh, T.scratch
local api = paw.api

local mixdiag

local function load()
  if not mixdiag then
    paw.ext.load("extensions/mixdiag")
    mixdiag = require("mixdiag")
  end
  mixdiag.clear()
  paw.opt.mixdiag_target = "streaming"
  paw.opt.mixdiag_ignore = ""
  return mixdiag
end

local function rate() return api.engine_get().sample_rate end

--- Write a 16-bit stereo WAV of `seconds`, with `fn(t)` giving left and right.
local function wav(name, seconds, fn)
  local sr = rate()
  local n = math.floor(seconds * sr)
  local out = {}
  local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
  local function u32(v) return u16(v % 65536) .. u16(math.floor(v / 65536)) end
  local function s16(x)
    local v = math.floor(math.max(-1, math.min(1, x)) * 32767 + 0.5)
    if v < 0 then v = v + 65536 end
    return u16(v)
  end
  for i = 0, n - 1 do
    local l, r = fn(i / sr)
    out[#out + 1] = s16(l) .. s16(r)
  end
  local data = table.concat(out)
  local header = "RIFF" .. u32(36 + #data) .. "WAVEfmt " .. u32(16) .. u16(1) .. u16(2) .. u32(sr) .. u32(sr * 4)
    .. u16(4) .. u16(16) .. "data" .. u32(#data)
  local path = scratch .. "/" .. name
  T.write_file(path, header .. data)
  return path
end

local function sine(freq, db)
  local amp = 10 ^ (db / 20)
  return function(t)
    local x = amp * math.sin(2 * math.pi * freq * t)
    return x, x
  end
end

--- A synth track holding notes over a stretch of beats.
local function synth(name, start, length, opts)
  local t = paw.add_track({ name = name, volume = opts and opts.volume or 0 })
  t:add_device("synth", { wave = opts and opts.wave or 0, attack = 0.005, release = 0.05, sustain = 1 })
  t:add_clip({ name = name, start = start, length = length,
    notes = { { pitch = opts and opts.pitch or "A3", start = 0, length = length } } })
  return t
end

local function audio(name, start, path)
  local t = paw.add_track({ name = name })
  t:add_clip({ name = name, start = start, file = path })
  return t
end

local function by_rule(findings, rule)
  local out = {}
  for _, f in ipairs(findings) do
    if f.rule == rule then out[#out + 1] = f end
  end
  return out
end

local function describe(findings)
  local lines = {}
  for _, f in ipairs(findings) do lines[#lines + 1] = f.severity .. " " .. f.rule .. ": " .. mixdiag.format(f) end
  return table.concat(lines, "\n")
end

local function one(findings, rule, pattern)
  local list = by_rule(findings, rule)
  if #list == 0 then error("no `" .. rule .. "` finding among:\n" .. describe(findings), 2) end
  if not pattern then return list[1], list end
  for _, f in ipairs(list) do
    if mixdiag.format(f):find(pattern) then return f, list end
  end
  error(string.format("no `%s` finding mentions %q among:\n%s", rule, pattern, describe(list)), 2)
end

local function none(findings, rule)
  if #by_rule(findings, rule) > 0 then error("unexpected `" .. rule .. "` finding:\n" .. describe(findings), 2) end
end

local function measure(scope)
  paw.flush()
  return mixdiag.analyze(scope or "song", { wait = true, quiet = true })
end

-- Measurement through the API -------------------------------------------------

test("mixdiag: a file of a -23 dBFS 1 kHz sine reads -23 LUFS", function()
  load()
  local path = wav("tone.wav", 12, sine(1000, -23))
  local r = api.measure({ file = path })
  near(r.integrated, -23, 0.1, "integrated")
  near(r.true_peak, -23, 0.1, "true peak")
  near(r.short_term_max, -23, 0.1, "short-term max")
  eq(r.clip_runs, 0, "no clipping")
  near(r.correlation, 1, 1e-3, "mono file")
  eq(#r.series.momentary, 120, "a point every 100 ms")
end)

test("mixdiag: a track's contribution is measured alone", function()
  load()
  fresh()
  paw.project.tempo = 120
  local a = synth("A", 0, 8, { volume = 0 })
  synth("B", 0, 8, { volume = -20, pitch = "E4" })
  paw.flush()
  local both = api.measure({ start = 0, ["end"] = 8 })
  local alone = api.measure({ start = 0, ["end"] = 8, track = a.id })
  local b_alone = api.measure({ start = 0, ["end"] = 8, track = paw.track("B").id })
  eq(alone.track, a.id, "the result says which track")
  near(alone.integrated, both.integrated, 0.2, "A is most of the mix")
  near(alone.integrated - b_alone.integrated, 20, 1, "B alone is 20 dB lower")
  eq(paw.track("B").solo, false, "the project's solos are untouched")
  near(alone.seconds, 4 + 1, 0.01, "8 beats at 120 bpm and a 1 s tail")
end)

-- Findings ------------------------------------------------------------------------

test("mixdiag: a clean mix has no findings", function()
  load()
  fresh()
  paw.project.tempo = 120
  synth("Pad", 0, 16, { volume = -6 })
  paw.opt.mixdiag_target = "none"
  local findings = measure()
  eq(describe(findings), "", "no findings")
  local r = mixdiag.result
  eq(r.integrated ~= nil, true, "it was measured")
  eq(mixdiag.line:find("LUFS") ~= nil, true, "a summary line")
end)

test("mixdiag: meeting EBU R 128 after following the advice", function()
  load()
  fresh()
  paw.project.tempo = 120
  synth("Pad", 0, 16, { volume = 0 })
  paw.opt.mixdiag_target = "ebu"
  local f = one(measure(), "loudness", "EBU R 128")
  eq(f.severity, "error", "a delivery rule")
  local r = mixdiag.result
  -- "lower the master by X dB": do it and measure again.
  paw.master.volume = paw.master.volume + (-23 - r.integrated)
  local after = measure()
  none(after, "loudness")
  none(after, "true_peak")
  near(mixdiag.result.integrated, -23, 0.1, "now at -23 LUFS")
end)

test("mixdiag: clipping, true peak, loudness and a track over full scale", function()
  load()
  fresh()
  paw.project.tempo = 120
  synth("Quiet", 0, 24, { volume = -18 })
  local hot = synth("Hot", 8, 8, { volume = 18, wave = 1 })
  local findings = measure()
  local clip = one(findings, "clip", "clips at bar 3")
  eq(clip.severity, "error", "clipping is an error")
  near(clip.beat, 8, 0.1, "where the hot part starts")
  local over = one(findings, "track_over", "Hot")
  eq(over.track, hot.id, "on the hot track")
  near(over.beat, 8, 0.1, "where it first went over")
  local tp = one(findings, "true_peak", "dBTP")
  eq(tp.track, 0, "on the master")
  one(findings, "loudness", "turns the song down")
end)

test("mixdiag: the findings are diagnostics on their tracks, fixed from the mixer", function()
  load()
  fresh()
  paw.project.tempo = 120
  synth("Quiet", 0, 24, { volume = -18 })
  local hot = synth("Hot", 8, 8, { volume = 18, wave = 1 })
  local findings = measure()
  paw.lsp.settle()
  local over = one(findings, "track_over", "Hot")
  local about = paw.diagnostic.get(paw.address.track(hot.id), { namespace = "mixdiag" })
  eq(#about, 1, "the track over full scale is a diagnostic on the track")
  eq(about[1].message, mixdiag.format(over), "saying what the report says")
  eq(#paw.diagnostic.get(nil, { namespace = "mixdiag" }), #findings, "one for each finding")
  -- The mixer marks the strip, and the fix is offered there.
  paw.ui.show("mixer")
  paw.ui.focus("mixer")
  paw.cursor.set_track(hot.id)
  local screen = table.concat(api.ui_snapshot(140, 50), "\n")
  eq(screen:find(paw.draw.g.warn, 1, true) ~= nil or screen:find(paw.draw.g.error, 1, true) ~= nil, true, "the strip is marked:\n" .. screen)
  api.undo_checkpoint()
  paw.keymap.feed("<leader>ca")
  local state = paw.pick.state()
  eq(state and state.matches[1]:find("Lower Hot by", 1, true) ~= nil, true, "the fix, in the picker")
  paw.keymap.feed("<CR>")
  api.undo_checkpoint()
  near(paw.track(hot.id).volume, 18 - over.lower, 1e-6, "the fader comes down by what the finding says")
  paw.undo()
  eq(paw.track(hot.id).volume, 18, "one undo puts it back")
  paw.ui.hide("mixer")
  paw.ui.focus("arrange")
  mixdiag.clear()
  eq(#paw.diagnostic.get(nil, { namespace = "mixdiag" }), 0, "cleared with the findings")
end)

test("mixdiag: true peak over the ceiling without clipping", function()
  load()
  fresh()
  paw.project.tempo = 120
  audio("Tone", 0, wav("hot.wav", 6, sine(1000, -0.4)))
  local findings = measure()
  none(findings, "clip")
  local f = one(findings, "true_peak", "ceiling")
  near(f.beat, 0, 12, "placed in the song")
  -- Louder than -14 LUFS, so the stricter -2 dBTP applies.
  eq(mixdiag.format(f):find("-2.0 dBTP") ~= nil, true, "Spotify's ceiling for loud masters: " .. mixdiag.format(f))
  paw.opt.mixdiag_target = "none"
  none(measure(), "true_peak")
end)

test("mixdiag: a passage out of phase, and a mix that cancels in mono", function()
  load()
  fresh()
  paw.project.tempo = 120
  synth("Bed", 0, 24, { volume = -12 })
  local flipped = wav("flipped.wav", 3, function(t)
    local x = 0.5 * math.sin(2 * math.pi * 300 * t)
    return x, -x
  end)
  audio("Wide", 10, flipped)
  local f = one(measure(), "phase", "correlation down to %-0.9%d from bar 3")
  near(f.beat, 10, 0.01, "where the flipped part starts")

  fresh()
  audio("Wide", 0, flipped)
  local g = one(measure(), "mono", "cancels completely")
  eq(g.severity, "error", "nothing left in mono")
end)

test("mixdiag: DC offset, infrasonic energy and silence at the ends", function()
  load()
  fresh()
  paw.project.tempo = 120
  audio("Offset", 8, wav("dc.wav", 4, function(t)
    local x = 0.2 * math.sin(2 * math.pi * 200 * t)
    return x + 0.05, x
  end))
  audio("Rumble", 16, wav("rumble.wav", 4, function(t)
    local x = 0.5 * math.sin(2 * math.pi * 12 * t)
    return x, x
  end))
  local tail = paw.add_track({ name = "Late" })
  tail:add_device("synth")
  tail:add_clip({ start = 28, length = 8, notes = {} })   -- an empty clip keeps the song going
  local findings = measure()
  local dc = one(findings, "dc", "left side from bar 3 for 4 s")
  eq(mixdiag.format(dc):find("5.00 %%") ~= nil, true, "5 % offset: " .. mixdiag.format(dc))
  near(dc.beat, 8, 1e-6, "placed where the offset starts")
  eq(#by_rule(findings, "dc"), 1, "only the left side")
  one(findings, "infrasonic", "below 22 Hz")
  local silence = by_rule(findings, "silence")
  eq(#silence, 2, "silence at both ends:\n" .. describe(findings))
  eq(silence[1].message:find("starts with 4.0 s") ~= nil, true, silence[1].message)
  eq(silence[2].message:find("before the end") ~= nil, true, silence[2].message)
  local late = one(findings, "no_sound", "made no sound")
  eq(late.track, tail.id, "the track with an empty clip")
end)

test("mixdiag: things that look forgotten", function()
  load()
  fresh()
  paw.project.tempo = 120
  local a = synth("Lead", 0, 8)
  a:devices()[1].bypass = true
  local b = synth("Pad", 0, 8, { volume = -10 })
  b.mute = true
  local c = synth("Keys", 0, 8, { volume = -10 })
  c:add_clip({ start = 8, length = 4, notes = { { pitch = 60, start = 0 } } }).muted = true
  local lane = c:automate("volume")
  lane:add(0, -6)
  lane:add(4, 0)
  lane.enabled = false
  local findings = measure()
  local forgotten = by_rule(findings, "forgotten")
  local text = describe(forgotten)
  for _, want in ipairs({ "on Lead is bypassed", "Pad is muted", "Keys has 1 muted clip", "volume automation on Keys is switched off" }) do
    eq(text:find(want, 1, true) ~= nil, true, "mentions `" .. want .. "`:\n" .. text)
  end
  -- A bypassed instrument also makes no sound.
  eq(one(findings, "no_sound").track, a.id, "the bypassed instrument's track")
  -- Solo: the measurement only hears soloed tracks.
  c.solo = true
  one(measure(), "forgotten", "soloed")
  -- Rules can be switched off by name.
  paw.opt.mixdiag_ignore = "forgotten, no_sound"
  local quiet = measure()
  none(quiet, "forgotten")
  none(quiet, "no_sound")
end)

test("mixdiag: a silent render, and rules other extensions add", function()
  load()
  fresh()
  local t = synth("Lead", 0, 8)
  t.mute = true
  one(measure(), "silent", "silent")
  mixdiag.rules.always = {
    desc = "a test rule",
    check = function(ctx, add) add({ severity = "hint", message = "hello " .. ctx.range.label, beat = 2 }) end,
  }
  local ok, findings = pcall(measure)
  mixdiag.rules.always = nil
  assert(ok, findings)
  eq(one(findings, "always").message, "hello song", "the added rule ran")
end)

-- Running it ----------------------------------------------------------------------

--- Poll a measurement started without waiting until it is done.
local function settle()
  T.until_(function()
    mixdiag.poll()
    return not mixdiag.job
  end, "the measurement to finish", 60000)
end

test("mixdiag: measuring in the background, the loop and a selection", function()
  load()
  fresh()
  paw.ui.focus("arrange")
  paw.keymap.feed("<Esc><Esc>")
  paw.project.tempo = 120
  synth("Pad", 0, 32, { volume = -6 })
  paw.flush()
  local done
  mixdiag.analyze("song", { quiet = true, done = function(f) done = f end })
  eq(mixdiag.job ~= nil, true, "running")
  eq(type(mixdiag.job.progress), "number", "with progress")
  settle()
  eq(type(done), "table", "the callback got the findings")
  near(mixdiag.result.seconds, 16 + 1, 0.01, "the whole song")
  eq(mixdiag.result.elapsed < 10, true, "measured quickly")

  paw.transport.loop_start, paw.transport.loop_end = 8, 16
  paw.cmd("mix.analyze", { "loop" })
  settle()
  eq(mixdiag.result.start, 8, "the loop's start")
  near(mixdiag.result.seconds, 4 + 1, 0.01, "the loop's length")
  eq(mixdiag.range_measured.label, "loop", "labelled")

  -- In visual mode <leader>xa measures the selection.
  paw.opt.grid = 1
  paw.cursor.set_track(paw.track("Pad"))
  paw.cursor.set_beat(4)
  paw.keymap.feed("v3l<leader>xa")
  eq(paw.keymap.mode, "n", "back to normal mode")
  settle()
  eq(mixdiag.range_measured.label, "selection", "the selection")
  eq(mixdiag.result.start, 4, "from the selection's start")
  near(mixdiag.result["end"], 7, 1e-9, "to its end")

  -- A measurement can be cancelled.
  mixdiag.analyze("song", { quiet = true })
  eq(mixdiag.cancel(), true, "cancelled")
  eq(mixdiag.job, nil, "nothing running")
  mixdiag.clear()
end)

--- A project with findings at known places: clipping from beat 8 (bar 3) on
--- the Hot track, a passage out of phase at beat 20 (bar 6), silence from
--- beat 26 and a muted clip at beat 28 on Keys.
local function findings_at_known_places()
  load()
  fresh()
  paw.ui.focus("arrange")
  paw.keymap.feed("<Esc><Esc>")
  paw.project.tempo = 120
  paw.opt.mixdiag_target = "none"
  local hot = synth("Hot", 8, 4, { volume = 18, wave = 1 })
  audio("Wide", 20, wav("flipped2.wav", 3, function(t)
    local x = 0.5 * math.sin(2 * math.pi * 300 * t)
    return x, -x
  end))
  local keys = synth("Keys", 0, 4, { volume = -20 })
  keys:add_clip({ start = 28, length = 4, notes = { { pitch = 60, start = 0 } } }).muted = true
  measure()
  return hot, keys
end

test("mixdiag: the findings are diagnostics: ]d and [d go from one to the next", function()
  local hot, keys = findings_at_known_places()
  local placed = {}
  for _, f in ipairs(mixdiag.findings) do
    if f.beat then placed[#placed + 1] = f end
  end
  eq(#placed >= 3, true, "findings with places:\n" .. describe(mixdiag.findings))
  paw.cursor.set_track(keys)
  paw.cursor.set_beat(2)
  T.keys("]d")
  near(paw.cursor.beat, 8, 0.01, "]d goes to the clipping on the master")
  eq(paw.cursor.track_id(), keys.id, "which leaves the cursor's track alone")
  eq(paw.ui.message.text:find("clips at bar 3", 1, true) ~= nil, true, "its message is shown: " .. paw.ui.message.text)
  T.keys("]d")
  near(paw.cursor.beat, 8, 0.1, "then to the track that went over, in the same block")
  eq(paw.cursor.track_id(), hot.id, "on that track")
  paw.cursor.set_beat(12)
  T.keys("]d")
  near(paw.cursor.beat, 20, 0.01, "the passage out of phase")
  T.keys("]d")
  near(paw.cursor.beat, 26, 0.1, "the silence after the last sound")
  T.keys("]d")
  near(paw.cursor.beat, 28, 1e-6, "the muted clip")
  eq(paw.cursor.track_id(), keys.id, "on its track")
  T.keys("2[d")
  near(paw.cursor.beat, 20, 0.01, "2[d goes back two")
  T.keys("[d")
  eq(paw.cursor.beat < 19, true, "a count goes further: " .. paw.cursor.beat .. "\n" .. describe(placed))
  -- Past the last finding it wraps to the first.
  paw.cursor.set_beat(40)
  T.keys("]d")
  eq(paw.cursor.beat, placed[1].beat, "wraps to the first")
  -- <C-o> comes back from a jump.
  paw.cursor.set_beat(12)
  T.keys("]d")
  T.keys("<C-o>")
  eq(paw.cursor.beat, 12, "<C-o> returns")
  mixdiag.clear()
end)

test("mixdiag: the list of findings, in a picker or in its own view", function()
  findings_at_known_places()
  local had = paw.pick
  -- Without a picker: a list of its own.
  paw.pick = nil
  paw.cursor.set_beat(0)
  T.keys("<leader>xx")
  eq(paw.ui.float and paw.ui.float.name, "mixdiag", "the list is open")
  local screen = table.concat(api.ui_snapshot(140, 40), "\n")
  eq(screen:find("clips at bar 3", 1, true) ~= nil, true, "it shows the clipping")
  eq(screen:find("error", 1, true) ~= nil, true, "with its severity")
  local view = require("mixdiag.view").list_view
  local wanted
  for i, item in ipairs(view.items) do
    if item.finding.rule == "phase" then wanted = i end
  end
  for _ = 1, wanted - 1 do paw.keymap.feed("j") end
  paw.keymap.feed("<CR>")
  eq(paw.ui.float, nil, "Enter closes it")
  near(paw.cursor.beat, 20, 0.01, "and goes to the finding")
  -- With a picker, the list goes to it.
  local spec
  paw.pick = function(s) spec = s end
  mixdiag.list()
  eq(spec.title, "Mix", "picker title")
  eq(#spec.items, #mixdiag.findings, "an item per finding")
  local item
  for _, it in ipairs(spec.items) do
    if it.finding.rule == "clip" then item = it end
  end
  eq(item.text:find("^error") ~= nil, true, "text starts with the severity: " .. item.text)
  near(item.beat, 8, 0.1, "the item has a beat")
  paw.cursor.set_beat(30)
  spec.on_choose(item)
  near(paw.cursor.beat, 8, 0.1, "choosing goes there")
  paw.pick = had
  mixdiag.clear()
end)

--- What a window of the report shows, as one string of its runs.
local function report_text()
  local painted = paw.canvas.paint("mixdiag", 1200, 400, { cell = { w = 10, h = 20 }, fresh = true })
  local text = {}
  for _, op in ipairs(painted.ops) do if op[1] == "m" then text[#text + 1] = op[6] end end
  return table.concat(text, " ")
end

test("mixdiag: the report in a window of its own measures, reads and goes to findings", function()
  load()
  fresh()
  paw.ui.focus("arrange")
  paw.keymap.feed("<Esc><Esc>")
  paw.canvas.open_view("mixdiag")
  eq(report_text():find("nothing measured yet", 1, true) ~= nil, true, "before a measurement")
  synth("Hot", 8, 4, { volume = 18, wave = 1 })
  paw.flush()
  paw.canvas.key("mixdiag", "a")
  eq(mixdiag.job ~= nil, true, "a measures the song")
  eq(report_text():find("measuring the song", 1, true) ~= nil, true, "and the report says so")
  settle()
  local text = report_text()
  eq(text:find("LUFS", 1, true) ~= nil and text:find("dBTP", 1, true) ~= nil, true, "the numbers: " .. text)
  eq(text:find("clips at bar 3", 1, true) ~= nil, true, "and the findings")
  -- The findings with a place are in a band under the window's ruler.
  local flag
  for _, e in ipairs(paw.frontend.band_state().entries) do
    if e.name:match("^clip") then flag = e end
  end
  eq(flag ~= nil and flag.color == paw.canvas.palette.error, true, "the clipping is flagged in the colour of an error")
  paw.cursor.set_beat(0)
  paw.frontend.act.band(flag.band, flag.index)
  near(paw.cursor.beat, 8, 0.01, "a click on it goes there")
  -- In the report, Enter goes to the finding chosen and leaves it open.
  paw.cursor.set_beat(0)
  local items = mixdiag.items()
  for i, item in ipairs(items) do
    if item.finding.rule == "clip" then
      for _ = 1, i - 1 do paw.canvas.key("mixdiag", "j") end
    end
  end
  paw.canvas.key("mixdiag", "<CR>")
  near(paw.cursor.beat, 8, 0.01, "Enter goes to the finding")
  eq(paw.canvas.open_views.mixdiag ~= nil, true, "and the report stays open")
  paw.canvas.close("mixdiag")
  mixdiag.clear()
  flag = nil
  for _, e in ipairs(paw.frontend.band_state().entries) do
    if e.name:match("^clip") then flag = e end
  end
  eq(flag, nil, "cleared, the flags go")
end)

test("mixdiag: marks above the arrange view, and the summary", function()
  findings_at_known_places()
  paw.opt.zoom = 2
  local screen = api.ui_snapshot(120, 20)
  eq(screen[1]:find("mix", 1, true) ~= nil, true, "the strip is docked on top: " .. screen[1])
  eq(screen[1]:find("E", 1, true) ~= nil, true, "with a mark for the clipping: " .. screen[1])
  T.keys("<leader>xs")
  eq(paw.ui.message.text:find("LUFS", 1, true) ~= nil, true, "summary: " .. paw.ui.message.text)
  T.keys("<leader>xt")
  eq(paw.opt.mixdiag_target ~= "none", true, "<leader>xt goes to the next target")
  paw.opt.mixdiag_target = "streaming"
  mixdiag.clear()
  screen = api.ui_snapshot(120, 20)
  eq(screen[1]:find("^ mix") == nil, true, "the strip goes with the findings")
end)

test("mixdiag: plugins are measured on the worker thread as a render plays them", function()
  load()
  local ran = 0
  for _, format in ipairs({ "clap", "lv2", "vst3" }) do
    local kind
    for _, info in ipairs(paw.device_types()) do
      if not kind and info.format == format and info.name:find("Limiter Stereo$") then kind = info.kind end
    end
    if kind then
      fresh()
      paw.project.tempo = 120
      local t = synth("Lead", 0, 8, { volume = 6, wave = 1 })
      t:add_device(kind)
      paw.flush()
      local rendered = T.render({ tail = 1, bits = 32 })
      local r = api.measure({ start = 0, ["end"] = 8, tail = 1 })
      near(r.sample_peak, 20 * math.log10(rendered.peak), 0.05, format .. ": the same peak as a render")
      eq(r.integrated ~= nil, true, format .. ": measured")
      ran = ran + 1
    end
  end
  if ran == 0 then return "skipped: test plugins not found" end
end)

test("mixdiag: the painted report draws meters, a spectrum and the findings, which can be clicked", function()
  load()
  fresh()
  paw.ui.focus("arrange")
  paw.keymap.feed("<Esc><Esc>")
  local offered = {}
  for _, entry in ipairs(paw.canvas.openable()) do offered[entry.name] = true end
  eq(offered.mixdiag_paint, true, "the window offers the painted report")
  eq(offered.mixdiag, nil, "instead of the terminal's")
  paw.canvas.open("mixdiag_paint")
  local function drawn()
    local ops = paw.canvas.paint("mixdiag_paint", 1000, 560, { fresh = true }).ops
    local texts = {}
    for _, op in ipairs(ops) do if op[1] == "t" then texts[#texts + 1] = op[4] end end
    return ops, table.concat(texts, "\n")
  end
  eq(select(2, drawn()):find("nothing measured yet", 1, true) ~= nil, true, "before a measurement")
  synth("Hot", 8, 4, { volume = 18, wave = 1 })
  paw.flush()
  paw.canvas.key("mixdiag_paint", "a")
  eq(mixdiag.job ~= nil, true, "a measures the song")
  settle()
  local ops, text = drawn()
  for _, word in ipairs({ "integrated", "true peak", "Spectrum", "Findings", "Hot" }) do
    eq(text:find(word, 1, true) ~= nil, true, "the report says " .. word)
  end
  local shape, outline, meters = 0, 0, 0
  for _, op in ipairs(ops) do
    if op[1] == "p" and op[5] ~= "" then shape = shape + 1 end
    if op[1] == "p" and op[3] == paw.canvas.palette.select and op[4] == 2 then outline = outline + 1 end
    if op[1] == "r" and op[6] == paw.canvas.palette.meter_clip then meters = meters + 1 end
  end
  eq(shape, 1, "the spectrum is one filled shape")
  eq(outline >= 1, true, "with its outline")
  eq(meters >= 1, true, "the hot track's meter is in the clipping colour")
  -- A click chooses a finding, and a click on the chosen one goes there.
  local wanted
  for i, item in ipairs(mixdiag.items()) do
    if item.finding.rule == "clip" then wanted = i end
  end
  local paint = paw.ui.views.mixdiag_paint
  local function row_y() return paint.findings_top + paint.top + (wanted - 1 - paint.first) * 22 + 11 end
  paw.cursor.set_beat(0)
  paw.canvas.pointer("mixdiag_paint", { kind = "down", x = paint.right_x + 20, y = row_y(), button = "left" })
  eq(require("mixdiag.view").list_view.at, wanted, "a click chooses the finding")
  eq(paw.cursor.beat, 0, "without going there")
  paw.canvas.pointer("mixdiag_paint", { kind = "down", x = paint.right_x + 20, y = row_y(), button = "left" })
  near(paw.cursor.beat, 8, 0.01, "the second click goes there")
  paw.canvas.pointer("mixdiag_paint", { kind = "hover", x = paint.right_x + 20, y = row_y() })
  eq(select(2, drawn()):find("clips", 1, true) ~= nil, true, "resting on it shows it in full")
  paw.canvas.key("mixdiag_paint", "q")
  eq(paw.canvas.open_views.mixdiag_paint, nil, "q closes the window")
  mixdiag.clear()
end)

test("mixdiag: <leader>xp opens the painted report in pixels where the terminal shows them, and the report in cells where it does not", function()
  load()
  fresh()
  local function closed()
    paw.keymap.feed("<Esc><Esc>")
    while paw.ui.float do paw.ui.close() end
    paw.ui.hide("mixdiag_paint")
    paw.ui.focus("arrange")
  end
  T.after(function()
    api.ui_caps_set({ graphics = false, cell = { w = 0, h = 0 } })
    paw.opt.graphics = true
    closed()
  end)
  for _, on in ipairs({ true, false }) do
    closed()
    api.ui_caps_set({ graphics = true, cell = { w = 10, h = 20 }, pixel_mouse = true, fg = "#cdd6f4" })
    paw.opt.graphics = on
    paw.keymap.feed("<leader>xp")
    eq(paw.ui.focused, "mixdiag_paint", "the key opens it, graphics " .. tostring(on))
    local lines = api.ui_snapshot(100, 30)
    local surface = (paw.ui.rects.surfaces or {})[1]
    if on then
      eq(surface and surface.name, "mixdiag_paint", "pixels: it keeps a surface")
    else
      eq(surface, nil, "cells: no surface")
      eq(table.concat(lines, "\n"):find("nothing measured yet", 1, true) ~= nil, true, "the report is drawn in cells")
    end
  end
end)
