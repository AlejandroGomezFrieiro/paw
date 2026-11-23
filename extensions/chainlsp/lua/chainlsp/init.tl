-- chain-lsp's entry for `paw.lsp`, as an nvim-lspconfig entry is for one
-- server: find the server, start it with paw's schema of the chain
-- language, and show it the chain files of the project.
--
-- The server (crates/chain-lsp) is generic and knows nothing of paw. paw
-- gives it the text of each file and its own schema (`paw.api.chain_schema`),
-- and shows its diagnostics in `:diagnostics`. paw edits no chain file yet:
-- the devices of a track become a chain file with the devices graph,
-- and its buffer `paw://track/<n>/devices` then gets this
-- server too.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local standard = require("paw.lsp.standard")
local type rpc = require("paw.lsp.rpc")
local type subjects = require("paw.lsp.subjects")
local type DiagnosticModule = require("paw.diagnostic")

local api = paw.api
local A = paw.address

local type Payload = rpc.Payload
local type Doc = standard.Doc
local type Client = standard.Client
local type AdapterApi = standard.AdapterApi

local record M
  --- The name of the server in `paw.lsp`, and of its subject and dialect.
  NAME: string
  --- The kind of address of a chain file: `paw://chain/<path in the project>`.
  SCHEME: string
  --- How deep under the project folder the files are looked for.
  DEPTH: integer
  --- paw's schema of the chain language, as JSON, which the server gets
  --- when it starts. A test gives a schema of its own.
  schema: function(): string
end
M.NAME = "chain-lsp"
M.SCHEME = "chain"
M.DEPTH = 3
M.schema = function(): string return api.chain_schema() end

local cmd = paw.option.define("chainlsp_cmd", "") -- the server to run; empty: $CHAIN_LSP, else chain-lsp on the PATH

local function words(text: string): {string}
  local out: {string} = {}
  for word in text:gmatch("%S+") do
    out[#out + 1] = word
  end
  return out
end

--- The server's command: `paw.opt.chainlsp_cmd` (words), else
--- `$CHAIN_LSP`, else `chain-lsp` on the PATH. Nil when there is none.
function M.server(): {string}
  local option = cmd:get()
  if option:match("%S") then
    return words(option)
  end
  local env = os.getenv("CHAIN_LSP")
  if env and env:match("%S") then
    return words(env)
  end
  local found = api.which("chain-lsp")
  return found and {found} or nil
end

-- The chain files of the project ---------------------------------------------------

--- The folder of the project, or nil for a project that is not saved.
function M.folder(): string
  local path = (api.project_get as function(string): string)("path")
  if not path then
    return nil
  end
  local stat = api.fs_stat(path)
  if stat and stat.dir then
    return path
  end
  return path:match("^(.*)/[^/]+$")
end

-- A path in an address: each byte that a URI cannot hold, as `%XX`.
local function encode(path: string): string
  return (path:gsub("[^%w%-%._~/]", function(c: string): string return string.format("%%%02X", c:byte()) end))
end

local function decode(text: string): string
  return (text:gsub("%%(%x%x)", function(hex: string): string return string.char(tonumber(hex, 16)) end))
end

--- The address of a file at `relative` in the project folder.
function M.address(relative: string): string
  return "paw://" .. M.SCHEME .. "/" .. encode(relative)
end

--- The path of the file of an address, in the project folder.
function M.path(address: string): string
  local relative = address:match("^paw://" .. M.SCHEME .. "/(.+)$")
  local folder = M.folder()
  if not relative or not folder then
    return nil
  end
  return folder .. "/" .. decode(relative)
end

--- The `.chain` files of the project folder and of its folders, up to
--- `M.DEPTH` deep, by their path in the folder, sorted. A hidden folder is
--- left out.
function M.files(): {string}
  local folder = M.folder()
  local out: {string} = {}
  local function walk(dir: string, prefix: string, depth: integer)
    for _, entry in ipairs(api.read_dir(dir)) do
      local relative = prefix .. entry.name
      if entry.is_dir then
        if depth < M.DEPTH and not entry.name:match("^%.") then
          walk(dir .. "/" .. entry.name, relative .. "/", depth + 1)
        end
      elseif entry.name:match("%.chain$") then
        out[#out + 1] = relative
      end
    end
  end
  if folder then
    walk(folder, "", 1)
  end
  table.sort(out)
  return out
end

-- The subject and the dialect ----------------------------------------------------

--- What paw sends of a chain file: its text.
local record ChainDoc
  text: string
end

local function read(path: string): string
  local file = path and io.open(path, "rb")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

--- The subject `chain`: each chain file of the project, as its text.
local subject: subjects.Subject = {
  language = "chain",
  own = function(uri: string): boolean return uri:match("^paw://" .. M.SCHEME .. "/") ~= nil end,
  targets = function(): {string}
    local out: {string} = {}
    for _, relative in ipairs(M.files()) do
      out[#out + 1] = M.address(relative)
    end
    return out
  end,
  build = function(address: string): Payload
    local text = read(M.path(address))
    if not text then
      return nil
    end
    local doc: ChainDoc = {text = text}
    return doc as Payload
  end,
  -- A file changes outside the project: `:chainlsp check` sends it again.
  depends = {},
  focus = false,
}

-- LSP's text documents, with the text of the file and not the subject as JSON.
local function open(_: Client, doc: Doc): string, Payload, boolean
  local params: standard.DidOpen = {
    textDocument = {uri = doc.uri, languageId = "chain", version = doc.version, text = (doc.data as ChainDoc).text},
  }
  return "textDocument/didOpen", params as Payload
end

local function change(_: Client, doc: Doc): string, Payload, boolean
  local params: standard.DidChange = {
    textDocument = {uri = doc.uri, version = doc.version},
    contentChanges = {{text = (doc.data as ChainDoc).text}},
  }
  return "textDocument/didChange", params as Payload
end

--- A diagnostic of chain-lsp: LSP's, with its place in the text.
local record ChainDiagnostic
  range: standard.Range
  severity: integer
  code: string
  message: string
end

--- The params of `textDocument/publishDiagnostics` from chain-lsp.
local record Published
  uri: string
  diagnostics: {ChainDiagnostic}
end

-- The diagnostics of a file: each on the file, with its line and column
-- (from 1) before its message.
local function publish(client: Client, payload: Payload, lsp: AdapterApi): Payload
  local params = payload as Published
  local doc = lsp.document(client, params.uri)
  if not doc then
    return
  end
  local list: {DiagnosticModule.Published} = {}
  for _, d in ipairs(params.diagnostics or {}) do
    local start = d.range and d.range.start
    local place = start and string.format("%d:%d ", start.line + 1, start.character + 1) or ""
    list[#list + 1] = {
      location = {uri = doc.address},
      severity = d.severity,
      message = place .. tostring(d.message),
      rule = d.code,
      source = "chain",
    }
  end
  lsp.publish(client, doc, list)
end

local handlers: {string: standard.Handler} = setmetatable(
  {["textDocument/publishDiagnostics"] = publish}, {__index = standard.handlers}
)

-- Starting --------------------------------------------------------------------------

--- Tell `paw.lsp` how to start the server, and what a chain file is to it.
function M.configure()
  A.scheme(
    M.SCHEME,
    {
      resolve = function(uri: string): A.Thing
        local path = M.path(uri)
        return path and api.fs_exists(path) and {path = path} as A.Thing or nil
      end,
      where = function(location: paw.contracts.Location): string
        return decode(location.uri:match("^paw://" .. M.SCHEME .. "/(.+)$") or location.uri)
      end,
    }
  )
  paw.lsp.subject(M.NAME, subject)
  paw.lsp.adapter(M.NAME, {name = M.NAME, open = open, change = change, handlers = handlers})
  paw.lsp.config(
    M.NAME,
    {
      cmd = function(): {string} return M.server() end,
      framing = "headers",
      adapter = M.NAME,
      attach = {subjects = {M.NAME}},
      -- paw's own kinds of device, with its plugins and Lua devices, as they
      -- are when the server starts.
      init_options = {schema = M.schema()},
      restart = {max = 3, within_s = 60},
    }
  )
end

--- Start the server. `loud`: say so when there is no server.
function M.start(loud: boolean): boolean
  if not M.server() then
    if loud then
      paw.notify("chainlsp: no server: set paw.opt.chainlsp_cmd or $CHAIN_LSP, or put chain-lsp on the PATH", "warn")
    end
    return false
  end
  M.configure()
  paw.lsp.enable(M.NAME)
  return true
end

function M.stop()
  paw.lsp.enable(M.NAME, false)
end

--- Send each chain file again, as it is on the disk now.
function M.check()
  paw.lsp.sync()
  paw.notify(string.format("chainlsp: %d chain files checked", #M.files()))
end

--- What `:chainlsp` shows.
function M.info_lines(): {paw.contracts.PageLine | string}
  local server = M.server()
  local lines: {paw.contracts.PageLine | string} = {
    {text = "Server", style = "Title"},
    "  "
      .. (
        server and table.concat(server, " ") or "not found: paw.opt.chainlsp_cmd, $CHAIN_LSP or chain-lsp on the PATH"
      ),
    "",
    {text = "Chain files of the project", style = "Title"},
  }
  local files = M.files()
  for _, relative in ipairs(files) do
    lines[#lines + 1] = "  " .. relative
  end
  if #files == 0 then
    lines[#lines + 1] = "  none"
  end
  lines[#lines + 1] = ""
  for _, line in ipairs(paw.lsp.info_lines()) do
    lines[#lines + 1] = line
  end
  return lines
end

return M
