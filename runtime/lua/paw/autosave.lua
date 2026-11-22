-- Safety copies. Plugins run inside this program, and one that crashes takes
-- the session with it, so every so often the project is written to a file
-- of its own, beside nothing the user saved. A copy is removed when the
-- project is saved or closed with nothing unsaved; one left behind by a
-- session that ended badly is offered again at the next start.
--
--   paw.opt.autosave = 60     -- seconds between copies; 0 turns them off
--   :recover                  -- list what was left behind, and open one
local api = paw.api
local M = {}

local env = api.env()
--- Where the copies go.
M.dir = env.state_dir .. "/recovery"

local copied -- the project's edit count when it was last copied or saved
local timer

--- The file this session's copy of the project goes in: one per project
--- file, or per session for a project that has no file yet.
function M.file()
  local path = api.project_get("path")
  if not path then return string.format("%s/untitled-%d.json", M.dir, env.pid) end
  -- The same project always gets the same name, whatever directory it is in.
  local hash = 5381
  for i = 1, #path do
    hash = (hash * 33 + path:byte(i)) % 4294967296
  end
  local name = path:match("([^/]+)%.[^./]*$") or path:match("([^/]+)$") or "project"
  return string.format("%s/%s-%08x.json", M.dir, name:gsub("[^%w%-_]", "_"), hash)
end

--- Write a copy now, if the project changed after the last copy (or with
--- `force`, as when a take starts). Returns the written file, or nil.
function M.copy(force)
  local p = api.project_get()
  if not force and (not paw.project.unsaved() or p.edits == copied) then return nil end
  -- Something being tried in a picker is not work to keep: the next copy has it if it stays.
  if not force and api.trial_active() then return nil end
  local file = M.file()
  api.project_backup(file, { path = p.path, name = p.name, time = os.time(), pid = env.pid })
  copied = p.edits
  return file
end

local function forget(file) os.remove(file or M.file()) end

local function alive(pid)
  local stat = io.open("/proc/" .. tostring(pid) .. "/stat")
  if stat then stat:close() end
  return stat ~= nil
end

--- The copies left by sessions that are gone: { file, path, name, time }.
function M.left_behind()
  local out = {}
  for _, entry in ipairs(api.read_dir(M.dir)) do
    local file = M.dir .. "/" .. entry.name
    local handle = not entry.is_dir and entry.name:match("%.json$") and io.open(file)
    if handle then
      -- The note is near the end of the file; the whole of it is JSON.
      local text = handle:read("*a")
      handle:close()
      local note = text:match('"recovery":(%b{})') or ""
      local pid = tonumber(note:match('"pid":(%d+)'))
      if pid and pid ~= env.pid and not alive(pid) then
        out[#out + 1] = {
          file = file,
          time = tonumber(note:match('"time":(%d+)')) or 0,
          path = note:match('"path":"(.-)"'),
          name = note:match('"name":"(.-)"') or entry.name,
        }
      end
    end
  end
  table.sort(out, function(a, b) return a.time > b.time end)
  return out
end

--- Open a copy that a session left, as the project that it is a copy of.
--- `opts.as_path` opens it under that file name (a `.bak`, which paw keeps).
--- `opts.plugins_offline` opens it with all plugins offline, if a plugin
--- possibly stopped the session.
function M.recover(file, opts)
  opts = opts or {}
  if not paw.project.guard("recover", opts.force) then return end
  api.project_recover(file, opts)
  if not opts.as_path then os.remove(file) end
  copied = nil
  M.offered = nil
  paw.notify("recovered " .. (api.project_get("path") or "an unsaved project") .. ": save it to keep it")
end

local function readable(file)
  local handle = io.open(file)
  if handle then handle:close() end
  return handle ~= nil
end

--- The files that can replace the project file `path` when paw cannot open
--- it. These are its `.bak` (the file before the last save) and the newest
--- safety copy of it, newest first: { file, path, kind, time }.
function M.alternatives(path)
  local out = {}
  -- A project folder is known by its project.toml, by its full path.
  if paw.project.is_folder(path) or (paw.files and paw.files.is_dir(path)) then
    path = paw.files.path((tostring(path):gsub("/+$", ""):gsub("/project%.toml$", ""))) .. "/project.toml"
  end
  for _, entry in ipairs(api.read_dir(M.dir)) do
    local file = M.dir .. "/" .. entry.name
    local handle = not entry.is_dir and entry.name:match("%.json$") and io.open(file)
    if handle then
      local text = handle:read("*a")
      handle:close()
      local note = text:match('"recovery":(%b{})') or ""
      if note:match('"path":"(.-)"') == path then
        local time = tonumber(note:match('"time":(%d+)')) or 0
        if not out[1] or time > out[1].time then
          out[1] = { file = file, path = path, kind = "safety copy", time = time }
        end
      end
    end
  end
  if readable(path .. ".bak") then
    out[#out + 1] = { file = path .. ".bak", path = path, kind = "backup", as_path = path, time = 0 }
  end
  return out
end

--- Offer the alternatives to a project that would not open, if there are
--- any: `:recover` lists them first. Returns how many there are.
function M.offer(path, err)
  local alternatives = M.alternatives(path)
  if #alternatives == 0 then return 0 end
  M.offered = { path = path, error = err, list = alternatives }
  -- What can be done first: the reason is long, and a narrow line cuts it.
  paw.notify(
    string.format(
      "%s will not open; `:recover` opens %s instead (%s)",
      (path:gsub("/+$", ""):gsub("/project%.toml$", ""):match("[^/]+$")) or path,
      #alternatives == 1 and ("its " .. alternatives[1].kind) or "its backup or safety copy",
      err
    ),
    "error"
  )
  return #alternatives
end

-- Opening a project that fails to parse names what can be opened instead,
-- however it is opened (`paw.project.load`, `paw.open`, `:edit`).
local function guarded(load)
  return function(path, ...)
    local ok, err = pcall(load, path, ...)
    if ok then
      M.offered = nil
      return
    end
    err = tostring(err):gsub("^[^:]*:%d+: ", ""):gsub("^runtime error: ", "")
    if M.offer(tostring(path), err:match("^[^\n]*")) > 0 then
      error(err .. "\n(`:recover` offers its backup or safety copy)", 0)
    end
    error(err, 0)
  end
end
rawset(paw.project, "load", guarded(paw.project.load))
api.project_load = guarded(api.project_load)

local function restart()
  if timer then paw.cancel(timer) end
  timer = nil
  local seconds = tonumber(paw.opt.autosave) or 0
  if seconds > 0 then timer = paw.every(seconds * 1000, function() paw.try(M.copy) end) end
end

paw.on("option.changed", function(e)
  if e.name == "autosave" then restart() end
end)
-- What is saved needs no copy; neither does a project that was replaced by
-- another, whether its changes were saved or thrown away on purpose.
local current = nil
paw.on("project.saved", function()
  forget(current)
  forget()
  current, copied = M.file(), api.project_get("edits")
end)
paw.on("project.loaded", function()
  forget(current)
  current, copied = M.file(), nil
  local takes = M.orphan_takes()
  if #takes > 0 then
    paw.notify(
      string.format(
        "%d recorded take%s in media/ %s not in the project: `:recover` to bring %s in",
        #takes,
        #takes == 1 and "" or "s",
        #takes == 1 and "is" or "are",
        #takes == 1 and "it" or "them"
      ),
      "warn"
    )
  end
end)

-- A take is in the safety copy from the moment it begins, and a disk that
-- will soon be full is mentioned before it is.
paw.on("transport.record", function(e)
  if (tonumber(paw.opt.autosave) or 0) > 0 and e.files and #e.files > 0 then paw.try(M.copy, true) end
  local rate = tonumber(e.bytes_per_second) or 0
  if rate > 0 and e.free then
    local minutes = e.free / rate / 60
    if minutes < (tonumber(paw.opt.record_warn_minutes) or 30) then
      paw.notify(
        string.format(
          "the disk has room for %d minute%s of recording (%.1f GB free)",
          math.floor(minutes),
          math.floor(minutes) == 1 and "" or "s",
          e.free / 1e9
        ),
        "warn"
      )
    end
  end
end)
paw.on("exit", function()
  if M.discard or not paw.project.unsaved() then
    -- Nothing unsaved, or `:q!` said the changes are not wanted.
    forget(current)
    forget()
  elseif (tonumber(paw.opt.autosave) or 0) > 0 then
    -- Ended some other way, such as its window being closed: keep the latest.
    paw.try(M.copy)
  end
end)

--- Recorded takes in the `media` directory of the project that no clip
--- uses, written after the last save of the project. A session that
--- stopped during or after a take, without a save, leaves them. A take that
--- you undid before a save is not one of them. { file, name }.
function M.orphan_takes()
  local path = api.project_get("path")
  if not path then return {} end
  local parent = path:match("^(.*)/[^/]*$") or "."
  local dir = parent .. "/media"
  local saved = 0
  for _, entry in ipairs(api.read_dir(parent)) do
    if parent .. "/" .. entry.name == path then saved = entry.mtime or 0 end
  end
  local used = {}
  for _, id in ipairs(api.track_list()) do
    for _, clip in ipairs(api.track_get(id).clips) do
      local file = api.clip_get(clip).file
      if file then used[file:match("([^/]+)$")] = true end
    end
  end
  local out = {}
  for _, entry in ipairs(api.read_dir(dir)) do
    if
      not entry.is_dir
      and entry.name:match("%-take%d+[%-%d]*%.wav$")
      and not used[entry.name]
      and (entry.mtime or 0) > saved
    then
      out[#out + 1] = { file = dir .. "/" .. entry.name, name = entry.name }
    end
  end
  if #out == 0 then return out end
  -- Projects that share the directory share `media`: a take another one
  -- uses is that one's.
  local others = {}
  for _, entry in ipairs(api.read_dir(parent)) do
    local file = parent .. "/" .. entry.name
    if not entry.is_dir and file ~= path and entry.name:match("%.json$") then
      local handle = io.open(file)
      if handle then
        others[#others + 1] = handle:read("*a")
        handle:close()
      end
    end
  end
  local kept = {}
  for _, take in ipairs(out) do
    local elsewhere = false
    for _, text in ipairs(others) do
      if text:find(take.name, 1, true) then
        elsewhere = true
        break
      end
    end
    if not elsewhere then kept[#kept + 1] = take end
  end
  return kept
end

--- Import an orphaned take. It goes on the track that it was recorded for,
--- if a track has the name that it starts with. If not, it goes on a new
--- track. It goes at the start of the song.
function M.import_take(file)
  local name = file:match("([^/]+)%-take%d+[%-%d]*%.wav$")
  local track
  for _, t in ipairs(paw.tracks()) do
    if name and t.name:gsub("[^%w%-_]", "_") == name then track = t end
  end
  local clip = paw.import_audio(file, { start = 0, track = track and track.id })
  paw.notify(
    string.format(
      "imported the take %s: %.1f beats on track “%s”",
      file:match("([^/]+)$"),
      clip.length,
      clip:track().name
    )
  )
  return clip
end

--- Everything `:recover` offers: the stand-ins for a project that would not
--- open, then the copies left by sessions that ended badly.
function M.choices()
  local list = {}
  for _, item in ipairs(M.offered and M.offered.list or {}) do
    list[#list + 1] = {
      file = item.file,
      as_path = item.as_path,
      time = item.time,
      path = item.path,
      name = item.kind == "backup" and "backup (before the last save)" or "safety copy",
    }
  end
  for _, item in ipairs(M.left_behind()) do
    if not (M.offered and item.file == (M.offered.list[1] or {}).file) then list[#list + 1] = item end
  end
  for _, item in ipairs(M.orphan_takes()) do
    list[#list + 1] = { file = item.file, take = true, time = 0, name = "take not in the project", path = item.name }
  end
  return list
end

paw.command("recover", function(ctx)
  local force = paw.project.discarding()
  local list = M.choices()
  if #list == 0 then return paw.notify("nothing was left behind to recover") end
  local which = tonumber(ctx.args[1])
  if which then
    if not list[which] then return paw.notify("there are " .. #list .. " to choose from", "warn") end
    local item = list[which]
    if item.take then return M.import_take(item.file) end
    return M.recover(item.file, { as_path = item.as_path, plugins_offline = ctx.args[2] == "offline", force = force })
  end
  local items = {}
  for i, item in ipairs(list) do
    local text = string.format(
      "%d  %s%s  %s",
      i,
      item.time > 0 and (os.date("%Y-%m-%d %H:%M", item.time) .. "  ") or "",
      item.name,
      item.path
          and ((item.path:match("[^/]+$") or item.path) .. "  (" .. (item.path:match("^(.*)/[^/]*$") or ".") .. ")")
        or "(never saved)"
    )
    items[#items + 1] = { text = text, file = item.file, as_path = item.as_path, take = item.take }
    -- A plugin may be what ended the session: the same, without them.
    if not item.take then
      items[#items + 1] =
        { text = text .. "  (plugins offline)", file = item.file, as_path = item.as_path, offline = true }
    end
  end
  if paw.pick then
    return paw.pick({
      title = "Recover",
      items = items,
      on_choose = function(item)
        if item.take then return M.import_take(item.file) end
        M.recover(item.file, { as_path = item.as_path, plugins_offline = item.offline or false, force = force })
      end,
    })
  end
  local lines = {
    "Unsaved work and takes that can be brought back. `:recover 1` opens the first, `:recover 1 offline` with every plugin offline.",
    "",
  }
  for i, item in ipairs(items) do
    lines[i + 2] = item.text
  end
  paw.ui.page("Recover", lines)
end, {
  desc = "Open a project that a session which ended badly left unsaved: `recover`, `recover 1`, `recover 1 offline` (plugins offline)",
})
paw.project.allow_discard("recover")

paw.on("startup", function()
  current = M.file()
  restart()
  if (tonumber(paw.opt.autosave) or 0) <= 0 then return end
  local list = M.left_behind()
  if #list > 0 then
    paw.notify(
      string.format(
        "%d unsaved project%s left by a session that ended badly: `:recover`",
        #list,
        #list == 1 and "" or "s"
      ),
      "warn"
    )
  end
end)

return M
