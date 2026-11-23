-- A client of TONE3000's public API (https://www.tone3000.com/api): search
-- the tones, list the models of a tone, download a model. Each request is a
-- `curl` process that paw starts (`paw.api.proc_spawn`), so a key never
-- waits on the network; a timer looks at the processes and calls back.
--
-- The token goes from the shell of the process to curl on its standard
-- input (`-H @-`): it is not on a command line, in a log, in the project or
-- in a file of paw (only the sign-in keeps its own tokens, in the keyring or
-- in a file of mode 600: tone3000_auth.tl). The process looks for it in this
-- order, and says which one it used:
--
--   1. the environment variable TONE3000_TOKEN;
--   2. the file that `paw.opt.plugstate_tone3000_token_file` names (only
--      its owner may read it: mode 600 or 400);
--   3. the keyring, through `secret-tool lookup application paw service
--      tone3000`, when secret-tool is there;
--   4. the sign-in of `:plugstate.tone3000_login` (tone3000_auth.tl), which
--      paw renews when it expires;
--   5. only when `paw.opt.plugstate_tone3000_plugin_session` is on: the
--      session of the TONE3000 plugin (the `t3k_tokens` value of
--      `~/.config/TONE3000/ui-preferences.settings`, as the plugin's
--      source keeps it), while it has not expired.
--
-- Without a token, a request goes without one. The API answers 401 when it
-- needs one, and paw says so. The requests of the sign-in itself (a POST
-- with a form) send no token: their form goes to curl on its standard
-- input too, as it holds a refresh token or a device code.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local type types = require("paw.types")

local api = paw.api

local record M
  --- A value of a query or a form: text, a number, or a flag.
  type Param = string | number | boolean

  --- A query or a form: `a=b&c=d` of it, in key order.
  type Params = {string: Param}

  --- What the process wrote to its status file: an error of the token
  --- file (`error`, `mode`), where the token came from (`source`: none,
  --- env, file, keyring, session, plugin), and the codes of curl and HTTP.
  record Status
    error: string
    mode: string
    source: string
    curl: string
    http: string
  end

  --- The JSON of an answer. Its shape depends on the request: each caller
  --- casts it to the record of its request.
  record Answer
  end

  --- An answer of TONE3000 that says what is wrong.
  record ErrorAnswer
    error: string
    error_description: string
    message: string
  end

  --- What a request gives back when it ends: `ok`, the HTTP code, the
  --- JSON (`data`), the file (`path`), the message when it failed, and
  --- where the token came from (`source`).
  record Result
    ok: boolean
    http: number
    data: Answer
    path: string
    message: string
    source: string
    status: Status
    limit: number
    timed_out: boolean
    head: string
    stderr: string
  end

  enum Kind
    "json"
    "file"
  end

  --- How to make a request: `kind` ("json", or "file" with `dest`), `what`
  --- (for the messages), `form` (a POST of it as a form, with no token),
  --- `token` (this token and no other), `timeout` in seconds.
  record RequestOptions
    kind: Kind
    dest: string
    what: string
    form: Params
    token: string
    timeout: number
    --- A request made again after the token of the sign-in was renewed.
    again: boolean
  end

  type Callback = function(result: Result)
  --- A token, or nil when there is none.
  type TokenCallback = function(token: string)

  --- The sign-in (tone3000_auth.tl): `token(cb)` calls back with the
  --- access token of the sign-in, or nil; `renew(cb)` renews it after a
  --- 401; `client_id()` is the key of the app, or nil.
  interface Auth
    token: function(cb: TokenCallback)
    renew: function(cb: TokenCallback)
    client_id: function(): string
  end

  --- An author of a tone.
  record User
    username: string
    display_name: string
  end

  --- A name in a list of the API: a size, a make, a tag.
  record Named
    name: string
  end

  --- A tone of TONE3000, as `/tones/search` gives it.
  record Tone
    id: integer
    title: string
    user: User
    gear: string
    format: string
    sizes: {string | Named}
    makes: {string | Named}
    tags: {string | Named}
    models_count: integer
    downloads_count: integer
    favorites_count: integer
    license: string
    url: string
    description: string
  end

  --- A model of a tone, as `/models` gives it.
  record Model
    id: integer
    name: string
    model_url: string
    format: string
    size: string
    architecture_version: integer
  end

  --- A page of tones or of models.
  record Page<T>
    data: {T}
    page: integer
    total_pages: integer
    total: integer
  end

  --- What a download gives back: the file, or nil and why; `cached` when
  --- paw had it already.
  type DownloadCallback = function(path: string, err?: string, cached?: boolean)

  ORIGIN: string
  --- How long a request may take, in seconds: an API call, a download.
  TIMEOUT: {Kind: number}
  --- The program that reads the keyring (tests give another).
  secret_tool: string
  --- A Unix socket to send the requests to in place of the network (tests).
  unix_socket: string
  --- More environment for the processes (tests).
  env: {string: string}
  --- The sign-in (tone3000_auth.tl sets it).
  auth: Auth
end

local type Result = M.Result

M.ORIGIN = "https://www.tone3000.com/api/v1"
M.TIMEOUT = {json = 20, file = 120}
M.secret_tool = "secret-tool"
-- A file with a TONE3000 access token (mode 600).
local token_file_option = paw.option.define("plugstate_tone3000_token_file", "")
-- Also use the session of the TONE3000 plugin.
local plugin_session_option = paw.option.define("plugstate_tone3000_plugin_session", false)
-- Another address of the API (empty: TONE3000's).
local api_option = paw.option.define("plugstate_tone3000_api", "")

--- The token file as the option names it (empty: none).
function M.token_file(): string
  return token_file_option:get() or ""
end

--- Whether paw may use the session of the TONE3000 plugin.
function M.plugin_session(): boolean
  return plugin_session_option:get()
end

--- A request that runs: its process, the files it writes, where a
--- download goes, and what to call when it ends.
local record Job
  proc: integer
  kind: M.Kind
  out: string
  status: string
  dest: string
  cb: M.Callback
  what: string
  limit: number
  deadline: number
end

-- The requests that run, by process; the timer that looks at them while
-- there are any; a count that makes the names of their files unique.
local jobs: {integer: Job} = {}
local ticker: integer
local serial = 0

-- The token file, with `~` as the home folder; empty when there is none.
local function token_path(): string
  return (M.token_file():gsub("^~", os.getenv("HOME") or "~"))
end

-- --- folders ------------------------------------------------------------------

--- Where paw keeps the files it downloads: `$XDG_CACHE_HOME/paw/tone3000`.
function M.cache_dir(): string
  local cache = os.getenv("XDG_CACHE_HOME")
  if not cache or cache == "" then
    cache = (os.getenv("HOME") or ".") .. "/.cache"
  end
  return cache .. "/paw/tone3000"
end

--- The settings file of the TONE3000 plugin that keeps its session.
function M.plugin_settings(): string
  return (os.getenv("HOME") or "") .. "/.config/TONE3000/ui-preferences.settings"
end

-- --- the plugin's session -------------------------------------------------------

local ENTITIES: {string: string} = {quot = '"', amp = "&", lt = "<", gt = ">", apos = "'"}

local function unescape(text: string): string
  return (
    text:gsub(
      "&(#?x?)(%w+);",
      function(kind: string, body: string): string
        if kind == "#x" then
          return string.char(math.floor(tonumber(body, 16) % 256))
        end
        if kind == "#" then
          return string.char(math.floor(tonumber(body) % 256))
        end
        return ENTITIES[body] or ("&" .. body .. ";")
      end
    )
  )
end

--- The tokens of the plugin's session, as its settings keep them.
local record PluginTokens
  access_token: string
  expires_at: number
end

--- The access token of the plugin's session, or nil and why. Only when the
--- user turned on `plugstate_tone3000_plugin_session`; paw only reads the
--- file. JUCE keeps its settings as XML: `<VALUE name="t3k_tokens"
--- val="{&quot;access_token&quot;: ...}"/>`, the value a JSON object with
--- `access_token`, `refresh_token` and `expires_at` (milliseconds).
function M.plugin_token(): string, string
  local path = M.plugin_settings()
  local f = io.open(path, "rb")
  if not f then
    return nil, "the TONE3000 plugin has no session here (" .. path .. ")"
  end
  local data = f:read(1048576) or ""
  f:close()
  local val = data:match('<VALUE%s+name="t3k_tokens"%s+val="([^"]*)"')
  if not val then
    return nil, "nobody is signed in to the TONE3000 plugin"
  end
  local tokens = api.json_decode(unescape(val)) as PluginTokens
  if type(tokens) ~= "table" or type(tokens.access_token) ~= "string" or tokens.access_token == "" then
    return nil, "the session of the TONE3000 plugin has no token"
  end
  local expires = tonumber(tokens.expires_at)
  if expires and expires < os.time() * 1000 + 30000 then
    return nil, "the session of the TONE3000 plugin has expired: open the plugin's window once to renew it"
  end
  return tokens.access_token
end

-- --- requests -----------------------------------------------------------------

local function percent(c: string): string
  return string.format("%%%02X", c:byte())
end

--- `a=b&c=d` of a table, in key order, without empty values.
function M.query(params?: M.Params): string
  params = params or {}
  local keys: {string} = {}
  for k, v in pairs(params) do
    if v ~= "" and v ~= false then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  local out: {string} = {}
  for _, k in ipairs(keys) do
    local v = params[k]
    local text = v == true and "true" or tostring(v)
    out[#out + 1] = k .. "=" .. text:gsub("[^%w%-%._~]", percent)
  end
  return table.concat(out, "&")
end

-- The process: find the token, then call curl. Its arguments: the URL, the
-- file for the body, the status file, the time limit, the token file, the
-- Unix socket, "post" for a form on the standard input. It writes
-- `key=value` lines to the status file at the end.
local SCRIPT = [=[
url=$1 out=$2 status=$3 limit=$4 tokfile=$5 sock=$6 post=$7
mkdir -p "$(dirname "$out")" "$(dirname "$status")" || exit 1
tok= src=none
say() { printf '%s\n' "$@" >> "$status.part"; }
if [ -n "$post" ]; then
  :
elif [ -n "${PAW_T3K_GIVEN_TOKEN:-}" ]; then
  tok=$PAW_T3K_GIVEN_TOKEN src=session
elif [ -n "${TONE3000_TOKEN:-}" ]; then
  tok=$TONE3000_TOKEN src=env
elif [ -n "$tokfile" ]; then
  if [ ! -f "$tokfile" ]; then
    say "error=token_file_missing"; mv "$status.part" "$status"; exit 0
  fi
  mode=$(stat -c %a -- "$tokfile")
  case $mode in
    600|400) ;;
    *) say "error=token_file_mode" "mode=$mode"; mv "$status.part" "$status"; exit 0 ;;
  esac
  tok=$(head -n 1 -- "$tokfile" | tr -d ' \t\r\n') src=file
  if [ -z "$tok" ]; then say "error=token_file_empty"; mv "$status.part" "$status"; exit 0; fi
elif [ -n "${PAW_T3K_SECRET_TOOL:-}" ] && command -v "$PAW_T3K_SECRET_TOOL" >/dev/null 2>&1 \
    && tok=$(timeout 10 "$PAW_T3K_SECRET_TOOL" lookup application paw service tone3000 2>/dev/null) && [ -n "$tok" ]; then
  src=keyring
elif [ -n "${PAW_T3K_SESSION_TOKEN:-}" ]; then
  tok=$PAW_T3K_SESSION_TOKEN src=session
elif [ -n "${PAW_T3K_PLUGIN_TOKEN:-}" ]; then
  tok=$PAW_T3K_PLUGIN_TOKEN src=plugin
fi
unset TONE3000_TOKEN PAW_T3K_PLUGIN_TOKEN PAW_T3K_SESSION_TOKEN PAW_T3K_GIVEN_TOKEN
set -- --silent --show-error --globoff --location --max-redirs 5 --connect-timeout 10 \
  --max-time "$limit" --user-agent paw-plugstate --header 'Accept: application/json' \
  --output "$out.part" --dump-header "$out.head" --write-out '%{http_code}'
if [ -n "$sock" ]; then set -- "$@" --unix-socket "$sock"; fi
if [ -n "$post" ]; then
  code=$(curl "$@" --header 'Content-Type: application/x-www-form-urlencoded' --data-binary @- -- "$url" 2> "$out.err")
elif [ -n "$tok" ]; then
  code=$(printf 'Authorization: Bearer %s\n' "$tok" | curl "$@" --header @- -- "$url" 2> "$out.err")
else
  code=$(curl "$@" -- "$url" 2> "$out.err")
fi
rc=$?
tok=
[ -f "$out.part" ] && mv "$out.part" "$out"
say "source=$src" "curl=$rc" "http=$code"
mv "$status.part" "$status"
]=]

local function read_all(path: string): string
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

local function parse_status(text: string): M.Status
  local out: {string: string} = {}
  for k, v in (text or ""):gmatch("([%w_]+)=([^\n]*)") do
    out[k] = v
  end
  return out as M.Status
end

local function retry_after(head: string): number
  local n = (head or ""):lower():match("\nretry%-after:%s*(%d+)")
  return n and tonumber(n)
end

-- The names of the sources of a token that TONE3000 did not take.
local SOURCES: {string: string} = {
  env = "variable TONE3000_TOKEN",
  file = "token file",
  keyring = "keyring",
  plugin = "plugin's session",
}

-- The message for an error of the token file, or nil.
local function token_file_error(s: M.Status): string
  local file = M.token_file()
  if s.error == "token_file_missing" then
    return "there is no token file " .. file
  elseif s.error == "token_file_mode" then
    return "the token file "
      .. file
      .. " can be read by others (mode "
      .. tostring(s.mode)
      .. "): paw uses it only with mode 600 (`chmod 600 <file>`)"
  elseif s.error == "token_file_empty" then
    return "the token file " .. file .. " is empty"
  end
end

-- The message for an error of curl, or nil when curl ran to the end.
local function curl_error(result: Result, what: string): string
  local rc = tonumber(result.status.curl)
  if result.timed_out or rc == 28 then
    return what .. " took more than " .. result.limit .. " s: TONE3000 does not answer"
  end
  if rc == 127 then
    return "curl is not installed: paw asks TONE3000 through curl"
  end
  if rc == 6 or rc == 7 or rc == 35 or rc == 52 or rc == 56 then
    return "offline: paw cannot reach TONE3000 ("
      .. ((result.stderr or ""):match("curl: %(%d+%) ([^\n]+)") or "no connection")
      .. ")"
  end
  if rc and rc ~= 0 then
    return "curl failed (" .. ((result.stderr or ""):match("([^\n]+)") or ("code " .. rc)) .. ")"
  end
end

-- The message for a 401: what to do about the token of each source.
local function unauthorized(source: string): string
  if source == "none" then
    return "not signed in: TONE3000 needs a token for this. Sign in with :plugstate.tone3000_login, or set "
      .. "TONE3000_TOKEN, a token file (paw.opt.plugstate_tone3000_token_file) or a keyring entry (see :help plugstate)"
  elseif source == "session" then
    return "TONE3000 does not take the token of your sign-in (it has expired or was revoked): "
      .. "sign in again with :plugstate.tone3000_login"
  end
  return "TONE3000 does not take the token from the "
    .. (SOURCES[source] or source)
    .. " (expired, or not a token): sign in again"
end

-- What TONE3000 said of the error, or nil.
local function said_of(result: Result): string
  local data = result.data as M.ErrorAnswer
  if type(data) ~= "table" then
    return nil
  end
  local said = data.error_description or data.message or data.error
  return said is string and said or nil
end

--- The message for a request that failed, in the words of the user.
function M.why(result: Result, what: string): string
  local early = token_file_error(result.status) or curl_error(result, what)
  if early then
    return early
  end
  local code = result.http
  local said = said_of(result)
  if code == 401 then
    return unauthorized(result.status.source)
  elseif code == 403 then
    return "TONE3000 does not let this account have it" .. (said and (" (" .. said .. ")") or "")
  elseif code == 404 then
    return "TONE3000 has no such " .. what
  elseif code == 429 then
    local wait = retry_after(result.head)
    return "rate limited: TONE3000 takes a limited number of requests a minute. Try again in "
      .. (wait and (wait .. " s") or "a minute")
  end
  return "TONE3000 answered " .. tostring(code) .. (said and (": " .. said) or "")
end

-- Whether the process ran to the end with a 2xx answer.
local function succeeded(result: Result): boolean
  local http = result.http
  return not result.timed_out
    and result.status.error == nil
    and tonumber(result.status.curl) == 0
    and http ~= nil
    and http >= 200
    and http < 300
end

-- The result of a job that ended (or ran out of time), from the files of
-- its process. The files go away; a download takes the place of its file.
local function finish(job: Job, timed_out: boolean): Result
  local status = parse_status(read_all(job.status) or "")
  local result: Result = {
    status = status,
    limit = job.limit,
    timed_out = timed_out,
    head = read_all(job.out .. ".head"),
    stderr = read_all(job.out .. ".err"),
    http = tonumber(status.http),
    source = status.source,
  }
  if job.kind == "json" then
    local body = read_all(job.out)
    if body and body ~= "" then
      result.data = api.json_decode(body) as M.Answer
    end
    os.remove(job.out)
  end
  result.ok = succeeded(result)
  if job.kind == "file" then
    if result.ok then
      result.path = job.dest
      if not os.rename(job.out, job.dest) then
        result.ok, result.message = false, "cannot keep the file in " .. job.dest
      end
    else
      os.remove(job.out)
    end
  elseif result.ok and type(result.data) ~= "table" then
    result.ok, result.message = false, "TONE3000 answered with something that is not JSON"
  end
  if not result.ok and not result.message then
    result.message = M.why(result, job.what)
  end
  for _, f in ipairs({job.status, job.out .. ".head", job.out .. ".err", job.out .. ".part", job.status .. ".part"}) do
    os.remove(f)
  end
  return result
end

--- Look at the requests and call back the ones that have ended. The timer
--- calls it; a test can too.
function M.pump()
  local now = api.now()
  for key, job in pairs(jobs) do
    local ok, st = pcall(api.proc_status, job.proc) as (boolean, types.ProcStatus)
    local over = now > job.deadline
    if not ok or not st.running or over then
      pcall(api.proc_kill, job.proc)
      jobs[key] = nil
      local result = finish(job, over and read_all(job.status) == nil)
      local fine, err = pcall(job.cb, result) as (boolean, string)
      if not fine then
        paw.notify("TONE3000: " .. tostring(err), "error")
      end
    end
  end
  if not next(jobs) and ticker then
    paw.cancel(ticker)
    ticker = nil
  end
end

--- The requests that have not ended.
function M.busy(): integer
  local n = 0
  for _ in pairs(jobs) do
    n = n + 1
  end
  return n
end

-- The environment of a process: where it may find a token.
local function env_of(opts: M.RequestOptions, session_token: string): {string: string}
  local env: {string: string} = {PAW_T3K_SECRET_TOOL = M.secret_tool or ""}
  if M.plugin_session() then
    env.PAW_T3K_PLUGIN_TOKEN = M.plugin_token() or ""
  end
  env.PAW_T3K_SESSION_TOKEN = session_token or ""
  env.PAW_T3K_GIVEN_TOKEN = opts.token or ""
  for k, v in pairs(M.env or {}) do
    env[k] = v
  end
  return env
end

local function spawn(url: string, opts: M.RequestOptions, kind: M.Kind, session_token: string, cb: M.Callback): integer
  serial = serial + 1
  local tmp = M.cache_dir() .. "/tmp"
  local stem = string.format("%s/%d-%d", tmp, math.floor(api.now()), serial)
  local limit = opts.timeout or M.TIMEOUT[kind]
  -- A download goes beside the file it becomes, so that it only has to be
  -- renamed.
  local out = kind == "file" and (opts.dest .. ".download") or (stem .. ".body")
  local argv = {
    "sh",
    "-c",
    SCRIPT,
    "paw-tone3000",
    url,
    out,
    stem .. ".status",
    tostring(limit),
    token_path(),
    M.unix_socket or "",
    opts.form and "post" or "",
  }
  local env = env_of(opts, session_token)
  local ok, proc = pcall(api.proc_spawn, argv, {env = env, pipe = opts.form ~= nil}) as (boolean, integer)
  if not ok then
    cb({ok = false, status = {}, message = "cannot start curl: " .. tostring(proc)})
    return
  end
  if opts.form then
    -- The form (a device code, a refresh token) goes on the standard input.
    pcall(api.proc_write, proc, M.query(opts.form))
    pcall(api.proc_close_input, proc)
  end
  jobs[proc] = {
    proc = proc,
    kind = kind,
    out = out,
    status = stem .. ".status",
    dest = opts.dest,
    cb = cb,
    what = opts.what or "answer",
    limit = limit,
    deadline = api.now() + (limit + 15) * 1000,
  }
  if not ticker then
    ticker = paw.every(50, M.pump)
  end
  return proc
end

--- Start a request. `opts`: `kind` ("json", or "file" with `dest`), `what`
--- (for the messages), `form` (a table: a POST of it as a form, with no
--- token), `token` (this token and no other). `cb(result)` gets `{ ok,
--- http, data, path, message, source }` when it ends. When the token of
--- the sign-in gets a 401, paw renews it and asks once more.
function M.request(url: string, opts: M.RequestOptions, cb: M.Callback): integer
  opts = opts or {}
  local kind = opts.kind or "json"
  if opts.form or opts.token or not M.auth then
    return spawn(url, opts, kind, nil, cb)
  end
  M.auth.token(
    function(session_token: string)
      spawn(
        url,
        opts,
        kind,
        session_token,
        function(result: Result)
          if result.http == 401 and result.source == "session" and not opts.again then
            M.auth.renew(
              function(fresh: string)
                if not fresh then
                  cb(result)
                  return
                end
                local again: M.RequestOptions = {
                  kind = opts.kind,
                  dest = opts.dest,
                  what = opts.what,
                  form = opts.form,
                  token = opts.token,
                  timeout = opts.timeout,
                  again = true,
                }
                M.request(url, again, cb)
              end
            )
            return
          end
          cb(result)
        end
      )
    end
  )
end

--- Stop every request without calling back (when the extension goes).
function M.cancel_all()
  for key, job in pairs(jobs) do
    pcall(api.proc_kill, job.proc)
    jobs[key] = nil
  end
  if ticker then
    paw.cancel(ticker)
    ticker = nil
  end
end

--- The address of the API, without a `/` at the end.
function M.origin(): string
  local o = api_option:get()
  if not o or o == "" then
    o = M.ORIGIN
  end
  return (o:gsub("/+$", ""))
end

--- Search the tones: `params` as `/tones/search` takes them (`query`,
--- `page`, `page_size`, `sort`, `gears`, `format`, `creators`,
--- `architecture`...).
function M.search(params: M.Params, cb: M.Callback): integer
  return M.request(M.origin() .. "/tones/search?" .. M.query(params), {what = "search"}, cb)
end

--- The models of a tone, a page of them.
function M.models(tone_id: integer, params: M.Params, cb: M.Callback): integer
  local p: M.Params = {tone_id = tone_id, page = 1, page_size = 100}
  for k, v in pairs(params or {}) do
    p[k] = v
  end
  return M.request(M.origin() .. "/models?" .. M.query(p), {what = "tone"}, cb)
end

-- --- the files ------------------------------------------------------------------

--- The kind of file of a model: "nam" or "wav", from its URL, else from the
--- format of its tone. Nil for a format that paw cannot load.
function M.extension(model: M.Model, tone?: M.Tone): string
  local ext = tostring(model.model_url or ""):gsub("[?#].*$", ""):match("%.(%w+)$")
  ext = ext and ext:lower()
  if ext == "nam" or ext == "wav" then
    return ext
  end
  local format = tone and tone.format or model.format
  if format == "nam" then
    return "nam"
  end
  if format == "ir" then
    return "wav"
  end
end

local function safe(name: string): string
  local s = tostring(name or ""):gsub("[/%z\1-\31]", " "):gsub("^[%s%.]+", ""):gsub("%s+$", "")
  if s == "" then
    s = "model"
  end
  return s:sub(1, 120)
end

--- Where a model is kept: `<cache>/<model id>/<its name>.<ext>`. The name
--- of the file is the name of the model, so the plugin and paw show it.
function M.cache_path(model: M.Model, tone?: M.Tone): string
  local ext = M.extension(model, tone) or "bin"
  return string.format("%s/%s/%s.%s", M.cache_dir(), tostring(model.id), safe(model.name), ext)
end

--- The file of a model, downloaded at most once. `cb(path)` or `cb(nil, why)`.
function M.download(model: M.Model, tone: M.Tone, cb: M.DownloadCallback)
  local dest = M.cache_path(model, tone)
  local f = io.open(dest, "rb")
  if f then
    local size = f:seek("end")
    f:close()
    if size and size > 0 then
      cb(dest, nil, true)
      return
    end
  end
  if not model.model_url or model.model_url == "" then
    cb(nil, "TONE3000 gives no file for this model")
    return
  end
  M.request(
    model.model_url,
    {kind = "file", dest = dest, what = "model"},
    function(result: Result)
      if result.ok then
        cb(result.path)
      else
        cb(nil, result.message)
      end
    end
  )
end

return M
