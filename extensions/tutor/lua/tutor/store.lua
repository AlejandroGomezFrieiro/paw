-- Where the tutor keeps its files, and reading and writing the progress file.
--
-- Everything goes in one directory of the tutor's own: the option
-- `tutor_dir` when it is set, else `$XDG_STATE_HOME/paw/tutor`
-- (`~/.local/state/paw/tutor`). Nothing is ever written to a project the
-- learner has open, nor to their configuration.
local M = {}

--- The tutor's directory, made if it is not there yet.
function M.dir()
  local dir = paw.opt.tutor_dir
  if not dir or dir == "" then
    local base = os.getenv("XDG_STATE_HOME")
    if not base or base == "" then base = (os.getenv("HOME") or ".") .. "/.local/state" end
    dir = base .. "/paw/tutor"
  end
  return dir
end

function M.ensure(dir)
  pcall(paw.api.fs_mkdir, dir)
  return dir
end

--- The file of a lesson's practice project: the `project.toml` of its
--- folder.
function M.practice(id)
  return M.ensure(M.dir() .. "/practice") .. "/" .. id .. "/project.toml"
end

function M.progress_path()
  return M.dir() .. "/progress.lua"
end

-- Plain Lua data written as a Lua literal, read back in an empty environment.
local function encode(value, indent)
  indent = indent or ""
  local kind = type(value)
  if kind == "string" then return string.format("%q", value) end
  if kind == "number" or kind == "boolean" then return tostring(value) end
  if kind ~= "table" then return "nil" end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local inner, parts = indent .. "  ", {}
  for _, k in ipairs(keys) do
    local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or "[" .. encode(k) .. "]"
    parts[#parts + 1] = inner .. key .. " = " .. encode(value[k], inner)
  end
  if #parts == 0 then return "{}" end
  return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
end
M.encode = encode

--- The progress file as a table: { current = { lesson, step }, lessons = { [id] = { done, steps } } }.
function M.load()
  local empty = { version = 1, lessons = {} }
  local file = io.open(M.progress_path(), "r")
  if not file then return empty end
  local text = file:read("*a")
  file:close()
  local chunk = loadstring(text, "=tutor progress")
  if not chunk then return empty end
  setfenv(chunk, {})
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return empty end
  data.lessons = type(data.lessons) == "table" and data.lessons or {}
  return data
end

function M.save(data)
  M.ensure(M.dir())
  local path = M.progress_path()
  local tmp = path .. ".tmp"
  local file = assert(io.open(tmp, "w"))
  file:write("-- The paw tutor's progress. Delete this file to start again.\nreturn ", encode(data), "\n")
  file:close()
  assert(os.rename(tmp, path))
end

M.exists = paw.api.fs_exists

return M
