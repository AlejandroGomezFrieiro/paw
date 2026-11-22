-- The host's half of a device written in Lua, run in the device's own Lua
-- state: it loads the script, says what the device is, and runs its blocks
-- over buffers the host owns. Not for scripts to use.
local path, name, dsp_source = ...
local ffi = require("ffi")

package.preload["paw.dsp"] = function() return assert(loadstring(dsp_source, "@paw/dsp.lua"))() end
local dsp = require("paw.dsp")
-- A device may keep modules of its own beside it.
local dir = path:match("^(.*)/[^/]*$") or "."
package.path = dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. package.path

local file, why = io.open(path, "rb")
if not file then error(why, 0) end
local text = file:read("*a")
file:close()
local chunk, err = loadstring(text, "@" .. name)
if not chunk then error(err, 0) end
local dev = chunk()
if type(dev) ~= "table" then error(name .. " must return its device: `return dsp.device { ... }`", 0) end
dev = dsp.device(dev)
if type(dev.process) ~= "function" and type(dev.sample) ~= "function" then
  error(name .. " has neither `process` nor `sample`: nothing to run each block", 0)
end

local H = {}

function H.describe()
  local params = {}
  for i, s in ipairs(dev._specs) do
    params[i] = {
      key = s.key,
      name = s.name,
      min = s.min,
      max = s.max,
      default = s.default,
      unit = s.unit,
      choices = s.choices or {},
    }
  end
  return {
    name = dev.name,
    category = dev.category,
    vendor = dev.vendor,
    midi_effect = dev.midi_effect == true,
    sidechain = dev.sidechain == true,
    params = params,
  }
end

local b, P, T, keys, key_left, key_right

function H.bind(ptr, max_block, max_events, sample_rate)
  b = dsp._block(dev, ptr, max_block, max_events, sample_rate)
  P = ffi.cast("double*", ptr.params)
  T = ffi.cast("paw_transport*", ptr.transport)
  key_left, key_right = ffi.cast("float*", ptr.key_left), ffi.cast("float*", ptr.key_right)
  keys = {}
  for i, s in ipairs(dev._specs) do
    keys[i] = s.key
  end
  if dev.init then dev.init(sample_rate, max_block) end
end

local function per_sample(blk)
  local sample, left, right = dev.sample, blk.left, blk.right
  for i = 0, blk.frames - 1 do
    left[i], right[i] = sample(left[i], right[i], blk)
  end
end

function H.run(frames, nevents, keyed)
  local values = b.params
  for i = 1, #keys do
    values[keys[i]] = P[i - 1]
  end
  b.frames, b.nevents, b.nout = frames, nevents, 0
  b.playing, b.tempo, b.beat, b.seconds = T.playing ~= 0, T.tempo, T.beat, T.seconds
  b.bar, b.bar_start, b.sig_num, b.sig_den = T.bar, T.bar_start, T.sig_num, T.sig_den
  if keyed then
    b.key_left, b.key_right = key_left, key_right
  else
    b.key_left, b.key_right = nil, nil
  end
  local process = dev.process or per_sample
  process(b)
  return b.nout
end

--- A call from a script in the session (`paw.api.device_call`, or a post to
--- every device of this kind): the device's own `dev.call(method, data)`,
--- run between two blocks. A number answers as its text.
function H.call(method, data)
  if type(dev.call) ~= "function" then error("this device has no method `" .. method .. "`", 0) end
  local answer = dev.call(method, data)
  if type(answer) == "number" then return tostring(answer) end
  if answer ~= nil and type(answer) ~= "string" then
    error("dev.call answers with a string, a number or nothing, not a " .. type(answer), 0)
  end
  return answer
end

return H
