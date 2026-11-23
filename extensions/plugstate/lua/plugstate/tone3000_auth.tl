-- Sign in to TONE3000 from paw: `:plugstate.tone3000_login` asks TONE3000
-- for a code by the device flow of OAuth (RFC 8628, as TONE3000's API
-- reference gives it: https://www.tone3000.com/api, "Device
-- Authorization"). paw shows the code and the address; you enter the code
-- on any device where you are signed in to TONE3000. A timer asks TONE3000
-- at its interval until you do, so no key waits.
--
-- The tokens go into the keyring (`secret-tool`, entry `application paw
-- service tone3000-session`) or else into a file that only you can read,
-- `$XDG_STATE_HOME/paw/tone3000-session.json` (mode 600). Never into a
-- project, a log or a message. paw renews the access token with the
-- refresh token when it expires, and after a 401.
--
-- The sign-in is a source of tokens after TONE3000_TOKEN, the token file
-- and the keyring entry of a token (tone3000_api.tl), and before the
-- plugin's session.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local client = require("plugstate.tone3000_api")
local type contracts = require("paw.contracts")
local type types = require("paw.types")

local api = paw.api

local type Result = client.Result
local type TokenCallback = client.TokenCallback

local record M is client.Auth
  --- A sign-in: its tokens, when the access token expires (seconds since
  --- the epoch), the app, the account and where paw keeps it (`store`:
  --- "keyring" or "file").
  record Session
    access_token: string
    refresh_token: string
    expires_at: number
    client_id: string
    username: string
    scope: string
    store: string
  end

  --- A sign-in in progress: the code to enter and where, when to ask
  --- TONE3000 next (`next_at`), until when the code works (`deadline`),
  --- and whether a request is out (`asking`) or the network was gone
  --- (`offline`).
  record Flow
    client_id: string
    polls: integer
    asking: boolean
    offline: boolean
    device_code: string
    user_code: string
    verification_uri: string
    verification_uri_complete: string
    interval: number
    expires_in: number
    deadline: number
    next_at: number
  end

  --- The attributes of the keyring entry of the sign-in.
  KEYRING: {string}
  --- Milliseconds in one second of the intervals of TONE3000 (tests make it short).
  SECOND: number
  --- Renew the access token when it has less than this many seconds left.
  MARGIN: number
  --- The sign-in, as paw keeps it in memory: nil (not read yet), false
  --- (none), or the sign-in.
  state: Session | boolean
  --- The sign-in in progress, or nil.
  flow: Flow
  --- Whether a renewal of the access token is out.
  renewing: boolean
  --- Look at the processes of the keyring and the file (the timer calls
  --- it; a test can too).
  run_pump: function()
end

local type Session = M.Session
local type Flow = M.Flow

local client_id_option = paw.option.define(
  "plugstate_tone3000_client_id", ""
) -- the publishable key (client_id) of your TONE3000 app
local session_file_option = paw.option.define(
  "plugstate_tone3000_session_file", ""
) -- the file of the sign-in when there is no keyring (empty: $XDG_STATE_HOME/paw/tone3000-session.json)
local store_option = paw.option.define(
  "plugstate_tone3000_store", "auto"
) -- where the sign-in goes: auto (the keyring, else the file), keyring or file

M.KEYRING = {"application", "paw", "service", "tone3000-session"}
M.SECOND = 1000
M.MARGIN = 60

local function say(text: string, level?: string)
  paw.notify("TONE3000: " .. text, level)
end

-- The sign-in in memory, or nil when there is none (or it is not read yet).
local function session(): Session
  local s = M.state
  return s is Session and s or nil
end

-- --- small processes -------------------------------------------------------------

--- What a process gives back: its exit code (nil when it did not start,
--- -1 when it ran out of time) and what it wrote.
local type RunCallback = function(code: integer, out: string)

--- A process that runs: what it wrote so far, until when it may run, and
--- what to call when it ends.
local record Run
  cb: RunCallback
  out: {string}
  deadline: number
end

local runs: {integer: Run} = {}
local run_ticker: integer

local function run_pump()
  -- A process that does not end is stopped on the wall clock: a test that
  -- moves the schedule clock must not kill a process that still works.
  local now = api.real_ms()
  for proc, r in pairs(runs) do
    local chunk = api.proc_read(proc)
    while chunk and chunk ~= "" do
      r.out[#r.out + 1] = chunk
      chunk = api.proc_read(proc)
    end
    local ok, st = pcall(api.proc_status, proc) as (boolean, types.ProcStatus)
    if not ok or (not st.running and chunk == nil) or now > r.deadline then
      pcall(api.proc_kill, proc)
      runs[proc] = nil
      local code = ok and not st.running and st.code or nil
      if now > r.deadline then
        code = -1
      end
      local fine, err = pcall(r.cb, code, table.concat(r.out)) as (boolean, string)
      if not fine then
        say(tostring(err), "error")
      end
    end
  end
  if not next(runs) and run_ticker then
    paw.cancel(run_ticker)
    run_ticker = nil
  end
end

--- Run a program, give it `input` on its standard input, and call back
--- with its exit code and what it wrote. Nothing goes on its command line
--- but `argv`.
local function run(argv: {string}, input: string, cb: RunCallback)
  local ok, proc = pcall(api.proc_spawn, argv, {pipe = true}) as (boolean, integer)
  if not ok then
    cb(nil, "")
    return
  end
  if input then
    pcall(api.proc_write, proc, input)
  end
  pcall(api.proc_close_input, proc)
  runs[proc] = {cb = cb, out = {}, deadline = api.real_ms() + 15000}
  if not run_ticker then
    run_ticker = paw.every(50, run_pump)
  end
end

M.run_pump = run_pump

--- The processes of the keyring and the file that have not ended.
function M.busy(): integer
  local n = 0
  for _ in pairs(runs) do
    n = n + 1
  end
  return n + (M.flow and M.flow.asking and 1 or 0) + (M.renewing and 1 or 0)
end

-- --- where the sign-in is kept ----------------------------------------------------------

--- The file of the sign-in when there is no keyring.
function M.session_file(): string
  local file = session_file_option:get() or ""
  if file ~= "" then
    return (file:gsub("^~", os.getenv("HOME") or "~"))
  end
  local state = os.getenv("XDG_STATE_HOME")
  if not state or state == "" then
    state = (os.getenv("HOME") or ".") .. "/.local/state"
  end
  return state .. "/paw/tone3000-session.json"
end

local function keyring_usable(): boolean
  local store = store_option:get() or "auto"
  local tool = client.secret_tool or ""
  return store ~= "file" and tool ~= "" and paw.health.executable(tool) ~= nil
end

local function argv_of(verb: string, label?: string): {string}
  local argv = {client.secret_tool, verb, label}
  for _, a in ipairs(M.KEYRING) do
    argv[#argv + 1] = a
  end
  return argv
end

local function decode(text: string): Session
  local s = text and text ~= "" and api.json_decode(text) as Session
  if type(s) == "table" and type(s.access_token) == "string" and s.access_token ~= "" then
    return s
  end
end

-- The callbacks that wait for the keyring while it is read, or nil.
local loading: {function(s: Session | boolean)} = nil

--- Read the sign-in (the file at once, the keyring through secret-tool)
--- and call back with it, or false.
function M.load(cb: function(s: Session | boolean))
  if M.state ~= nil then
    cb(M.state)
    return
  end
  if loading then
    loading[#loading + 1] = cb
    return
  end
  local f = io.open(M.session_file(), "rb")
  if f then
    local s = decode(f:read(65536))
    f:close()
    if s then
      s.store = "file"
      M.state = s
      cb(s)
      return
    end
  end
  if not keyring_usable() then
    M.state = false
    cb(false)
    return
  end
  loading = {cb}
  run(
    argv_of("lookup"),
    nil,
    function(code: integer, out: string)
      local s = code == 0 and decode(out) or nil
      if s then
        s.store = "keyring"
      end
      M.state = s or false
      local waiting = loading
      loading = nil
      for _, w in ipairs(waiting) do
        w(M.state)
      end
    end
  )
end

--- What paw keeps of a sign-in (not where it is kept).
local record Kept
  access_token: string
  refresh_token: string
  expires_at: number
  client_id: string
  username: string
  scope: string
end

local function encode(s: Session): string
  local kept: Kept = {
    access_token = s.access_token,
    refresh_token = s.refresh_token,
    expires_at = s.expires_at,
    client_id = s.client_id,
    username = s.username,
    scope = s.scope,
  }
  return api.json_encode(kept)
end

local function write_file(s: Session, cb: function(ok: boolean, path: string))
  local path = M.session_file()
  -- umask 077 before the file is made: no moment where others can read it.
  run(
    {
      "sh",
      "-c",
      'umask 077 && mkdir -p "$(dirname "$1")" && cat > "$1.part" && chmod 600 "$1.part" && mv "$1.part" "$1"',
      "paw-tone3000",
      path,
    },
    encode(s),
    function(code: integer)
      if code == 0 then
        s.store = "file"
      end
      cb(code == 0, path)
    end
  )
end

--- Keep a sign-in: in the keyring, else in the file. `cb(where)` or `cb(nil)`.
function M.save(s: Session, cb: function(where: string))
  M.state = s
  local function to_file()
    write_file(s, function(ok: boolean, path: string) cb(ok and ("the file " .. path) or nil) end)
  end
  if not keyring_usable() then
    to_file()
    return
  end
  run(
    argv_of("store", "--label=TONE3000 sign-in of paw"),
    encode(s),
    function(code: integer)
      if code == 0 then
        s.store = "keyring"
        os.remove(M.session_file())
        cb("the keyring")
        return
      end
      if store_option:get() == "keyring" then
        cb(nil)
        return
      end
      to_file()
    end
  )
end

--- Forget the sign-in: the file, the keyring entry and the memory.
function M.forget(cb?: function(done: boolean))
  M.state = false
  local had_file = os.remove(M.session_file()) ~= nil
  if not keyring_usable() then
    if cb then
      cb(had_file)
    end
    return
  end
  run(
    argv_of("clear"),
    nil,
    function()
      if cb then
        cb(true)
      end
    end
  )
end

-- --- the requests of OAuth ---------------------------------------------------------------

--- An answer of the OAuth endpoints: the tokens, or a device code to enter
--- (`device_authorization`), or what is wrong (`error`).
local record OAuthAnswer
  access_token: string
  refresh_token: string
  expires_in: number
  scope: string
  device_code: string
  user_code: string
  verification_uri: string
  verification_uri_complete: string
  interval: number
  error: string
  error_description: string
  username: string
end

-- The answer of a request as OAuth's record: an empty one when it has none.
local function answer(result: Result): OAuthAnswer
  local d = result.data as OAuthAnswer
  return type(d) == "table" and d or {}
end

local function oauth(path: string): string
  return client.origin() .. "/oauth/" .. path
end

--- The key of the app (`client_id`), or nil.
function M.client_id(): string
  local id = client_id_option:get() or ""
  if id == "" then
    id = os.getenv("TONE3000_CLIENT_ID") or ""
  end
  return id ~= "" and id or nil
end

local client_id = M.client_id

local function error_of(result: Result): string, string
  local d = answer(result)
  return type(d.error) == "string" and d.error or nil,
    type(d.error_description) == "string" and d.error_description or nil
end

local function from_answer(data: OAuthAnswer, cid: string, before?: Session): Session
  local s: Session = {
    access_token = data.access_token,
    refresh_token = data.refresh_token or (before and before.refresh_token),
    client_id = cid,
    scope = data.scope,
    username = before and before.username,
  }
  local life = tonumber(data.expires_in)
  if life then
    s.expires_at = os.time() + life
  end
  return s
end

-- The callbacks that wait for the renewal that is out.
local renew_waiting: {TokenCallback} = {}

--- Renew the access token with the refresh token. `cb(token)`, nil when
--- it cannot.
function M.renew(cb: TokenCallback)
  renew_waiting[#renew_waiting + 1] = cb
  if M.renewing then
    return
  end
  local s = session()
  local function done(token: string)
    M.renewing = nil
    local waiting = renew_waiting
    renew_waiting = {}
    for _, w in ipairs(waiting) do
      w(token)
    end
  end
  if not s or not s.refresh_token or s.refresh_token == "" then
    done(nil)
    return
  end
  M.renewing = true
  client.request(
    oauth("token"),
    {
      form = {grant_type = "refresh_token", refresh_token = s.refresh_token, client_id = s.client_id or client_id()},
      what = "renewal of the sign-in",
    },
    function(result: Result)
      if M.state ~= s then
        local now = session()
        done(now and now.access_token or nil)
        return
      end
      local data = answer(result)
      if result.ok and type(data.access_token) == "string" then
        local fresh = from_answer(data, s.client_id, s)
        M.save(fresh, function() done(fresh.access_token) end)
        return
      end
      local err = error_of(result)
      if err == "invalid_grant" or err == "invalid_client" then
        say("your sign-in has ended (" .. err .. "): sign in again with :plugstate.tone3000_login", "warn")
        M.forget(function() done(nil) end)
        return
      end
      -- Offline, or TONE3000 does not answer: keep the sign-in, try the old token.
      done(s.access_token)
    end
  )
end

-- The token of TONE3000_TOKEN: the test's environment of the client
-- first, then paw's.
local function env_token(): string
  local env = client.env and client.env.TONE3000_TOKEN
  if env == nil then
    env = os.getenv("TONE3000_TOKEN")
  end
  return env or ""
end

--- The access token of the sign-in for a request, renewed first when it
--- expires. Nil when a source before it has a token (TONE3000_TOKEN, a
--- token file), or there is no sign-in.
function M.token(cb: TokenCallback)
  if env_token() ~= "" or client.token_file() ~= "" then
    cb(nil)
    return
  end
  M.load(
    function(loaded: Session | boolean)
      if not (loaded is Session) then
        cb(nil)
        return
      end
      local s = loaded as Session
      if s.expires_at and s.expires_at < os.time() + M.MARGIN and s.refresh_token then
        M.renew(cb)
        return
      end
      cb(s.access_token)
    end
  )
end

client.auth = M

-- --- the device flow ------------------------------------------------------------------

local ticker: integer

local function stop(flow: Flow, text?: string, level?: string)
  if M.flow == flow then
    M.flow = nil
  end
  if ticker and not M.flow then
    paw.cancel(ticker)
    ticker = nil
  end
  if text then
    say(text, level)
  end
end

-- Name the account of a new sign-in: one request, with the new token only.
local function name_account(s: Session, where: string)
  client.request(
    client.origin() .. "/user",
    {token = s.access_token, what = "account"},
    function(r: Result)
      local user = answer(r)
      if r.ok and type(user.username) == "string" then
        s.username = user.username
        if M.state == s then
          M.save(s, function() end)
        end
      end
      say(
        "signed in"
          .. (s.username and (" as " .. s.username) or "")
          .. ". paw keeps the tokens in "
          .. where
          .. " and renews them. :plugstate.tone3000_logout forgets them"
      )
    end
  )
end

local function signed_in(flow: Flow, data: OAuthAnswer)
  local s = from_answer(data, flow.client_id)
  M.flow = nil
  M.save(
    s,
    function(where: string)
      if not where then
        stop(
          flow,
          "signed in, but paw cannot keep the tokens (the keyring and "
            .. M.session_file()
            .. " fail): they last until paw quits",
          "warn"
        )
        return
      end
      stop(flow)
      name_account(s, where)
    end
  )
end

local function expired(flow: Flow): string
  return "the code " .. flow.user_code .. " has expired before it was entered: :plugstate.tone3000_login for a new one"
end

local function unknown_client(cid: string): string
  return "TONE3000 does not know the client_id " .. cid .. ": copy the publishable key from TONE3000's settings again"
end

-- What a poll that got no token does: wait, slow down, or stop.
local function poll_failed(flow: Flow, result: Result)
  local err, desc = error_of(result)
  flow.polls = flow.polls + 1
  if err == "authorization_pending" then
    flow.next_at = api.now() + flow.interval * M.SECOND
  elseif err == "slow_down" then
    flow.interval = flow.interval + 5
    flow.next_at = api.now() + flow.interval * M.SECOND
  elseif err == "access_denied" then
    stop(flow, "the sign-in was declined on TONE3000. Nothing changed", "warn")
  elseif err == "expired_token" then
    stop(flow, expired(flow), "warn")
  elseif err == "invalid_client" then
    stop(flow, unknown_client(flow.client_id), "error")
  elseif err then
    stop(
      flow,
      "the sign-in failed (" .. err .. (desc and (": " .. desc) or "") .. "): :plugstate.tone3000_login again",
      "error"
    )
  else
    -- Offline for a moment: say it once, and ask again at the interval.
    if not flow.offline then
      say(tostring(result.message) .. ". paw keeps waiting for the code", "warn")
    end
    flow.offline = true
    flow.next_at = api.now() + flow.interval * M.SECOND
  end
end

local function poll(flow: Flow)
  flow.asking = true
  client.request(
    oauth("token"),
    {
      form = {
        grant_type = "urn:ietf:params:oauth:grant-type:device_code",
        device_code = flow.device_code,
        client_id = flow.client_id,
      },
      what = "sign-in",
    },
    function(result: Result)
      flow.asking = false
      if M.flow ~= flow then
        return
      end
      local data = answer(result)
      if result.ok and type(data.access_token) == "string" then
        signed_in(flow, data)
        return
      end
      poll_failed(flow, result)
    end
  )
end

--- Look at the sign-in in progress: ask TONE3000 when its interval has
--- passed, and stop when the code has expired. The timer calls it; a test
--- can too.
function M.tick()
  local flow = M.flow
  if not flow then
    stop(nil)
    return
  end
  if flow.asking or not flow.next_at then
    return
  end
  local now = api.now()
  if now > flow.deadline then
    stop(flow, expired(flow), "warn")
    return
  end
  if now >= flow.next_at then
    flow.next_at = nil
    poll(flow)
  end
end

--- The lines of the float that shows the code.
function M.code_lines(flow: Flow): {string | contracts.PageLine}
  local lines: {string | contracts.PageLine} = {
    {text = "Sign in to TONE3000", style = "Title"} as contracts.PageLine,
    "",
    "1. On a phone or a computer, open " .. flow.verification_uri,
    "2. Enter this code:",
    "",
    {text = "      " .. flow.user_code, style = "Title"} as contracts.PageLine,
    "",
  }
  if flow.verification_uri_complete then
    lines[#lines + 1] = "Or open this address, which has the code in it:"
    lines[#lines + 1] = flow.verification_uri_complete
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = string.format(
    "The code expires in %d minutes. paw waits in the background:", math.floor(flow.expires_in / 60 + 0.5)
  )
  lines[#lines + 1] = "close this float with q or Esc and work on. The message line tells when you are signed in."
  lines[#lines + 1] = ":plugstate.tone3000_logout stops the sign-in."
  lines[#lines + 1] = ""
  lines[#lines + 1] = {text = "Powered by TONE3000 · https://www.tone3000.com", style = "Dim"} as contracts.PageLine
  return lines
end

-- The flow with the code that TONE3000 gave: show it, and start the timer.
local function got_code(flow: Flow, d: OAuthAnswer)
  flow.device_code, flow.user_code = d.device_code, d.user_code
  flow.verification_uri = type(d.verification_uri) == "string" and d.verification_uri
    or "https://www.tone3000.com/activate"
  flow.verification_uri_complete = type(d.verification_uri_complete) == "string" and d.verification_uri_complete or nil
  flow.interval = math.max(1, tonumber(d.interval) or 5)
  flow.expires_in = tonumber(d.expires_in) or 600
  flow.deadline = api.now() + flow.expires_in * M.SECOND
  flow.next_at = api.now() + flow.interval * M.SECOND
  pcall(paw.ui.page, "Sign in to TONE3000", M.code_lines(flow), {width = 80, height = 18})
  say("open " .. flow.verification_uri .. " and enter the code " .. flow.user_code .. ". paw waits …")
  if not ticker then
    ticker = paw.every(250, M.tick)
  end
end

--- Start the sign-in.
function M.login()
  local cid = client_id()
  if not cid then
    say(
      "no client_id: set paw.opt.plugstate_tone3000_client_id (or TONE3000_CLIENT_ID) to the publishable key "
        .. "of your app in TONE3000's settings. See :help plugstate",
      "warn"
    )
    return
  end
  if M.flow then
    stop(M.flow)
  end
  local flow: Flow = {client_id = cid, polls = 0}
  M.flow = flow
  flow.asking = true
  say("asking TONE3000 for a sign-in code …")
  client.request(
    oauth("device_authorization"),
    {form = {client_id = cid, scope = "read"}, what = "sign-in code"},
    function(result: Result)
      flow.asking = false
      if M.flow ~= flow then
        return
      end
      local d = answer(result)
      if result.ok and type(d.device_code) == "string" and type(d.user_code) == "string" then
        got_code(flow, d)
        return
      end
      local err, desc = error_of(result)
      if err == "invalid_client" then
        stop(flow, unknown_client(cid), "error")
        return
      end
      stop(
        flow,
        "no sign-in code: " .. (err and (err .. (desc and (": " .. desc) or "")) or tostring(result.message)),
        "error"
      )
    end
  )
end

--- Stop a sign-in in progress and forget the tokens.
function M.logout()
  local was_flow = M.flow
  if was_flow then
    stop(was_flow)
  end
  M.load(
    function(loaded: Session | boolean)
      if not (loaded is Session) then
        say(was_flow and "the sign-in stopped" or "not signed in: there was nothing to forget")
        return
      end
      local s = loaded as Session
      local where = s.store == "keyring" and "the keyring" or M.session_file()
      M.forget(
        function()
          say(
            "signed out: paw forgot the tokens of "
              .. (s.username or "your account")
              .. " ("
              .. where
              .. "). "
              .. "TONE3000 has no way to revoke them from paw: the access token works until it expires"
          )
        end
      )
    end
  )
end

local function minutes(s: Session): string
  if not s.expires_at then
    return "an unknown time"
  end
  local left = s.expires_at - os.time()
  if left <= 0 then
    return "no time (paw renews it at the next request)"
  end
  if left < 120 then
    return left .. " s"
  end
  return math.floor(left / 60) .. " min"
end

-- The parts of `:plugstate.tone3000_status` with the sign-in `s` (or none).
local function status_parts(s: Session): {string}
  local parts: {string} = {}
  local file = client.token_file()
  if env_token() ~= "" then
    parts[#parts + 1] = "the token of TONE3000_TOKEN comes first"
  elseif file ~= "" then
    parts[#parts + 1] = "the token file " .. file .. " comes first"
  end
  local flow = M.flow
  if flow then
    parts[#parts + 1] = flow.user_code
      and (
        "a sign-in waits for the code " .. flow.user_code .. " at " .. flow.verification_uri
      ) or "a sign-in asks for its code"
  end
  if s then
    parts[#parts + 1] = "signed in"
      .. (s.username and (" as " .. s.username) or "")
      .. "; the access token works for "
      .. minutes(s)
      .. "; the tokens are in "
      .. (s.store == "keyring" and "the keyring" or M.session_file())
  elseif not flow then
    parts[#parts + 1] = "not signed in"
  end
  if not client_id() then
    parts[#parts + 1] = "no client_id (paw.opt.plugstate_tone3000_client_id)"
  end
  return parts
end

--- Say where the token comes from, without the network.
function M.status()
  M.load(
    function(loaded: Session | boolean)
      local s = loaded is Session and loaded or nil
      say(table.concat(status_parts(s), ". "))
    end
  )
end

paw.command(
  "plugstate.tone3000_login",
  function() M.login() end,
  {
    desc = "Sign in to TONE3000: show a code to enter at tone3000.com/activate, then keep the tokens in the keyring",
  }
)
paw.command(
  "plugstate.tone3000_logout",
  function() M.logout() end,
  {
    desc = "Forget the TONE3000 sign-in (and stop one in progress)",
  }
)
paw.command(
  "plugstate.tone3000_status",
  function() M.status() end,
  {
    desc = "Tell if paw is signed in to TONE3000, where the token comes from and when it expires",
  }
)

--- Stop everything (when the extension goes, and in tests).
function M.reset()
  if M.flow then
    stop(M.flow)
  end
  M.flow, M.state, M.renewing, loading, renew_waiting = nil, nil, nil, nil, {}
  for proc in pairs(runs) do
    pcall(api.proc_kill, proc)
  end
  runs = {}
  if run_ticker then
    paw.cancel(run_ticker)
    run_ticker = nil
  end
  if ticker then
    paw.cancel(ticker)
    ticker = nil
  end
end

return M
