-- `require("paw.dsp")`: what a device written in Lua is made with. A device
-- is a file that returns `dsp.device { ... }`: its name, its parameters, and
-- a `process` function given each block of sound. See
-- docs/reference/lua-devices.md.
--
--   local dsp = require("paw.dsp")
--   local dev = dsp.device {
--     name = "Gain",
--     params = { { key = "gain", name = "Gain", min = -60, max = 12, default = 0, unit = "dB" } },
--   }
--   function dev.process(b)
--     local g = dsp.gain(b.params.gain)
--     for i = 0, b.frames - 1 do
--       b.left[i], b.right[i] = b.left[i] * g, b.right[i] * g
--     end
--   end
--   return dev
--
-- Sound is in `ffi` float arrays counted from 0, so loops over it are
-- compiled by LuaJIT. The device runs in a process of its own: a script that
-- fails or hangs stops alone and is shown as stopped.
local ffi = require("ffi")

local M = {}

if not pcall(ffi.typeof, "paw_event") then
  ffi.cdef([[
    typedef struct { int32_t frame, type, channel, key; double value; int32_t from, attr; } paw_event;
    typedef struct { double sample_rate, tempo, beat, seconds, bar_start, bar, sig_num, sig_den, playing; } paw_transport;
    int paw_open(const char *path, int flags) __asm__("open");
    int paw_close(int fd) __asm__("close");
    int64_t paw_lseek(int fd, int64_t offset, int whence) __asm__("lseek");
    void *paw_mmap(void *addr, size_t length, int prot, int flags, int fd, int64_t offset) __asm__("mmap");
    int paw_munmap(void *addr, size_t length) __asm__("munmap");
  ]])
end

-- What an event is: `e.type` is one of these.
M.NOTE_ON = 1 -- e.key, e.value (velocity, 0 to 1), e.channel (1 to 16), e.attr (see M.attr)
M.NOTE_OFF = 2 -- e.key, e.channel
M.CC = 3 -- e.key (the controller's number), e.value (0 to 1), e.channel
M.BEND = 4 -- e.value (-1 to 1, 0 at rest), e.channel
M.PRESSURE = 5 -- channel pressure: e.value (0 to 1), e.channel
M.PROGRAM = 6 -- e.key (the program), e.value (the bank, or -1), e.channel
M.ALL_NOTES_OFF = 7
M.OTHER = 8 -- anything else (a note's own controllers, RPNs): pass it on with b:pass(e)

--- A note-on's MIDI 2.0 attribute as `{ type, data }`, or nil when it has
--- none. `e.attr` holds it as one number, `type * 65536 + data`, 0 for
--- none, so that a device can compare it without making a table:
---   if e.attr ~= 0 then local a = dsp.attr(e) ... end
--- `paw.attr.describe` names it.
function M.attr(e)
  local packed = tonumber(e.attr)
  if packed == 0 then return nil end
  return { type = math.floor(packed / 65536), data = packed % 65536 }
end

-- Numbers -----------------------------------------------------------------------

local exp, log, pow, sin, cos, sqrt, pi = math.exp, math.log, math.pow, math.sin, math.cos, math.sqrt, math.pi
local ln10_20 = log(10) / 20

--- A level in decibels as a gain: `dsp.gain(-6)` is about 0.5. Below
--- -144 dB it is silence.
function M.gain(db)
  if db <= -144 then return 0 end
  return exp(db * ln10_20)
end

--- A gain in decibels: `dsp.db(0.5)` is about -6. Silence is -144.
function M.db(gain)
  gain = gain < 0 and -gain or gain
  if gain < 6.3e-8 then return -144 end
  return log(gain) / ln10_20
end

function M.clamp(x, lo, hi)
  if x < lo then
    return lo
  elseif x > hi then
    return hi
  end
  return x
end

--- A MIDI note number as a frequency in Hz (69 is A at 440).
function M.mtof(note) return 440 * pow(2, (note - 69) / 12) end

--- Equal-power pan: the left and right gains for `pan` from -1 to 1.
function M.pan(pan)
  local a = (M.clamp(pan, -1, 1) + 1) * pi / 4
  return cos(a), sin(a)
end

--- A soft clip: tanh, close enough and cheaper.
function M.saturate(x)
  if x > 3 then
    return 1
  elseif x < -3 then
    return -1
  end
  local x2 = x * x
  return x * (27 + x2) / (27 + 9 * x2)
end

--- A float array of `n` zeros, counted from 0: a delay line, a table.
function M.buffer(n) return ffi.new("float[?]", n) end

local Mapped = {}
Mapped.__index = Mapped

--- Let go of the file now rather than when the map is collected.
function Mapped:close()
  if self.base then
    ffi.C.paw_munmap(ffi.gc(self.base, nil), self.size)
    self.base, self.data, self.n = nil, nil, 0
  end
end

--- A file of 32-bit floats (little-endian, as written on this machine), as a
--- read-only array counted from 0: `m.data[i]` for `i` below `m.n`. The file
--- is mapped, not copied, so devices that map one file share its memory, and
--- it is read in at once: map in `dev.call` or `dev.init`, never in
--- `process`. `m:close()` lets it go; so does collecting `m`. Large data
--- (sound for the device to play) reaches a device this way: the script
--- that sends it writes a file and calls the device with its path.
function M.map(path)
  local C = ffi.C
  local fd = C.paw_open(path, 0)
  if fd < 0 then error("cannot open " .. tostring(path), 2) end
  local size = C.paw_lseek(fd, 0, 2)
  if size <= 0 then
    C.paw_close(fd)
    return setmetatable({ n = 0, size = 0 }, Mapped)
  end
  -- MAP_PRIVATE | MAP_POPULATE: read in now, not on the first touch.
  local base = C.paw_mmap(nil, size, 1, 0x8002, fd, 0)
  C.paw_close(fd)
  if base == ffi.cast("void *", -1) then error("cannot map " .. tostring(path), 2) end
  local m = setmetatable({ size = size, n = tonumber(size) / 4 - (tonumber(size) / 4) % 1 }, Mapped)
  m.base = ffi.gc(base, function(p) C.paw_munmap(p, size) end)
  m.data = ffi.cast("const float *", base)
  return m
end

-- Filters ------------------------------------------------------------------------

local OnePole = {}
OnePole.__index = OnePole

--- A one-pole filter: `f = dsp.onepole(1000, sr)`, then `f:lowpass(x)` or
--- `f:highpass(x)` once a sample. One filter per channel.
function M.onepole(hz, sample_rate)
  local f = setmetatable({ a = 0, z = 0 }, OnePole)
  if hz then f:set(hz, sample_rate) end
  return f
end

function OnePole:set(hz, sample_rate) self.a = exp(-2 * pi * hz / sample_rate) end

function OnePole:lowpass(x)
  local z = x + self.a * (self.z - x)
  self.z = z
  return z
end

function OnePole:highpass(x) return x - self:lowpass(x) end

function OnePole:reset() self.z = 0 end

local Biquad = {}
Biquad.__index = Biquad

--- A biquad filter (the RBJ cookbook's): `f = dsp.biquad("lowpass", 800,
--- 0.7, 0, sr)`, then `f:process(x)` once a sample. Shapes: lowpass,
--- highpass, bandpass, notch, peak, lowshelf, highshelf; `gain_db` is for
--- the last three. One filter per channel.
function M.biquad(shape, hz, q, gain_db, sample_rate)
  local f = setmetatable({ b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, z1 = 0, z2 = 0 }, Biquad)
  if shape then f:set(shape, hz, q, gain_db, sample_rate) end
  return f
end

function Biquad:set(shape, hz, q, gain_db, sample_rate)
  local w = 2 * pi * M.clamp(hz, 1, sample_rate * 0.49) / sample_rate
  local cw, sw = cos(w), sin(w)
  local alpha = sw / (2 * (q > 0 and q or 0.707))
  local A = pow(10, (gain_db or 0) / 40)
  local b0, b1, b2, a0, a1, a2
  if shape == "lowpass" then
    b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
  elseif shape == "highpass" then
    b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
  elseif shape == "bandpass" then
    b0, b1, b2 = alpha, 0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
  elseif shape == "notch" then
    b0, b1, b2 = 1, -2 * cw, 1
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
  elseif shape == "peak" then
    b0, b1, b2 = 1 + alpha * A, -2 * cw, 1 - alpha * A
    a0, a1, a2 = 1 + alpha / A, -2 * cw, 1 - alpha / A
  elseif shape == "lowshelf" or shape == "highshelf" then
    local s = shape == "lowshelf" and 1 or -1
    local r = 2 * sqrt(A) * alpha
    b0 = A * ((A + 1) - s * (A - 1) * cw + r)
    b1 = s * 2 * A * ((A - 1) - s * (A + 1) * cw)
    b2 = A * ((A + 1) - s * (A - 1) * cw - r)
    a0 = (A + 1) + s * (A - 1) * cw + r
    a1 = -s * 2 * ((A - 1) + s * (A + 1) * cw)
    a2 = (A + 1) + s * (A - 1) * cw - r
  else
    error("no biquad shape `" .. tostring(shape) .. "`", 2)
  end
  self.b0, self.b1, self.b2 = b0 / a0, b1 / a0, b2 / a0
  self.a1, self.a2 = a1 / a0, a2 / a0
end

function Biquad:process(x)
  local y = self.b0 * x + self.z1
  self.z1 = self.b1 * x - self.a1 * y + self.z2
  self.z2 = self.b2 * x - self.a2 * y
  return y
end

function Biquad:reset()
  self.z1, self.z2 = 0, 0
end

local Smoother = {}
Smoother.__index = Smoother

--- Glide towards a value instead of jumping, so a parameter moved during a
--- block does not click: `s = dsp.smoother(20, sr)` (milliseconds), then
--- `s:next(target)` once a sample.
function M.smoother(ms, sample_rate)
  local s = setmetatable({ value = nil, a = 0 }, Smoother)
  s.a = exp(-1 / (math.max(ms, 0.01) * 0.001 * sample_rate))
  return s
end

function Smoother:next(target)
  local v = self.value
  if v == nil then
    self.value = target
    return target
  end
  v = target + self.a * (v - target)
  self.value = v
  return v
end

-- The device ---------------------------------------------------------------------

local Block = {}
Block.__index = Block

--- Send an event from this block, at `frame` (0 to b.frames - 1); out of
--- order is fine. `b:note_on(frame, key, velocity, channel)` and the others
--- below are the common ones. `channel` is 1 to 16 (1 when left out). An
--- all-notes-off has no channel and comes in with 0, which it may send back.
--- Any other value is an error, and the device stops with its message.
function Block:send(frame, type, key, value, channel, attr)
  local n = self.nout
  if n >= self.max_events then return end
  local no_channel = type == M.ALL_NOTES_OFF and channel == 0
  if channel ~= nil and not no_channel and not (channel >= 1 and channel <= 16 and channel % 1 == 0) then
    error("a channel is a whole number from 1 to 16, not " .. tostring(channel), 2)
  end
  local e = self.out[n]
  e.frame, e.type, e.key, e.value, e.channel, e.from = frame, type, key or 0, value or 0, channel or 1, 0
  -- (`type` is the event's kind here.) A table is `{ type, data }`.
  if attr and not tonumber(attr) then attr = attr.type * 65536 + (attr.data or 0) end
  e.attr = attr or 0
  self.nout = n + 1
end

--- `attr`, if given, is a MIDI 2.0 attribute: `{ type, data }` or one number as `e.attr` has it.
function Block:note_on(frame, key, velocity, channel, attr) self:send(frame, M.NOTE_ON, key, velocity, channel, attr) end
function Block:note_off(frame, key, channel) self:send(frame, M.NOTE_OFF, key, 0, channel) end
function Block:cc(frame, number, value, channel) self:send(frame, M.CC, number, value, channel) end

--- Send an event that came in on, as it is (at `frame`, if given): a MIDI
--- effect keeps what it does not change with this.
function Block:pass(e, frame)
  local n = self.nout
  if n >= self.max_events then return end
  local o = self.out[n]
  ffi.copy(o, e, ffi.sizeof("paw_event"))
  if frame then o.frame = frame end
  self.nout = n + 1
end

local function param_spec(p, i)
  if type(p) ~= "table" then error("parameter " .. i .. " is not a table", 3) end
  local key = p.key or p[1] or (p.name and p.name:lower():gsub("[^%w]+", "_"))
  if type(key) ~= "string" or key == "" then error("parameter " .. i .. " has no key", 3) end
  -- The words of the kernel's schema of a parameter (`types.ParamSchema`,
  -- as the chain language has them) are read too: `minimum`, `maximum` and
  -- `enum` are `min`, `max` and `choices`, and a `boolean` is a choice of
  -- off and on.
  local choices, default = p.choices or p.enum, p.default
  if p.type == "boolean" then
    choices = choices or { "off", "on" }
    if type(default) == "boolean" then default = default and "on" or "off" end
  elseif p.type ~= nil and p.type ~= "number" and p.type ~= "integer" and p.type ~= "string" then
    error("parameter " .. key .. ": a Lua device has no parameter of the type " .. tostring(p.type), 3)
  end
  local spec = { key = key, name = p.name or key, unit = p.unit or "", choices = choices }
  if choices then
    spec.min, spec.max = 0, #choices - 1
    -- A choice's default may be given by its name or by its number from 1.
    default = default or 1
    if type(default) == "string" then
      for n, c in ipairs(choices) do
        if c == default then default = n end
      end
    end
    spec.default = (tonumber(default) or 1) - 1
  else
    spec.min, spec.max = p.min or p.minimum or 0, p.max or p.maximum or 1
    spec.default = default or spec.min
  end
  if spec.max < spec.min then error("parameter " .. key .. ": its max is below its min", 3) end
  return spec
end

--- Declare a device. Fields:
---   name      what the device is called (else the file's name)
---   category  "effect" (the default) or "instrument"
---   vendor    who made it, shown beside the name
---   params    a list of `{ key =, name =, min =, max =, default =, unit = }`,
---             or `{ key =, choices = { "Soft", "Hard" }, default = "Soft" }`;
---             the words of `types.ParamSchema` (`type`, `minimum`,
---             `maximum`, `enum`) are read too
---   midi_effect  true for a device whose events replace those that came in
---             (an arpeggiator); otherwise what came in is passed on with
---             whatever the device sends added to it
---   sidechain true to listen to another part (b.key_left, b.key_right)
--- Functions put on the device:
---   dev.init(sample_rate, max_block)  once, before the first block
---   dev.process(b)   each block: b.left, b.right (float arrays from 0),
---                    b.frames, b.params (values by key), b.events and
---                    b.nevents, b.sample_rate, and the transport
---                    (b.playing, b.tempo, b.beat, b.seconds, b.bar,
---                    b.bar_start, b.sig_num, b.sig_den)
---   dev.sample(l, r, b)  instead of process: one frame, returning the new l, r
function M.device(def)
  if type(def) ~= "table" then error("dsp.device takes a table", 2) end
  if def._specs then return def end
  local specs = {}
  for i, p in ipairs(def.params or {}) do
    specs[i] = param_spec(p, i)
  end
  local seen = {}
  for _, s in ipairs(specs) do
    if seen[s.key] then error("two parameters have the key " .. s.key, 2) end
    seen[s.key] = true
  end
  def._specs = specs
  def.category = def.category or "effect"
  if def.category ~= "effect" and def.category ~= "instrument" then
    error('category must be "effect" or "instrument", not ' .. tostring(def.category), 2)
  end
  return def
end

--- For the host: the block a device is given, over the host's buffers.
function M._block(dev, ptr, max_block, max_events, sample_rate)
  local b = setmetatable({
    left = ffi.cast("float*", ptr.left),
    right = ffi.cast("float*", ptr.right),
    key_left = nil,
    key_right = nil,
    events = ffi.cast("paw_event*", ptr.events_in),
    out = ffi.cast("paw_event*", ptr.events_out),
    frames = 0,
    nevents = 0,
    nout = 0,
    max_block = max_block,
    max_events = max_events,
    sample_rate = sample_rate,
    params = {},
    playing = false,
    tempo = 120,
    beat = 0,
    seconds = 0,
    bar = 0,
    bar_start = 0,
    sig_num = 4,
    sig_den = 4,
  }, Block)
  for _, s in ipairs(dev._specs) do
    b.params[s.key] = s.default
  end
  dev.values = b.params
  dev.sample_rate = sample_rate
  return b
end

return M
