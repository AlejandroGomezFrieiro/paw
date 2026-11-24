-- The built-in mixing effects as scripts and frontends see them: their
-- parameters as text, sliders on a log scale, readings, and rendering
-- through them in a project.
local T = ...
local advance = T.advance
local test, eq, near, fresh, render = T.test, T.eq, T.near, T.fresh, T.render
local paw = require("paw")
local api = paw.api

local function info(kind, key)
  for _, d in ipairs(api.device_types()) do
    if d.kind == kind then
      for _, p in ipairs(d.params) do
        if p.key == key then return p end
      end
    end
  end
  error("no " .. kind .. "." .. key)
end

test("devices: values read in their units", function()
  local fmt = paw.params.format
  eq(fmt(info("eq", "b5_freq"), 2500), "2.5 kHz", "kilohertz")
  eq(fmt(info("eq", "b5_freq"), 80), "80 Hz", "hertz")
  eq(fmt(info("eq", "b5_freq"), 12500), "12.5 kHz", "above ten kilohertz")
  eq(fmt(info("eq", "b5_gain"), -18), "-18.0 dB", "decibels with one decimal")
  eq(fmt(info("eq", "b5_q"), 0.71), "0.71", "Q")
  eq(fmt(info("eq", "b5_type"), 3), "Bell", "a choice by name")
end)

test("devices: frequency sliders and keys move on a log scale", function()
  local p = info("eq", "b5_freq")
  near(paw.params.fraction(p, 632.46), 0.5, 0.001, "the middle of 20 Hz to 20 kHz is 632 Hz")
  near(paw.params.from_fraction(p, 0.5), 632.46, 0.1, "and back")
  local up = paw.params.step(p, 1000, 1)
  eq(up > 1060 and up < 1080, true, "a key press is a hundredth of the travel, about 7 %: " .. up)
  local gain = info("eq", "b5_gain")
  near(paw.params.step(gain, 0, 1), 0.5, 1e-9, "a gain moves in round steps")
  eq(paw.params.step(info("eq", "b5_type"), 3, 1), 4, "a choice moves to the next option")
end)

test("devices: the equaliser reports its curve", function()
  fresh()
  local t = paw.add_part()
  local e = t:add_device("eq", { b4_gain = 6, b4_freq = 1000, b4_q = 1 })
  paw.flush()
  local curve = paw.params.read(e, "curve", 64)
  eq(#curve, 64, "as many points as asked for")
  near(curve[1], 0, 0.05, "flat at 20 Hz")
  local most = -100
  for _, v in ipairs(curve) do
    most = math.max(most, v)
  end
  near(most, 6, 0.1, "6 dB at the top of the bell")
  near(paw.params.read(e, "at", 1000)[1], 6, 0.001, "and at one frequency")
  e:set("b4_gain", -3)
  paw.flush()
  near(paw.params.read(e, "at", 1000)[1], -3, 0.001, "following its settings")
end)

test("devices: an equaliser in a part changes the render", function()
  fresh()
  local s = {}
  for i = 1, 48000 do
    s[i] = 0.25 * math.sin(2 * math.pi * 1000 * (i - 1) / 48000)
  end
  local file = T.scratch .. "/sine1k.wav"
  T.write_wav(file, s, s, 48000)
  local t = paw.add_part()
  t:add_clip({ file = file, start = 0, length = 2 })
  near(render({ tail = 0 }).peak, 0.25, 0.002, "a quarter to begin with")
  t:add_device("eq", { b4_gain = 6, b4_freq = 1000 })
  near(render({ tail = 0 }).peak, 0.25 * 10 ^ (6 / 20), 0.005, "6 dB louder through a 6 dB bell")
end)

--- One click in silence, as a file.
local function click(name, level)
  local s = {}
  for i = 1, 48000 do
    s[i] = 0
  end
  s[12001] = level
  return T.write_wav(T.scratch .. "/" .. name .. ".wav", s)
end

--- The samples of a render above a twentieth, as `frame:value`.
local function loud_samples()
  local out = {}
  for i, v in ipairs(T.samples(render({ tail = 0, bits = 16 }))) do
    if math.abs(v) > 0.05 then out[#out + 1] = string.format("%d:%.2f", i - 1, v) end
  end
  return table.concat(out, " ")
end

test("devices: a compressor that looks ahead is lined up with the other parts", function()
  fresh()
  local file = click("click", 0.2)
  local a = paw.add_part({ name = "Ahead" })
  local b = paw.add_part({ name = "Plain" })
  a:add_clip({ file = file, start = 0, length = 2 })
  b:add_clip({ file = file, start = 0, length = 2 })
  eq(loud_samples(), "12000:0.40", "two clicks land on one sample")
  local c = a:add_device("compressor", { lookahead = 5, threshold = 0 })
  paw.flush()
  advance(50)
  near(api.engine_get().latency, 5, 0.01, "the engine knows the compressor is 5 ms late")
  eq(loud_samples(), "12000:0.40", "and holds the other part back to match")
  c:set("lookahead", 2)
  paw.flush()
  advance(50)
  near(api.engine_get().latency, 2, 0.01, "a new look-ahead is a new latency")
  eq(loud_samples(), "12000:0.40", "still together")
  a:add_device("gate", { lookahead = 3, threshold = -60 })
  paw.flush()
  advance(50)
  near(api.engine_get().latency, 5, 0.01, "a gate's look-ahead adds to it")
  eq(loud_samples(), "12000:0.40", "and still together")
end)

test("devices: a compressor's meters and curve are read from scripts", function()
  fresh()
  api.engine_restart({})
  local s = {}
  for i = 1, 96000 do
    s[i] = (i % 100 < 50) and 0.5 or -0.5
  end
  local file = T.write_wav(T.scratch .. "/square.wav", s)
  local t = paw.add_part()
  t:add_clip({ file = file, start = 0, length = 4 })
  local c = t:add_device("compressor", { threshold = -20, ratio = 4, knee = 0 })
  paw.flush()
  local curve = paw.params.read(c, "curve", 61)
  near(curve[61], -20 + 20 / 4, 0.01, "0 dB in comes out 15 dB down at 4:1 from -20 dB")
  near(curve[1], -60, 0.01, "below the threshold nothing changes")
  paw.transport.seek(0)
  paw.transport.play()
  -- Over half a second of sound at 512 frames a block.
  T.next_block(60)
  local m = paw.params.read(c, "meters")
  paw.transport.stop()
  -- A -6 dB square: 14 dB over, 3:1 of it taken off at 4:1 → 10.5 dB of reduction.
  near(m.gr, -10.5, 0.1, "the gain reduction of the last block: " .. tostring(m.gr))
end)

test("devices: the meter and the tuner are read while the song plays", function()
  fresh()
  api.engine_restart({})
  local s = {}
  -- An A at 110 Hz, at -20 dBFS on both sides.
  for i = 1, 48000 * 4 do
    s[i] = 0.1 * math.sin(2 * math.pi * 110 * (i - 1) / 48000)
  end
  local file = T.write_wav(T.scratch .. "/a110.wav", s, s, 48000)
  local t = paw.add_part({ name = "Guitar" })
  t:add_clip({ file = file, start = 0, length = 8 })
  local tuner = t:add_device("tuner")
  local meter = t:add_device("meter")
  paw.flush()
  local quiet = paw.params.read(meter, "meters")
  eq(quiet.integrated, -200, "nothing measured yet reads -200")
  eq(paw.params.read(tuner, "pitch").note, "-", "and the tuner hears nothing")
  paw.transport.seek(0)
  paw.transport.play()
  -- Most of a second of sound at 512 frames a block.
  T.next_block(80)
  local pitch = paw.params.read(tuner, "pitch")
  local m = paw.params.read(meter, "meters")
  paw.transport.stop()
  eq(pitch.note, "A2", "the tuner names the note")
  near(pitch.cents, 0, 1, "in tune")
  eq(pitch.confidence > 0.9, true, "and is sure of it")
  -- -20 dBFS on both sides is -20.7 LUFS at 1 kHz; at 110 Hz the
  -- K-weighting's high-pass takes another 0.98 dB off.
  near(m.momentary, -21.67, 0.1, "momentary loudness")
  near(m.sample_peak, -20, 0.05, "sample peak")
  near(m.correlation, 1, 0.01, "the two sides are the same")
  local spectrum = paw.params.read(meter, "spectrum", 32)
  eq(#spectrum, 32, "a spectrum of as many bands as asked for")
end)

test("devices: every built-in preset names parameters its device has, inside their ranges", function()
  local count = 0
  for _, d in ipairs(api.device_types()) do
    local by_key = {}
    for _, p in ipairs(d.params) do
      by_key[p.key] = p
    end
    for _, preset in ipairs(paw.params.presets(d.kind)) do
      for key, value in pairs(preset.params) do
        local p = by_key[key]
        eq(p ~= nil, true, d.kind .. " preset " .. preset.name .. " sets " .. key)
        local v = paw.params.preset_value(p, value)
        eq(v >= p.min and v <= p.max, true, preset.name .. ": " .. key .. " = " .. tostring(value))
      end
      count = count + 1
    end
  end
  eq(count >= 25, true, "presets for the effects: " .. count)
  fresh()
  local t = paw.add_part()
  local e = t:add_device("delay")
  paw.params.apply(e, "Dotted eighth")
  eq(paw.params.format(e:info().params[4], e:get().params.sync), "1/8.", "a choice set by name")
end)

test("devices: the device panel draws what the effects are doing", function()
  fresh()
  local t = paw.add_part({ name = "Vocal" })
  t:add_device("eq", { b4_gain = 6 })
  t:add_device("compressor")
  t:add_device("tuner")
  t:add_device("meter")
  paw.flush()
  paw.cursor.set_part(t)
  paw.ui.show("devices")
  local screen = table.concat(api.ui_snapshot(140, 160), "\n")
  eq(screen:find("+18 dB", 1, true) ~= nil, true, "the equaliser's curve with its scale")
  eq(screen:find("1k", 1, true) ~= nil, true, "and its frequencies")
  eq(screen:find("GR", 1, true) ~= nil, true, "the compressor's gain reduction")
  eq(screen:find("play a single note", 1, true) ~= nil, true, "the tuner, waiting for a note")
  eq(screen:find("LUFS", 1, true) ~= nil, true, "the meter's loudness")
  paw.ui.hide("devices")
end)

test("devices: :eq, :tuner and :loudness open the effects' windows", function()
  fresh()
  local t = paw.add_part({ name = "Vox" })
  paw.cursor.set_part(t)
  paw.cmd("eq")
  eq(#t:devices(), 1, "a part without an equaliser gets one")
  eq(t:devices()[1]:get().kind, "eq", "an equaliser")
  paw.cmd("eq")
  eq(#t:devices(), 1, "and the second time opens the same one")
  local names = {}
  for _, w in ipairs(paw.canvas.windows()) do
    names[w.name] = w.title
  end
  eq(names.eq_window, "EQ · Vox", "its window is open")
  eq(paw.ui.focused, "devices", "the keyboard stays in the device panel")
  local painted = paw.canvas.paint("eq_window", 900, 420)
  local texts = {}
  for _, op in ipairs(painted.ops) do
    if op[1] == "t" then texts[#texts + 1] = op[4] end
  end
  eq(table.concat(texts, " "):find("1k", 1, true) ~= nil, true, "the grid is painted")
  paw.cmd("tuner")
  eq(t:devices()[2]:get().kind, "tuner", "a tuner is added")
  eq(#paw.canvas.paint("tuner_window", 520, 300).ops > 5, true, "and painted")
  paw.cmd("loudness")
  eq(paw.master:devices()[#paw.master:devices()]:get().kind, "meter", "the master gets a meter")
  eq(#paw.canvas.paint("meter_window", 720, 380).ops > 5, true, "and its window is painted")
  for _, name in ipairs({ "eq_window", "tuner_window", "meter_window" }) do
    paw.canvas.close(name)
  end
end)

test("devices: dragging a band's dot in the EQ window moves the band", function()
  fresh()
  local t = paw.add_part({ name = "Vox" })
  paw.cursor.set_part(t)
  paw.cmd("eq")
  local e = t:devices()[1]
  paw.canvas.paint("eq_window", 900, 420)
  -- Band 4 is a bell at 800 Hz, 0 dB: its dot is where those are drawn.
  local x0, w = 44, 900 - 44 - 16
  local y0, h = 40, 420 - 40 - 28
  local dot_x = x0 + math.log(800 / 20) / math.log(1000) * w
  local dot_y = y0 + h / 2
  paw.canvas.pointer("eq_window", { kind = "down", x = dot_x, y = dot_y, button = 1 })
  local to_x = x0 + math.log(2000 / 20) / math.log(1000) * w
  local to_y = y0 + (1 - (6 + 18) / 36) * h
  paw.canvas.pointer("eq_window", { kind = "move", x = to_x, y = to_y, button = 1 })
  paw.canvas.pointer("eq_window", { kind = "up", x = to_x, y = to_y, button = 1 })
  near(e:get().params.b4_freq, 2000, 1, "the band moved to 2 kHz")
  near(e:get().params.b4_gain, 6, 0.01, "and up to +6 dB")
  paw.canvas.pointer("eq_window", { kind = "wheel", x = to_x, y = to_y, dy = 1 })
  near(e:get().params.b4_q, 1.12, 0.001, "the wheel widens or narrows it")
  paw.canvas.close("eq_window")
end)

test("devices: a synced delay follows a tempo change in the map", function()
  fresh()
  paw.project.tempo = 120
  paw.tempo.set(4, 60)
  -- A click at 4 s: beat 6, after the change to 60 bpm.
  local s = {}
  for i = 1, 48000 * 7 do
    s[i] = 0
  end
  s[48000 * 4 + 1] = 0.5
  local t = paw.add_part()
  t:add_clip({ file = T.write_wav(T.scratch .. "/late-click.wav", s), start = 0, length = 9 })
  local quarter
  for i, name in ipairs(t:add_device("delay"):info().params[4].choices) do
    if name == "1/4" then quarter = i - 1 end
  end
  t:devices()[1]:set({ sync = quarter, mix = 1, feedback = 0 })
  local out = {}
  for i, v in ipairs(T.samples(render({ ["end"] = 9, tail = 0, bits = 16 }))) do
    if math.abs(v) > 0.05 then out[#out + 1] = i - 1 end
  end
  eq(out[1], 192000, "the click")
  eq(
    math.abs(out[#out] - 240000) < 24,
    true,
    "the echo a second later: a quarter at 60, not at 120: " .. table.concat(out, " ")
  )
end)

test("devices: no effect trips the NaN guard at the ends of its ranges", function()
  fresh()
  local said = 0
  local handle = paw.on("device.invalid", function() said = said + 1 end)
  local tone = T.tone("edges", 4)
  for _, d in ipairs(api.device_types()) do
    if d.format == "builtin" and d.category == "effect" then
      for _, which in ipairs({ "min", "max" }) do
        local params = {}
        for _, p in ipairs(d.params) do
          params[p.key] = p[which]
        end
        local dev = tone:add_device(d.kind, params)
        local info = render({ ["end"] = 2, tail = 0 })
        eq(info.nonfinite or 0, 0, d.kind .. " at every " .. which .. " renders finite")
        dev:remove()
      end
    end
  end
  paw.off(handle)
  eq(said, 0, "and nothing was reported invalid")
end)
