-- Tests of the sign-in to TONE3000 (lua/plugstate/tone3000_auth.lua):
-- the device flow of OAuth, polling, slow_down, an expired code, a declined
-- sign-in, the renewal of the tokens and where paw keeps them. No test goes
-- to the network: the mock of tests_tone3000.lua answers, with the fields
-- and errors of TONE3000's API reference (https://www.tone3000.com/api,
-- "Device Authorization" and "Refresh Token"). The first test takes the
-- steps of docs/how-to/sign-in-to-tone3000.md with the keys. The runner
-- loads this file after tests_tone3000.lua (names in order), which sets T.t3k.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api
local H = T.t3k

local auth, client
-- The messages of the test (paw.ui.messages keeps only the last 500).
local log = {}

local function start()
  log = {}
  local notify = paw.notify
  paw.notify = function(text, ...)
    log[#log + 1] = tostring(text)
    return notify(text, ...)
  end
  T.after(function() paw.notify = notify end)
  H.load()
  auth = require("plugstate.tone3000_auth")
  client = H.client()
  local m = H.mock()
  local cache = H.setup(m)
  local second = auth.SECOND
  auth.SECOND = 1 -- one second of TONE3000's intervals lasts a millisecond
  T.after(function() auth.SECOND = second end)
  return m, cache
end

local function wait(m, done, what)
  H.wait(m, function()
    auth.tick()
    auth.run_pump()
    return done()
  end, what)
end

local function settled() return H.idle() and auth.busy() == 0 end

--- The messages since `from`, as one text.
local function said(from)
  local out = {}
  for i = (from or 0) + 1, #log do out[#out + 1] = log[i] end
  return table.concat(out, "\n")
end

local function has(text, part, what) eq(text:find(part, 1, true) ~= nil, true, (what or part) .. ": " .. text) end

local function mode_of(path)
  local p = io.popen("stat -c %a '" .. path .. "' 2>/dev/null")
  local mode = p:read("*l")
  p:close()
  return mode
end

--- The routes of OAuth. `script` gives the answers of the token endpoint
--- to the polls, in order.
local function oauth(m, opts)
  opts = opts or {}
  local polls = opts.polls or {}
  m.device = { device_code = "dc-1", user_code = "BCDF-GHJK", verification_uri = "https://www.tone3000.com/activate",
    verification_uri_complete = "https://www.tone3000.com/activate?user_code=BCDF-GHJK",
    expires_in = opts.expires_in or 600, interval = 5 }
  m.polled, m.renewals = 0, 0
  m.reply = function(req)
    if req.path == "/api/v1/oauth/device_authorization" then
      if req.form.client_id ~= "pk_test" then
        return { status = 400, body = '{"error":"invalid_client","error_description":"unknown client_id"}' }
      end
      return { status = 200, body = api.json_encode(m.device) }
    elseif req.path == "/api/v1/oauth/token" and req.form.grant_type == "urn:ietf:params:oauth:grant-type:device_code" then
      m.polled = m.polled + 1
      m.intervals = m.intervals or {}
      m.intervals[m.polled] = auth.flow and auth.flow.interval
      local answer = polls[m.polled] or polls[#polls]
      if type(answer) == "string" then
        return { status = 400, body = api.json_encode({ error = answer, error_description = "the " .. answer .. " of the mock" }) }
      end
      return { status = 200, body = api.json_encode(answer) }
    elseif req.path == "/api/v1/oauth/token" and req.form.grant_type == "refresh_token" then
      m.renewals = m.renewals + 1
      if opts.renew then return opts.renew(req) end
      return { status = 400, body = '{"error":"invalid_grant"}' }
    elseif req.path == "/api/v1/user" then
      if not req.auth then return { status = 401, body = '{"error":"unauthorized"}' } end
      return { status = 200, body = api.json_encode({ id = "u1", username = "tester" }) }
    elseif opts.search and req.path == "/api/v1/tones/search" then
      return opts.search(req)
    end
  end
end

local TOKENS = { access_token = "at-1", refresh_token = "rt-1", token_type = "bearer", expires_in = 3600, scope = "read" }

local function session_file() return paw.opt.plugstate_tone3000_session_file end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

--- Ask for a search with no device, and give the token it was sent with.
local function token_of_search(m)
  local n, got = #m.requests, nil
  client.search({ query = "plexi" }, function(r) got = r end)
  wait(m, function() return got ~= nil and settled() end, "the search ends")
  for i = #m.requests, n + 1, -1 do
    if m.requests[i].path == "/api/v1/tones/search" then return m.requests[i].auth, got end
  end
  return nil, got
end

test("plugstate: :plugstate.tone3000_login signs in by the device flow: a code, polls, slow_down, the tokens in a 0600 file", function()
  local m = start()
  oauth(m, { polls = { "authorization_pending", "slow_down", "authorization_pending", TOKENS } })
  T.fresh()
  local from = #log

  T.keys(":plugstate.tone3000_login<CR>")
  eq(#m.requests, 0, "without a client_id nothing is asked")
  has(said(from), "no client_id", "it says what is missing")

  paw.opt.plugstate_tone3000_client_id = "pk_test"
  from = #log
  T.keys(":plugstate.tone3000_login<CR>")
  wait(m, function() return auth.flow and auth.flow.user_code ~= nil end, "the code")
  local req = m.requests[1]
  eq(req.method .. " " .. req.path, "POST /api/v1/oauth/device_authorization", "the device code is asked for")
  eq(req.form.client_id .. "|" .. req.form.scope, "pk_test|read", "with the client_id and the read scope")
  eq(req.auth, nil, "and no token")
  local float = paw.frontend.float(100, 30)
  eq(float and float.title, "Sign in to TONE3000", "a float shows the code")
  local text = table.concat(float.lines, "\n")
  has(text, "BCDF-GHJK", "the code")
  has(text, "https://www.tone3000.com/activate", "the address")
  has(text, "Powered by TONE3000", "and TONE3000's name")
  has(said(from), "enter the code BCDF-GHJK", "the message line has the code too")
  T.keys("<Esc>")
  eq(paw.frontend.float(100, 30), nil, "Esc closes the float; the sign-in goes on")

  wait(m, function() return auth.flow == nil and settled() and auth.state end, "signed in")
  eq(m.polled, 4, "polled until the code was entered")
  local poll = m.requests[2]
  eq(poll.form.grant_type .. "|" .. poll.form.device_code .. "|" .. poll.form.client_id,
    "urn:ietf:params:oauth:grant-type:device_code|dc-1|pk_test", "a poll sends the device code")
  eq(m.intervals[2], 5, "the interval of TONE3000")
  eq(m.intervals[3], 10, "slow_down adds 5 s to it")
  has(said(from), "signed in as tester", "it names the account")
  local user = m.requests[#m.requests]
  eq(user.path .. " " .. tostring(user.auth), "/api/v1/user at-1", "with one request with the new token")

  local file = session_file()
  eq(mode_of(file), "600", "only the user can read the file of the sign-in")
  local kept = api.json_decode(read(file))
  eq(kept.access_token .. "|" .. kept.refresh_token .. "|" .. kept.client_id .. "|" .. kept.username,
    "at-1|rt-1|pk_test|tester", "it keeps the tokens, the client_id and the account")
  eq(kept.expires_at > os.time() + 3500, true, "and when the access token expires")

  -- A request takes the token of the sign-in.
  auth.state = nil -- as after a restart of paw: from the file
  local token, result = token_of_search(m)
  eq(token, "at-1", "a search sends the token of the sign-in")
  eq(result.source, "session", "and says where it came from")
  for _, text in ipairs(log) do
    eq(text:find("at-1", 1, true) or text:find("rt-1", 1, true) or text:find("dc-1", 1, true), nil,
      "no message shows a token: " .. text)
  end

  from = #log
  T.keys(":plugstate.tone3000_status<CR>")
  wait(m, settled, "the status")
  has(said(from), "signed in as tester", "the status names the account")
  has(said(from), file, "and where the tokens are")

  from = #log
  T.keys(":plugstate.tone3000_logout<CR>")
  wait(m, settled, "the sign-out")
  eq(read(file), nil, "the sign-out removes the file")
  has(said(from), "signed out", "and says so")
  eq(token_of_search(m), nil, "after it no token is sent")
end)

test("plugstate: the TONE3000 sign-in stops when the code expires, is declined or the client_id is wrong", function()
  local m = start()
  paw.opt.plugstate_tone3000_client_id = "pk_test"
  T.fresh()

  oauth(m, { polls = { "authorization_pending", "expired_token" } })
  local from = #log
  auth.login()
  wait(m, function() return auth.flow == nil and settled() end, "the end")
  has(said(from), "has expired", "TONE3000 says the code expired")
  eq(not auth.state, true, "no sign-in")
  paw.ui.close()

  oauth(m, { polls = { "access_denied" } })
  from = #log
  auth.login()
  wait(m, function() return auth.flow == nil and settled() end, "the end")
  has(said(from), "declined", "a declined sign-in")
  paw.ui.close()

  -- The code expires before TONE3000 is asked again.
  oauth(m, { polls = { "authorization_pending" }, expires_in = 1 })
  from = #log
  local polled = m.polled
  auth.login()
  wait(m, function() return auth.flow == nil and settled() end, "the end")
  eq(m.polled, polled, "an expired code is not polled")
  has(said(from), "has expired", "paw says the code expired")
  paw.ui.close()

  oauth(m)
  paw.opt.plugstate_tone3000_client_id = "pk_wrong"
  from = #log
  auth.login()
  wait(m, function() return auth.flow == nil and settled() end, "the end")
  has(said(from), "does not know the client_id pk_wrong", "a wrong client_id")

  -- Offline: paw says so once and keeps waiting.
  paw.opt.plugstate_tone3000_client_id = "pk_test"
  oauth(m, { polls = { "authorization_pending", TOKENS } })
  auth.login()
  wait(m, function() return auth.flow and auth.flow.user_code end, "the code")
  local socket = client.unix_socket
  client.unix_socket = T.scratch .. "/t3k-mock/nobody-listens.sock"
  from = #log
  wait(m, function() return auth.flow and auth.flow.offline and settled() end, "offline")
  has(said(from), "paw keeps waiting", "offline for a moment")
  client.unix_socket = socket
  wait(m, function() return auth.flow == nil and settled() and auth.state end, "signed in after all")
end)

test("plugstate: paw renews the TONE3000 sign-in when it expires and after a 401, and forgets it when it has ended", function()
  local m = start()
  T.fresh()
  local next_token = 2
  oauth(m, {
    renew = function(req)
      if req.form.refresh_token ~= "rt-1" then return { status = 400, body = '{"error":"invalid_grant"}' } end
      local token = "at-" .. next_token
      next_token = next_token + 1
      return { status = 200, body = api.json_encode({ access_token = token, token_type = "bearer", expires_in = 3600, scope = "read" }) }
    end,
    search = function(req)
      if req.auth == "at-stale" then return { status = 401, body = '{"error":"unauthorized"}' } end
      return { status = 200, body = '{"data":[],"page":1,"page_size":10,"total":0,"total_pages":1}' }
    end,
  })
  local function signed_in(token, expires_at)
    T.write_file(session_file(), api.json_encode({ access_token = token, refresh_token = "rt-1", client_id = "pk_test",
      expires_at = expires_at, username = "tester" }))
    auth.state = nil
  end

  signed_in("at-1", os.time() - 10)
  eq(token_of_search(m), "at-2", "an expired access token is renewed before the request")
  local renewal = m.requests[1]
  eq(renewal.path .. "|" .. renewal.form.grant_type .. "|" .. renewal.form.refresh_token .. "|" .. renewal.form.client_id,
    "/api/v1/oauth/token|refresh_token|rt-1|pk_test", "with the refresh token and the client_id")
  local kept = api.json_decode(read(session_file()))
  eq(kept.access_token .. "|" .. kept.refresh_token, "at-2|rt-1", "the new token is kept, and the refresh token stays")
  eq(mode_of(session_file()), "600", "in the file that only the user reads")

  -- Two requests at once ask for one renewal.
  signed_in("at-1", os.time() - 10)
  local before, a, b = m.renewals, nil, nil
  client.search({ query = "a" }, function(r) a = r end)
  client.search({ query = "b" }, function(r) b = r end)
  wait(m, function() return a and b and settled() end, "both end")
  eq(m.renewals - before, 1, "one renewal for both")

  signed_in("at-stale", os.time() + 3600)
  local n = #m.requests
  local token, result = token_of_search(m)
  eq(token, "at-" .. (next_token - 1), "a 401 renews the token, and the request is asked again")
  eq(result.ok, true, "and works")
  eq(#m.requests - n, 3, "the request, the renewal, the request again")

  -- The refresh token has ended: paw forgets the sign-in.
  T.write_file(session_file(), api.json_encode({ access_token = "at-1", refresh_token = "rt-gone", client_id = "pk_test",
    expires_at = os.time() - 10 }))
  auth.state = nil
  local from = #log
  token, result = token_of_search(m)
  eq(token, nil, "no token")
  has(said(from), "sign in again with :plugstate.tone3000_login", "it says to sign in again")
  eq(read(session_file()), nil, "and forgets the tokens")

  -- TONE3000_TOKEN and a token file come before the sign-in.
  signed_in("at-1", os.time() + 3600)
  client.env = { TONE3000_TOKEN = "token-of-env" }
  eq(token_of_search(m), "token-of-env", "TONE3000_TOKEN comes first")
  client.env = { TONE3000_TOKEN = "" }
  local file = T.scratch .. "/t3k-auth-token"
  T.write_file(file, "token-of-file\n")
  os.execute("chmod 600 '" .. file .. "'")
  paw.opt.plugstate_tone3000_token_file = file
  eq(token_of_search(m), "token-of-file", "a token file comes before the sign-in")
  paw.opt.plugstate_tone3000_token_file = ""
  eq(token_of_search(m), "at-1", "then the sign-in")
end)

test("plugstate: the TONE3000 sign-in goes into the keyring through secret-tool, on its standard input", function()
  local m = start()
  T.fresh()
  -- A secret-tool of the test: it keeps the secret in a file of the
  -- scratch folder, and its arguments in another.
  local dir = T.scratch .. "/fake-keyring"
  os.execute("mkdir -p '" .. dir .. "'")
  local tool = dir .. "/secret-tool"
  T.write_file(tool, table.concat({
    "#!/bin/sh",
    'printf "%s\\n" "$*" >> "' .. dir .. '/args"',
    'case "$1" in',
    '  store) cat > "' .. dir .. '/secret" ;;',
    '  lookup) [ "$*" = "lookup application paw service tone3000-session" ] && [ -f "' .. dir .. '/secret" ] && cat "' .. dir .. '/secret" ;;',
    '  clear) rm -f "' .. dir .. '/secret" ;;',
    "esac",
  }, "\n") .. "\n")
  os.execute("chmod 700 '" .. tool .. "'")
  client.secret_tool = tool
  paw.opt.plugstate_tone3000_store = "auto"
  paw.opt.plugstate_tone3000_client_id = "pk_test"
  oauth(m, { polls = { TOKENS } })

  local from = #log
  auth.login()
  wait(m, function() return auth.flow == nil and settled() and auth.state and auth.state.username end, "signed in")
  has(said(from), "in the keyring", "it says where the tokens are")
  eq(api.json_decode(read(dir .. "/secret")).access_token, "at-1", "the keyring has the sign-in")
  eq(read(session_file()), nil, "and no file")
  local args = read(dir .. "/args")
  has(args, "store --label=TONE3000 sign-in of paw application paw service tone3000-session", "the entry")
  eq(args:find("at-1", 1, true) or args:find("rt-1", 1, true), nil, "no token on a command line")

  -- The keyring entry of a token (`service tone3000`) is another entry:
  -- the fake secret-tool has none, so the sign-in gives the token.
  auth.state = nil
  eq(token_of_search(m), "at-1", "after a restart, the sign-in comes from the keyring")

  auth.logout()
  wait(m, settled, "the sign-out")
  eq(read(dir .. "/secret"), nil, "the sign-out clears the keyring entry")
end)
