-- Language servers ("lenses"), as `vim.lsp`, over anything with an address.
-- A server is told about subjects (paw/lsp/subjects.tl: a clip, a part,
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
-- Its dialect is LSP's own (paw/lsp/standard.tl) unless its config names
-- an adapter (`paw.lsp.adapter`), as MIDI LSP's extension does for `midi/*`.
--
--   paw.lsp.config("mixcheck", { cmd = { "python3", "mixcheck.py" }, attach = { subjects = { "mix" } } })
--   paw.lsp.enable("mixcheck")
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local A = require("paw.address")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local util = require("paw.util")
local registry = require("paw.registry")
local rpc = require("paw.lsp.rpc")
local document = require("paw.lsp.document")
local subjects = require("paw.lsp.subjects")
local standard = require("paw.lsp.standard")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type UiModule = require("paw.ui")
local type objects = require("paw.objects")
local type DiagnosticModule = require("paw.diagnostic")
local type HarmonyModule = require("paw.harmony")
local type CompleteModule = require("paw.complete")
local type SeatsModule = require("paw.seats")
local type MusicModule = require("paw.music")
local type CursorModule = require("paw.cursor")
local type DocumentModule = require("paw.lsp.document")
local type PickModule = require("paw.pick")
local type FrontendModule = require("paw.frontend")

local type Payload = rpc.Payload
local type Location = contracts.Location
local type Client = standard.Client
local type Config = standard.Config
local type Doc = standard.Doc
local type Adapter = standard.Adapter
local type Which = standard.Which
local type RpcError = rpc.RpcError
local type Message = rpc.Message
local type Published = DiagnosticModule.Published

--- The labels of servers on addresses (paw/annotation.lua, in Lua): what
--- this module calls of it.
local record Annotations
  set: function(namespace: string, doc: string, list: {standard.Annotation})
  reset: function(namespace: string, doc?: string)
  get: function(uri: string): {standard.Annotation}
end

--- What paw keeps over a reload (paw/state.lua, in Lua): the processes of
--- the servers, to stop those a reload left running.
local record State
  lsp_procs: {integer}
end

--- The gestures of the window (paw/frontend.tl) that this module adds.
local record Act
  note_hover: function(clip: integer, place: integer)
end

local record Paw is partial.Paw
  ui: UiModule
  annotation: Annotations
  state: State
  diagnostic: DiagnosticModule
  harmony: HarmonyModule
  complete: CompleteModule
  seats: SeatsModule
  music: MusicModule
  cursor: CursorModule
  pick: PickModule
  frontend: FrontendModule
  time: objects.Time
  version: string
  wait: function(ms: number)
end
local paw = (_G as {string: Paw}).paw

--- A run of a one-shot server: its client and document, what it printed,
--- the file of its input, and the timer that stops it.
local record Run
  client: Client
  doc: Doc
  out: {string}
  input: string
  timer: integer
end

--- What a one-shot command prints: what it found, or an error.
local record OneshotOutput
  findings: {standard.Finding}
  error: string
end

--- A document of a subject that has a file (a render): its path.
local record WithPath
  path: string
end

--- What a server heard of a clip, and which server it was.
local record Heard
  chords: {HarmonyModule.ProvidedChord}
  keys: {HarmonyModule.ProvidedKey}
  key: HarmonyModule.ProvidedKey
  client: string
end

--- The params of `window/logMessage` and `window/showMessage`: `type` 1
--- is an error, 2 a warning.
local record LogMessage
  message: string
  type: integer
end

--- An item of `workspace/configuration`.
local record ConfigurationParams
  items: {Payload}
end

--- A section of a hover: the server and its lines.
local record Section
  client: string
  lines: {string}
end

--- A server that holds a location, and the document that holds it.
local record Holder
  client: Client
  doc: Doc
end

--- A completion request still out.
local record Out
  client: Client
  id: integer
end

--- An enabled server as `paw.lsp.clients()` gives it.
local record Info
  name: string
  status: string
  error: string
  transport: standard.Transport
  subjects: {string}
  capabilities: standard.RawCapabilities
  features: standard.Capabilities
  server: standard.ServerInfo
  pid: integer
  documents: {integer | string}
  client: Client
end

--- The payload of `lsp.status`: the server, its state, and the document a
--- one-shot run was about.
local record StatusChanged
  client: string
  status: string
  document: string
end

--- The payload of `lsp.analysis`: the clip and the server.
local record Analysed
  clip: integer
  client: string
end

--- What a page of `:lsp` shows: text, or text in a style.
local type Line = string | contracts.PageLine

--- A pick of `paw.lsp.code_actions`: its line, and what it does.
local record ActionItem
  text: string
  run: function()
end

local record M
  type Run = Run
  type OneshotOutput = OneshotOutput
  type Heard = Heard
  type Section = Section
  type Info = Info
  type StatusChanged = StatusChanged
  type Analysed = Analysed
  type Line = Line
  --- The configs, by name, with the extension that configured each one.
  configs: registry.Registry<Config>
  --- Start a configured server (`on` false stops it).
  enable: function(name: string, on?: boolean): Client
  --- What a server sends, in any dialect, by method: the answer, for a request.
  handlers: {string: function(client: Client, params: Payload, message?: Message): Payload}
  --- The dialects, by name, with the extension that added each one.
  adapters: registry.Registry<Adapter>
  --- The last that a server heard in a clip, by the clip's id.
  analysis: {integer: Heard}
  --- How long the edits pause before what changed is sent.
  debounce_ms: number
  --- The last messages to and from servers, for `:lsp log`.
  log: {string}
  --- The subjects, by name, with the extension that added each one
  --- (paw/lsp/subjects.tl).
  subjects: registry.Registry<subjects.Subject>
  --- What the adapters call with what a server said.
  adapter_api: standard.AdapterApi
  --- paw/lsp/document.tl: the document of a clip.
  document_module: DocumentModule
  --- The timer of the next `sync`.
  timer: integer
  --- The completion requests still out.
  pending_completion: {Out}
  --- The event `lsp.status`: a language server started, failed or stopped.
  status_changed: events.Event<StatusChanged>
  --- The event `lsp.analysis`: the analysis of a clip arrived from a language server.
  analysed: events.Event<Analysed>
  log_path: function(name: string): string
end
-- A server whose config goes (the extension that configured it unloads)
-- stops. A server in this process keeps the module that started it, and
-- the extension loaded again starts a new one.
M.configs = registry.new(
  "lsp",
  "language servers",
  {
    changed = function(name: string, config: Config)
      if not config then
        M.enable(name, false)
      end
    end,
  }
)
M.handlers = {}
M.adapters = registry.new("lsp_adapters", "language server dialects")
M.adapters:put("standard", standard as Adapter)
M.analysis = {}
M.debounce_ms = 250
M.log = {}
M.subjects = subjects.list
M.status_changed = events.event("lsp.status")
M.analysed = events.event("lsp.analysis")

local clients: {string: Client} = {}
local by_proc: {integer: Client} = {} -- process id -> client
local runs: {integer: Run} = {} -- process id -> a one-shot run

for _, id in ipairs(paw.state.lsp_procs or {}) do
  pcall(api.proc_kill, id)
end
local function remember_procs()
  local ids: {integer} = {}
  for id in pairs(by_proc) do
    ids[#ids + 1] = id
  end
  for id in pairs(runs) do
    ids[#ids + 1] = id
  end
  paw.state.lsp_procs = ids
end

-- Settings are objects to a server, even when they are empty.
local function object(t: {string: util.Data}): Payload
  if t == nil then
    return nil
  end
  local out: {string: util.Data} = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return rpc.object(out)
end

local function note(client: Client, text: string)
  local line = string.format("%s %s", client and client.name or "lsp", text)
  M.log[#M.log + 1] = line
  if #M.log > 400 then
    table.remove(M.log, 1)
  end
  api.log("[lsp] " .. line)
end

local function client_of(which: Which): Client
  if which is Client then
    return which
  end
  return clients[which]
end

-- An adapter, with the standard functions for those it leaves out.
local standard_mt: metatable<Adapter> = {__index = standard as Adapter}

--- Add a subject (see paw/lsp/subjects.tl).
function M.subject(name: string, spec: subjects.Subject)
  subjects.define(name, spec)
end

--- Add a dialect: how a kind of server is spoken to (see paw/lsp/standard.tl
--- for the functions an adapter has; any it leaves out are the standard ones).
function M.adapter(name: string, spec: Adapter)
  M.adapters:put(name, setmetatable(spec, standard_mt))
end

-- Sending ---------------------------------------------------------------------

local dispatch: function(client: Client, message: Message)

local function send(client: Client, message: Message): boolean
  if client.transport == "lua" then
    -- In-process: the handler is called directly, the answer handed back the same way.
    local server = client.server
    local handler = server and server[message.method]
    if message.id ~= nil then
      local ok, result: boolean, Payload = true, nil
      if handler then
        ok, result = pcall(handler, message.params, client.ctx) as (boolean, Payload)
      end
      local answer: Message = {jsonrpc = "2.0", id = message.id}
      if not handler then
        answer.error = {code = -32601, message = "unknown method " .. message.method}
      elseif not ok then
        answer.error = {code = -32603, message = tostring(result)}
      else
        answer.result = result
      end
      dispatch(client, answer)
    elseif handler then
      local ok, err = pcall(handler, message.params, client.ctx) as (boolean, string)
      if not ok then
        note(client, message.method .. ": " .. tostring(err))
      end
    end
    return true
  end
  if not client.proc then
    return false
  end
  local ok, err = pcall(api.proc_write, client.proc, rpc.frame(message, client.config.framing)) as (boolean, string)
  if not ok then
    note(client, "could not send: " .. tostring(err))
  end
  return ok
end

local function live(client: Client): boolean
  if not client then
    return false
  end
  return client.proc ~= nil or (client.transport == "lua" and client.server ~= nil)
end

--- Send a request to a server. paw calls `cb(err, result)` with its answer.
--- Returns the id of the request, or nil when the server is not there.
function M.request(
  which: Which, method: string, params?: Payload, cb?: function(err: RpcError, result?: Payload)
): integer
  local client = client_of(which)
  if not live(client) then
    if cb then
      cb({code = -32803, message = "the server is not running"})
    end
    return nil
  end
  client.next_id = client.next_id + 1
  local id = client.next_id
  client.pending[id] = {method = method, cb = cb}
  if not send(client, {jsonrpc = "2.0", id = id, method = method, params = params or rpc.object()}) then
    client.pending[id] = nil
    if cb then
      cb({code = -32803, message = "the server is not running"})
    end
    return nil
  end
  return id
end

--- Tell a server something that has no answer.
function M.notify(which: Which, method: string, params?: Payload): boolean
  local client = client_of(which)
  if not live(client) then
    return false
  end
  return send(client, {jsonrpc = "2.0", method = method, params = params or rpc.object()})
end

--- The params of `$/cancelRequest`.
local record Cancel
  id: integer
end

--- Tell a server to forget a request that it did not answer yet.
function M.cancel(which: Which, id: integer)
  local client = client_of(which)
  if client and client.pending[id] then
    client.pending[id] = nil
    local params: Cancel = {id = id}
    M.notify(client, "$/cancelRequest", params as Payload)
  end
end

-- LSP's names of the features (`hoverProvider`, `completionProvider`).
local LSP_NAMES: {string: string} = {
  hoverProvider = "hover",
  completionProvider = "completion",
  codeActionProvider = "actions",
  diagnosticProvider = "diagnostics",
  analysisProvider = "analysis",
}

-- What a server said it can do of a feature: true, or the lanes of a
-- completion; nil when it cannot.
local function cap_of(caps: standard.Capabilities, feature: string): boolean | standard.CompletionCaps
  if not caps then
    return nil
  end
  if feature == "completion" then
    return caps.completion
  end
  if feature == "hover" then
    return caps.hover
  end
  if feature == "actions" then
    return caps.actions
  end
  if feature == "diagnostics" then
    return caps.diagnostics
  end
  if feature == "annotations" then
    return caps.annotations
  end
  if feature == "analysis" then
    return not not caps.analysis
  end
  if feature == "subjects" then
    return caps.subjects ~= nil
  end
  if feature == "commands" then
    return caps.commands ~= nil
  end
  if feature == "raw" then
    return caps.raw ~= nil
  end
  return nil
end

--- True if a server that runs (a client or its name) gives a feature:
--- "hover", "completion", "actions", "diagnostics", "analysis", or
--- "completion" with a lane: `has(name, "completion", "velocity")`. LSP's
--- names (`hoverProvider`, `completionProvider`) are taken too.
function M.has(which: Which, feature: string, lane?: string): boolean
  local client = client_of(which)
  feature = LSP_NAMES[feature] or feature
  local cap = client and client.status == "running" and cap_of(client.caps, feature)
  if not cap then
    return false
  end
  if lane then
    for _, l in ipairs(cap is standard.CompletionCaps and cap.lanes or {"notes"}) do
      if l == lane then
        return true
      end
    end
    return false
  end
  return true
end

-- Documents -------------------------------------------------------------------

-- What a server is attached to: `attach = { subjects = {...}, where = {...} }`,
-- or the older `{ kinds = { "clip" }, parts = {...}, drums = bool }`; else
-- what it asked for at initialize; else clips.
local function attachment(client: Client): {string}, subjects.Where
  local attach: standard.Attach = client.config.attach or {}
  local names = attach.subjects or attach.kinds or (client.caps and client.caps.subjects) or {"clip"}
  local where: subjects.Where = {parts = attach.parts, drums = attach.drums}
  local given = attach.where or {}
  if given.parts ~= nil then
    where.parts = given.parts
  end
  if given.drums ~= nil then
    where.drums = given.drums
  end
  if given.focus ~= nil then
    where.focus = given.focus
  end
  return names, where
end

-- A copy of `where`, with `focus` as given.
local function focused(where: subjects.Where, focus: boolean): subjects.Where
  return {parts = where.parts, drums = where.drums, focus = focus}
end

--- True if a server is attached to an address (for its subject, or for any subject).
function M.attaches(which: Which, address: string, subject?: string): boolean
  local client = client_of(which)
  if not client then
    return false
  end
  local names, where = attachment(client)
  for _, name in ipairs(names) do
    local spec = subjects.list:get(name)
    if spec and (not subject or subject == name) then
      for _, target in ipairs(spec.targets(focused(where, false))) do
        if target == address then
          return true
        end
      end
    end
  end
  return false
end

--- The document a server holds under a URI, or nil.
function M.document(which: Which, uri: string): Doc
  local client = client_of(which)
  return client and client.docs[uri]
end

local function publish(client: Client, doc: Doc, list: {Published})
  paw.diagnostic.set(client.name, doc.uri, list)
end

local function close_doc(client: Client, uri: string)
  local doc = client.docs[uri]
  if not doc then
    return
  end
  client.docs[uri] = nil
  if client.transport ~= "oneshot" then
    local method, params = client.adapter.close(client, doc)
    if method then
      M.notify(client, method, params)
    end
  end
  paw.diagnostic.reset(client.name, uri)
  if paw.annotation then
    paw.annotation.reset(client.name, uri)
  end
  if doc.subject == "clip" then
    local id = A.parse(doc.address).clip
    if M.analysis[id] and M.analysis[id].client == client.name then
      M.analysis[id] = nil
    end
    -- The last server with the clip's document: its key need not be
    -- kept up to date after each edit.
    for _, other in pairs(clients) do
      if other.docs[uri] then
        return
      end
    end
    document.release(id)
  end
end

local run_oneshot: function(client: Client, doc: Doc)

-- Send a subject's document to a server if it changed since it was last
-- sent, or was never sent.
local function send_doc(client: Client, name: string, address: string, kept?: boolean): Doc
  local spec = subjects.list:get(name)
  local uri = subjects.uri(name, address)
  local key = spec.key and spec.key(address)
  local data: Payload
  if not spec.key then
    local ok, built = pcall(spec.build, address, nil) as (boolean, Payload)
    if not ok or built == nil then
      close_doc(client, uri)
      return nil
    end
    data = built
    local text = rpc.encode(built)
    local h = 5381
    for i = 1, #text do
      h = (h * 33 + text:byte(i)) % 4294967296
    end
    key = string.format("%08x", h)
  elseif key == nil then
    close_doc(client, uri)
    return nil
  end
  local doc = client.docs[uri]
  if doc and doc.key == key then
    return doc
  end
  data = data or spec.build(address, nil, key)
  if data == nil then
    close_doc(client, uri)
    return nil
  end
  local new: Doc = {
    uri = uri,
    subject = name,
    address = address,
    language = spec.language,
    key = key,
    version = (doc and doc.version or 0) + 1,
    data = data,
    kept = kept or (doc and doc.kept),
  }
  client.docs[uri] = new
  if client.transport == "oneshot" then
    run_oneshot(client, new)
  else
    -- A notification in LSP; a dialect may make it a request (MIDI LSP answers them).
    local method: string
    local params: Payload
    local ask: boolean
    if doc and client.adapter.change then
      method, params, ask = client.adapter.change(client, new)
    end
    if not method then
      method, params, ask = client.adapter.open(client, new)
    end
    if ask then
      M.request(
        client,
        method,
        params,
        function(err: RpcError)
          if err then
            note(client, "the document was refused: " .. tostring(err.message))
          end
        end
      )
    else
      M.notify(client, method, params)
    end
  end
  return new
end

local function ready(client: Client): boolean
  return client.status == "running"
    or client.status == "ready"
    or client.status == "failed" and client.transport == "oneshot"
end

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
      local wanted: {string: {string}} = {}
      for _, name in ipairs(names) do
        local spec = subjects.list:get(name)
        if spec then
          local w = where
          if w.focus == nil then
            w = focused(where, spec.focus ~= false and (name == "clip" or name == "part"))
          end
          for _, address in ipairs(spec.targets(w)) do
            wanted[subjects.uri(name, address)] = {name, address}
          end
        end
      end
      for uri, doc in pairs(client.docs) do
        if not wanted[uri] and not doc.kept then
          close_doc(client, uri)
        end
      end
      for _, t in pairs(wanted) do
        send_doc(client, t[1], t[2])
      end
      for _, doc in pairs(client.docs) do
        if doc.kept then
          send_doc(client, doc.subject, doc.address, true)
        end
      end
    end
  end
end

-- What changed is sent once the edits have paused for `debounce_ms`.
local function schedule()
  if M.timer or not next(clients) then
    return
  end
  M.timer = paw.defer(function() M.timer = nil; M.sync() end, M.debounce_ms)
end

--- Make a server keep a subject of an address open, when paw would send it
--- and when it would not (`keep` false releases it). A clip id names its clip.
function M.attach(which: Which, address: string | integer, keep?: boolean, subject?: string): boolean
  local client = client_of(which)
  if not client then
    return false
  end
  local addr = address is integer and A.clip(address) or address as string
  subject = subject or (subjects.split(addr)) or "clip"
  local uri = subjects.uri(subject, addr)
  if keep == false then
    if client.docs[uri] then
      client.docs[uri].kept = nil
    end
    M.sync()
    return true
  end
  if not ready(client) or not subjects.list:get(subject) then
    return false
  end
  return send_doc(client, subject, addr, true) ~= nil
end

-- Answers ---------------------------------------------------------------------

-- What adapters call with what a server said, in this program's terms.
local lsp: standard.AdapterApi = {
  document = function(client: Client, uri: string): Doc return client.docs[uri] end,
  publish = publish,
  annotate = function(client: Client, doc: Doc, list: {standard.Annotation})
    if paw.annotation then
      paw.annotation.set(client.name, doc.uri, list)
    end
  end,
  request = function(
    which: Which, method: string, params?: Payload, cb?: function(err: RpcError, result?: Payload)
  ): integer
    return M.request(which, method, params, cb)
  end,
  notify = function(which: Which, method: string, params?: Payload): boolean
    return M.notify(which, method, params)
  end,
}
M.adapter_api = lsp

-- What the servers heard, offered to `paw.harmony` for the stretch asked.
local function harmony_provider(from: number, to: number): {HarmonyModule.ProvidedChord}, {HarmonyModule.ProvidedKey}
  local chords: {HarmonyModule.ProvidedChord} = {}
  local keys: {HarmonyModule.ProvidedKey} = {}
  for _, a in pairs(M.analysis) do
    for _, ch in ipairs(a.chords or {}) do
      if ch.at < to and ch.at + ch.length > from then
        chords[#chords + 1] = ch
      end
    end
    for _, k in ipairs(a.keys or {}) do
      if k.at < to and k.at + k.length > from then
        keys[#keys + 1] = k
      end
    end
  end
  if #chords == 0 and #keys == 0 then
    return nil
  end
  table.sort(
    chords, function(a: HarmonyModule.ProvidedChord, b: HarmonyModule.ProvidedChord): boolean return a.at < b.at end
  )
  table.sort(keys, function(a: HarmonyModule.ProvidedKey, b: HarmonyModule.ProvidedKey): boolean return a.at < b.at end)
  return chords, keys
end

local provided = false
--- What a server heard of a clip's harmony: `{ chords = { { at, length, root, quality, bass, name, roman, tones } },
--- keys = { { at, length, tonic, mode, name } }, key }`, in project beats.
lsp.analysis = function(client: Client, doc: Doc, analysis: standard.Analysis)
  local parsed = A.parse(doc.address)
  local id = parsed and parsed.clip
  if not id then
    return
  end
  M.analysis[id] = {
    chords = analysis.chords or {}, keys = analysis.keys or {}, key = analysis.key, client = client.name
  }
  if not provided and paw.harmony and paw.harmony.provide then
    paw.harmony.provide("lsp", harmony_provider, 50)
    provided = true
  elseif paw.harmony and paw.harmony.invalidate then
    -- An answer that comes after the edit it is about: read anew.
    paw.harmony.invalidate()
  end
  events.emit(M.analysed, {clip = id, client = client.name})
end

M.handlers["window/logMessage"] = function(client: Client, params: Payload): Payload
  note(client, tostring((params as LogMessage).message))
end
M.handlers["window/showMessage"] = function(client: Client, payload: Payload): Payload
  local params = payload as LogMessage
  note(client, tostring(params.message))
  paw.notify(
    client.name .. ": " .. tostring(params.message),
    params.type == 1 and "error" or params.type == 2 and "warn" or "info"
  )
end
M.handlers["workspace/configuration"] = function(client: Client, params: Payload): Payload
  local out: {Payload} = {}
  local items = (params as ConfigurationParams).items
  for i = 1, items and #items or 1 do
    out[i] = object(client.config.settings) or rpc.object()
  end
  return out as Payload
end
-- A server asks for an edit: made as one undo step, as any fix is.
M.handlers["workspace/applyEdit"] = function(_: Client, payload: Payload): Payload
  local params = payload as standard.ApplyEdit
  local changes = type(params.edit) == "table" and params.edit.paw or {}
  local ok, why = A.edit(changes, params.label or "An edit a server asked for")
  local result: standard.ApplyEditResult = {applied = ok == true, failureReason = why}
  return result as Payload
end

dispatch = function(client: Client, message: Message)
  if message.invalid then
    note(client, "sent something that is not JSON-RPC: " .. tostring(message.error))
    return
  end
  local err = message.error
  if message.id ~= nil and not message.method then
    local waiting = client.pending[message.id]
    client.pending[message.id] = nil
    if waiting and waiting.cb then
      if err then
        waiting.cb(err as RpcError)
      else
        waiting.cb(nil, message.result)
      end
    end
    return
  end
  local dialect = client.adapter.handlers and client.adapter.handlers[message.method]
  local handler: function(client: Client, params: Payload, message?: Message): Payload = M.handlers[message.method]
  if dialect then
    handler = function(c: Client, p: Payload, m?: Message): Payload return dialect(c, p, lsp, m) end
  end
  if message.id ~= nil then
    -- A request of the server's own: always answered.
    local reply: Message = {jsonrpc = "2.0", id = message.id}
    if handler then
      local ok, result = pcall(handler, client, message.params or {} as Payload, message) as (boolean, Payload)
      if ok then
        reply.result = result == nil and rpc.object() or result
      else
        reply.error = {code = -32603, message = tostring(result)}
      end
    else
      reply.error = {code = -32601, message = "unknown method " .. tostring(message.method)}
    end
    send(client, reply)
  elseif handler then
    local ok, why = pcall(handler, client, message.params or {} as Payload, message) as (boolean, string)
    if not ok then
      note(client, message.method .. ": " .. tostring(why))
    end
  end
end

-- One-shot servers --------------------------------------------------------------

local function command_of(config: Config): {string}
  local cmd = config.cmd
  if cmd is standard.CommandFn then
    cmd = cmd()
  end
  if cmd is string then
    return {cmd}
  end
  return cmd is {string} and #cmd > 0 and cmd or nil
end

-- The command line of a one-shot run: `{file}`, `{input}`, `{uri}`, `{subject}`
-- and each setting are put in; a word that is exactly a placeholder with no
-- value is left out with the option before it (`--target {target}` goes when
-- no target is set).
local function oneshot_argv(client: Client, doc: Doc, input_path: string): {string}
  local values: {string: string} = {
    file = (doc.data as WithPath).path, input = input_path, uri = doc.uri, subject = doc.subject, address = doc.address
  }
  for k, v in pairs(client.config.settings or {}) do
    if v is string or v is number then
      values[k] = tostring(v)
    end
  end
  local out: {string} = {}
  for _, word in ipairs(command_of(client.config) or {}) do
    local alone = word:match("^{([%w_]+)}$")
    if alone and values[alone] == nil then
      if #out > 0 and out[#out]:match("^%-") then
        out[#out] = nil
      end
    else
      out[#out + 1] = (
        word:gsub("{([%w_]+)}", function(k: string): string return values[k] ~= nil and tostring(values[k]) or "" end)
      )
    end
  end
  return out
end

-- What a one-shot command printed, as diagnostics: `{ findings = { { rule,
-- severity, message, time_s?, ... } } }`; a finding of severity "off" is
-- left out. The config's `diagnostic(finding, doc)` may say more (a
-- location, fixes).
local function findings(client: Client, doc: Doc, out: OneshotOutput): {Published}
  local list: {Published} = {}
  for _, f in ipairs(type(out.findings) == "table" and out.findings or {}) do
    if f.severity ~= "off" then
      local d = client.config.diagnostic and client.config.diagnostic(f, doc) or nil
      d = d or {}
      local at: Location = {uri = doc.address, selector = f.time_s and {seconds = {f.time_s, f.time_s}} or nil}
      if not d.location then
        d.location = at
      end
      d.severity = d.severity or f.severity
      d.message = d.message or f.message
      d.rule = d.rule or f.rule
      d.source = d.source or client.name
      d.data = d.data or f as DiagnosticModule.Data
      list[#list + 1] = d
    end
  end
  return list
end

run_oneshot = function(client: Client, doc: Doc)
  -- A newer version of the document stops the run for the older one.
  for proc, run in pairs(runs) do
    if run.client == client and run.doc.uri == doc.uri then
      runs[proc] = nil
      pcall(api.proc_kill, proc)
    end
  end
  if client.config.accepts and not client.config.accepts(doc) then
    return
  end
  local input = client.config.input and client.config.input(doc) or doc.data
  if input == nil then
    return
  end
  local path = util.tmpname()
  local f = io.open(path, "w")
  f:write(rpc.encode(input))
  f:close()
  local argv = oneshot_argv(client, doc, path)
  local ok, proc = pcall(
    api.proc_spawn, argv, {pipe = true, log = M.log_path(client.name), env = client.config.env, cwd = client.config.cwd}
  ) as (boolean, integer)
  if not ok then
    os.remove(path)
    client.status, client.error = "failed", tostring(proc)
    note(client, "failed: " .. tostring(proc))
    return
  end
  pcall(api.proc_write, proc, rpc.encode(input))
  pcall(api.proc_close_input, proc)
  local run: Run = {client = client, doc = doc, out = {}, input = path}
  runs[proc] = run
  remember_procs()
  client.status, client.running = "running", (client.running or 0) + 1
  note(client, "runs " .. table.concat(argv, " "))
  run.timer = paw.defer(
    function()
      if runs[proc] ~= run then
        return
      end
      runs[proc] = nil
      pcall(api.proc_kill, proc)
      os.remove(path)
      client.running = client.running - 1
      client.status, client.error = "failed", "took longer than " .. (client.config.timeout_ms or 60000) .. " ms"
      note(client, client.error)
    end,
    client.config.timeout_ms or 60000
  )
end

-- The exit code of a process, or nil.
local function exit_code(proc: integer): integer
  local ok, status = pcall(api.proc_status, proc) as (boolean, types.ProcStatus)
  return ok and status and status.code or nil
end

local function oneshot_done(proc: integer, run: Run)
  runs[proc] = nil
  remember_procs()
  if run.timer then
    paw.cancel(run.timer)
  end
  os.remove(run.input)
  local client = run.client
  client.running = math.max(0, (client.running or 1) - 1)
  local text = table.concat(run.out)
  local decoded = api.json_decode(text:match("^%s*(.-)%s*$") or "")
  local out = type(decoded) == "table" and decoded as OneshotOutput or nil
  local code = exit_code(proc)
  pcall(api.proc_kill, proc)
  if client.docs[run.doc.uri] ~= run.doc then
    return
  end
  if not out or out.error or (code and code ~= 0 and not out.findings) then
    client.status = "failed"
    client.error = out and out.error and tostring(out.error)
      or (text == "" and "printed nothing" or "printed what is not JSON") .. (code and (" (exit " .. code .. ")") or "")
    note(client, "failed: " .. client.error)
    events.emit(M.status_changed, {client = client.name, status = "failed"})
    return
  end
  client.status, client.error = (client.running or 0) > 0 and "running" or "ready", nil
  publish(client, run.doc, findings(client, run.doc, out))
  note(
    client,
    string.format("%s: %d finding%s", run.doc.uri, #(out.findings or {}), #(out.findings or {}) == 1 and "" or "s")
  )
  events.emit(M.status_changed, {client = client.name, status = client.status, document = run.doc.uri})
end

-- Starting and stopping ------------------------------------------------------

local start: function(client: Client)

local function forget(client: Client, status: string, why?: string)
  if client.proc then
    by_proc[client.proc] = nil
    pcall(api.proc_kill, client.proc)
    client.proc = nil
    remember_procs()
  end
  for id, waiting in pairs(client.pending) do
    client.pending[id] = nil
    if waiting.cb then
      pcall(waiting.cb, {code = -32803, message = "the server stopped"} as RpcError)
    end
  end
  client.status, client.error = status, why or client.error
  for uri in pairs(client.docs) do
    close_doc(client, uri)
  end
  client.docs = {}
  paw.diagnostic.reset(client.name)
  if paw.annotation then
    paw.annotation.reset(client.name)
  end
  for id, a in pairs(M.analysis) do
    if a.client == client.name then
      M.analysis[id] = nil
    end
  end
  note(client, status .. (why and (": " .. why) or ""))
  events.emit(M.status_changed, {client = client.name, status = status})
  api.ui_redraw()
end

-- The process ended without being asked: start it again if the config
-- allows that many restarts in that time.
local function died(client: Client)
  local code = exit_code(client.proc)
  forget(client, "dead", "the server stopped" .. (code and (" with code " .. code) or ""))
  local restart: standard.Restart = client.config.restart or {}
  local now = api.now()
  local recent: {number} = {}
  for _, t in ipairs(client.restarts) do
    if now - t < (restart.within_s or 60) * 1000 then
      recent[#recent + 1] = t
    end
  end
  client.restarts = recent
  if #recent < (restart.max or 0) then
    client.restarts[#client.restarts + 1] = now
    paw.defer(
      function()
        if clients[client.name] == client and client.status == "dead" then
          start(client)
        end
      end,
      500
    )
  end
end

events.on(
  kernel.proc_output,
  function(event: kernel.ProcOutput)
    local run = runs[event.id]
    if run then
      while runs[event.id] == run do
        local bytes = api.proc_read(event.id)
        if bytes == nil then
          return oneshot_done(event.id, run)
        end
        if bytes == "" then
          return
        end
        run.out[#run.out + 1] = bytes
      end
      return
    end
    local client = by_proc[event.id]
    if not client then
      return
    end
    while client.proc == event.id do
      local bytes = api.proc_read(event.id)
      if bytes == nil then
        return died(client)
      end
      if bytes == "" then
        return
      end
      for _, message in ipairs(client.reader:push(bytes)) do
        dispatch(client, message)
      end
    end
  end
)

--- Where a server's errors are written.
function M.log_path(name: string): string
  return api.env().state_dir .. "/paw/lsp-" .. tostring(name):gsub("[^%w%-_.]", "_") .. ".log"
end

local function subject_names(): {string}
  local out: {string} = {}
  for name in pairs(subjects.list:entries()) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

start = function(client: Client)
  client.pending, client.docs, client.next_id = {}, {}, 0
  local config = client.config
  local adapter = config.adapter
  if adapter is Adapter then
    client.adapter = setmetatable(adapter, standard_mt)
  else
    client.adapter = M.adapters:get(adapter or "standard")
  end
  if not client.adapter then
    return forget(client, "dead", "no adapter `" .. tostring(config.adapter) .. "`")
  end
  if config.kind == "oneshot" then
    client.transport, client.status, client.error = "oneshot", "ready", nil
    client.caps = {diagnostics = true, subjects = (config.attach or {}).subjects}
    if not command_of(config) then
      return forget(client, "dead", "no command to run")
    end
    note(client, "ready")
    return M.sync()
  end
  local log = M.log_path(client.name)
  pcall(api.fs_mkdir, log:match("^(.*)/"))
  if config.server then
    client.transport, client.server = "lua", config.server
    -- What the server is handed: `notify` sends this program a notification,
    -- `request` asks it something and returns the answer.
    client.ctx = {
      name = client.name,
      notify = function(method: string, params?: Payload) dispatch(client, {method = method, params = params}) end,
      request = function(method: string, params?: Payload): Payload
        local dialect = client.adapter.handlers and client.adapter.handlers[method]
        if dialect then
          return dialect(client, params or {} as Payload, lsp)
        end
        local handler = M.handlers[method]
        if handler then
          return handler(client, params or {} as Payload)
        end
        error("unknown method " .. tostring(method))
      end,
    }
  else
    local cmd = command_of(config)
    if not cmd then
      return forget(client, "dead", "no command to start it with")
    end
    local ok, proc = pcall(api.proc_spawn, cmd, {pipe = true, log = log, env = config.env, cwd = config.cwd})
      as (boolean, integer)
    if not ok then
      return forget(client, "dead", tostring(proc))
    end
    client.transport, client.proc, client.reader = "process", proc, rpc.reader(config.framing)
    by_proc[proc] = client
    remember_procs()
    note(client, "started: " .. table.concat(cmd, " "))
  end
  client.status, client.error = "starting", nil
  local offer: standard.Offer = {
    processId = nil,
    clientInfo = {name = "paw", version = paw.version},
    capabilities = {
      paw = {
        subjects = subject_names(),
        addresses = true,
        workspaceEdit = true,
        features = {"diagnostics", "annotations", "hover", "codeAction", "completion", "analysis"},
      },
    },
    initializationOptions = object(config.init_options),
    configuration = object(config.settings),
  }
  local proc = client.proc
  M.request(
    client,
    "initialize",
    client.adapter.initialize(client, offer) as Payload,
    function(err: RpcError, payload: Payload)
      if client.proc ~= proc then
        return
      end
      if err or type(payload) ~= "table" then
        return forget(client, "dead", "initialize failed: " .. tostring(err and err.message or "no answer"))
      end
      local result = payload as standard.InitializeResult
      client.caps, client.info = client.adapter.capabilities(client, result), result.serverInfo or {}
      client.protocol = tonumber(result.protocolVersion)
      local method, params = client.adapter.initialized(client, result)
      if method then
        M.notify(client, method, params)
      end
      client.status = "running"
      note(
        client,
        "running"
          .. (client.info.name and (": " .. client.info.name .. " " .. tostring(client.info.version or "")) or "")
      )
      events.emit(M.status_changed, {client = client.name, status = "running"})
      M.sync()
    end
  )
end

local function stop(client: Client, status?: string)
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
  for proc, run in pairs(runs) do
    if run.client == client then
      runs[proc] = nil
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
---   attach       { subjects = { "clip", "mix", ... }, where = { focus, parts = { "Flute*" }, drums } }
---   settings     sent at initialize and with `workspace/didChangeConfiguration`
---   init_options sent once, as `initializationOptions`
---   restart      { max = 3, within_s = 60 }: restarts after it dies (none by default)
---   env, cwd     for the process
function M.config(name: string, config?: Config): Config
  -- The fields given replace the old ones; the others stay. A new table,
  -- so that the config below it stays as it was when this one goes.
  local fields: {string: util.Data} = {}
  for _, given in ipairs({(M.configs:get(name) or {}) as {string: util.Data}, (config or {}) as {string: util.Data}}) do
    for k, v in pairs(given) do
      fields[k] = v
    end
  end
  local merged = fields as Config
  M.configs:put(name, merged)
  local client = clients[name]
  if client then
    client.config = merged
    if config and config.settings and client.status == "running" then
      local params: standard.DidChangeConfiguration = {settings = object(merged.settings)}
      M.notify(client, "workspace/didChangeConfiguration", params as Payload)
    end
  end
  return merged
end

--- Start a configured server (`on` false stops it).
function M.enable(name: string, on?: boolean): Client
  local client = clients[name]
  if on == false then
    if client then
      stop(client)
      clients[name] = nil
    end
    return
  end
  local config = M.configs:get(name)
  if not config then
    error("no server `" .. tostring(name) .. "`: paw.lsp.config it first", 2)
  end
  if client and live(client) then
    return client
  end
  client = client or {name = name, restarts = {}, pending = {}, docs = {}, caps = {}, next_id = 0}
  client.config = config
  clients[name] = client
  start(client)
  return client
end

--- Stop a server and start it again.
function M.restart(name: string): Client
  local client = clients[name]
  if not client then
    return M.enable(name)
  end
  stop(client, "restarting")
  client.restarts = {}
  start(client)
  return client
end

--- Stop every server, or the one named.
function M.stop(name?: string)
  for n, client in pairs(clients) do
    if not name or n == name then
      stop(client)
      clients[n] = nil
    end
  end
end

--- The servers that were enabled, as `{ name, status, error, transport,
--- subjects, capabilities, server, pid, documents, client }`.
function M.clients(): {Info}
  local out: {Info} = {}
  for name, client in pairs(clients) do
    local docs: {integer | string} = {}
    for uri, doc in pairs(client.docs) do
      local id = doc.subject == "clip" and A.parse(doc.address).clip
      docs[#docs + 1] = id or uri
    end
    table.sort(docs, function(a: integer | string, b: integer | string): boolean return tostring(a) < tostring(b) end)
    -- What the server said it can do, or (a one-shot command) what paw gives it.
    local caps = client.caps
    local pid: integer
    if client.proc then
      local ok, status = pcall(api.proc_status, client.proc) as (boolean, types.ProcStatus)
      pid = ok and status and status.pid or nil
    end
    out[#out + 1] = {
      name = name,
      status = client.status,
      error = client.error,
      transport = client.transport,
      subjects = (attachment(client)),
      capabilities = caps and (caps.raw or caps as standard.RawCapabilities),
      features = caps,
      server = client.info,
      pid = pid,
      documents = docs,
      client = client,
    }
  end
  table.sort(out, function(a: Info, b: Info): boolean return a.name < b.name end)
  return out
end

--- Wait in a script until each server started and answered all requests,
--- and each one-shot run is complete. Stop after `ms` (10 s by default).
--- Returns true if all of this happened.
function M.settle(ms?: number): boolean
  local deadline = api.real_ms() + (ms or 10000)
  M.sync()
  while api.real_ms() < deadline do
    local busy = false
    for _, client in pairs(clients) do
      busy = busy
        or client.status == "starting"
        or (client.proc and next(client.pending) ~= nil)
        or (client.running or 0) > 0
    end
    if not busy then
      return true
    end
    paw.wait(10)
  end
  return false
end

-- By location: hover and actions ------------------------------------------------

-- The documents of running servers that hold a location, most specific first.
local function holders(location: Location, feature: string): {Holder}
  local out: {Holder} = {}
  for _, client in pairs(clients) do
    if client.status == "running" and M.has(client, feature) then
      local best: Doc
      for _, doc in pairs(client.docs) do
        if A.within(location.uri, doc.address) and (not best or #doc.address > #best.address) then
          best = doc
        end
      end
      if best then
        out[#out + 1] = {client = client, doc = best}
      end
    end
  end
  table.sort(out, function(a: Holder, b: Holder): boolean return a.client.name < b.client.name end)
  return out
end

--- Ask each server that hovers, and contains the location, for its text
--- there. `cb(sections)` gets `{ { client, lines } }` when all servers answer.
function M.hover_at(location: Location, cb: function(sections: {Section}))
  M.sync()
  local asked = 1
  local sections: {Section} = {}
  local function finish()
    asked = asked - 1
    if asked == 0 then
      table.sort(sections, function(a: Section, b: Section): boolean return a.client < b.client end)
      cb(sections)
    end
  end
  for _, h in ipairs(holders(location, "hover")) do
    local method, params, translate = h.client.adapter.hover(h.client, h.doc, location)
    if method then
      asked = asked + 1
      M.request(
        h.client,
        method,
        params,
        function(err: RpcError, result: Payload)
          if not err then
            local lines = translate(result)
            if #lines > 0 then
              sections[#sections + 1] = {client = h.client.name, lines = lines}
            end
          end
          finish()
        end
      )
    end
  end
  finish()
end

--- Ask each server that gives actions, and contains the location, for the
--- actions there. `cb(actions)` gets `{ { title, source, edit | run } }`.
function M.actions_at(location: Location, cb: function(actions: {standard.Action}))
  M.sync()
  local asked = 1
  local out: {standard.Action} = {}
  local function finish()
    asked = asked - 1
    if asked == 0 then
      cb(out)
    end
  end
  for _, h in ipairs(holders(location, "actions")) do
    local method, params, translate = h.client.adapter.actions(h.client, h.doc, location, lsp)
    if method then
      asked = asked + 1
      M.request(
        h.client,
        method,
        params,
        function(err: RpcError, result: Payload)
          if not err then
            for _, a in ipairs(translate(result)) do
              a.source = h.client.name
              out[#out + 1] = a
            end
          end
          finish()
        end
      )
    end
  end
  finish()
end

-- The location of a place in a clip: the note there, or the clip at that time.
local function clip_location(id: integer, pitch: integer, beat: number): Location
  local n = api.clip_note_at(id, pitch, beat)
  if n and n.id then
    return A.location(A.note(id, n.id))
  end
  return A.location(A.clip(id), {time = {beat, beat}, pitch = {pitch, pitch}})
end

--- Ask about a place in a clip (`pitch` and `beat` from its start), as before
--- addresses: the same as `hover_at` on the note there.
function M.hover(id: integer, pitch: integer, beat: number, cb: function(sections: {Section}))
  M.hover_at(clip_location(id, pitch, beat), cb)
end

-- A title for a location, for floats and pickers.
local function title_of(location: Location): string
  local p = A.parse(location.uri)
  if p and p.kind == "note" then
    local n = A.resolve(location.uri) as types.Note
    local ok, c = pcall(api.clip_get, p.clip) as (boolean, types.Clip)
    if n and ok then
      return paw.music.name(n.pitch) .. " " .. paw.time.format(c.start + n.start)
    end
  end
  return paw.diagnostic.where({location = location} as DiagnosticModule.Diagnostic)
end

--- The hover float itself: the diagnostics' lines, then each server's.
function M.show_lines(location: Location, lines: {Line}, sections: {Section})
  for _, s in ipairs(sections) do
    if #lines > 0 then
      lines[#lines + 1] = ""
    end
    lines[#lines + 1] = {text = s.client, style = "Title"}
    for _, line in ipairs(s.lines) do
      lines[#lines + 1] = "  " .. line
    end
  end
  if #lines == 0 then
    return paw.notify("nothing to say about " .. title_of(location))
  end
  local width = 20
  for _, line in ipairs(lines) do
    width = math.max(width, api.str_width(line is contracts.PageLine and line.text or line as string) + 4)
  end
  paw.ui.page(title_of(location), lines, {width = math.min(100, width), height = math.min(30, #lines + 3)})
end

--- Show what is known about a location (by default what is under the
--- cursor of the focused view): the diagnostics about it and what it holds,
--- then each server's hover, in a float.
function M.show_hover(id?: integer | Location, pitch?: integer, beat?: number)
  local location: Location
  if id is Location then
    location = id
  elseif id then
    location = clip_location(id, pitch, beat)
  else
    location = paw.ui.location() as Location
  end
  if not location then
    return paw.notify("nothing here to ask about", "warn")
  end
  local lines: {Line} = {}
  for _, d in ipairs(paw.diagnostic.get(location.uri)) do
    lines[#lines + 1] = {text = paw.diagnostic.format(d), style = paw.diagnostic.group("Diagnostic", d.severity)}
    for _, fix in ipairs(d.fixes) do
      lines[#lines + 1] = "  fix: " .. tostring(fix.title)
    end
  end
  for _, a in ipairs(paw.annotation and paw.annotation.get(location.uri) or {}) do
    lines[#lines + 1] = a.label
  end
  -- The answers may come in another person's turn: the float is shown to whoever asked.
  local seat = paw.seats and paw.seats.current
  M.hover_at(
    location,
    function(sections: {Section})
      if seat and seat ~= paw.seats.current then
        paw.seats.within(seat, function() M.show_lines(location, lines, sections) end)
        return
      end
      M.show_lines(location, lines, sections)
    end
  )
end

--- Pick a fix or an action for a location (by default what is under the
--- cursor of the focused view; off a note in the piano roll, the
--- diagnostics where the cursor is), and carry it out as one undo step.
function M.code_actions(location?: Location)
  location = location or paw.ui.location() as Location
  if not location then
    return paw.notify("nothing here to act on", "warn")
  end
  local p = A.parse(location.uri)
  local fixes: {DiagnosticModule.Action}
  if p and p.kind == "clip" and location.selector and location.selector.time then
    -- Off a note: the diagnostics of the clip that cover this time.
    fixes = {}
    local at = location.selector.time[1]
    for _, d in ipairs(paw.diagnostic.get(p.clip)) do
      if at >= (d.at or 0) - 1e-9 and at < (d.at or 0) + math.max(d.length or 0, 1e-6) then
        for _, fix in ipairs(d.fixes) do
          fixes[#fixes + 1] = {
            title = fix.title, diagnostic = d, run = function(): boolean return paw.diagnostic.apply(d, fix) end
          }
        end
      end
    end
  else
    fixes = paw.diagnostic.actions(location.uri)
  end
  local seat = paw.seats and paw.seats.current
  M.actions_at(
    location,
    function(more: {standard.Action})
      local items: {ActionItem} = {}
      for _, a in ipairs(fixes) do
        items[#items + 1] = {
          text = string.format("%s  (%s)", a.title, a.diagnostic.rule or a.diagnostic.source), run = a.run
        }
      end
      for _, a in ipairs(more) do
        items[#items + 1] = {
          text = string.format("%s  (%s)", a.title, a.source),
          run = a.run
            or function()
              local ok, why = A.edit(a.edit or {}, a.title)
              if not ok then
                paw.notify("cannot: " .. tostring(why), "warn")
              end
            end,
        }
      end
      if #items == 0 then
        return paw.notify("no fixes here")
      end
      local function show()
        local spec: contracts.PickSource<ActionItem> = {
          title = "Code actions",
          items = items,
          on_choose = function(item: ActionItem)
            if item then
              item.run()
            end
          end,
        }
        paw.pick(spec)
      end
      -- The answers may come in another person's turn: the picker is theirs who asked.
      if seat and seat ~= paw.seats.current then
        paw.seats.within(seat, show)
        return
      end
      show()
    end
  )
end

-- Completion -------------------------------------------------------------------

--- A completion source over each server that runs and suggests, in the
--- shape that `paw.complete.register` takes. `ctx` names the `clip` and the
--- start of the suggestion (`at`, beats from the start of the clip), with
--- an optional `selection` (a note set of the clip) and `controller`. paw
--- calls `done(items)` one time.
function M.complete(ctx: standard.CompleteContext, done: function(items: {CompleteModule.ItemInput}))
  local given = ctx.clip
  local id = given is standard.ClipRef and given.id or given as integer
  if not id then
    return done(nil)
  end
  -- A copy with the clip as its id: every field of the request goes on to
  -- the adapters, which may read more of it than paw.complete's own.
  local copy: {string: util.Data} = {}
  for k, v in pairs(ctx as {string: util.Data}) do
    copy[k] = v
  end
  copy.clip = id
  ctx = copy as standard.CompleteContext
  local items: {CompleteModule.ItemInput} = {}
  local asked = 1
  local ids: {Out} = {}
  local function finish()
    asked = asked - 1
    if asked == 0 then
      done(#items > 0 and items or nil)
    end
  end
  for _, client in pairs(clients) do
    if client.status == "running" and M.has(client, "completion") and M.attaches(client, A.clip(id), "clip") then
      local held = client.docs[A.clip(id)]
      local doc = send_doc(client, "clip", A.clip(id), held and held.kept)
      if doc then
        for _, ask in ipairs(client.adapter.complete(client, doc, ctx) or {}) do
          asked = asked + 1
          local request = M.request(
            client,
            ask.method,
            ask.params,
            function(err: RpcError, result: Payload)
              if not err and type(result) == "table" then
                for _, item in ipairs(ask.translate(result)) do
                  item.source = item.source or client.name
                  items[#items + 1] = item
                end
              end
              finish()
            end
          )
          if request then
            ids[#ids + 1] = {client = client, id = request}
          end
        end
      end
    end
  end
  M.pending_completion = ids
  finish()
end

--- Forget the completion requests still out (a newer one replaced them).
function M.complete_cancel()
  for _, r in ipairs(M.pending_completion or {}) do
    M.cancel(r.client, r.id)
  end
  M.pending_completion = nil
end

-- Offered to `paw.complete` when it is there, whichever is loaded first.
local offered = false
local function offer()
  if offered or not (paw.complete and paw.complete.register) then
    return
  end
  offered = true
  paw.complete.register(
    {
      name = "lsp",
      priority = 100,
      views = {"pianoroll"},
      auto = true,
      complete = function(ctx: CompleteModule.Context, done: function(items: {CompleteModule.ItemInput}))
        M.complete(ctx as standard.CompleteContext, done)
      end,
      cancel = function() M.complete_cancel() end,
    }
  )
end
offer()
events.on(events.startup, offer)

-- Following the project ------------------------------------------------------------

-- The piano roll and its clips load before this module (paw/init.lua).
local pianoroll = require("paw.views.pianoroll")
local roll_clips = require("paw.roll_clips")
events.on(
  pianoroll.opened,
  function()
    if next(clients) then
      M.sync()
    end
  end
)
events.on(A.changed, schedule)
events.on(paw.cursor.changed, schedule)
-- Every clip the piano roll edits is open with the servers, not only the active one.
events.on(
  roll_clips.changed,
  function()
    if next(clients) then
      M.sync()
    end
  end
)
events.on(events.exit, function() M.stop() end)

-- `:lsp` -------------------------------------------------------------------------

--- What `:lsp info` shows: each server, its transport, state, what it is
--- attached to and can do, and what it holds.
function M.info_lines(): {Line}
  local lines: {Line} = {}
  local names: {string} = {}
  for name in pairs(M.configs:entries()) do
    names[#names + 1] = name
  end
  table.sort(names)
  if #names == 0 then
    return {
      "No language servers are configured.", "", "paw.lsp.config(name, { cmd = { ... } }) and paw.lsp.enable(name)."
    }
  end
  for _, name in ipairs(names) do
    local client, config = clients[name], M.configs:get(name)
    lines[#lines + 1] = {text = name .. "  " .. (client and client.status or "off"), style = "Title"}
    local transport = config.server and "in-process Lua" or config.kind == "oneshot" and "one-shot command" or "process"
    local adapter = config.adapter
    lines[#lines + 1] = "  transport "
      .. transport
      .. (adapter and (", " .. (adapter is string and adapter or "its own") .. " dialect") or "")
    if not config.server then
      local cmd = command_of(config)
      lines[#lines + 1] = "  command   " .. (cmd and table.concat(cmd, " ") or "(none found)")
    end
    if client then
      if client.error then
        lines[#lines + 1] = "  error     " .. client.error
      end
      if client.info and client.info.name then
        lines[#lines + 1] = "  server    " .. client.info.name .. " " .. tostring(client.info.version or "")
      end
      lines[#lines + 1] = "  subjects  " .. table.concat((attachment(client)), ", ")
      local feats: {string} = {}
      for _, k in ipairs({"diagnostics", "hover", "actions", "completion", "annotations", "analysis"}) do
        if cap_of(client.caps, k) then
          feats[#feats + 1] = k
        end
      end
      if #feats > 0 then
        lines[#lines + 1] = "  can       " .. table.concat(feats, ", ")
      end
      local docs: {string} = {}
      for uri in pairs(client.docs) do
        docs[#docs + 1] = uri
      end
      table.sort(docs)
      if #docs > 0 then
        lines[#lines + 1] = "  documents " .. table.concat(docs, ", ")
      end
    end
    if not config.server then
      lines[#lines + 1] = "  errors to " .. M.log_path(name)
    end
    lines[#lines + 1] = ""
  end
  return lines
end

--- `:lsp [info|start|stop|restart|log] [name]`.
function M.command(ctx: contracts.CommandContext)
  local verb = ctx.args[1] as string or "info"
  local name = ctx.args[2] as string
  if verb == "info" then
    paw.ui.page("Language servers", M.info_lines())
  elseif verb == "log" then
    paw.ui.page("Language servers: log", #M.log > 0 and M.log or {"Nothing yet."}, {bottom = true})
  elseif verb == "stop" then
    M.stop(name)
  elseif verb == "start" or verb == "restart" then
    local names: {string} = {}
    if name then
      names[1] = name
    else
      for n in pairs(M.configs:entries()) do
        names[#names + 1] = n
      end
    end
    for _, n in ipairs(names) do
      local ok, err = pcall(verb == "start" and M.enable or M.restart, n) as (boolean, string)
      if not ok then
        paw.notify(tostring(err), "error")
      end
    end
  else
    paw.notify("lsp: info, start, stop, restart or log", "warn")
  end
end

--- What `:lsp` completes to: its words and the configured servers.
function M.command_complete(): {string}
  local out = {"info", "log", "start", "stop", "restart"}
  for name in pairs(M.configs:entries()) do
    out[#out + 1] = name
  end
  return out
end

-- The window's gestures on the piano roll's notes.
local act = paw.frontend.act as Act
function act.note_hover(clip: integer, place: integer)
  local n = api.clip_notes(clip)[place]
  if n then
    M.show_hover(clip, n.pitch, n.start)
  end
end

M.document_module = document
return M
