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
-- and the keyring entry of a token (tone3000_api.lua), and before the
-- plugin's session.
local api = paw.api
local client = require("plugstate.tone3000_api")

local M = {}

paw.option.define("plugstate_tone3000_client_id", "") -- the publishable key (client_id) of your TONE3000 app
paw.option.define("plugstate_tone3000_session_file", "") -- the file of the sign-in when there is no keyring (empty: $XDG_STATE_HOME/paw/tone3000-session.json)
paw.option.define("plugstate_tone3000_store", "auto") -- where the sign-in goes: auto (the keyring, else the file), keyring or file

--- The attributes of the keyring entry of the sign-in.
M.KEYRING = { "application", "paw", "service", "tone3000-session" }
--- Milliseconds in one second of the intervals of TONE3000 (tests make it short).
M.SECOND = 1000
--- Renew the access token when it has less than this many seconds left.
M.MARGIN = 60

local function say(text, level) paw.notify("TONE3000: " .. text, level) end

-- --- small processes -------------------------------------------------------------

local runs, run_ticker = {}, nil

local function run_pump()
  local now = api.now()
  for proc, r in pairs(runs) do
    local chunk = api.proc_read(proc)
    while chunk and chunk ~= "" do
      r.out[#r.out + 1] = chunk
      chunk = api.proc_read(proc)
    end
    local ok, st = pcall(api.proc_status, proc)
    if not ok or (not st.running and chunk == nil) or now > r.deadline then
      pcall(api.proc_kill, proc)
      runs[proc] = nil
      local code = ok and not st.running and st.code or nil
      if now > r.deadline then code = -1 end
      local fine, err = pcall(r.cb, code, table.concat(r.out))
      if not fine then say(tostring(err), "error") end
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
local function run(argv, input, cb)
  local ok, proc = pcall(api.proc_spawn, argv, { pipe = true })
  if not ok then return cb(nil, "") end
  if input then pcall(api.proc_write, proc, input) end
  pcall(api.proc_close_input, proc)
  runs[proc] = { cb = cb, out = {}, deadline = api.now() + 15000 }
  if not run_ticker then run_ticker = paw.every(50, run_pump) end
end

M.run_pump = run_pump

--- The processes of the keyring and the file that have not ended.
function M.busy()
  local n = 0
  for _ in pairs(runs) do
    n = n + 1
  end
  return n + (M.flow and M.flow.asking and 1 or 0) + (M.renewing and 1 or 0)
end

-- --- where the sign-in is kept ----------------------------------------------------------

--- The file of the sign-in when there is no keyring.
function M.session_file()
  local file = paw.opt.plugstate_tone3000_session_file or ""
  if file ~= "" then return (file:gsub("^~", os.getenv("HOME") or "~")) end
  local state = os.getenv("XDG_STATE_HOME")
  if not state or state == "" then state = (os.getenv("HOME") or ".") .. "/.local/state" end
  return state .. "/paw/tone3000-session.json"
end

local function keyring_usable()
  local store = paw.opt.plugstate_tone3000_store or "auto"
  return store ~= "file" and (client.secret_tool or "") ~= "" and paw.health.executable(client.secret_tool) ~= nil
end

local function argv_of(verb, ...)
  local argv = { client.secret_tool, verb, ... }
  for _, a in ipairs(M.KEYRING) do
    argv[#argv + 1] = a
  end
  return argv
end

--- The sign-in, as paw keeps it in memory: nil (not read yet), false
--- (none), or `{ access_token, refresh_token, expires_at, client_id,
--- username, store }`.
M.state = nil

local function decode(text)
  local s = text and text ~= "" and api.json_decode(text)
  if type(s) == "table" and type(s.access_token) == "string" and s.access_token ~= "" then return s end
end

local loading = nil

--- Read the sign-in (the file at once, the keyring through secret-tool)
--- and call back with it, or false.
function M.load(cb)
  if M.state ~= nil then return cb(M.state) end
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
      return cb(s)
    end
  end
  if not keyring_usable() then
    M.state = false
    return cb(false)
  end
  loading = { cb }
  run(argv_of("lookup"), nil, function(code, out)
    local s = code == 0 and decode(out) or nil
    if s then s.store = "keyring" end
    M.state = s or false
    local waiting = loading
    loading = nil
    for _, w in ipairs(waiting) do
      w(M.state)
    end
  end)
end

local KEEP = { "access_token", "refresh_token", "expires_at", "client_id", "username", "scope" }

local function encode(s)
  local out = {}
  for _, k in ipairs(KEEP) do
    out[k] = s[k]
  end
  return api.json_encode(out)
end

local function write_file(s, cb)
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
    function(code)
      if code == 0 then s.store = "file" end
      cb(code == 0, path)
    end
  )
end

--- Keep a sign-in: in the keyring, else in the file. `cb(where)` or `cb(nil)`.
function M.save(s, cb)
  M.state = s
  local function to_file()
    write_file(s, function(ok, path) cb(ok and ("the file " .. path) or nil) end)
  end
  if not keyring_usable() then return to_file() end
  run(argv_of("store", "--label=TONE3000 sign-in of paw"), encode(s), function(code)
    if code == 0 then
      s.store = "keyring"
      os.remove(M.session_file())
      return cb("the keyring")
    end
    if paw.opt.plugstate_tone3000_store == "keyring" then return cb(nil) end
    to_file()
  end)
end

--- Forget the sign-in: the file, the keyring entry and the memory.
function M.forget(cb)
  M.state = false
  local had_file = os.remove(M.session_file()) ~= nil
  if not keyring_usable() then return cb and cb(had_file) end
  run(argv_of("clear"), nil, function()
    if cb then cb(true) end
  end)
end

-- --- the requests of OAuth ---------------------------------------------------------------

local function oauth(path) return client.origin() .. "/oauth/" .. path end

local function client_id()
  local id = paw.opt.plugstate_tone3000_client_id or ""
  if id == "" then id = os.getenv("TONE3000_CLIENT_ID") or "" end
  return id ~= "" and id or nil
end

M.client_id = client_id

local function error_of(result)
  local d = type(result.data) == "table" and result.data or {}
  return type(d.error) == "string" and d.error or nil,
    type(d.error_description) == "string" and d.error_description or nil
end

local function from_answer(data, cid, before)
  local s = {
    access_token = data.access_token,
    refresh_token = data.refresh_token or (before and before.refresh_token),
    client_id = cid,
    scope = data.scope,
    username = before and before.username,
  }
  local life = tonumber(data.expires_in)
  if life then s.expires_at = os.time() + life end
  return s
end

local renew_waiting = {}

--- Renew the access token with the refresh token. `cb(token)`, nil when
--- it cannot.
function M.renew(cb)
  renew_waiting[#renew_waiting + 1] = cb
  if M.renewing then return end
  local s = M.state
  local function done(token)
    M.renewing = nil
    local waiting = renew_waiting
    renew_waiting = {}
    for _, w in ipairs(waiting) do
      w(token)
    end
  end
  if not s or not s.refresh_token or s.refresh_token == "" then return done(nil) end
  M.renewing = true
  client.request(oauth("token"), {
    form = { grant_type = "refresh_token", refresh_token = s.refresh_token, client_id = s.client_id or client_id() },
    what = "renewal of the sign-in",
  }, function(result)
    if M.state ~= s then return done(M.state and M.state.access_token or nil) end
    if result.ok and type(result.data.access_token) == "string" then
      local fresh = from_answer(result.data, s.client_id, s)
      return M.save(fresh, function() done(fresh.access_token) end)
    end
    local err = error_of(result)
    if err == "invalid_grant" or err == "invalid_client" then
      say("your sign-in has ended (" .. err .. "): sign in again with :plugstate.tone3000_login", "warn")
      return M.forget(function() done(nil) end)
    end
    -- Offline, or TONE3000 does not answer: keep the sign-in, try the old token.
    done(s.access_token)
  end)
end

--- The access token of the sign-in for a request, renewed first when it
--- expires. Nil when a source before it has a token (TONE3000_TOKEN, a
--- token file), or there is no sign-in.
function M.token(cb)
  local env = client.env and client.env.TONE3000_TOKEN
  if env == nil then env = os.getenv("TONE3000_TOKEN") end
  if (env or "") ~= "" or (paw.opt.plugstate_tone3000_token_file or "") ~= "" then return cb(nil) end
  M.load(function(s)
    if not s then return cb(nil) end
    if s.expires_at and s.expires_at < os.time() + M.MARGIN and s.refresh_token then return M.renew(cb) end
    cb(s.access_token)
  end)
end

client.auth = M

-- --- the device flow ------------------------------------------------------------------

local ticker = nil

local function stop(flow, text, level)
  if M.flow == flow then M.flow = nil end
  if ticker and not M.flow then
    paw.cancel(ticker)
    ticker = nil
  end
  if text then say(text, level) end
end

local function signed_in(flow, data)
  local s = from_answer(data, flow.client_id)
  M.flow = nil
  M.save(s, function(where)
    if not where then
      return stop(
        flow,
        "signed in, but paw cannot keep the tokens (the keyring and "
          .. M.session_file()
          .. " fail): they last until paw quits",
        "warn"
      )
    end
    stop(flow)
    -- Name the account: one request, with the new token only.
    client.request(client.origin() .. "/user", { token = s.access_token, what = "account" }, function(r)
      if r.ok and type(r.data.username) == "string" then
        s.username = r.data.username
        if M.state == s then M.save(s, function() end) end
      end
      say(
        "signed in"
          .. (s.username and (" as " .. s.username) or "")
          .. ". paw keeps the tokens in "
          .. where
          .. " and renews them. :plugstate.tone3000_logout forgets them"
      )
    end)
  end)
end

local function poll(flow)
  flow.asking = true
  client.request(oauth("token"), {
    form = {
      grant_type = "urn:ietf:params:oauth:grant-type:device_code",
      device_code = flow.device_code,
      client_id = flow.client_id,
    },
    what = "sign-in",
  }, function(result)
    flow.asking = false
    if M.flow ~= flow then return end
    if result.ok and type(result.data.access_token) == "string" then return signed_in(flow, result.data) end
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
      stop(
        flow,
        "the code " .. flow.user_code .. " has expired before it was entered: :plugstate.tone3000_login for a new one",
        "warn"
      )
    elseif err == "invalid_client" then
      stop(
        flow,
        "TONE3000 does not know the client_id "
          .. flow.client_id
          .. ": copy the publishable key from TONE3000's settings again",
        "error"
      )
    elseif err then
      stop(
        flow,
        "the sign-in failed (" .. err .. (desc and (": " .. desc) or "") .. "): :plugstate.tone3000_login again",
        "error"
      )
    else
      -- Offline for a moment: say it once, and ask again at the interval.
      if not flow.offline then say(tostring(result.message) .. ". paw keeps waiting for the code", "warn") end
      flow.offline = true
      flow.next_at = api.now() + flow.interval * M.SECOND
    end
  end)
end

--- Look at the sign-in in progress: ask TONE3000 when its interval has
--- passed, and stop when the code has expired. The timer calls it; a test
--- can too.
function M.tick()
  local flow = M.flow
  if not flow then return stop(nil) end
  if flow.asking or not flow.next_at then return end
  local now = api.now()
  if now > flow.deadline then
    return stop(
      flow,
      "the code " .. flow.user_code .. " has expired before it was entered: :plugstate.tone3000_login for a new one",
      "warn"
    )
  end
  if now >= flow.next_at then
    flow.next_at = nil
    poll(flow)
  end
end

--- The lines of the float that shows the code.
function M.code_lines(flow)
  local lines = {
    { text = "Sign in to TONE3000", style = "Title" },
    "",
    "1. On a phone or a computer, open " .. flow.verification_uri,
    "2. Enter this code:",
    "",
    { text = "      " .. flow.user_code, style = "Title" },
    "",
  }
  if flow.verification_uri_complete then
    lines[#lines + 1] = "Or open this address, which has the code in it:"
    lines[#lines + 1] = flow.verification_uri_complete
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = string.format(
    "The code expires in %d minutes. paw waits in the background:",
    math.floor(flow.expires_in / 60 + 0.5)
  )
  lines[#lines + 1] = "close this float with q or Esc and work on. The message line tells when you are signed in."
  lines[#lines + 1] = ":plugstate.tone3000_logout stops the sign-in."
  lines[#lines + 1] = ""
  lines[#lines + 1] = { text = "Powered by TONE3000 · https://www.tone3000.com", style = "Dim" }
  return lines
end

--- Start the sign-in.
function M.login()
  local cid = client_id()
  if not cid then
    return say(
      "no client_id: set paw.opt.plugstate_tone3000_client_id (or TONE3000_CLIENT_ID) to the publishable key "
        .. "of your app in TONE3000's settings. See :help plugstate",
      "warn"
    )
  end
  if M.flow then stop(M.flow) end
  local flow = { client_id = cid, polls = 0 }
  M.flow = flow
  flow.asking = true
  say("asking TONE3000 for a sign-in code …")
  client.request(
    oauth("device_authorization"),
    { form = { client_id = cid, scope = "read" }, what = "sign-in code" },
    function(result)
      flow.asking = false
      if M.flow ~= flow then return end
      local d = result.data
      if not result.ok or type(d.device_code) ~= "string" or type(d.user_code) ~= "string" then
        local err, desc = error_of(result)
        if err == "invalid_client" then
          return stop(
            flow,
            "TONE3000 does not know the client_id "
              .. cid
              .. ": copy the publishable key from TONE3000's settings again",
            "error"
          )
        end
        return stop(
          flow,
          "no sign-in code: " .. (err and (err .. (desc and (": " .. desc) or "")) or tostring(result.message)),
          "error"
        )
      end
      flow.device_code, flow.user_code = d.device_code, d.user_code
      flow.verification_uri = type(d.verification_uri) == "string" and d.verification_uri
        or "https://www.tone3000.com/activate"
      flow.verification_uri_complete = type(d.verification_uri_complete) == "string" and d.verification_uri_complete
        or nil
      flow.interval = math.max(1, tonumber(d.interval) or 5)
      flow.expires_in = tonumber(d.expires_in) or 600
      flow.deadline = api.now() + flow.expires_in * M.SECOND
      flow.next_at = api.now() + flow.interval * M.SECOND
      pcall(paw.ui.page, "Sign in to TONE3000", M.code_lines(flow), { width = 80, height = 18 })
      say("open " .. flow.verification_uri .. " and enter the code " .. flow.user_code .. ". paw waits …")
      if not ticker then ticker = paw.every(250, M.tick) end
    end
  )
end

--- Stop a sign-in in progress and forget the tokens.
function M.logout()
  local was_flow = M.flow
  if was_flow then stop(was_flow) end
  M.load(function(s)
    if not s then return say(was_flow and "the sign-in stopped" or "not signed in: there was nothing to forget") end
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
  end)
end

local function minutes(s)
  if not s.expires_at then return "an unknown time" end
  local left = s.expires_at - os.time()
  if left <= 0 then return "no time (paw renews it at the next request)" end
  if left < 120 then return left .. " s" end
  return math.floor(left / 60) .. " min"
end

--- Say where the token comes from, without the network.
function M.status()
  local function rest(s)
    local parts = {}
    local env = client.env and client.env.TONE3000_TOKEN
    if env == nil then env = os.getenv("TONE3000_TOKEN") end
    local file = paw.opt.plugstate_tone3000_token_file or ""
    if (env or "") ~= "" then
      parts[#parts + 1] = "the token of TONE3000_TOKEN comes first"
    elseif file ~= "" then
      parts[#parts + 1] = "the token file " .. file .. " comes first"
    end
    if M.flow then
      parts[#parts + 1] = M.flow.user_code
          and ("a sign-in waits for the code " .. M.flow.user_code .. " at " .. M.flow.verification_uri)
        or "a sign-in asks for its code"
    end
    if s then
      parts[#parts + 1] = "signed in"
        .. (s.username and (" as " .. s.username) or "")
        .. "; the access token works for "
        .. minutes(s)
        .. "; the tokens are in "
        .. (s.store == "keyring" and "the keyring" or M.session_file())
    elseif not M.flow then
      parts[#parts + 1] = "not signed in"
    end
    if not client_id() then parts[#parts + 1] = "no client_id (paw.opt.plugstate_tone3000_client_id)" end
    say(table.concat(parts, ". "))
  end
  M.load(rest)
end

paw.command("plugstate.tone3000_login", function() M.login() end, {
  desc = "Sign in to TONE3000: show a code to enter at tone3000.com/activate, then keep the tokens in the keyring",
})
paw.command("plugstate.tone3000_logout", function() M.logout() end, {
  desc = "Forget the TONE3000 sign-in (and stop one in progress)",
})
paw.command("plugstate.tone3000_status", function() M.status() end, {
  desc = "Tell if paw is signed in to TONE3000, where the token comes from and when it expires",
})

--- Stop everything (when the extension goes, and in tests).
function M.reset()
  if M.flow then stop(M.flow) end
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
