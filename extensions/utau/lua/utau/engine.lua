-- The paw-utau-engine process and the connection to it.
--
-- The engine connects to a socket this side listens on. Reading never blocks: `pump` takes
-- whatever has arrived and hands each message to `handlers[name]`. The
-- process and socket handles are kept in `paw.state`, so that after
-- `:reload` the old engine can be stopped rather than left running.
local api = paw.api
local proto = require("utau.proto")

local M = {
  state = "off", -- off, missing, starting, ready, failed
  reason = nil, -- why it is missing or failed
  info = nil, -- the engine's Hello
  handlers = {}, -- message name -> function(message, frame)
  on_connect = nil, -- called once the socket is up, to send the project
}

local link -- { proc, listener, conn, path, buf = { chunks } }

local exists = paw.api.fs_exists

local function home() return os.getenv("HOME") or "." end

--- Where the engine is: the `utau_engine` option, `$PAW_UTAU_ENGINE`, the
--- one built with the extension (`bin/` beside it, where the Nix package
--- puts it), or `paw-utau-engine` on the PATH.
function M.find()
  local loaded = paw.ext.loaded.utau
  -- `false`, not nil, where there is nothing: the list must have no holes.
  local candidates = {
    paw.opt.utau_engine or false,
    os.getenv("PAW_UTAU_ENGINE") or false,
    loaded and loaded.path .. "/bin/paw-utau-engine" or false,
  }
  for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
    candidates[#candidates + 1] = dir .. "/paw-utau-engine"
  end
  for _, path in ipairs(candidates) do
    if type(path) == "string" and path ~= "" and exists(path) then return path end
  end
end

local function cache_dir()
  local base = os.getenv("XDG_CACHE_HOME")
  if not base or base == "" then base = home() .. "/.cache" end
  return base .. "/paw"
end

--- The engine's own log file.
function M.log_path() return cache_dir() .. "/utau-engine.log" end

local function socket_path()
  local dir = os.getenv("XDG_RUNTIME_DIR")
  if not dir or dir == "" then dir = (os.getenv("TMPDIR") or "/tmp") end
  return string.format("%s/paw-utau/engine-%d-%d.sock", dir, os.time(), math.floor(api.now() * 1000) % 1000000)
end

local function save()
  paw.state.utau_link = link and { proc = link.proc, listener = link.listener, conn = link.conn, path = link.path }
end

--- Send an encoded frame. Returns false when there is no connection.
function M.send(frame)
  if not (link and link.conn and M.state ~= "failed") then return false end
  local ok, err = pcall(api.sock_write, link.conn, frame)
  if not ok then
    M.fail("lost the engine: " .. tostring(err))
    return false
  end
  return true
end

function M.connected() return link ~= nil and link.conn ~= nil end

--- Stop the engine, politely if it is listening.
function M.stop()
  if not link then return end
  if link.conn then
    pcall(api.sock_write, link.conn, proto.encode.shutdown())
    api.sock_close(link.conn)
  end
  if link.listener then api.sock_close(link.listener) end
  if link.proc then
    -- It exits on its own after Shutdown; give it a moment, then insist.
    local deadline = api.now() + 2000
    while api.now() < deadline and api.proc_status(link.proc).running do
      api.sleep(20)
    end
    api.proc_kill(link.proc)
  end
  link = nil
  save()
  M.state, M.info = "off", nil
end

function M.fail(reason)
  M.state, M.reason = "failed", reason
  if link then
    if link.conn then api.sock_close(link.conn) end
    if link.listener then api.sock_close(link.listener) end
    if link.proc then api.proc_kill(link.proc) end
  end
  link = nil
  save()
  paw.notify("utau: " .. reason, "error")
end

--- Start the engine unless it is running. Returns whether it is starting or up.
function M.start()
  if link then return true end
  local engine = M.find()
  if not engine then
    M.state, M.reason = "missing", "paw-utau-engine not found: set PAW_UTAU_ENGINE or paw.opt.utau_engine"
    return false
  end
  local path = socket_path()
  local listener = api.sock_listen(path)
  local argv = { engine, "--socket", path, "--log-level", paw.opt.utau_log_level }
  local function flag(name, value)
    if value and value ~= "" then
      argv[#argv + 1] = name
      argv[#argv + 1] = value
    end
  end
  flag(
    "--openutau-dir",
    paw.opt.utau_openutau_dir ~= "" and paw.opt.utau_openutau_dir or os.getenv("PAW_UTAU_OPENUTAU_DIR")
  )
  flag("--data-dir", paw.opt.utau_data_dir)
  flag("--cache-dir", paw.opt.utau_cache_dir)
  pcall(paw.api.fs_mkdir, cache_dir())
  local ok, proc = pcall(api.proc_spawn, argv, { log = M.log_path() })
  if not ok then
    api.sock_close(listener)
    M.state, M.reason = "failed", tostring(proc)
    return false
  end
  link = { proc = proc, listener = listener, path = path, chunks = {}, started = api.now() }
  M.state, M.reason, M.info = "starting", nil, nil
  save()
  return true
end

--- Stop an engine a previous Lua state started, before `:reload`. Its
--- connection may be in the middle of a frame, so a fresh start is safer
--- than picking it up.
function M.reset_stale()
  local saved = paw.state.utau_link
  if not saved or link then return end
  paw.state.utau_link = nil
  if saved.conn then pcall(api.sock_close, saved.conn) end
  if saved.listener then pcall(api.sock_close, saved.listener) end
  if saved.proc then pcall(api.proc_kill, saved.proc) end
end

--- OpenUtau's data folder the engine reads voicebanks from, or nil for
--- its own default (`$XDG_DATA_HOME/OpenUtau`).
function M.openutau_dir()
  local dir = paw.opt.utau_openutau_dir ~= "" and paw.opt.utau_openutau_dir or os.getenv("PAW_UTAU_OPENUTAU_DIR")
  if dir and dir ~= "" then return dir end
end

local temps = 0

--- A path for a temporary file, in `$TMPDIR` (or /tmp).
function M.tmp(suffix)
  temps = temps + 1
  local dir = os.getenv("TMPDIR")
  if not dir or dir == "" then dir = "/tmp" end
  return string.format("%s/paw-utau-%d-%d-%d%s", dir, api.env().pid, os.time(), temps, suffix or "")
end

--- Run the engine once for one of its one-shot modes (`--convert`,
--- `--export`, `--install`), waiting up to `seconds`. Returns the exit code
--- and what it printed.
function M.tool(args, seconds)
  local exe = M.find()
  if not exe then error("paw-utau-engine not found: set PAW_UTAU_ENGINE or paw.opt.utau_engine", 0) end
  local argv = { exe }
  for _, a in ipairs(args) do
    argv[#argv + 1] = a
  end
  local dir = M.openutau_dir()
  if dir then
    argv[#argv + 1] = "--openutau-dir"
    argv[#argv + 1] = dir
  end
  local out = M.tmp(".log")
  local proc = api.proc_spawn(argv, { log = out })
  local deadline = api.now() + (seconds or 120) * 1000
  while api.proc_status(proc).running do
    if api.now() > deadline then
      api.proc_kill(proc)
      os.remove(out)
      error("paw-utau-engine took too long", 0)
    end
    api.sleep(20)
  end
  local code = api.proc_status(proc).code
  api.proc_kill(proc)
  local file = io.open(out, "rb")
  local text = file and file:read("*a") or ""
  if file then file:close() end
  os.remove(out)
  return code, text
end

local function dispatch(frame)
  local name = proto.name[frame.type]
  local ok, message = pcall(proto.message, frame)
  if not ok then return paw.notify("utau: bad " .. tostring(name) .. " message: " .. tostring(message), "warn") end
  if frame.type == proto.type.Hello then
    M.info, M.state = message, "ready"
  elseif frame.type == proto.type.Ping then
    M.send(proto.encode.pong(message.nonce))
  end
  local handler = name and M.handlers[name]
  if handler then paw.try(handler, message, frame) end
end

--- Read whatever the engine has sent and act on it. Returns whether
--- anything arrived.
function M.pump()
  if not link then return false end
  local got = false
  if not link.conn then
    local conn = api.sock_accept(link.listener)
    if conn then
      link.conn = conn
      save()
      M.send(proto.encode.hello(0))
      if M.on_connect then paw.try(M.on_connect) end
    end
  end
  if link and link.conn then
    while true do
      local chunk = api.sock_read(link.conn, 4 * 1024 * 1024)
      if chunk == nil then
        M.fail("the engine closed the connection (see " .. M.log_path() .. ")")
        return got
      end
      if chunk == "" then break end
      link.chunks[#link.chunks + 1] = chunk
      got = true
    end
    if got then
      local ok, frames, rest = pcall(proto.split, table.concat(link.chunks))
      if not ok then
        M.fail("the engine sent something unreadable: " .. tostring(frames))
        return got
      end
      link.chunks = { rest }
      for _, frame in ipairs(frames) do
        dispatch(frame)
      end
    end
  end
  if link and link.proc then
    local status = api.proc_status(link.proc)
    if not status.running then
      M.fail(string.format("the engine exited (code %s); its log is %s", tostring(status.code), M.log_path()))
    end
  end
  return got
end

return M
