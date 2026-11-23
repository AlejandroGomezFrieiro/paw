-- The state of a VST3 plugin as a `.vstpreset` file, which is how a
-- DAWproject file keeps it, and as paw keeps it (u32 size, component state,
-- u32 size, controller state).
--
-- A .vstpreset is: "VST3", version (int32 = 1), the class id as 32 ASCII
-- characters, the offset of the chunk list (int64); then the data; then the
-- chunk list: "List", a count (int32) and for each chunk an id ("Comp" or
-- "Cont"), its offset and its size (int64 each). All little-endian.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local b64 = paw.bytes
local M = {}

local function u64(n: integer): string
  return b64.le32(n % 4294967296) .. b64.le32(n // 4294967296)
end

local function r64(data: string, at: integer): integer
  return (b64.u32(data, at) or 0) + (b64.u32(data, at + 4) or 0) * 4294967296
end

--- A .vstpreset from paw's state of a plugin, with its class id when known.
function M.preset(state: string, class?: string): string
  local comp, ctrl = b64.vst3_split(state)
  comp, ctrl = comp or "", ctrl or ""
  local cid = (class or ""):upper():gsub("[^%x]", "")
  cid = (cid .. string.rep("0", 32)):sub(1, 32)
  local head = 4 + 4 + 32 + 8
  local list_at = head + #comp + #ctrl
  local list = "List" .. b64.le32(2) .. "Comp" .. u64(head) .. u64(#comp) .. "Cont" .. u64(head + #comp) .. u64(#ctrl)
  return "VST3" .. b64.le32(1) .. cid .. u64(list_at) .. comp .. ctrl .. list
end

--- paw's state and the class id from a .vstpreset, or nil and why.
function M.state(preset: string): string, string
  if preset:sub(1, 4) ~= "VST3" then
    return nil, "not a .vstpreset file"
  end
  local class = preset:sub(9, 40)
  local list_at = r64(preset, 41) + 1
  if preset:sub(list_at, list_at + 3) ~= "List" then
    return nil, "the .vstpreset has no chunk list"
  end
  local count = b64.u32(preset, list_at + 4) or 0
  local chunks: {string: string} = {}
  for i = 0, count - 1 do
    local at = list_at + 8 + i * 20
    local id = preset:sub(at, at + 3)
    local offset, size = r64(preset, at + 4), r64(preset, at + 12)
    chunks[id] = preset:sub(offset + 1, offset + size)
  end
  if not chunks.Comp then
    return nil, "the .vstpreset has no component state"
  end
  local ctrl = chunks.Cont or ""
  return b64.vst3_join(chunks.Comp, ctrl), class
end

return M
