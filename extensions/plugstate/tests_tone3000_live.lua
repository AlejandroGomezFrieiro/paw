-- Live tests of plugstate against TONE3000's real API. They run only when
-- the person who runs them asks, with a token of their own:
--
--   TONE3000_TOKEN_FILE=<a file of mode 600 with an access token>
--   PAW_TEST_TONE3000_LIVE=1   the sign-in of :plugstate.tone3000_login
--                              (PAW_TEST_TONE3000_SESSION_FILE names its
--                              file; PAW_TEST_TONE3000_KEYRING=1 reads the
--                              keyring)
--
-- `tests/tools/live.sh tone3000` runs them. Else each test is skipped with
-- the reason. A run makes about seven requests (TONE3000 permits 100 a
-- minute, fewer for the search) and downloads one small model, into the
-- scratch cache of the test, which the suite removes. The answers are
-- compared with the mock of tests_tone3000.lua, so that the mock stays
-- true. The runner loads it after tests_tone3000.lua (names in order), which sets T.t3k.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api
local H = T.t3k

-- What the tests find, for the tests after them. `mock`: the mock that
-- answers in place of TONE3000 when the tests test themselves.
local live = { requests = 0 }

local function mode()
  if live.mock then return "file", live.mock.token_file end
  local file = os.getenv("TONE3000_TOKEN_FILE") or ""
  if file ~= "" then return "file", file end
  if (os.getenv("PAW_TEST_TONE3000_LIVE") or "") ~= "" then return "sign-in" end
end

local SKIP = "skipped: a live test of TONE3000 (set TONE3000_TOKEN_FILE, or PAW_TEST_TONE3000_LIVE=1 after "
  .. ":plugstate.tone3000_login; see docs/how-to/sign-in-to-tone3000.md)"

--- The client against the real API, with the token that the person gave.
local function start()
  local how, file = mode()
  H.load()
  local client = H.client()
  local auth = require("plugstate.tone3000_auth")
  local cache = H.setup(nil)
  client.unix_socket = live.mock and live.mock.path or nil
  paw.opt.plugstate_tone3000_api = live.mock and "http://t3k.test/api/v1" or ""
  if how == "file" then
    paw.opt.plugstate_tone3000_token_file = file
  else
    paw.opt.plugstate_tone3000_session_file = os.getenv("PAW_TEST_TONE3000_SESSION_FILE") or ""
    if (os.getenv("PAW_TEST_TONE3000_KEYRING") or "") ~= "" then
      client.secret_tool = "secret-tool"
      paw.opt.plugstate_tone3000_store = "auto"
    end
    paw.opt.plugstate_tone3000_client_id = os.getenv("TONE3000_CLIENT_ID") or ""
  end
  -- Count the requests: each one that goes to TONE3000.
  if not live.counting then
    local request = client.request
    live.counting = true
    client.request = function(...)
      live.requests = live.requests + 1
      return request(...)
    end
    T.after(function()
      client.request = request
      live.counting = nil
    end)
  end
  return client, auth, cache
end

local function ask(client, auth, fn)
  local got
  fn(function(r) got = r end)
  H.wait(live.mock, function()
    auth.run_pump()
    return got ~= nil and H.idle() and auth.busy() == 0
  end, "TONE3000 answers")
  return got
end

-- --- the shapes of the answers ---------------------------------------------------

local function kind(v)
  local t = type(v)
  if t == "table" then return next(v) == nil and "table" or (v[1] ~= nil and "list" or "table") end
  return t
end

--- Each field of the mock's objects is in at least one of TONE3000's, with
--- the same kind of value. Gives the fields that TONE3000 has and the mock
--- does not, for the log.
local function compare(what, mocks, lives)
  local seen, extra = {}, {}
  for _, obj in ipairs(lives) do
    for k, v in pairs(obj) do
      seen[k] = seen[k] or {}
      seen[k][kind(v)] = true
    end
  end
  local sample = mocks[1]
  for k, v in pairs(sample) do
    local kinds = seen[k]
    eq(kinds ~= nil, true, what .. ": TONE3000 has the field " .. k .. " of the mock")
    local want = kind(v)
    -- An empty list of the mock is a table; a list of TONE3000 may be empty.
    local fine = kinds[want] or (want == "table" and kinds.list) or (want == "list" and kinds.table)
    eq(
      fine ~= nil,
      true,
      what
        .. "."
        .. k
        .. " is a "
        .. want
        .. " in the mock; TONE3000 gives "
        .. table.concat(
          (function()
            local o = {}
            for x in pairs(kinds) do
              o[#o + 1] = x
            end
            return o
          end)(),
          ", "
        )
    )
  end
  for k in pairs(seen) do
    if sample[k] == nil then extra[#extra + 1] = k end
  end
  table.sort(extra)
  if #extra > 0 then
    print("      live: " .. what .. " fields that the mock does not have: " .. table.concat(extra, ", "))
  end
end

-- The fixed search of the tests: a well-known amp, models only, the most
-- downloaded first. The test takes the first tone with models.
local QUERY = { query = "deluxe reverb", gears = "amp", format = "nam", sort = "downloads-all-time", page_size = 5 }

-- The sizes of NAM models, smallest first.
local SIZES = { nano = 1, feather = 2, lite = 3, standard = 4 }

--- The 16-bit samples of a render.
local function samples(info)
  local data = T.read_file(info.path)
  local at = data:find("data", 1, true) + 8
  local out = {}
  for i = at, #data - 1, 2 do
    local lo, hi = data:byte(i, i + 1)
    local v = lo + hi * 256
    if v >= 32768 then v = v - 65536 end
    out[#out + 1] = v
  end
  return out
end

--- How different two renders are: the mean of the absolute differences,
--- from 0 to 1.
local function difference(a, b)
  local x, y = samples(a), samples(b)
  local n, sum = math.min(#x, #y), 0
  for i = 1, n do
    sum = sum + math.abs(x[i] - y[i])
  end
  return n > 0 and sum / n / 32768 or 0
end

local function kind_of(format, pattern)
  for _, info in ipairs(paw.device_types()) do
    if info.format == format and info.name:find(pattern) then return info.kind end
  end
end

-- --- tests -----------------------------------------------------------------------

local steps = {}

steps[1] = {
  "plugstate live: TONE3000 searches by words and filters, gives pages, and its answers have the mock's shapes",
  function()
    if not mode() then return SKIP end
    local client, auth = start()
    if mode() == "sign-in" then
      local s = ask(client, auth, function(cb) auth.load(cb) end)
      if not s then return "skipped: no sign-in found (:plugstate.tone3000_login first, or set TONE3000_TOKEN_FILE)" end
    end
    local first = ask(client, auth, function(cb) client.search(QUERY, cb) end)
    eq(first.ok, true, "the search works: " .. tostring(first.message))
    eq(first.source, mode() == "file" and "file" or "session", "with the token that was given")
    local page = first.data
    eq(type(page.data), "table", "a page of tones")
    eq(#page.data <= 5, true, "at most page_size tones")
    for _, t in ipairs(page.data) do
      eq(t.format, "nam", "format=nam gives models only: " .. tostring(t.title))
      eq(t.gear, "amp", "gears=amp gives amps only: " .. tostring(t.title))
    end
    local mock_page = { data = {}, page = 1, page_size = 5, total = 0, total_pages = 1 }
    compare("PaginatedResponse", { mock_page }, { page })

    eq(
      (tonumber(page.total_pages) or 0) >= 2,
      true,
      "the search has more than one page (" .. tostring(page.total) .. " tones)"
    )
    local p2 = { page = 2 }
    for k, v in pairs(QUERY) do
      p2[k] = p2[k] or v
    end
    local second = ask(client, auth, function(cb) client.search(p2, cb) end)
    eq(second.ok, true, "page 2: " .. tostring(second.message))
    eq(tonumber(second.data.page), 2, "TONE3000 gives page 2")
    local ids = {}
    for _, t in ipairs(page.data) do
      ids[t.id] = true
    end
    for _, t in ipairs(second.data.data) do
      eq(ids[t.id], nil, "page 2 has other tones than page 1: " .. tostring(t.title))
    end

    local tones = {}
    for _, t in ipairs(page.data) do
      tones[#tones + 1] = t
    end
    for _, t in ipairs(second.data.data) do
      tones[#tones + 1] = t
    end
    compare("Tone", { H.tone(1, "a tone") }, tones)
    local users = {}
    for _, t in ipairs(tones) do
      users[#users + 1] = t.user
    end
    compare("Tone.user", { H.tone(1, "a tone").user }, users)
    for _, t in ipairs(tones) do
      if (tonumber(t.models_count) or 0) > 0 then
        live.tone = t
        break
      end
    end
    eq(live.tone ~= nil, true, "a tone with models")
  end,
}

steps[2] = {
  "plugstate live: the models of a TONE3000 tone, and a 401 for a bad token",
  function()
    if not mode() then return SKIP end
    if not live.tone then return "skipped: the search found no tone" end
    local client, auth = start()
    local result = ask(client, auth, function(cb) client.models(live.tone.id, { page_size = 100 }, cb) end)
    eq(result.ok, true, "the models: " .. tostring(result.message))
    local models = result.data.data
    eq(type(models) == "table" and #models > 0, true, "the tone has models")
    compare("Model", { H.model(1, 1, "a model") }, models)
    -- The smallest model of the first architecture, which every NAM plays.
    local best
    for _, m in ipairs(models) do
      local a1 = m.architecture_version == nil or tonumber(m.architecture_version) == 1
      if a1 and client.extension(m, live.tone) == "nam" then
        if not best or (SIZES[m.size] or 9) < (SIZES[best.size] or 9) then best = m end
      end
    end
    eq(best ~= nil, true, "a .nam model of the first architecture")
    live.model = best

    local bad = ask(
      client,
      auth,
      function(cb)
        client.request(client.origin() .. "/user", { token = "not-a-token-of-paw-tests", what = "account" }, cb)
      end
    )
    eq(bad.http, 401, "a bad token gets a 401")
    eq(bad.message:find("does not take", 1, true) ~= nil, true, "and paw says the token is not taken: " .. bad.message)

    if mode() == "sign-in" then
      local me = ask(
        client,
        auth,
        function(cb) client.request(client.origin() .. "/user", { what = "account" }, cb) end
      )
      eq(me.ok, true, "the account of the sign-in: " .. tostring(me.message))
      eq(type(me.data.username), "string", "has a user name")
    end
  end,
}

steps[3] = {
  "plugstate live: one model from TONE3000 downloads once, plays in NAM (and TONE3000), and comes from the cache",
  function()
    if not mode() then return SKIP end
    if not live.model then return "skipped: no model found" end
    local client, auth, cache = start()
    local search = H.search()
    local nam = kind_of("lv2", "^Neural Amp Modeler$")
    local before = live.requests
    local path, err, cached
    local loaded_into

    T.fresh()
    if nam then
      local part = T.tone("guitar", 2, "A2")
      paw.cursor.set_part(part.id)
      local amp = part:add_device(nam)
      paw.flush()
      api.undo_checkpoint()
      local dry = T.render({ tail = 0 })
      search.load_model({ device = amp.id, params = {} }, live.tone, live.model)
      H.wait(
        live.mock,
        function() return H.idle() and require("plugstate").slot(amp.id).value ~= nil end,
        "the model loads"
      )
      path = require("plugstate").slot(amp.id).value
      local wet = T.render({ tail = 0 })
      local d = difference(dry, wet)
      eq(d > 0.001, true, "the model changes the sound in NAM (difference " .. d .. ")")
      loaded_into = "nam"
    else
      local r = ask(client, auth, function(cb)
        client.download(live.model, live.tone, function(p, e) cb({ path = p, err = e }) end)
      end)
      path, err = r.path, r.err
    end
    eq(live.requests - before, 1, "one download")
    eq(path ~= nil and path:sub(1, #cache) == cache, true, "into the scratch cache: " .. tostring(path or err))
    local head = T.read_file(path):sub(1, 4096)
    eq(head:find('"architecture"', 1, true) ~= nil, true, "a .nam file (JSON with an architecture)")

    -- The second load: from the cache, no request.
    before = live.requests
    client.download(live.model, live.tone, function(p, e, c)
      path, err, cached = p, e, c
    end)
    eq(cached, true, "the second load comes from the cache")
    eq(live.requests, before, "with no request")

    local t3k = (os.getenv("PAW_TEST_TONE3000") or "") ~= "" and kind_of("clap", "^TONE3000$")
    if t3k then
      T.fresh()
      local part = T.tone("guitar", 2, "A2")
      paw.cursor.set_part(part.id)
      local amp = part:add_device(t3k)
      paw.flush()
      api.undo_checkpoint()
      local dry = T.render({ tail = 0 })
      search.load_model({ device = amp.id, params = {} }, live.tone, live.model)
      H.wait(live.mock, function()
        local kept = ((api.device_get(amp.id).meta or {}).plugstate or {}).tone3000
        return H.idle() and kept ~= nil
      end, "the model loads into TONE3000")
      eq(live.requests, before, "TONE3000 takes it from the cache too")
      local d = difference(dry, T.render({ tail = 0 }))
      eq(d > 0.001, true, "the model changes the sound in TONE3000 (difference " .. d .. ")")
      loaded_into = (loaded_into and (loaded_into .. ", ") or "") .. "tone3000"
    end
    print(
      string.format(
        "      live: %s by %s, model %s (%s), %d requests, played in %s",
        tostring(live.tone.title),
        tostring((live.tone.user or {}).username),
        tostring(live.model.name),
        tostring(live.model.size),
        live.requests,
        loaded_into or "no plugin (NAM not found)"
      )
    )
    eq(live.requests <= 10, true, "few requests: " .. live.requests)
  end,
}

for _, step in ipairs(steps) do
  test(step[1], step[2])
end

--- A .nam file as small as the test needs.
local NAM = '{"version": "0.5.4", "architecture": "WaveNet", "config": {}, "weights": []}'

test("plugstate: the live tests of TONE3000 run against the mock, with one download and few requests", function()
  H.load()
  local m = H.mock()
  T.after(function()
    m.close()
    live.mock, live.tone, live.model, live.requests = nil, nil, nil, 0
  end)
  -- With the plugins, a model that NAM plays.
  local models = os.getenv("PAW_TEST_NAM_MODELS")
  if models and kind_of("lv2", "^Neural Amp Modeler$") then NAM = T.read_file(models .. "/BossLSTM-1x16.nam") end
  m.token_file = T.scratch .. "/t3k-live-token"
  T.write_file(m.token_file, "token-of-the-live-test\n")
  os.execute("chmod 600 '" .. m.token_file .. "'")
  for i = 1, 8 do
    m.tones[i] = H.tone(300 + i, "Deluxe Reverb " .. i, { make = "Fender" })
    local small = H.model(3000 + i * 10 + 1, 300 + i, "Deluxe " .. i .. " nano")
    small.size = "nano"
    m.models[300 + i] = { H.model(3000 + i * 10, 300 + i, "Deluxe " .. i .. " standard"), small }
    m.files[3000 + i * 10] = NAM
    m.files[3000 + i * 10 + 1] = NAM
  end
  m.tones[9] = H.tone(399, "Deluxe Reverb pedal", { gear = "pedal" })
  m.reply = function(req)
    if req.path == "/api/v1/user" then
      if req.auth ~= "token-of-the-live-test" then return { status = 401, body = '{"error":"unauthorized"}' } end
      return { status = 200, body = '{"id":"u1","username":"tester"}' }
    end
  end
  live.mock = m
  for _, step in ipairs(steps) do
    local skipped = step[2]()
    eq(skipped, nil, step[1] .. " runs")
  end
  eq(live.model.size, "nano", "the smallest model is chosen")
  local files = 0
  for _, req in ipairs(m.requests) do
    if req.path:match("^/files/") then files = files + 1 end
    eq(
      req.auth == "token-of-the-live-test" or req.path == "/api/v1/user",
      true,
      "each request has the token: " .. req.path
    )
  end
  eq(files, 1, "one download")
  eq(#m.requests, live.requests, "the count of requests is true")
  eq(#m.requests <= 6, true, "few requests: " .. #m.requests)
end)
