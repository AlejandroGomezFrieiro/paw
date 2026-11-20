-- Bytes of binary formats: base64 (the form plugin states cross `paw.api`
-- in, and the form of binary blocks in REAPER and DAWproject files) and
-- little-endian numbers. Base64 runs in Rust (`paw.api.base64_*`), as
-- states can be megabytes.
--
--   paw.bytes.base64(data)       -- text, padded with `=`
--   paw.bytes.unbase64(text)     -- the bytes; raises when it is not base64
--   paw.bytes.u32(data, at)      -- the number at `at` (from 1), nil past the end
--   paw.bytes.le32(n)            -- four bytes
--   paw.bytes.vst3_split(state)  -- a VST3 state's component and controller parts
local api = require("paw.api")

local M = {}

--- Base64 text of bytes, padded with `=`.
M.base64 = api.base64_encode

--- The bytes of base64 text (either alphabet, padded or not, spaces and
--- line ends passed over). Raises when the text is not base64.
function M.unbase64(text)
  local bytes, why = api.base64_decode(text)
  if not bytes then error("not base64: " .. why, 2) end
  return bytes
end

--- The unsigned 16-bit little-endian number at `at` (from 1), or nil past the end.
function M.u16(data, at)
  local a, b = data:byte(at, at + 1)
  if not b then return nil end
  return a + b * 256
end

--- The unsigned 32-bit little-endian number at `at` (from 1), or nil past the end.
function M.u32(data, at)
  local a, b, c, d = data:byte(at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

--- Two bytes of an unsigned 16-bit number, little-endian.
function M.le16(n)
  n = n % 65536
  return string.char(n % 256, math.floor(n / 256))
end

--- Four bytes of an unsigned 32-bit number, little-endian.
function M.le32(n)
  n = n % 4294967296
  return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

--- The component's part and the controller's part of a VST3 plugin's
--- state as paw keeps it (each after its length, 32 bits, little-endian),
--- or nil and why. A state without a controller part gives "" for it.
function M.vst3_split(raw)
  local size = M.u32(raw, 1)
  if not size or 4 + size > #raw then return nil, "not a VST3 state" end
  local csize = M.u32(raw, 5 + size)
  return raw:sub(5, 4 + size), csize and raw:sub(9 + size, 8 + size + csize) or ""
end

--- A VST3 plugin's state as paw keeps it, from its component's part and
--- its controller's part.
function M.vst3_join(component, controller)
  return M.le32(#component) .. component .. M.le32(#controller) .. controller
end

return M
