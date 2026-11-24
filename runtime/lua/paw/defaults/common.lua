-- What more than one part of the default commands and keys uses
-- (paw/defaults/*.lua).
local util = paw.util
local cursor = paw.cursor
local map = paw.keymap.set

local M = {}

function M.need_part()
  local part = cursor.part()
  if not part then paw.notify("no part selected", "warn") end
  return part
end

--- The parts of the selection in the arrange view, or else the part of
--- the cursor: ids, empty when there is no part.
function M.chosen_parts()
  local selection = paw.keymap.selection()
  if selection and selection.view == "arrange" then
    local rows, out = paw.groups.rows(), {}
    for row = math.max(1, selection.r0), selection.r1 do
      if rows[row] then out[#out + 1] = rows[row] end
    end
    if #out > 0 then return out end
  end
  local id = cursor.part_id()
  return id and { id } or {}
end

function M.need_clip()
  local clip = cursor.clip()
  if not clip then paw.notify("no clip under the cursor", "warn") end
  return clip
end

--- Whether a path is a folder that is not a project: it opens as a list
--- of its files to edit (`paw.files`), not as a project.
function M.plain_folder(path)
  return path ~= nil
    and path ~= ""
    and paw.files.is_dir(path)
    and not paw.project.is_folder(path)
    and not paw.nest.song_of(paw.files.path(path))
end

--- Pan as it is shown, L30 C R25, read back into -100..100.
function M.read_pan(text)
  text = text:upper()
  if text == "C" then return 0 end
  local side, n = text:match("^([LR])%s*([%d%.]+)")
  if side then return (side == "L" and -1 or 1) * tonumber(n) end
  return tonumber((text:match("^([%+%-]?[%d%.]+)")))
end

--- Read a parameter's value as it is shown: a choice by name, or a number.
function M.param_reader(p)
  return function(text)
    if #p.choices > 0 then
      local low = text:lower()
      for i, choice in ipairs(p.choices) do
        if tostring(choice):lower() == low then return i - 1 end
      end
      for i, choice in ipairs(p.choices) do
        if tostring(choice):lower():sub(1, #low) == low then return i - 1 end
      end
    end
    return tonumber((text:match("^([%+%-]?[%d%.]+)")))
  end
end

function M.amap(lhs, rhs, desc, opts) map(lhs, rhs, util.merge({ view = "arrange", desc = desc }, opts)) end

M.motion = { motion = true }

return M
