-- The standard dialect: LSP's own shapes, which a server speaks unless its
-- config names another adapter (`paw.lsp.adapter`).
--
--   initialize                     capabilities.paw = { subjects, annotations, analysis }
--   textDocument/didOpen           { textDocument = { uri, languageId, version, text = the subject as JSON } }
--   textDocument/didChange         full text each time
--   textDocument/didClose
--   textDocument/publishDiagnostics  diagnostics[i].data = { location = { uri, selector }, fixes = { { title, edit = { changes } } } }
--   paw/publishAnnotations         { uri, annotations = { { location, label, kind } } }
--   paw/publishAnalysis            { uri, chords, keys, key } in project beats
--   textDocument/hover             params.paw.location: what is asked about
--   textDocument/codeAction        params.paw.location; answered { title, edit = { paw = changes } } or { title, command }
--   textDocument/completion        params.paw = { location, at }; items' data = { notes, velocities, controls }
--   workspace/applyEdit            from the server: { edit = { paw = changes }, label }
--
-- A server run in-process (`server = table`) is sent the subject as a table
-- (`textDocument.data`) instead of JSON text.
--
-- The records here are what every dialect shares with paw/lsp/init.tl: a
-- client, its config, a document, an adapter and what an adapter calls
-- back (`lsp`). A message's own params and results are `rpc.Payload`,
-- which each handler casts once to the record of its method.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local rpc = require("paw.lsp.rpc")
local A = require("paw.address")
local type types = require("paw.types")
local type util = require("paw.util")
local type contracts = require("paw.contracts")
local type DiagnosticModule = require("paw.diagnostic")
local type HarmonyModule = require("paw.harmony")
local type CompleteModule = require("paw.complete")
local type subjects = require("paw.lsp.subjects")

local type Payload = rpc.Payload
local type Location = contracts.Location

-- The shapes paw and every dialect share ---------------------------------------

--- How a server is reached: a process, a table in this process, or a
--- command run once per version of a subject.
local enum Transport
  "process"
  "lua"
  "oneshot"
end

--- A document a server holds: a subject's projection of an address, with
--- the version and key it was sent under. `kept` holds it open when paw
--- would not send it.
local record Doc
  uri: string
  subject: string
  address: string
  language: string
  key: string
  version: integer
  data: Payload
  kept: boolean
end

--- What a server can complete: its lanes (`notes`, `velocity`, `line`, `cc`).
local record CompletionCaps
  lanes: {string}
end

--- What a server can do, in paw's words, and `raw`, what it said.
local record Capabilities
  subjects: {string}
  diagnostics: boolean
  hover: boolean
  actions: boolean
  completion: CompletionCaps
  annotations: boolean
  --- What it hears of the harmony, as the server says it.
  analysis: Payload
  commands: {string}
  raw: RawCapabilities
end

--- The `paw` part of a server's capabilities.
local record PawCapabilities
  subjects: {string}
  annotations: boolean
  analysis: Payload
end

--- LSP's options of `completionProvider`, with paw's lanes.
local record CompletionOptions
  lanes: {string}
end

--- LSP's options of `executeCommandProvider`.
local record CommandOptions
  commands: {string}
end

--- A server's capabilities as it says them at `initialize`: LSP's names
--- (a provider is true or a table of options) and paw's own part.
local record RawCapabilities
  hoverProvider: boolean | Payload
  codeActionProvider: boolean | Payload
  completionProvider: boolean | CompletionOptions
  executeCommandProvider: CommandOptions
  diagnosticProvider: boolean | Payload
  analysisProvider: Payload
  paw: PawCapabilities
end

--- Who the server says it is.
local record ServerInfo
  name: string
  version: string
end

--- What a server answers to `initialize`.
local record InitializeResult
  capabilities: RawCapabilities
  serverInfo: ServerInfo
  protocolVersion: number
end

--- Who paw is, at `initialize`.
local record ClientInfo
  name: string
  version: string
end

--- What paw offers at `initialize` (`capabilities.paw`): the subjects,
--- that it speaks in addresses and takes workspace edits, its features.
local record PawOffer
  subjects: {string}
  addresses: boolean
  workspaceEdit: boolean
  features: {string}
end

--- The capabilities that paw offers.
local record OfferCapabilities
  paw: PawOffer
end

--- What paw sends at `initialize`. A dialect may add its protocol's
--- version (`protocolVersion`).
local record Offer
  processId: integer
  clientInfo: ClientInfo
  capabilities: OfferCapabilities
  initializationOptions: Payload
  configuration: Payload
  protocolVersion: integer
end

--- Which subjects a server is shown, and where: `subjects` (or the older
--- `kinds`), `where`, and the older `tracks` and `drums`.
local record Attach
  subjects: {string}
  kinds: {string}
  where: subjects.Where
  tracks: {string}
  drums: boolean
end

--- How many times a server is started again after it dies, and within
--- how many seconds.
local record Restart
  max: integer
  within_s: number
end

--- What a one-shot command printed of one thing it found: the rule, the
--- severity (`off` leaves it out), the message and, for a sound, the time
--- in seconds.
local record Finding
  rule: string
  severity: DiagnosticModule.Level
  message: string
  time_s: number
end

--- What a server in this process is handed: `notify` sends this program a
--- notification, `request` asks it something and returns the answer.
local record ServerContext
  name: string
  notify: function(method: string, params?: Payload)
  request: function(method: string, params?: Payload): Payload
end

--- A server in this process: a handler for each method, which returns the
--- answer of a request.
local type Server = {string: function(params: Payload, ctx: ServerContext): Payload}

--- A function that gives the command of a server.
local type CommandFn = function(): {string} | string

--- The command of a server: its words, one word, or a function giving them.
local type Command = {string} | string | CommandFn

--- How to start a server and what to show it (`paw.lsp.config`; the top
--- of paw/lsp/init.tl tells each field).
local record Config
  cmd: Command
  server: Server
  kind: string
  framing: rpc.Framing
  adapter: string | Adapter
  attach: Attach
  settings: {string: util.Data}
  init_options: {string: util.Data}
  restart: Restart
  env: {string: string}
  cwd: string
  timeout_ms: number
  accepts: function(doc: Doc): boolean
  input: function(doc: Doc): Payload
  diagnostic: function(finding: Finding, doc: Doc): DiagnosticModule.Published
end

--- What a request waits for: its method and the function the answer goes to.
local record Pending
  method: string
  cb: function(err: rpc.RpcError, result?: Payload)
end

--- A server that was enabled, and its state.
local record Client
  name: string
  config: Config
  status: string
  error: string
  transport: Transport
  proc: integer
  reader: rpc.Reader
  server: Server
  ctx: ServerContext
  adapter: Adapter
  caps: Capabilities
  info: ServerInfo
  protocol: number
  pending: {rpc.Id: Pending}
  docs: {string: Doc}
  next_id: integer
  restarts: {number}
  running: integer
end

--- A label of a server on an address (`paw.annotation`).
local record Annotation
  location: Location
  label: string
  kind: string
  tooltip: string
end

--- What a server heard of a clip's harmony, in project beats.
local record Analysis
  chords: {HarmonyModule.ProvidedChord}
  keys: {HarmonyModule.ProvidedKey}
  key: HarmonyModule.ProvidedKey
end

--- An action of a server at a location: a workspace edit, or `run`.
local record Action
  title: string
  edit: {A.Change}
  run: function()
  source: string
end

--- A clip given by its object rather than its id.
local record ClipRef
  id: integer
end

--- What a completion asks about (`paw.lsp.complete`): the clip, the beat
--- the suggestion starts at (from the clip's start), a note set of the
--- clip, a controller, and who asked.
local record CompleteContext
  clip: integer | ClipRef
  at: number
  selection: {types.Note}
  controller: integer
  count: integer
  mode: string
  trigger: string
end

--- One request of a completion: its method and params, and how its answer
--- becomes items of `paw.complete`.
local record Ask
  method: string
  params: Payload
  translate: function(result: Payload): {CompleteModule.ItemInput}
end

--- A request of a server, or a request or notification of paw, by a
--- client or a client's name.
local type Which = Client | string

--- What an adapter's handlers call with what a server said, in this
--- program's terms (`paw.lsp.adapter_api`).
local record AdapterApi
  document: function(client: Client, uri: string): Doc
  publish: function(client: Client, doc: Doc, list: {DiagnosticModule.Published})
  annotate: function(client: Client, doc: Doc, list: {Annotation})
  request: function(
    which: Which, method: string, params?: Payload, cb?: function(err: rpc.RpcError, result?: Payload)
  ): integer
  notify: function(which: Which, method: string, params?: Payload): boolean
  analysis: function(client: Client, doc: Doc, analysis: Analysis)
end

--- A handler of what a server sends in a dialect: its answer, for a request.
local type Handler = function(client: Client, params: Payload, lsp: AdapterApi, message?: rpc.Message): Payload

--- A dialect: how a kind of server is spoken to. An adapter that leaves a
--- function out has the standard one.
local record Adapter
  name: string
  initialize: function(client: Client, offer: Offer): Offer
  capabilities: function(client: Client, result: InitializeResult): Capabilities
  initialized: function(client: Client, result: InitializeResult): string, Payload
  open: function(client: Client, doc: Doc): string, Payload, boolean
  change: function(client: Client, doc: Doc): string, Payload, boolean
  close: function(client: Client, doc: Doc): string, Payload
  handlers: {string: Handler}
  hover: function(client: Client, doc: Doc, location: Location): string, Payload, function(result: Payload): {string}
  actions: function(client: Client, doc: Doc, location: Location, lsp: AdapterApi): string, Payload, function(
    result: Payload
  ): {Action}
  complete: function(client: Client, doc: Doc, ctx: CompleteContext): {Ask}
end

-- LSP's messages, as the standard dialect sends and reads them -----------------

--- A document as `textDocument/didOpen` names it: the subject as JSON
--- text, or, to a server in this process, as a table (`data`).
local record TextDocument
  uri: string
  languageId: string
  version: integer
  text: string
  data: Payload
end

--- The params of `textDocument/didOpen`.
local record DidOpen
  textDocument: TextDocument
end

--- A change of `textDocument/didChange`: the whole text, or the table.
local record ContentChange
  text: string
  data: Payload
end

--- The params of `textDocument/didChange`.
local record DidChange
  textDocument: TextDocument
  contentChanges: {ContentChange}
end

--- The params of `textDocument/didClose`.
local record DidClose
  textDocument: TextDocument
end

--- What a diagnostic of LSP holds in `data`: paw's location and fixes.
local record DiagnosticData
  location: string | Location
  fixes: {DiagnosticModule.Fix}
end

--- A diagnostic as LSP has it.
local record LspDiagnostic
  severity: DiagnosticModule.Level
  message: string
  code: string
  source: string
  data: DiagnosticData
end

--- The params of `textDocument/publishDiagnostics`.
local record PublishDiagnostics
  uri: string
  diagnostics: {LspDiagnostic}
end

--- A label as `paw/publishAnnotations` has it.
local record LspAnnotation
  location: string | Location
  label: string
  kind: string
  tooltip: string
end

--- The params of `paw/publishAnnotations`.
local record PublishAnnotations
  uri: string
  annotations: {LspAnnotation}
end

--- The params of `paw/publishAnalysis`: the harmony in project beats.
local record PublishAnalysis
  uri: string
  chords: {HarmonyModule.ProvidedChord}
  keys: {HarmonyModule.ProvidedKey}
  key: HarmonyModule.ProvidedKey
end

--- A place in a text, as LSP has it.
local record Position
  line: integer
  character: integer
end

--- A stretch of a text, as LSP has it.
local record Range
  start: Position
  ["end"]: Position
end

--- What paw adds to a request about a place: the location, and for a
--- completion where it starts and the note set chosen.
local record PawPlace
  location: Location
  at: number
  selection: {types.Note}
end

--- The context of a request about a place: `textDocument/codeAction`
--- sends the diagnostics there, `textDocument/completion` the kind of
--- trigger (1 when asked, 3 when paw asks by itself).
local record PlaceContext
  diagnostics: {LspDiagnostic}
  triggerKind: integer
end

--- The params of a request about a place (`textDocument/hover`,
--- `codeAction`, `completion`): LSP's place, with paw's.
local record PlaceParams
  textDocument: TextDocument
  position: Position
  paw: PawPlace
  range: Range
  context: PlaceContext
end

--- Markup, as LSP's hover has it.
local record Markup
  value: string
end

--- The contents of a hover that are not plain text: markup (`value`),
--- or a list of texts and markup.
local record Contents is {string | Markup}
  value: string
end

--- LSP's hover: text, markup, or a list of either.
local record Hover
  contents: string | Contents
end

--- A command of LSP: its name and arguments.
local record LspCommand
  command: string
  arguments: {Payload}
end

--- The edit of a code action: paw's changes.
local record ActionEdit
  paw: {A.Change}
end

--- A code action as LSP has it.
local record CodeAction
  title: string
  edit: ActionEdit
  command: string | LspCommand
end

--- The params of `workspace/executeCommand`.
local record ExecuteCommand
  command: string
  arguments: {Payload}
end

--- What a completion item carries in `data`: notes, velocities, controller moves.
local record CompletionData
  notes: {CompleteModule.NoteInput}
  velocities: {integer: number}
  controls: {types.Control}
end

--- A completion item, as LSP has it.
local record CompletionItem
  label: string
  detail: string
  data: CompletionData
end

--- LSP's completion list (or a list of items alone).
local record CompletionList is {CompletionItem}
  items: {CompletionItem}
end

--- The params of `workspace/applyEdit` from a server.
local record ApplyEdit
  edit: ActionEdit
  label: string
end

--- The params of `workspace/didChangeConfiguration`.
local record DidChangeConfiguration
  settings: Payload
end

--- The answer to `workspace/applyEdit`.
local record ApplyEditResult
  applied: boolean
  failureReason: string
end

local record M
  type Payload = Payload
  type Transport = Transport
  type Doc = Doc
  type CompletionCaps = CompletionCaps
  type Capabilities = Capabilities
  type PawCapabilities = PawCapabilities
  type CompletionOptions = CompletionOptions
  type CommandOptions = CommandOptions
  type RawCapabilities = RawCapabilities
  type ServerInfo = ServerInfo
  type InitializeResult = InitializeResult
  type ClientInfo = ClientInfo
  type PawOffer = PawOffer
  type OfferCapabilities = OfferCapabilities
  type Offer = Offer
  type Attach = Attach
  type Restart = Restart
  type Finding = Finding
  type ServerContext = ServerContext
  type Server = Server
  type CommandFn = CommandFn
  type Command = Command
  type Config = Config
  type Pending = Pending
  type Client = Client
  type Annotation = Annotation
  type Analysis = Analysis
  type Action = Action
  type ClipRef = ClipRef
  type CompleteContext = CompleteContext
  type Ask = Ask
  type Which = Which
  type AdapterApi = AdapterApi
  type Handler = Handler
  type Adapter = Adapter
  type TextDocument = TextDocument
  type DidOpen = DidOpen
  type ContentChange = ContentChange
  type DidChange = DidChange
  type DidClose = DidClose
  type DiagnosticData = DiagnosticData
  type LspDiagnostic = LspDiagnostic
  type PublishDiagnostics = PublishDiagnostics
  type LspAnnotation = LspAnnotation
  type PublishAnnotations = PublishAnnotations
  type PublishAnalysis = PublishAnalysis
  type Position = Position
  type Range = Range
  type PawPlace = PawPlace
  type PlaceContext = PlaceContext
  type PlaceParams = PlaceParams
  type Markup = Markup
  type Contents = Contents
  type Hover = Hover
  type LspCommand = LspCommand
  type ActionEdit = ActionEdit
  type CodeAction = CodeAction
  type ExecuteCommand = ExecuteCommand
  type CompletionData = CompletionData
  type CompletionItem = CompletionItem
  type CompletionList = CompletionList
  type ApplyEdit = ApplyEdit
  type ApplyEditResult = ApplyEditResult
  type DidChangeConfiguration = DidChangeConfiguration
  name: string
  initialize: function(client: Client, offer: Offer): Offer
  capabilities: function(client: Client, result: InitializeResult): Capabilities
  initialized: function(client: Client, result: InitializeResult): string, Payload
  open: function(client: Client, doc: Doc): string, Payload, boolean
  change: function(client: Client, doc: Doc): string, Payload, boolean
  close: function(client: Client, doc: Doc): string, Payload
  handlers: {string: Handler}
  hover: function(client: Client, doc: Doc, location: Location): string, Payload, function(result: Payload): {string}
  actions: function(client: Client, doc: Doc, location: Location, lsp: AdapterApi): string, Payload, function(
    result: Payload
  ): {Action}
  complete: function(client: Client, doc: Doc, ctx: CompleteContext): {Ask}
end
M.name = "standard"

local function text_document(client: Client, doc: Doc): TextDocument
  local td: TextDocument = {uri = doc.uri, languageId = doc.language, version = doc.version}
  if client.transport == "lua" then
    td.data = doc.data
  else
    td.text = rpc.encode(doc.data)
  end
  return td
end

function M.initialize(_: Client, offer: Offer): Offer
  return offer
end

function M.capabilities(_: Client, result: InitializeResult): Capabilities
  local raw = type(result.capabilities) == "table" and result.capabilities or {}
  local paw_caps = type(raw.paw) == "table" and raw.paw or {}
  local completion = raw.completionProvider
  return {
    subjects = paw_caps.subjects,
    diagnostics = true,
    hover = raw.hoverProvider and true or false,
    actions = raw.codeActionProvider and true or false,
    completion = completion and {lanes = completion is CompletionOptions and completion.lanes or {"notes"}} or nil,
    annotations = paw_caps.annotations and true or false,
    analysis = paw_caps.analysis,
    commands = type(raw.executeCommandProvider) == "table" and raw.executeCommandProvider.commands or nil,
    raw = raw,
  }
end

function M.initialized(_: Client, _: InitializeResult): string, Payload
  return "initialized", rpc.object()
end

function M.open(client: Client, doc: Doc): string, Payload, boolean
  local params: DidOpen = {textDocument = text_document(client, doc)}
  return "textDocument/didOpen", params as Payload
end

function M.change(client: Client, doc: Doc): string, Payload, boolean
  local change: ContentChange = client.transport == "lua" and {data = doc.data} or {text = rpc.encode(doc.data)}
  local params: DidChange = {textDocument = {uri = doc.uri, version = doc.version}, contentChanges = {change}}
  return "textDocument/didChange", params as Payload
end

function M.close(_: Client, doc: Doc): string, Payload
  local params: DidClose = {textDocument = {uri = doc.uri}}
  return "textDocument/didClose", params as Payload
end

local function location_of(doc: Doc, loc: string | Location): Location
  if loc is string then
    return {uri = loc}
  end
  return loc or {uri = doc.address}
end

M.handlers = {}

M.handlers["textDocument/publishDiagnostics"] = function(client: Client, payload: Payload, lsp: AdapterApi): Payload
  local params = payload as PublishDiagnostics
  local doc = lsp.document(client, params.uri)
  if not doc then
    return
  end
  local list: {DiagnosticModule.Published} = {}
  for _, d in ipairs(params.diagnostics or {}) do
    local data: DiagnosticData = type(d.data) == "table" and d.data or {}
    list[#list + 1] = {
      location = location_of(doc, data.location),
      severity = d.severity,
      message = d.message,
      rule = d.code,
      source = d.source or client.name,
      fixes = data.fixes,
      data = data as DiagnosticModule.Data,
    }
  end
  lsp.publish(client, doc, list)
end

M.handlers["paw/publishAnnotations"] = function(client: Client, payload: Payload, lsp: AdapterApi): Payload
  local params = payload as PublishAnnotations
  local doc = lsp.document(client, params.uri)
  if not doc then
    return
  end
  local list: {Annotation} = {}
  for _, a in ipairs(params.annotations or {}) do
    list[#list + 1] = {location = location_of(doc, a.location), label = a.label, kind = a.kind, tooltip = a.tooltip}
  end
  lsp.annotate(client, doc, list)
end

M.handlers["paw/publishAnalysis"] = function(client: Client, payload: Payload, lsp: AdapterApi): Payload
  local params = payload as PublishAnalysis
  local doc = lsp.document(client, params.uri)
  if doc then
    lsp.analysis(client, doc, params as Analysis)
  end
end

local function about(doc: Doc, location: Location): PlaceParams
  return {textDocument = {uri = doc.uri}, position = {line = 0, character = 0}, paw = {location = location}}
end

function M.hover(_: Client, doc: Doc, location: Location): string, Payload, function(result: Payload): {string}
  return "textDocument/hover",
    about(doc, location) as Payload,
    function(payload: Payload): {string}
      if type(payload) ~= "table" then
        return {}
      end
      local contents = (payload as Hover).contents
      local text: string
      if contents is Contents then
        if contents.value then
          text = contents.value
        else
          local parts: {string} = {}
          for _, c in ipairs(contents) do
            parts[#parts + 1] = c is Markup and c.value or tostring(c)
          end
          text = table.concat(parts, "\n")
        end
      else
        text = contents
      end
      local out: {string} = {}
      for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
        out[#out + 1] = line
      end
      if out[#out] == "" then
        out[#out] = nil
      end
      return out
    end
end

function M.actions(client: Client, doc: Doc, location: Location, lsp: AdapterApi): string, Payload, function(
  result: Payload
): {Action}
  local params = about(doc, location)
  params.range = {start = params.position, ["end"] = params.position}
  params.context = {diagnostics = {}}
  return "textDocument/codeAction",
    params as Payload,
    function(result: Payload): {Action}
      local out: {Action} = {}
      for _, a in ipairs(type(result) == "table" and result as {CodeAction} or {}) do
        local changes = type(a.edit) == "table" and a.edit.paw
        local command: LspCommand
        local given = a.command
        if given is LspCommand then
          command = given
        elseif given then
          command = {command = given}
        end
        if changes or command then
          out[#out + 1] = {
            title = a.title,
            edit = changes or nil,
            run = command
              and function()
                local run: ExecuteCommand = {command = command.command, arguments = command.arguments}
                lsp.request(client, "workspace/executeCommand", run as Payload)
              end or nil,
          }
        end
      end
      return out
    end
end

function M.complete(_: Client, doc: Doc, ctx: CompleteContext): {Ask}
  local at = ctx.at or 0
  local params = about(doc, {uri = A.clip(ctx.clip as integer), selector = {time = {at, at}}})
  params.paw.at, params.paw.selection = ctx.at, ctx.selection
  params.context = {triggerKind = ctx.trigger == "auto" and 3 or 1}
  return {
    {
      method = "textDocument/completion",
      params = params as Payload,
      translate = function(result: Payload): {CompleteModule.ItemInput}
        local list = result as CompletionList
        local items: {CompletionItem} = type(result) == "table" and (list.items or list as {CompletionItem}) or {}
        local out: {CompleteModule.ItemInput} = {}
        for _, item in ipairs(items) do
          local data: CompletionData = type(item.data) == "table" and item.data or {}
          out[#out + 1] = {
            label = item.label,
            detail = item.detail,
            notes = data.notes or {},
            velocities = data.velocities,
            controls = data.controls,
          }
        end
        return out
      end,
    },
  }
end

return M
