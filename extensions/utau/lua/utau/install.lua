-- Installing singers: `paw-utau-engine --install` puts a
-- voicebank archive (zip, rar, 7z, uar), a Vogen singer (.vogeon) or a
-- dependency package (.oudep) into OpenUtau's data folder, as OpenUtau's
-- own window does, finding the singer type and the file name encoding by
-- itself. A voicebank that is already a folder is copied into the
-- `Singers` folder there. The folder is `paw.opt.utau_openutau_dir`, else
-- `$PAW_UTAU_OPENUTAU_DIR`, else `~/.local/share/OpenUtau` (under
-- `$XDG_DATA_HOME`); the engine reads voicebanks from it. After an install
-- the running engine looks for singers again.
local api = paw.api
local engine = require("utau.engine")
local proto = require("utau.proto")

local M = {}

M.KINDS = { zip = true, rar = true, ["7z"] = true, uar = true, vogeon = true, oudep = true }

--- OpenUtau's data folder that singers go to.
function M.target(opts)
  if opts and opts.to then return opts.to end
  local dir = engine.openutau_dir()
  if dir then return dir end
  local data = os.getenv("XDG_DATA_HOME")
  if not data or data == "" then data = (os.getenv("HOME") or ".") .. "/.local/share" end
  return data .. "/OpenUtau"
end

local function is_dir(path)
  local stat = paw.api.fs_stat(path)
  return stat ~= nil and stat.dir
end

--- Ask the running engine to look for singers again.
function M.rescan() engine.send(proto.encode.request_singers(true)) end

--- Install a voicebank archive, package or folder. `opts.to` installs into
--- another OpenUtau folder. Returns `{ { kind, path }, ... }`.
function M.install(path, opts)
  opts = opts or {}
  path = tostring(path):gsub("/+$", "")
  if path:sub(1, 1) ~= "/" then path = (os.getenv("PWD") or ".") .. "/" .. path end
  local target = M.target(opts)
  local installed = {}
  if is_dir(path) then
    local singers = target .. "/Singers"
    local dest = singers .. "/" .. path:match("([^/]+)$")
    if is_dir(dest) then error(path:match("([^/]+)$") .. " is installed already", 0) end
    pcall(paw.api.fs_mkdir, singers)
    local copied, why = pcall(paw.api.fs_copy, path, dest)
    if not copied or not is_dir(dest) then
      error("could not copy " .. path .. " to " .. singers .. ": " .. tostring(why), 0)
    end
    installed[1] = { kind = "folder", path = dest }
  else
    local ext = (path:match("%.([%w]+)$") or ""):lower()
    if not M.KINDS[ext] then error("install a voicebank archive (zip, rar, 7z, uar), .vogeon, .oudep or folder", 0) end
    local f = io.open(path, "rb")
    if not f then error("no such file " .. path, 0) end
    f:close()
    local args = { "--install", path, "--install-to", target }
    if opts.singer_type then
      args[#args + 1] = "--singer-type"
      args[#args + 1] = opts.singer_type
    end
    if opts.encoding then
      args[#args + 1] = "--archive-encoding"
      args[#args + 1] = opts.encoding
    end
    local code, out = engine.tool(args, opts.timeout or 1800)
    for line in out:gmatch("[^\n]+") do
      local kind, where = line:match("^installed: (%S+) (.+)$")
      if kind then installed[#installed + 1] = { kind = kind, path = where } end
    end
    if code ~= 0 then
      local why = out:match("error: ([^\n]+)")
        or out:match("paw%-utau%-engine: ([^\n]+)")
        or ("exit code " .. tostring(code))
      error("could not install " .. path:match("([^/]+)$") .. ": " .. why, 0)
    end
  end
  M.rescan()
  return installed
end

--- The singers in an OpenUtau folder, read from the folders themselves:
--- `{ { name, folder, type, path } }`, by name.
function M.folders(opts)
  local singers = M.target(opts) .. "/Singers"
  local out = {}
  local ok, entries = pcall(api.read_dir, singers)
  for _, e in ipairs(ok and entries or {}) do
    if e.is_dir then
      local dir = singers .. "/" .. e.name
      local name, kind = e.name, "classic"
      local f = io.open(dir .. "/character.txt", "rb")
      if f then
        local text = f:read("*a")
        f:close()
        local n = text:match("[Nn]ame%s*=%s*([^\r\n]+)")
        -- Old banks write character.txt in Shift_JIS; their folder name reads better then.
        if n and not n:find("[\128-\255]") then name = n end
      end
      local y = io.open(dir .. "/character.yaml", "rb")
      if y then
        local text = y:read("*a")
        y:close()
        kind = text:match("singer_type:%s*['\"]?(%w+)") or kind
      end
      local ds = io.open(dir .. "/dsconfig.yaml", "rb")
      if ds then
        ds:close()
        kind = "diffsinger"
      end
      out[#out + 1] = { name = name, folder = e.name, type = kind, path = dir }
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

--- The installed singers: the engine's list when it has sent one, else
--- what the folder holds.
function M.installed(opts)
  local utau = require("utau")
  if not (opts and opts.to) and #utau.singers > 0 then
    local out = {}
    for _, s in ipairs(utau.singers) do
      out[#out + 1] = { name = s.name, id = s.id, type = s.type, path = s.location, author = s.author }
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
  end
  return M.folders(opts)
end

return M
