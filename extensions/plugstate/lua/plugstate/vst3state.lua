-- A VST3 plugin's state as paw keeps it: the component's state, then the
-- controller's, each after its length (32 bits, little-endian).
--
--   local vst3 = require("plugstate.vst3state")
--   local component, controller = vst3.split(raw)
--   raw = vst3.join(component, controller)
local M = {}

--- The component's part and the controller's part of a state, or nil and
--- why. A state without a controller part gives "" for it.
function M.split(raw)
  local size = paw.bytes.u32(raw, 1)
  if not size or 4 + size > #raw then return nil, "not a VST3 state" end
  local csize = paw.bytes.u32(raw, 5 + size)
  return raw:sub(5, 4 + size), csize and raw:sub(9 + size, 8 + size + csize) or ""
end

--- The state of a component's part and a controller's part.
function M.join(component, controller)
  return paw.bytes.le32(#component) .. component .. paw.bytes.le32(#controller) .. controller
end

return M
