-- Language servers ("lenses"), as `vim.lsp`, over anything with an address.
-- A server is told about subjects (paw/lsp/subjects.lua: a clip, a track,
-- the mix, a render, the project, or one an extension adds), and what it
-- says goes to the generic stores: diagnostics (`paw.diagnostic`), labels
-- (`paw.annotation`), the chords and key it hears (`paw.harmony`),
-- suggestions (`paw.complete`), hover and fixes asked for by location.
-- Nothing here knows any server by name.
--
-- A server is one of three things:
--   a process speaking JSON-RPC on its standard input and output, lines or
--     Content-Length headers (`cmd`);
--   a command run once per version of a subject, reading it from a file or
--     its input and printing what it found (`kind = "oneshot"`);
--   a Lua table in this process with the same handlers (`server = { ... }`).
-- Its dialect is LSP's own (paw/lsp/standard.lua) unless its config names
-- an adapter (`paw.lsp.adapter`), as MIDI LSP's extension does for `midi/*`.
--
--   paw.lsp.config("mixcheck", { cmd = { "python3", "mixcheck.py" }, attach = { subjects = { "mix" } } })
--   paw.lsp.enable("mixcheck")
local api = paw.api
local A = paw.address
local rpc = require("paw.lsp.rpc")
local document = require("paw.lsp.document")
local subjects = require("paw.lsp.subjects")

local M = {
  configs = {},     -- name -> config
  handlers = {},    -- method -> function(client, params, message): what a server sends, in any dialect
  adapters = { standard = require("paw.lsp.standard") },
  analysis = {},    -- clip id -> { key, keys, chords, client }: the last a server heard there
  debounce_ms = 250,
  log = {},         -- the last messages to and from servers, for `:lsp log`
  subjects = subjects.list,
}

local clients = {}  -- name -> client
local by_proc = {}  -- process id -> client, or a one-shot run

for _, id in ipairs(paw.state.lsp_procs or {}) do pcall(api.proc_kill, id) end
local function remember_procs()
  local ids = {}
  for id in pairs(by_proc) do ids[#ids + 1] = id end
  paw.state.lsp_procs = ids
end

-- Settings are objects to a server, even when they are empty.
local function object(t)
  if t == nil then return nil end
  local out = rpc.object()
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function note(client, text)
  local line = string.format("%s %s", client and client.name or "lsp", text)
  M.log[#M.log + 1] = line
  if #M.log > 400 then table.remove(M.log, 1) end
  api.log("[lsp] " .. line)
end

local function client_of(which)
  if type(which) == "table" then return which end
  return clients[which]
end

--- Add a subject (see paw/lsp/subjects.lua).
function M.subject(name, spec) subjects.define(name, spec) end

--- Add a dialect: how a kind of server is spoken to (see paw/lsp/standard.lua
--- for the functions an adapter has; any it leaves out are the standard ones).
function M.adapter(name, spec)
  M.adapters[name] = setmetatable(spec, { __index = M.adapters.standard })
end

-- Sending ---------------------------------------------------------------------

local dispatch

local function send(client, message)
  if client.transport == "lua" then
    -- In-process: the handler is called directly, the answer handed back the same way.
    local server = client.server
    local handler = server and server[message.method]
    if message.id ~= nil then
      local ok, result = true, nil
      if handler then ok, result = pcall(handler, message.params, client.ctx) end
      local answer = { jsonrpc = "2.0", id = message.id }
      if not handler then answer.error = { code = -32601, message = "unknown method " .. message.method }
      elseif not ok then answer.error = { code = -32603, message = tostring(result) }
      else answer.result = result end
      dispatch(client, answer)
    elseif handler then
      local ok, err = pcall(handler, message.params, client.ctx)
      if not ok then note(client, message.method .. ": " .. tostring(err)) end
    end
    return true
  end
  if not client.proc then return false end
  local ok, err = pcall(api.proc_write, client.proc, rpc.frame(message, client.config.framing))
  if not ok then note(client, "could not send: " .. tostring(err)) end
  return ok
end

local function live(client) return client and (client.proc or client.transport == "lua" and client.server) end

--- Send a request to a server. paw calls `cb(err, result)` with its answer.
--- Returns the id of the request, or nil when the server is not there.
function M.request(which, method, params, cb)
  local client = client_of(which)
  if not live(client) then
    if cb then cb({ code = -32803, message = "the server is not running" }) end
    return nil
  end
  client.next_id = client.next_id + 1
  local id = client.next_id
  client.pending[id] = { method = method, cb = cb }
  if not send(client, { jsonrpc = "2.0", id = id, method = method, params = params or rpc.object() }) then
    client.pending[id] = nil
    if cb then cb({ code = -32803, message = "the server is not running" }) end
    return nil
  end
  return id
end

--- Tell a server something that has no answer.
function M.notify(which, method, params)
  local client = client_of(which)
  if not live(client) then return false end
  return send(client, { jsonrpc = "2.0", method = method, params = params or rpc.object() })
end

--- Tell a server to forget a request that it did not answer yet.
function M.cancel(which, id)
  local client = client_of(which)
  if client and client.pending[id] then
    client.pending[id] = nil
    M.notify(client, "$/cancelRequest", { id = id })
  end
end

--- Whether a server said it can do something: "diagnostics", "hover",
--- "actions", "annotations", "analysis", "completion" (with a lane:
--- `has(name, "completion", "velocity")`). LSP's names (`hoverProvider`,
--- `completionProvider`) are taken too.
local LSP_NAMES = { hoverProvider = "hover", completionProvider = "completion", codeActionProvider = "actions",
  diagnosticProvider = "diagnostics", analysisProvider = "analysis" }
--- True if a server that runs (a client or its name) gives a feature:
--- "hover", "completion", "actions", "diagnostics", "analysis".
function M.has(which, feature, lane)
  local client = client_of(which)
  feature = LSP_NAMES[feature] or feature
  local cap = client and client.status == "running" and client.caps[feature]
  if not cap then return false end
  if lane then
    for _, l in ipairs(type(cap) == "table" and cap.lanes or { "notes" }) do
      if l == lane then return true end
    end
    return false
  end
  return true
end

-- Documents -------------------------------------------------------------------

-- What a server is attached to: `attach = { subjects = {...}, where = {...} }`,
-- or the older `{ kinds = { "clip" }, tracks = {...}, drums = bool }`; else
-- what it asked for at initialize; else clips.
local function attachment(client)
  local attach = client.config.attach or {}
  local names = attach.subjects or attach.kinds or (client.caps and client.caps.subjects) or { "clip" }
  local where = paw.util.merge({ tracks = attach.tracks, drums = attach.drums }, attach.where or {})
  return names, where
end

--- True if a server is attached to an address (for its subject, or for any subject).
function M.attaches(which, address, subject)
  local client = client_of(which)
  if not client then return false end
  local names, where = attachment(client)
  for _, name in ipairs(names) do
    local spec = subjects.list[name]
    if spec and (not subject or subject == name) then
      for _, target in ipairs(spec.targets(paw.util.merge(where, { focus = false }))) do
        if target == address then return true end
      end
    end
  end
  return false
end

--- The document a server holds under a URI, or nil.
function M.document(which, uri)
  local client = client_of(which)
  return client and client.docs[uri]
end

local function publish(client, doc, list)
  paw.diagnostic.set(client.name, doc.uri, list)
end

local function close_doc(client, uri)
  local doc = client.docs[uri]
  if not doc then return end
  client.docs[uri] = nil
  if client.transport ~= "oneshot" then
    local method, params = client.adapter.close(client, doc)
    if method then M.notify(client, method, params) end
  end
  paw.diagnostic.reset(client.name, uri)
  if paw.annotation then paw.annotation.reset(client.name, uri) end
  if doc.subject == "clip" then
    local id = A.parse(doc.address).clip
    if M.analysis[id] and M.analysis[id].client == client.name then M.analysis[id] = nil end
  end
end

local run_oneshot

-- Send a subject's document to a server if it changed since it was last
-- sent, or was never sent.
local function send_doc(client, name, address, kept)
  local spec = subjects.list[name]
  local uri = subjects.uri(name, address)
  local key = spec.key and spec.key(address)
  local data
  if not spec.key then
    local ok, built = pcall(spec.build, address, nil)
    if not ok or built == nil then return close_doc(client, uri) end
    data = built
    local text = rpc.encode(built)
    local h = 5381
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
    key = string.format("%08x", h)
  elseif key == nil then
    return close_doc(client, uri)
  end
  local doc = client.docs[uri]
  if doc and doc.key == key then return doc end
  data = data or spec.build(address, nil, key)
  if data == nil then return close_doc(client, uri) end
  local new = { uri = uri, subject = name, address = address, language = spec.language, key = key,
    version = (doc and doc.version or 0) + 1, data = data, kept = kept or (doc and doc.kept) }
  client.docs[uri] = new
  if client.transport == "oneshot" then
    run_oneshot(client, new)
  else
    -- A notification in LSP; a dialect may make it a request (MIDI LSP answers them).
    local method, params, ask
    if doc and client.adapter.change then method, params, ask = client.adapter.change(client, new) end
    if not method then method, params, ask = client.adapter.open(client, new) end
    if ask then
      M.request(client, method, params, function(err)
        if err then note(client, "the document was refused: " .. tostring(err.message)) end
      end)
    else
      M.notify(client, method, params)
    end
  end
  return new
end

local function ready(client) return client.status == "running" or client.status == "ready" or client.status == "failed" and client.transport == "oneshot" end

--- Update each server now. Open the documents that it is attached to, send
--- the changes, and close the documents that it is not attached to now.
--- Requests call this first, so they are about the current state.
function M.sync()
  if M.timer then
    paw.cancel(M.timer)
    M.timer = nil
  end
  for _, client in pairs(clients) do
    if ready(client) then
      local names, where = attachment(client)
      local wanted = {}
      for _, name in ipairs(names) do
        local spec = subjects.list[name]
        if spec then
          local w = where
          if w.focus == nil then w = paw.util.merge(where, { focus = spec.focus ~= false and (name == "clip" or name == "track") }) end
          for _, address in ipairs(spec.targets(w)) do wanted[subjects.uri(name, address)] = { name, address } end
        end
      end
      for uri, doc in pairs(client.docs) do
        if not wanted[uri] and not doc.kept then close_doc(client, uri) end
      end
      for _, t in pairs(wanted) do send_doc(client, t[1], t[2]) end
      for _, doc in pairs(client.docs) do
        if doc.kept then send_doc(client, doc.subject, doc.address, true) end
      end
    end
  end
end

-- What changed is sent once the edits have paused for `debounce_ms`.
local function schedule()
  if M.timer or not next(clients) then return end
  M.timer = paw.defer(function()
    M.timer = nil
    M.sync()
  end, M.debounce_ms)
end

--- Make a server keep a subject of an address open, when paw would send it
--- and when it would not (`keep` false releases it). A clip id names its clip.
function M.attach(which, address, keep, subject)
  local client = client_of(which)
  if not client then return false end
  if type(address) == "number" then address = A.clip(address) end
  subject = subject or select(1, subjects.split(address)) or "clip"
  local uri = subjects.uri(subject, address)
  if keep == false then
    if client.docs[uri] then client.docs[uri].kept = nil end
    M.sync()
    return true
  end
  if not ready(client) or not subjects.list[subject] then return false end
  return send_doc(client, subject, address, true) ~= nil
end

-- Answers ---------------------------------------------------------------------

-- What adapters call with what a server said, in this program's terms.
local lsp = {
  document = function(client, uri) return client.docs[uri] end,
  publish = publish,
  annotate = function(client, doc, list) if paw.annotation then paw.annotation.set(client.name, doc.uri, list) end end,
  request = function(...) return M.request(...) end,
  notify = function(...) return M.notify(...) end,
}
M.adapter_api = lsp

-- What the servers heard, offered to `paw.harmony` for the stretch asked.
local function harmony_provider(from, to)
  local chords, keys = {}, {}
  for _, a in pairs(M.analysis) do
    for _, ch in ipairs(a.chords or {}) do
      if ch.at < to and ch.at + ch.length > from then chords[#chords + 1] = ch end
    end
    for _, k in ipairs(a.keys or {}) do
      if k.at < to and k.at + k.length > from then keys[#keys + 1] = k end
    end
  end
  if #chords == 0 and #keys == 0 then return nil end
  table.sort(chords, function(a, b) return a.at < b.at end)
  table.sort(keys, function(a, b) return a.at < b.at end)
  return chords, keys
end

local provided = false
--- What a server heard of a clip's harmony: `{ chords = { { at, length, root, quality, bass, name, roman, tones } },
--- keys = { { at, length, tonic, mode, name } }, key }`, in project beats.
function lsp.analysis(client, doc, analysis)
  local id = A.parse(doc.address) and A.parse(doc.address).clip
  if not id then return end
  M.analysis[id] = { chords = analysis.chords or {}, keys = analysis.keys or {}, key = analysis.key, client = client.name }
  if not provided and paw.harmony and paw.harmony.provide then
    paw.harmony.provide("lsp", harmony_provider, 50)
    provided = true
  elseif paw.harmony and paw.harmony.invalidate then
    -- An answer that comes after the edit it is about: read anew.
    paw.harmony.invalidate()
  end
  paw.emit("lsp.analysis", { clip = id, client = client.name })
end

M.handlers["window/logMessage"] = function(client, params) note(client, tostring(params.message)) end
M.handlers["window/showMessage"] = function(client, params)
  note(client, tostring(params.message))
  paw.notify(client.name .. ": " .. tostring(params.message), params.type == 1 and "error" or params.type == 2 and "warn" or "info")
end
M.handlers["workspace/configuration"] = function(client, params)
  local out = {}
  for i = 1, #(params.items or { 1 }) do out[i] = object(client.config.settings) or rpc.object() end
  return out
end
-- A server asks for an edit: made as one undo step, as any fix is.
M.handlers["workspace/applyEdit"] = function(_, params)
  local changes = type(params.edit) == "table" and params.edit.paw or {}
  local ok, why = A.edit(changes, params.label or "An edit a server asked for")
  return { applied = ok == true, failureReason = why }
end

dispatch = function(client, message)
  if message.invalid then
    note(client, "sent something that is not JSON-RPC: " .. tostring(message.error))
    return
  end
  if message.id ~= nil and not message.method then
    local waiting = client.pending[message.id]
    client.pending[message.id] = nil
    if waiting and waiting.cb then
      if message.error then waiting.cb(message.error) else waiting.cb(nil, message.result) end
    end
    return
  end
  local dialect = client.adapter.handlers and client.adapter.handlers[message.method]
  local handler = dialect and function(c, p, m) return dialect(c, p, lsp, m) end or M.handlers[message.method]
  if message.id ~= nil then
    -- A request of the server's own: always answered.
    local reply = { jsonrpc = "2.0", id = message.id }
    if handler then
      local ok, result = pcall(handler, client, message.params or {}, message)
      if ok then reply.result = result == nil and rpc.object() or result
      else reply.error = { code = -32603, message = tostring(result) } end
    else
      reply.error = { code = -32601, message = "unknown method " .. tostring(message.method) }
    end
    send(client, reply)
  elseif handler then
    local ok, err = pcall(handler, client, message.params or {}, message)
    if not ok then note(client, message.method .. ": " .. tostring(err)) end
  end
end

-- One-shot servers --------------------------------------------------------------

-- The command line of a one-shot run: `{file}`, `{input}`, `{uri}`, `{subject}`
-- and each setting are put in; a word that is exactly a placeholder with no
-- value is left out with the option before it (`--target {target}` goes when
-- no target is set).
local function oneshot_argv(client, doc, input_path)
  local values = { file = doc.data.path, input = input_path, uri = doc.uri, subject = doc.subject, address = doc.address }
  for k, v in pairs(client.config.settings or {}) do
    if type(v) == "string" or type(v) == "number" then values[k] = tostring(v) end
  end
  local out = {}
  local cmd = client.config.cmd
  if type(cmd) == "function" then cmd = cmd() end
  for _, word in ipairs(cmd or {}) do
    local alone = word:match("^{([%w_]+)}$")
    if alone and values[alone] == nil then
      if #out > 0 and out[#out]:match("^%-") then out[#out] = nil end
    else
      out[#out + 1] = (word:gsub("{([%w_]+)}", function(k) return values[k] ~= nil and tostring(values[k]) or "" end))
    end
  end
  return out
end

-- What a one-shot command printed, as diagnostics: `{ findings = { { rule,
-- severity, message, time_s?, ... } } }`; a finding of severity "off" is
-- left out. The config's `diagnostic(finding, doc)` may say more (a
-- location, fixes).
local function findings(client, doc, out)
  local list = {}
  for _, f in ipairs(type(out.findings) == "table" and out.findings or {}) do
    if f.severity ~= "off" then
      local d = client.config.diagnostic and client.config.diagnostic(f, doc) or nil
      d = d or {}
      d.location = d.location or { uri = doc.address, selector = f.time_s and { seconds = { f.time_s, f.time_s } } or nil }
      d.severity = d.severity or f.severity
      d.message = d.message or f.message
      d.rule = d.rule or f.rule
      d.source = d.source or client.name
      d.data = d.data or f
      list[#list + 1] = d
    end
  end
  return list
end

run_oneshot = function(client, doc)
  -- A newer version of the document stops the run for the older one.
  for proc, run in pairs(by_proc) do
    if run.oneshot and run.client == client and run.doc.uri == doc.uri then
      by_proc[proc] = nil
      pcall(api.proc_kill, proc)
    end
  end
  if client.config.accepts and not client.config.accepts(doc) then return end
  local input = client.config.input and client.config.input(doc) or doc.data
  if input == nil then return end
  local path = os.tmpname()
  local f = io.open(path, "w")
  f:write(rpc.encode(input))
  f:close()
  local argv = oneshot_argv(client, doc, path)
  local ok, proc = pcall(api.proc_spawn, argv, { pipe = true, log = M.log_path(client.name), env = client.config.env, cwd = client.config.cwd })
  if not ok then
    os.remove(path)
    client.status, client.error = "failed", tostring(proc)
    note(client, "failed: " .. tostring(proc))
    return
  end
  pcall(api.proc_write, proc, rpc.encode(input))
  pcall(api.proc_close_input, proc)
  local run = { oneshot = true, client = client, doc = doc, out = {}, input = path }
  by_proc[proc] = run
  remember_procs()
  client.status, client.running = "running", (client.running or 0) + 1
  note(client, "runs " .. table.concat(argv, " "))
  run.timer = paw.defer(function()
    if by_proc[proc] ~= run then return end
    by_proc[proc] = nil
    pcall(api.proc_kill, proc)
    os.remove(path)
    client.running = client.running - 1
    client.status, client.error = "failed", "took longer than " .. (client.config.timeout_ms or 60000) .. " ms"
    note(client, client.error)
  end, client.config.timeout_ms or 60000)
end

local function oneshot_done(proc, run)
  by_proc[proc] = nil
  remember_procs()
  if run.timer then paw.cancel(run.timer) end
  os.remove(run.input)
  local client = run.client
  client.running = math.max(0, (client.running or 1) - 1)
  local text = table.concat(run.out)
  local out = api.json_decode(text:match("^%s*(.-)%s*$") or "")
  local code = (select(2, pcall(api.proc_status, proc)) or {}).code
  pcall(api.proc_kill, proc)
  if client.docs[run.doc.uri] ~= run.doc then return end
  if type(out) ~= "table" or out.error or (code and code ~= 0 and not out.findings) then
    client.status = "failed"
    client.error = type(out) == "table" and out.error and tostring(out.error)
      or (text == "" and "printed nothing" or "printed what is not JSON") .. (code and (" (exit " .. code .. ")") or "")
    note(client, "failed: " .. client.error)
    paw.emit("lsp.status", { client = client.name, status = "failed" })
    return
  end
  client.status, client.error = (client.running or 0) > 0 and "running" or "ready", nil
  publish(client, run.doc, findings(client, run.doc, out))
  note(client, string.format("%s: %d finding%s", run.doc.uri, #(out.findings or {}), #(out.findings or {}) == 1 and "" or "s"))
  paw.emit("lsp.status", { client = client.name, status = client.status, document = run.doc.uri })
end

-- Starting and stopping ------------------------------------------------------

local start

local function forget(client, status, why)
  if client.proc then
    by_proc[client.proc] = nil
    pcall(api.proc_kill, client.proc)
    client.proc = nil
    remember_procs()
  end
  for id, waiting in pairs(client.pending) do
    client.pending[id] = nil
    if waiting.cb then pcall(waiting.cb, { code = -32803, message = "the server stopped" }) end
  end
  client.status, client.error = status, why or client.error
  for uri in pairs(client.docs) do close_doc(client, uri) end
  client.docs = {}
  paw.diagnostic.reset(client.name)
  if paw.annotation then paw.annotation.reset(client.name) end
  for id, a in pairs(M.analysis) do
    if a.client == client.name then M.analysis[id] = nil end
  end
  note(client, status .. (why and (": " .. why) or ""))
  paw.emit("lsp.status", { client = client.name, status = status })
  api.ui_redraw()
end

-- The process ended without being asked: start it again if the config
-- allows that many restarts in that time.
local function died(client)
  local code = (select(2, pcall(api.proc_status, client.proc)) or {}).code
  forget(client, "dead", "the server stopped" .. (code and (" with code " .. code) or ""))
  local restart = client.config.restart or {}
  local now = api.now()
  local recent = {}
  for _, t in ipairs(client.restarts) do
    if now - t < (restart.within_s or 60) * 1000 then recent[#recent + 1] = t end
  end
  client.restarts = recent
  if #recent < (restart.max or 0) then
    client.restarts[#client.restarts + 1] = now
    paw.defer(function()
      if clients[client.name] == client and client.status == "dead" then start(client) end
    end, 500)
  end
end

paw.on("proc.output", function(event)
  local owner = by_proc[event.id]
  if not owner then return end
  if owner.oneshot then
    while by_proc[event.id] == owner do
      local bytes = api.proc_read(event.id)
      if bytes == nil then return oneshot_done(event.id, owner) end
      if bytes == "" then return end
      owner.out[#owner.out + 1] = bytes
    end
    return
  end
  local client = owner
  while client.proc == event.id do
    local bytes = api.proc_read(event.id)
    if bytes == nil then return died(client) end
    if bytes == "" then return end
    for _, message in ipairs(client.reader:push(bytes)) do dispatch(client, message) end
  end
end)

local function command_of(config)
  local cmd = config.cmd
  if type(cmd) == "function" then cmd = cmd() end
  if type(cmd) == "string" then cmd = { cmd } end
  return type(cmd) == "table" and #cmd > 0 and cmd or nil
end

--- Where a server's errors are written.
function M.log_path(name)
  return api.env().state_dir .. "/paw/lsp-" .. tostring(name):gsub("[^%w%-_.]", "_") .. ".log"
end

local function subject_names()
  local out = {}
  for name in pairs(subjects.list) do out[#out + 1] = name end
  table.sort(out)
  return out
end

start = function(client)
  client.pending, client.docs, client.next_id = {}, {}, 0
  local config = client.config
  client.adapter = type(config.adapter) == "table" and setmetatable(config.adapter, { __index = M.adapters.standard })
    or M.adapters[config.adapter or "standard"]
  if not client.adapter then return forget(client, "dead", "no adapter `" .. tostring(config.adapter) .. "`") end
  if config.kind == "oneshot" then
    client.transport, client.status, client.error = "oneshot", "ready", nil
    client.caps = { diagnostics = true, subjects = (config.attach or {}).subjects }
    if not command_of(config) then return forget(client, "dead", "no command to run") end
    note(client, "ready")
    return M.sync()
  end
  local log = M.log_path(client.name)
  pcall(paw.api.fs_mkdir, log:match("^(.*)/"))
  if config.server then
    client.transport, client.server = "lua", config.server
    -- What the server is handed: `notify` sends this program a notification,
    -- `request` asks it something and returns the answer.
    client.ctx = {
      name = client.name,
      notify = function(method, params) dispatch(client, { method = method, params = params }) end,
      request = function(method, params)
        local dialect = client.adapter.handlers and client.adapter.handlers[method]
        if dialect then return dialect(client, params or {}, lsp) end
        local handler = M.handlers[method]
        if handler then return handler(client, params or {}) end
        error("unknown method " .. tostring(method))
      end,
    }
  else
    local cmd = command_of(config)
    if not cmd then return forget(client, "dead", "no command to start it with") end
    local ok, proc = pcall(api.proc_spawn, cmd, { pipe = true, log = log, env = config.env, cwd = config.cwd })
    if not ok then return forget(client, "dead", tostring(proc)) end
    client.transport, client.proc, client.reader = "process", proc, rpc.reader(config.framing)
    by_proc[proc] = client
    remember_procs()
    note(client, "started: " .. table.concat(cmd, " "))
  end
  client.status, client.error = "starting", nil
  local offer = {
    processId = nil,
    clientInfo = { name = "paw", version = paw.version },
    capabilities = { paw = { subjects = subject_names(), addresses = true, workspaceEdit = true,
      features = { "diagnostics", "annotations", "hover", "codeAction", "completion", "analysis" } } },
    initializationOptions = object(config.init_options),
    configuration = object(config.settings),
  }
  local proc = client.proc
  M.request(client, "initialize", client.adapter.initialize(client, offer), function(err, result)
    if client.proc ~= proc then return end
    if err or type(result) ~= "table" then
      return forget(client, "dead", "initialize failed: " .. tostring(err and err.message or "no answer"))
    end
    client.caps, client.info = client.adapter.capabilities(client, result), result.serverInfo or {}
    client.protocol = tonumber(result.protocolVersion)
    local method, params = client.adapter.initialized(client, result)
    if method then M.notify(client, method, params) end
    client.status = "running"
    note(client, "running" .. (client.info.name and (": " .. client.info.name .. " " .. tostring(client.info.version or "")) or ""))
    paw.emit("lsp.status", { client = client.name, status = "running" })
    M.sync()
  end)
end

local function stop(client, status)
  if client.proc then
    local proc = client.proc
    -- LSP's way out: `shutdown`, then `exit`. The process is let go of
    -- at once, and killed if it is still there in a while.
    M.request(client, "shutdown", nil)
    M.notify(client, "exit")
    pcall(api.proc_close_input, proc)
    paw.defer(function() pcall(api.proc_kill, proc) end, 1000)
    by_proc[proc] = nil
    client.proc = nil
  elseif client.transport == "lua" then
    M.request(client, "shutdown", nil)
    client.server = nil
  end
  for proc, run in pairs(by_proc) do
    if run.oneshot and run.client == client then
      by_proc[proc] = nil
      pcall(api.proc_kill, proc)
    end
  end
  forget(client, status or "stopped")
end

--- Say how to start a server and what to show it, as `vim.lsp.config`. A
--- second call changes only the fields it gives.
---   cmd          the program and its arguments (or a function giving them)
---   server       instead: a Lua table of handlers, run in this process
---   kind         "oneshot": `cmd` is run once per version of each subject
---                (placeholders `{file}`, `{input}`, `{uri}` and the settings),
---                with `timeout_ms`, `accepts(doc)` (whether to run on it),
---                `input(doc)` (what it is given, the subject by default)
---                and `diagnostic(finding, doc)` (a location, fixes)
---   framing      "lines" (newline-delimited JSON, the default) or "headers" (Content-Length)
---   adapter      the dialect, by name or as a table (LSP's own by default)
---   attach       { subjects = { "clip", "mix", ... }, where = { focus, tracks = { "Flute*" }, drums } }
---   settings     sent at initialize and with `workspace/didChangeConfiguration`
---   init_options sent once, as `initializationOptions`
---   restart      { max = 3, within_s = 60 }: restarts after it dies (none by default)
---   env, cwd     for the process
function M.config(name, config)
  local old = M.configs[name] or {}
  for k, v in pairs(config or {}) do old[k] = v end
  M.configs[name] = old
  local client = clients[name]
  if client then
    client.config = old
    if config and config.settings and client.status == "running" then
      M.notify(client, "workspace/didChangeConfiguration", { settings = object(old.settings) })
    end
  end
  return old
end

--- Start a configured server (`on` false stops it).
function M.enable(name, on)
  local client = clients[name]
  if on == false then
    if client then
      stop(client)
      clients[name] = nil
    end
    return
  end
  local config = M.configs[name]
  if not config then error("no server `" .. tostring(name) .. "`: paw.lsp.config it first", 2) end
  if client and live(client) then return client end
  client = client or { name = name, restarts = {}, pending = {}, docs = {}, caps = {}, next_id = 0 }
  client.config = config
  clients[name] = client
  start(client)
  return client
end

--- Stop a server and start it again.
function M.restart(name)
  local client = clients[name]
  if not client then return M.enable(name) end
  stop(client, "restarting")
  client.restarts = {}
  start(client)
  return client
end

--- Stop every server, or the one named.
function M.stop(name)
  for n, client in pairs(clients) do
    if not name or n == name then
      stop(client)
      clients[n] = nil
    end
  end
end

--- The servers that were enabled, as `{ name, status, error, transport,
--- subjects, capabilities, server, pid, documents, client }`.
function M.clients()
  local out = {}
  for name, client in pairs(clients) do
    local docs = {}
    for uri, doc in pairs(client.docs) do
      local id = doc.subject == "clip" and A.parse(doc.address).clip
      docs[#docs + 1] = id or uri
    end
    table.sort(docs, function(a, b) return tostring(a) < tostring(b) end)
    local pid = client.proc and (select(2, pcall(api.proc_status, client.proc)) or {}).pid
    out[#out + 1] = { name = name, status = client.status, error = client.error, transport = client.transport,
      subjects = (attachment(client)), capabilities = client.caps and client.caps.raw or client.caps, features = client.caps,
      server = client.info, pid = pid, documents = docs, client = client }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- Wait in a script until each server started and answered all requests,
--- and each one-shot run is complete. Stop after `ms` (10 s by default).
--- Returns true if all of this happened.
function M.settle(ms)
  local deadline = api.now() + (ms or 10000)
  M.sync()
  while api.now() < deadline do
    local busy = false
    for _, client in pairs(clients) do
      busy = busy or client.status == "starting" or (client.proc and next(client.pending) ~= nil) or (client.running or 0) > 0
    end
    if not busy then return true end
    paw.wait(10)
  end
  return false
end

-- By location: hover and actions ------------------------------------------------

-- The documents of running servers that hold a location, most specific first.
local function holders(location, feature)
  local out = {}
  for _, client in pairs(clients) do
    if client.status == "running" and M.has(client, feature) then
      local best
      for _, doc in pairs(client.docs) do
        if A.within(location.uri, doc.address) and (not best or #doc.address > #best.address) then best = doc end
      end
      if best then out[#out + 1] = { client = client, doc = best } end
    end
  end
  table.sort(out, function(a, b) return a.client.name < b.client.name end)
  return out
end

--- Ask each server that hovers, and contains the location, for its text
--- there. `cb(sections)` gets `{ { client, lines } }` when all servers answer.
function M.hover_at(location, cb)
  M.sync()
  local asked, sections = 1, {}
  local function finish()
    asked = asked - 1
    if asked == 0 then
      table.sort(sections, function(a, b) return a.client < b.client end)
      cb(sections)
    end
  end
  for _, h in ipairs(holders(location, "hover")) do
    local method, params, translate = h.client.adapter.hover(h.client, h.doc, location)
    if method then
      asked = asked + 1
      M.request(h.client, method, params, function(err, result)
        if not err then
          local lines = translate(result)
          if #lines > 0 then sections[#sections + 1] = { client = h.client.name, lines = lines } end
        end
        finish()
      end)
    end
  end
  finish()
end

--- Ask each server that gives actions, and contains the location, for the
--- actions there. `cb(actions)` gets `{ { title, source, edit | run } }`.
function M.actions_at(location, cb)
  M.sync()
  local asked, out = 1, {}
  local function finish()
    asked = asked - 1
    if asked == 0 then cb(out) end
  end
  for _, h in ipairs(holders(location, "actions")) do
    local method, params, translate = h.client.adapter.actions(h.client, h.doc, location, lsp)
    if method then
      asked = asked + 1
      M.request(h.client, method, params, function(err, result)
        if not err then
          for _, a in ipairs(translate(result)) do
            a.source = h.client.name
            out[#out + 1] = a
          end
        end
        finish()
      end)
    end
  end
  finish()
end

-- The location of a place in a clip: the note there, or the clip at that time.
local function clip_location(id, pitch, beat)
  local n = api.clip_note_at(id, pitch, beat)
  if n and n.id then return A.location(A.note(id, n.id)) end
  return A.location(A.clip(id), { time = { beat, beat }, pitch = { pitch, pitch } })
end

--- Ask about a place in a clip (`pitch` and `beat` from its start), as before
--- addresses: the same as `hover_at` on the note there.
function M.hover(id, pitch, beat, cb) M.hover_at(clip_location(id, pitch, beat), cb) end

-- A title for a location, for floats and pickers.
local function title_of(location)
  local p = A.parse(location.uri)
  if p and p.kind == "note" then
    local n = A.resolve(location.uri)
    local ok, c = pcall(api.clip_get, p.clip)
    if n and ok then return paw.music.name(n.pitch) .. " " .. paw.time.format(c.start + n.start) end
  end
  return paw.diagnostic.where({ location = location })
end

--- Show what is known about a location (by default what is under the
--- cursor of the focused view): the diagnostics about it and what it holds,
--- then each server's hover, in a float.
function M.show_hover(id, pitch, beat)
  local location = type(id) == "table" and id or id and clip_location(id, pitch, beat) or paw.ui.location()
  if not location then return paw.notify("nothing here to ask about", "warn") end
  local lines = {}
  for _, d in ipairs(paw.diagnostic.get(location.uri)) do
    lines[#lines + 1] = { text = paw.diagnostic.format(d), style = paw.diagnostic.group("Diagnostic", d.severity) }
    for _, fix in ipairs(d.fixes) do lines[#lines + 1] = "  fix: " .. tostring(fix.title) end
  end
  for _, a in ipairs(paw.annotation and paw.annotation.get(location.uri) or {}) do lines[#lines + 1] = a.label end
  -- The answers may come in another person's turn: the float is shown to whoever asked.
  local seat = paw.seats and paw.seats.current
  M.hover_at(location, function(sections)
    if seat and seat ~= paw.seats.current then return paw.seats.within(seat, M.show_lines, location, lines, sections) end
    M.show_lines(location, lines, sections)
  end)
end

--- The hover float itself: the diagnostics' lines, then each server's.
function M.show_lines(location, lines, sections)
  for _, s in ipairs(sections) do
    if #lines > 0 then lines[#lines + 1] = "" end
    lines[#lines + 1] = { text = s.client, style = "Title" }
    for _, line in ipairs(s.lines) do lines[#lines + 1] = "  " .. line end
  end
  if #lines == 0 then return paw.notify("nothing to say about " .. title_of(location)) end
  local width = 20
  for _, line in ipairs(lines) do width = math.max(width, api.str_width(type(line) == "table" and line.text or line) + 4) end
  paw.ui.page(title_of(location), lines, { width = math.min(100, width), height = math.min(30, #lines + 3) })
end

--- Pick a fix or an action for a location (by default what is under the
--- cursor of the focused view; off a note in the piano roll, the
--- diagnostics where the cursor is), and carry it out as one undo step.
function M.code_actions(location)
  location = location or paw.ui.location()
  if not location then return paw.notify("nothing here to act on", "warn") end
  local p = A.parse(location.uri)
  local fixes
  if p and p.kind == "clip" and location.selector and location.selector.time then
    -- Off a note: the diagnostics of the clip that cover this time.
    fixes = {}
    local at = location.selector.time[1]
    for _, d in ipairs(paw.diagnostic.get(p.clip)) do
      if at >= (d.at or 0) - 1e-9 and at < (d.at or 0) + math.max(d.length or 0, 1e-6) then
        for _, fix in ipairs(d.fixes) do
          fixes[#fixes + 1] = { title = fix.title, diagnostic = d, run = function() return paw.diagnostic.apply(d, fix) end }
        end
      end
    end
  else
    fixes = paw.diagnostic.actions(location.uri)
  end
  local seat = paw.seats and paw.seats.current
  M.actions_at(location, function(more)
    local items = {}
    for _, a in ipairs(fixes) do
      items[#items + 1] = { text = string.format("%s  (%s)", a.title, a.diagnostic.rule or a.diagnostic.source), run = a.run }
    end
    for _, a in ipairs(more) do
      items[#items + 1] = { text = string.format("%s  (%s)", a.title, a.source), run = a.run or function()
        local ok, why = A.edit(a.edit or {}, a.title)
        if not ok then paw.notify("cannot: " .. tostring(why), "warn") end
      end }
    end
    if #items == 0 then return paw.notify("no fixes here") end
    local function show()
      paw.pick({
        title = "Code actions",
        items = items,
        on_choose = function(item) if item then item.run() end end,
      })
    end
    -- The answers may come in another person's turn: the picker is theirs who asked.
    if seat and seat ~= paw.seats.current then return paw.seats.within(seat, show) end
    show()
  end)
end

-- Completion -------------------------------------------------------------------

--- A completion source over each server that runs and suggests, in the
--- shape that `paw.complete.register` takes. `ctx` names the `clip` and the
--- start of the suggestion (`at`, beats from the start of the clip), with
--- an optional `selection` (a note set of the clip) and `controller`. paw
--- calls `done(items)` one time.
function M.complete(ctx, done)
  local id = ctx.clip and (type(ctx.clip) == "table" and ctx.clip.id or ctx.clip)
  if not id then return done(nil) end
  ctx = paw.util.merge(ctx, { clip = id })
  local items, asked, ids = {}, 1, {}
  local function finish()
    asked = asked - 1
    if asked == 0 then done(#items > 0 and items or nil) end
  end
  for _, client in pairs(clients) do
    if client.status == "running" and M.has(client, "completion") and M.attaches(client, A.clip(id), "clip") then
      local doc = send_doc(client, "clip", A.clip(id), client.docs[A.clip(id)] and client.docs[A.clip(id)].kept)
      if doc then
        for _, ask in ipairs(client.adapter.complete(client, doc, ctx) or {}) do
          asked = asked + 1
          local request = M.request(client, ask.method, ask.params, function(err, result)
            if not err and type(result) == "table" then
              for _, item in ipairs(ask.translate(result)) do
                item.source = item.source or client.name
                items[#items + 1] = item
              end
            end
            finish()
          end)
          if request then ids[#ids + 1] = { client = client, id = request } end
        end
      end
    end
  end
  M.pending_completion = ids
  finish()
end

--- Forget the completion requests still out (a newer one replaced them).
function M.complete_cancel()
  for _, r in ipairs(M.pending_completion or {}) do M.cancel(r.client, r.id) end
  M.pending_completion = nil
end

-- Offered to `paw.complete` when it is there, whichever is loaded first.
local offered = false
local function offer()
  if offered or not (paw.complete and paw.complete.register) then return end
  offered = true
  paw.complete.register({
    name = "lsp", priority = 100, views = { "pianoroll" }, auto = true,
    complete = function(ctx, done) M.complete(ctx, done) end,
    cancel = function() M.complete_cancel() end,
  })
end
offer()
paw.on("startup", offer)

-- Following the project ------------------------------------------------------------

paw.on("pianoroll.opened", function() if next(clients) then M.sync() end end)
paw.on("address.changed", schedule)
paw.on("cursor.changed", schedule)
-- Every clip the piano roll edits is open with the servers, not only the active one.
paw.on("roll_clips.changed", function() if next(clients) then M.sync() end end)
paw.on("exit", function() M.stop() end)

-- `:lsp` -------------------------------------------------------------------------

--- What `:lsp info` shows: each server, its transport, state, what it is
--- attached to and can do, and what it holds.
function M.info_lines()
  local lines = {}
  local names = {}
  for name in pairs(M.configs) do names[#names + 1] = name end
  table.sort(names)
  if #names == 0 then return { "No language servers are configured.", "", "paw.lsp.config(name, { cmd = { ... } }) and paw.lsp.enable(name)." } end
  for _, name in ipairs(names) do
    local client, config = clients[name], M.configs[name]
    lines[#lines + 1] = { text = name .. "  " .. (client and client.status or "off"), style = "Title" }
    local transport = config.server and "in-process Lua" or config.kind == "oneshot" and "one-shot command" or "process"
    lines[#lines + 1] = "  transport " .. transport .. (config.adapter and (", " .. (type(config.adapter) == "string" and config.adapter or "its own") .. " dialect") or "")
    if not config.server then
      local cmd = command_of(config)
      lines[#lines + 1] = "  command   " .. (cmd and table.concat(cmd, " ") or "(none found)")
    end
    if client then
      if client.error then lines[#lines + 1] = "  error     " .. client.error end
      if client.info and client.info.name then lines[#lines + 1] = "  server    " .. client.info.name .. " " .. tostring(client.info.version or "") end
      lines[#lines + 1] = "  subjects  " .. table.concat((attachment(client)), ", ")
      local feats = {}
      for _, k in ipairs({ "diagnostics", "hover", "actions", "completion", "annotations", "analysis" }) do
        if client.caps and client.caps[k] then feats[#feats + 1] = k end
      end
      if #feats > 0 then lines[#lines + 1] = "  can       " .. table.concat(feats, ", ") end
      local docs = {}
      for uri in pairs(client.docs) do docs[#docs + 1] = uri end
      table.sort(docs)
      if #docs > 0 then lines[#lines + 1] = "  documents " .. table.concat(docs, ", ") end
    end
    if not config.server then lines[#lines + 1] = "  errors to " .. M.log_path(name) end
    lines[#lines + 1] = ""
  end
  return lines
end

--- `:lsp [info|start|stop|restart|log] [name]`.
function M.command(ctx)
  local verb, name = ctx.args[1] or "info", ctx.args[2]
  if verb == "info" then
    paw.ui.page("Language servers", M.info_lines())
  elseif verb == "log" then
    paw.ui.page("Language servers: log", #M.log > 0 and M.log or { "Nothing yet." }, { bottom = true })
  elseif verb == "stop" then
    M.stop(name)
  elseif verb == "start" or verb == "restart" then
    local names = {}
    if name then names[1] = name else for n in pairs(M.configs) do names[#names + 1] = n end end
    for _, n in ipairs(names) do
      local ok, err = pcall(verb == "start" and M.enable or M.restart, n)
      if not ok then paw.notify(tostring(err), "error") end
    end
  else
    paw.notify("lsp: info, start, stop, restart or log", "warn")
  end
end

--- What `:Lsp` completes to: its words and the configured servers.
function M.command_complete()
  local out = { "info", "log", "start", "stop", "restart" }
  for name in pairs(M.configs) do out[#out + 1] = name end
  return out
end

-- The window's gestures on the piano roll's notes.
function paw.frontend.act.note_hover(clip, place)
  local n = api.clip_notes(clip)[place]
  if n then M.show_hover(clip, n.pitch, n.start) end
end

M.document_module = document
return M
