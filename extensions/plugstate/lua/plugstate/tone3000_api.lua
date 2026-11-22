-- A client of TONE3000's public API (https://www.tone3000.com/api): search
-- the tones, list the models of a tone, download a model. Each request is a
-- `curl` process that paw starts (`paw.api.proc_spawn`), so a key never
-- waits on the network; a timer looks at the processes and calls back.
--
-- The token goes from the shell of the process to curl on its standard
-- input (`-H @-`): it is not on a command line, in a log, in the project or
-- in a file of paw (only the sign-in keeps its own tokens, in the keyring or
-- in a file of mode 600: tone3000_auth.lua). The process looks for it in this order, and says which
-- one it used:
--
--   1. the environment variable TONE3000_TOKEN;
--   2. the file that `paw.opt.plugstate_tone3000_token_file` names (only
--      its owner may read it: mode 600 or 400);
--   3. the keyring, through `secret-tool lookup application paw service
--      tone3000`, when secret-tool is there;
--   4. the sign-in of `:plugstate.tone3000_login` (tone3000_auth.lua), which
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
local api = paw.api

local M = {}

M.ORIGIN = "https://www.tone3000.com/api/v1"
--- How long a request may take, in seconds: an API call, a download.
M.TIMEOUT = { json = 20, file = 120 }
--- The program that reads the keyring (tests give another).
M.secret_tool = "secret-tool"
--- A Unix socket to send the requests to in place of the network (tests).
M.unix_socket = nil
--- More environment for the processes (tests).
M.env = nil
--- The sign-in (tone3000_auth.lua sets it): `token(cb)` calls back with the
--- access token of the sign-in, or nil; `renew(cb)` renews it after a 401.
M.auth = nil

local jobs, ticker, serial = {}, nil, 0

-- --- folders ------------------------------------------------------------------

--- Where paw keeps the files it downloads: `$XDG_CACHE_HOME/paw/tone3000`.
function M.cache_dir()
  local cache = os.getenv("XDG_CACHE_HOME")
  if not cache or cache == "" then cache = (os.getenv("HOME") or ".") .. "/.cache" end
  return cache .. "/paw/tone3000"
end

--- The settings file of the TONE3000 plugin that keeps its session.
function M.plugin_settings() return (os.getenv("HOME") or "") .. "/.config/TONE3000/ui-preferences.settings" end

-- --- the plugin's session -------------------------------------------------------

local ENTITIES = { quot = '"', amp = "&", lt = "<", gt = ">", apos = "'" }

local function unescape(text)
  return (
    text:gsub("&(#?x?)(%w+);", function(kind, body)
      if kind == "#x" then return string.char(tonumber(body, 16) % 256) end
      if kind == "#" then return string.char(tonumber(body) % 256) end
      return ENTITIES[body] or ("&" .. body .. ";")
    end)
  )
end

--- The access token of the plugin's session, or nil and why. Only when the
--- user turned on `plugstate_tone3000_plugin_session`; paw only reads the
--- file. JUCE keeps its settings as XML: `<VALUE name="t3k_tokens"
--- val="{&quot;access_token&quot;: ...}"/>`, the value a JSON object with
--- `access_token`, `refresh_token` and `expires_at` (milliseconds).
function M.plugin_token()
  local path = M.plugin_settings()
  local f = io.open(path, "rb")
  if not f then return nil, "the TONE3000 plugin has no session here (" .. path .. ")" end
  local data = f:read(1048576) or ""
  f:close()
  local val = data:match('<VALUE%s+name="t3k_tokens"%s+val="([^"]*)"')
  if not val then return nil, "nobody is signed in to the TONE3000 plugin" end
  local tokens = api.json_decode(unescape(val))
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

--- `a=b&c=d` of a table, in key order, without empty values.
function M.query(params)
  local keys = {}
  for k, v in pairs(params or {}) do
    if v ~= nil and v ~= "" and v ~= false then keys[#keys + 1] = k end
  end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    local v = params[k]
    if v == true then v = "true" end
    out[#out + 1] = k
      .. "="
      .. tostring(v):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end)
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

local function read_all(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function parse_status(text)
  local out = {}
  for k, v in (text or ""):gmatch("([%w_]+)=([^\n]*)") do
    out[k] = v
  end
  return out
end

local function retry_after(head)
  local n = (head or ""):lower():match("\nretry%-after:%s*(%d+)")
  return n and tonumber(n)
end

--- The message for a request that failed, in the words of the user.
local function why(result, what)
  local s = result.status
  if s.error == "token_file_missing" then
    return "there is no token file " .. tostring(paw.opt.plugstate_tone3000_token_file)
  elseif s.error == "token_file_mode" then
    return "the token file "
      .. tostring(paw.opt.plugstate_tone3000_token_file)
      .. " can be read by others (mode "
      .. tostring(s.mode)
      .. "): paw uses it only with mode 600 (`chmod 600 <file>`)"
  elseif s.error == "token_file_empty" then
    return "the token file " .. tostring(paw.opt.plugstate_tone3000_token_file) .. " is empty"
  end
  local rc = tonumber(s.curl)
  if result.timed_out or rc == 28 then
    return what .. " took more than " .. result.limit .. " s: TONE3000 does not answer"
  end
  if rc == 127 then return "curl is not installed: paw asks TONE3000 through curl" end
  if rc == 6 or rc == 7 or rc == 35 or rc == 52 or rc == 56 then
    return "offline: paw cannot reach TONE3000 ("
      .. ((result.stderr or ""):match("curl: %(%d+%) ([^\n]+)") or "no connection")
      .. ")"
  end
  if rc and rc ~= 0 then
    return "curl failed (" .. ((result.stderr or ""):match("([^\n]+)") or ("code " .. rc)) .. ")"
  end
  local code = result.http
  local said = type(result.data) == "table"
    and (result.data.error_description or result.data.message or result.data.error)
  said = type(said) == "string" and said or nil
  if code == 401 then
    if s.source == "none" then
      return "not signed in: TONE3000 needs a token for this. Sign in with :plugstate.tone3000_login, or set "
        .. "TONE3000_TOKEN, a token file (paw.opt.plugstate_tone3000_token_file) or a keyring entry (see :help plugstate)"
    elseif s.source == "session" then
      return "TONE3000 does not take the token of your sign-in (it has expired or was revoked): "
        .. "sign in again with :plugstate.tone3000_login"
    end
    return "TONE3000 does not take the token from the "
      .. (({
        env = "variable TONE3000_TOKEN",
        file = "token file",
        keyring = "keyring",
        plugin = "plugin's session",
      })[s.source] or s.source)
      .. " (expired, or not a token): sign in again"
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

M.why = why

local function finish(job, timed_out)
  local status_text = read_all(job.status) or ""
  local result = {
    status = parse_status(status_text),
    limit = job.limit,
    timed_out = timed_out,
    head = read_all(job.out .. ".head"),
    stderr = read_all(job.out .. ".err"),
  }
  result.http = tonumber(result.status.http)
  result.source = result.status.source
  if job.kind == "json" then
    local body = read_all(job.out)
    if body and body ~= "" then result.data = api.json_decode(body) end
    os.remove(job.out)
  end
  result.ok = not timed_out
    and result.status.error == nil
    and tonumber(result.status.curl) == 0
    and result.http
    and result.http >= 200
    and result.http < 300
  if job.kind == "file" then
    if result.ok then
      result.path = job.dest
      local fine = os.rename(job.out, job.dest)
      if not fine then
        result.ok, result.message = false, "cannot keep the file in " .. job.dest
      end
    else
      os.remove(job.out)
    end
  elseif result.ok and type(result.data) ~= "table" then
    result.ok, result.message = false, "TONE3000 answered with something that is not JSON"
  end
  if not result.ok and not result.message then result.message = why(result, job.what) end
  for _, f in ipairs({ job.status, job.out .. ".head", job.out .. ".err", job.out .. ".part", job.status .. ".part" }) do
    os.remove(f)
  end
  return result
end

--- Look at the requests and call back the ones that have ended. The timer
--- calls it; a test can too.
function M.pump()
  local now = api.now()
  for key, job in pairs(jobs) do
    local ok, st = pcall(api.proc_status, job.proc)
    local over = now > job.deadline
    if not ok or not st.running or over then
      pcall(api.proc_kill, job.proc)
      jobs[key] = nil
      local result = finish(job, over and read_all(job.status) == nil)
      local fine, err = pcall(job.cb, result)
      if not fine then paw.notify("TONE3000: " .. tostring(err), "error") end
    end
  end
  if not next(jobs) and ticker then
    paw.cancel(ticker)
    ticker = nil
  end
end

--- The requests that have not ended.
function M.busy()
  local n = 0
  for _ in pairs(jobs) do
    n = n + 1
  end
  return n
end

local function spawn(url, opts, kind, session_token, cb)
  serial = serial + 1
  local tmp = M.cache_dir() .. "/tmp"
  local stem = string.format("%s/%d-%d", tmp, math.floor(api.now()), serial)
  local limit = opts.timeout or M.TIMEOUT[kind]
  local env = { PAW_T3K_SECRET_TOOL = M.secret_tool or "" }
  if paw.opt.plugstate_tone3000_plugin_session then env.PAW_T3K_PLUGIN_TOKEN = M.plugin_token() or "" end
  env.PAW_T3K_SESSION_TOKEN = session_token or ""
  env.PAW_T3K_GIVEN_TOKEN = opts.token or ""
  for k, v in pairs(M.env or {}) do
    env[k] = v
  end
  local token_file = (paw.opt.plugstate_tone3000_token_file or ""):gsub("^~", os.getenv("HOME") or "~")
  -- A download goes beside the file it becomes, so that it only has to be
  -- renamed.
  local out = kind == "file" and (opts.dest .. ".download") or (stem .. ".body")
  local post = opts.form and "post" or ""
  local argv = {
    "sh",
    "-c",
    SCRIPT,
    "paw-tone3000",
    url,
    out,
    stem .. ".status",
    tostring(limit),
    token_file,
    M.unix_socket or "",
    post,
  }
  local ok, proc = pcall(api.proc_spawn, argv, { env = env, pipe = opts.form ~= nil })
  if not ok then
    cb({ ok = false, status = {}, message = "cannot start curl: " .. tostring(proc) })
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
  if not ticker then ticker = paw.every(50, M.pump) end
  return proc
end

--- Start a request. `opts`: `kind` ("json", or "file" with `dest`), `what`
--- (for the messages), `form` (a table: a POST of it as a form, with no
--- token), `token` (this token and no other). `cb(result)` gets `{ ok,
--- http, data, path, message, source }` when it ends. When the token of
--- the sign-in gets a 401, paw renews it and asks once more.
function M.request(url, opts, cb)
  opts = opts or {}
  local kind = opts.kind or "json"
  if opts.form or opts.token or not M.auth then return spawn(url, opts, kind, nil, cb) end
  M.auth.token(function(session_token)
    spawn(url, opts, kind, session_token, function(result)
      if result.http == 401 and result.source == "session" and not opts.again then
        return M.auth.renew(function(fresh)
          if not fresh then return cb(result) end
          local again = {}
          for k, v in pairs(opts) do
            again[k] = v
          end
          again.again = true
          M.request(url, again, cb)
        end)
      end
      cb(result)
    end)
  end)
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

local function origin()
  local o = paw.opt.plugstate_tone3000_api
  if not o or o == "" then o = M.ORIGIN end
  return (o:gsub("/+$", ""))
end

M.origin = origin

--- Search the tones: `params` as `/tones/search` takes them (`query`,
--- `page`, `page_size`, `sort`, `gears`, `format`, `creators`,
--- `architecture`...).
function M.search(params, cb) return M.request(origin() .. "/tones/search?" .. M.query(params), { what = "search" }, cb) end

--- The models of a tone, a page of them.
function M.models(tone_id, params, cb)
  local p = { tone_id = tone_id, page = 1, page_size = 100 }
  for k, v in pairs(params or {}) do
    p[k] = v
  end
  return M.request(origin() .. "/models?" .. M.query(p), { what = "tone" }, cb)
end

-- --- the files ------------------------------------------------------------------

--- The kind of file of a model: "nam" or "wav", from its URL, else from the
--- format of its tone. Nil for a format that paw cannot load.
function M.extension(model, tone)
  local ext = tostring(model.model_url or ""):gsub("[?#].*$", ""):match("%.(%w+)$")
  ext = ext and ext:lower()
  if ext == "nam" or ext == "wav" then return ext end
  local format = tone and tone.format or model.format
  if format == "nam" then return "nam" end
  if format == "ir" then return "wav" end
end

local function safe(name)
  local s = tostring(name or ""):gsub("[/%z\1-\31]", " "):gsub("^[%s%.]+", ""):gsub("%s+$", "")
  if s == "" then s = "model" end
  return s:sub(1, 120)
end

--- Where a model is kept: `<cache>/<model id>/<its name>.<ext>`. The name
--- of the file is the name of the model, so the plugin and paw show it.
function M.cache_path(model, tone)
  local ext = M.extension(model, tone) or "bin"
  return string.format("%s/%s/%s.%s", M.cache_dir(), tostring(model.id), safe(model.name), ext)
end

--- The file of a model, downloaded at most once. `cb(path)` or `cb(nil, why)`.
function M.download(model, tone, cb)
  local dest = M.cache_path(model, tone)
  local f = io.open(dest, "rb")
  if f then
    local size = f:seek("end")
    f:close()
    if size and size > 0 then return cb(dest, nil, true) end
  end
  if not model.model_url or model.model_url == "" then return cb(nil, "TONE3000 gives no file for this model") end
  return M.request(model.model_url, { kind = "file", dest = dest, what = "model" }, function(result)
    if result.ok then
      cb(result.path)
    else
      cb(nil, result.message)
    end
  end)
end

return M
