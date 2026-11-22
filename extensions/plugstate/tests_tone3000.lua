-- Tests of plugstate's search of TONE3000's library (lua/plugstate/
-- tone3000_api.lua, tone3000_search.lua). extensions/plugstate/tests.lua
-- loads this file.
--
-- No test goes to the network: a mock of the API answers on a Unix socket
-- (curl's --unix-socket), with the shapes of TONE3000's API reference
-- (https://www.tone3000.com/api: PaginatedResponse, Tone, Model). The live
-- tests are in tests_tone3000_live.lua; they compare TONE3000's answers with
-- this mock.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local plugstate, search, client

local function load()
  if not plugstate then
    paw.ext.load("extensions/plugstate")
    plugstate = require("plugstate")
  end
  search = require("plugstate.tone3000_search")
  client = search.client
  return plugstate
end

local keys = T.keys

-- --- the mock of the API ------------------------------------------------------------

--- A tone as the API gives it (the fields of `Tone` in the reference).
local function tone(id, title, opts)
  opts = opts or {}
  return {
    id = id,
    user_id = "u" .. id,
    title = title,
    description = opts.description or ("A capture of " .. title),
    gear = opts.gear or "amp",
    images = {},
    is_public = true,
    links = {},
    format = opts.format or "nam",
    license = opts.license or "cc-by",
    sizes = { opts.size or "standard" },
    makes = { { id = 1, name = opts.make or "Marshall" } },
    tags = { { id = 2, name = "rock" } },
    models_count = opts.models or 2,
    a1_models_count = opts.models or 2,
    a2_models_count = 0,
    irs_count = 0,
    custom_models_count = 0,
    downloads_count = 10 * id,
    favorites_count = id,
    is_favorite = false,
    url = "https://www.tone3000.com/tones/t-" .. id,
    user = { id = "u" .. id, username = opts.by or "capturer", display_name = "A Capturer", is_verified = false },
    created_at = "2026-01-01T00:00:00Z",
    updated_at = "2026-01-01T00:00:00Z",
    published_at = "2026-01-01T00:00:00Z",
  }
end

local function model(id, tone_id, name, ext)
  return {
    id = id,
    tone_id = tone_id,
    name = name,
    size = "standard",
    architecture_version = 1,
    user_id = "u",
    model_url = "http://t3k.test/files/" .. id .. "." .. (ext or "nam"),
    content_hash = "nam-content-v1:" .. string.rep("0", 64),
    created_at = "2026-01-01T00:00:00Z",
    updated_at = "2026-01-01T00:00:00Z",
    metadata = {},
  }
end

local function unquery(q)
  local out = {}
  for k, v in (q or ""):gmatch("([^&=]+)=([^&]*)") do
    out[k] = v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  end
  return out
end

local REASON = {
  [200] = "OK",
  [400] = "Bad Request",
  [401] = "Unauthorized",
  [403] = "Forbidden",
  [404] = "Not Found",
  [429] = "Too Many Requests",
}

--- A mock of the endpoints that paw uses, on a Unix socket. `m.requests`
--- has each request: `{ method, path, query, auth, args, form }` (`form`:
--- the fields of a POST). `m.reply(req)` may answer
--- in place of the routes: `{ status, body, headers }`, or false for no
--- answer at all.
local function mock()
  local m = { requests = {}, conns = {}, tones = {}, models = {}, files = {}, need_token_for_files = true }
  m.path = T.scratch .. "/t3k-mock/" .. math.floor(api.now()) .. ".sock"
  m.listener = api.sock_listen(m.path)

  local function respond(conn, status, body, headers)
    local head =
      { "HTTP/1.1 " .. status .. " " .. (REASON[status] or "Status"), "Content-Length: " .. #body, "Connection: close" }
    for k, v in pairs(headers or { ["Content-Type"] = "application/json" }) do
      head[#head + 1] = k .. ": " .. v
    end
    api.sock_write(conn, table.concat(head, "\r\n") .. "\r\n\r\n" .. body)
  end

  local function route(req)
    if m.reply then
      local r = m.reply(req)
      if r ~= nil then return r end
    end
    local q = unquery(req.query)
    if req.path == "/api/v1/tones/search" then
      local found = {}
      local words = (q.query or ""):lower()
      for _, t in ipairs(m.tones) do
        if
          (words == "" or t.title:lower():find(words, 1, true))
          and (not q.format or t.format == q.format)
          and (not q.gears or t.gear == q.gears)
          and (not q.creators or t.user.username == q.creators)
        then
          found[#found + 1] = t
        end
      end
      local page, size = tonumber(q.page) or 1, tonumber(q.page_size) or 10
      local data = {}
      for i = (page - 1) * size + 1, math.min(#found, page * size) do
        data[#data + 1] = found[i]
      end
      return {
        status = 200,
        body = api.json_encode({
          data = data,
          page = page,
          page_size = size,
          total = #found,
          total_pages = math.max(1, math.ceil(#found / size)),
        }),
      }
    elseif req.path == "/api/v1/models" then
      local data = m.models[tonumber(q.tone_id)] or {}
      return {
        status = 200,
        body = api.json_encode({ data = data, page = 1, page_size = 100, total = #data, total_pages = 1 }),
      }
    end
    local id = req.path:match("^/files/(%d+)%.")
    if id and m.files[tonumber(id)] then
      if m.need_token_for_files and not req.auth then
        return { status = 401, body = api.json_encode({ error = "unauthorized", message = "Authentication required" }) }
      end
      return { status = 200, body = m.files[tonumber(id)], headers = { ["Content-Type"] = "application/octet-stream" } }
    end
    return { status = 404, body = api.json_encode({ error = "not_found" }) }
  end

  --- Accept, read and answer what has come.
  function m.serve()
    while true do
      local conn = api.sock_accept(m.listener)
      if not conn then break end
      m.conns[#m.conns + 1] = { id = conn, data = "" }
    end
    for i = #m.conns, 1, -1 do
      local c = m.conns[i]
      local chunk = api.sock_read(c.id)
      if chunk then c.data = c.data .. chunk end
      local head_end = c.data:find("\r\n\r\n", 1, true)
      local length = head_end and tonumber(c.data:sub(1, head_end):lower():match("\r\ncontent%-length:%s*(%d+)")) or 0
      if not c.answered and head_end and #c.data >= head_end + 3 + length then
        local method, target = c.data:match("^(%u+) (%S+)")
        local path, query = target:match("^([^?]*)%??(.*)$")
        local auth = c.data:match("\r\n[Aa]uthorization: Bearer ([^\r\n]+)")
        local body = c.data:sub(head_end + 4, head_end + 3 + length)
        local req = {
          method = method,
          path = path,
          query = query,
          auth = auth,
          args = unquery(query),
          form = method == "POST" and unquery(body) or nil,
        }
        m.requests[#m.requests + 1] = req
        local r = route(req)
        c.answered = true
        if r then
          respond(c.id, r.status, r.body, r.headers)
          api.sock_close(c.id)
          table.remove(m.conns, i)
        end
      elseif chunk == nil then
        api.sock_close(c.id)
        table.remove(m.conns, i)
      end
    end
  end

  function m.close()
    for _, c in ipairs(m.conns) do
      pcall(api.sock_close, c.id)
    end
    m.conns = {}
    pcall(api.sock_close, m.listener)
  end

  return m
end

--- Serve the mock and look at the requests until `done()` (30 seconds at
--- most, the limit of T.until_: a loaded machine is slow, not wrong).
local function wait(m, done, what)
  local deadline = api.now() + 30000
  while api.now() < deadline do
    if m then m.serve() end
    client.pump()
    if done() then return end
    api.sleep(5)
  end
  error("waited in vain: " .. (what or "?"), 2)
end

local function idle() return client.busy() == 0 end

local function last_message()
  local last = paw.ui.messages[#paw.ui.messages]
  return last and last.text or ""
end

--- The client as a test uses it: the mock's socket, a cache of the test's
--- own, no token from the environment or the keyring of the person who
--- runs the suite, and never the plugin's session unless a test asks.
local function setup(m)
  load()
  local was = {
    socket = client.unix_socket,
    env = client.env,
    tool = client.secret_tool,
    cache = client.cache_dir,
    settings = client.plugin_settings,
    timeout = client.TIMEOUT.json,
    api = paw.opt.plugstate_tone3000_api,
    file = paw.opt.plugstate_tone3000_token_file,
    session = paw.opt.plugstate_tone3000_plugin_session,
    client_id = paw.opt.plugstate_tone3000_client_id,
    session_file = paw.opt.plugstate_tone3000_session_file,
    store = paw.opt.plugstate_tone3000_store,
  }
  local cache = T.scratch .. "/t3k-cache-" .. math.floor(api.now())
  client.unix_socket = m and m.path
  client.env = { TONE3000_TOKEN = "" }
  client.secret_tool = ""
  client.cache_dir = function() return cache end
  client.plugin_settings = function() return T.scratch .. "/no-such-plugin-settings" end
  paw.opt.plugstate_tone3000_api = "http://t3k.test/api/v1"
  paw.opt.plugstate_tone3000_token_file = ""
  paw.opt.plugstate_tone3000_plugin_session = false
  -- The sign-in: none, in a file of the test's own, never the keyring.
  paw.opt.plugstate_tone3000_client_id = ""
  paw.opt.plugstate_tone3000_session_file = cache .. "-session.json"
  paw.opt.plugstate_tone3000_store = "file"
  client.auth.reset()
  T.after(function()
    client.auth.reset()
    paw.opt.plugstate_tone3000_client_id = was.client_id
    paw.opt.plugstate_tone3000_session_file = was.session_file
    paw.opt.plugstate_tone3000_store = was.store
    client.cancel_all()
    if m then m.close() end
    client.unix_socket, client.env, client.secret_tool, client.cache_dir = was.socket, was.env, was.tool, was.cache
    client.plugin_settings, client.TIMEOUT.json = was.settings, was.timeout
    paw.opt.plugstate_tone3000_api = was.api
    paw.opt.plugstate_tone3000_token_file = was.file
    paw.opt.plugstate_tone3000_plugin_session = was.session
    paw.ui.close()
  end)
  return cache
end

--- A device that an adapter of the test knows: the synth of a track. It
--- takes .nam models and .wav impulse responses; what it holds is the name
--- of its preset, which `device_load` sets as one undo step.
local function fake_device()
  local track = T.tone("guitar", 2, "A2")
  paw.cursor.set_track(track.id)
  local d = track:devices()[1]
  local loaded = {}
  plugstate.adapter({
    name = "t3k-test",
    desc = "a test device that takes models",
    matches = function(dev) return dev.id == d.id end,
    slots = function(id)
      local meta = api.device_get(id).meta or {}
      return {
        {
          key = "model",
          label = "Model",
          what = "model",
          kind = "file",
          types = { "nam" },
          value = loaded[meta.preset or ""],
        },
        { key = "ir", label = "Cabinet", what = "impulse response", kind = "file", types = { "wav" } },
      }
    end,
    load = function(id, dev, slot, path)
      loaded[plugstate.stem(path)] = path
      return { name = plugstate.stem(path), params = dev.params }
    end,
  })
  T.after(function()
    for i, a in ipairs(plugstate.adapters) do
      if a.name == "t3k-test" then
        table.remove(plugstate.adapters, i)
        break
      end
    end
  end)
  api.undo_checkpoint()
  return d, track
end

local function fill(m)
  m.tones = {
    tone(101, "Plexi Crunch", { by = "ampnerd", models = 2 }),
    tone(102, "Plexi Clean", { by = "ampnerd", models = 1, license = "cc0" }),
    tone(103, "Deluxe Reverb", { make = "Fender", by = "other" }),
    tone(104, "Plexi Cab 4x12", { gear = "cab", format = "ir", models = 1 }),
    tone(105, "Plexi on AIDA", { format = "aida-x" }),
  }
  m.models[101] = { model(1101, 101, "Plexi Crunch Gain 5"), model(1102, 101, "Plexi Crunch Gain 8") }
  m.models[102] = { model(1201, 102, "Plexi Clean") }
  m.models[104] = { model(1401, 104, "4x12 SM57", "wav") }
  m.files[1101] = "NAM-BYTES-1101"
  m.files[1102] = "NAM-BYTES-1102"
  m.files[1201] = "NAM-BYTES-1201"
  m.files[1401] = "RIFF-1401"
end

local function picker() return paw.pick.state() end

local function wait_picker(m, title)
  wait(m, function()
    local p = picker()
    return p and p.title:find(title, 1, true) and idle()
  end, "a picker " .. title)
  return picker()
end

local function select_line(text)
  local p = picker()
  for i, line in ipairs(p.matches) do
    if line:find(text, 1, true) then
      for _ = 2, i do
        paw.keymap.feed("<C-n>")
      end
      return
    end
  end
  error("no line with " .. text .. " in " .. table.concat(p.matches, " | "), 2)
end

-- The mock and the helpers, for the tests of the sign-in and the live tests
-- (tests_tone3000_auth.lua, tests_tone3000_live.lua).
T.t3k = {
  load = load,
  mock = mock,
  setup = setup,
  wait = wait,
  idle = idle,
  last_message = last_message,
  tone = tone,
  model = model,
  fill = fill,
  fake_device = fake_device,
  picker = picker,
  client = function() return client end,
  search = function() return search end,
}

-- --- tests ---------------------------------------------------------------------------

test("plugstate: TONE3000 search with keys: a tone, its models, a download into the cache, one undo step", function()
  load()
  local m = mock()
  local cache = setup(m)
  fill(m)
  m.need_token_for_files = false
  fresh()
  local d = fake_device()
  paw.ui.focus("devices")
  paw.fx.select(d.id)

  keys("\\t")
  keys("plexi<CR>")
  local p = wait_picker(m, "TONE3000")
  eq(m.requests[1].path, "/api/v1/tones/search", "the search endpoint")
  eq(m.requests[1].args.query, "plexi", "with the words")
  eq(m.requests[1].args.format, nil, "a device that takes models and impulse responses asks for both")
  eq(m.requests[1].auth, nil, "no token: none is sent")
  eq(#p.matches, 4, "the tones TONE3000 finds")
  eq(
    p.matches[1]:find("Plexi Crunch", 1, true) ~= nil and p.matches[1]:find("ampnerd", 1, true) ~= nil,
    true,
    "a line has the title and the author: " .. p.matches[1]
  )
  eq(p.matches[4]:find("cannot load aida", 1, true) ~= nil, true, "a format paw cannot load says so")

  keys("<CR>")
  p = wait_picker(m, "2 models")
  eq(m.requests[2].path, "/api/v1/models", "Enter on a tone asks for its models")
  eq(m.requests[2].args.tone_id, "101", "of that tone")
  select_line("Gain 8")
  keys("<CR>")
  local want = cache .. "/1102/Plexi Crunch Gain 8.nam"
  wait(m, function() return idle() and plugstate.slot(d.id).value == want end, "the model loads")
  eq(T.read_file(want), "NAM-BYTES-1102", "the file is in the cache, a folder per model")
  eq(m.requests[3].path, "/files/1102.nam", "downloaded from its model_url")
  local meta = api.device_get(d.id).meta
  eq(meta.preset, "Plexi Crunch Gain 8", "the device shows the name of the model")
  local kept = meta.plugstate.tone3000.model
  eq(
    table.concat({ kept.tone_id, kept.model_id, kept.tone, kept.author, kept.license }, "|"),
    "101|1102|Plexi Crunch|ampnerd|cc-by",
    "the project keeps the tone, the model, the author and the license"
  )

  paw.ui.focus("devices")
  keys("u")
  eq(plugstate.slot(d.id).value, nil, "u takes the load back")
  eq(((api.device_get(d.id).meta or {}).plugstate or {}).tone3000, nil, "with what it kept, in one step")
  keys("<C-r>")

  -- The same model again: from the cache, with no download.
  local before = #m.requests
  search.load_model({ device = d.id, params = {} }, m.tones[1], m.models[101][2])
  eq(#m.requests, before, "a model in the cache is not downloaded again")
  eq(plugstate.slot(d.id).value, want, "and loads at once")

  -- A tone with one model loads it with no second list; an impulse
  -- response goes into the slot of impulse responses.
  keys(":plugstate.search type=ir cab<CR>")
  wait_picker(m, "“cab”")
  eq(m.requests[#m.requests].args.format, "ir", "type=ir asks for impulse responses")
  keys("<CR>")
  wait(
    m,
    function() return idle() and ((api.device_get(d.id).meta.plugstate or {}).tone3000 or {}).ir ~= nil end,
    "the IR loads"
  )
  eq(api.device_get(d.id).meta.plugstate.tone3000.ir.model, "4x12 SM57", "into the slot of impulse responses")
end)

test("plugstate: TONE3000 search pages, filters and says what fails (401, 429, offline, a time limit)", function()
  load()
  local m = mock()
  setup(m)
  for i = 1, 30 do
    m.tones[i] = tone(200 + i, string.format("Amp %02d", i), { by = i % 2 == 0 and "even" or "odd" })
  end
  fresh()
  local d = fake_device()

  search.search(d.id, { words = "amp" })
  local p = wait_picker(m, "page 1 of 2")
  eq(#p.matches, 26, "25 tones and the line of the next page")
  eq(p.matches[26]:find("next page", 1, true) ~= nil, true, "the last line asks for the next page")
  keys("<A-n>")
  p = wait_picker(m, "page 2 of 2")
  eq(#p.matches, 6, "five tones and the line of the page before")
  eq(m.requests[2].args.page, "2", "page 2 asked for")
  paw.ui.close()
  keys(":plugstate.search gear=amp by=even sort=newest amp<CR>")
  wait_picker(m, "page 1 of 1")
  local q = m.requests[3].args
  eq(
    table.concat({ q.gears, q.creators, q.sort, q.query }, "|"),
    "amp|even|newest|amp",
    "gear, author and sort go to the API"
  )
  eq(#picker().matches, 15, "the tones of that author")
  paw.ui.close()

  -- A download without a token: TONE3000 needs one.
  fill(m)
  search.load_model({ device = d.id, params = {} }, m.tones[2], m.models[102][1])
  wait(m, idle, "the download ends")
  eq(last_message():find("not signed in", 1, true) ~= nil, true, "401 without a token: " .. last_message())

  m.reply = function(req)
    if req.path == "/api/v1/tones/search" then
      return { status = 429, body = '{"error":"rate_limited"}', headers = { ["Retry-After"] = "30" } }
    end
  end
  search.search(d.id, { words = "plexi" })
  wait(m, idle, "the search ends")
  eq(
    last_message():find("rate limited", 1, true) ~= nil and last_message():find("30 s", 1, true) ~= nil,
    true,
    "429: " .. last_message()
  )

  m.reply = function() return false end -- no answer
  client.TIMEOUT.json = 1
  search.search(d.id, { words = "plexi" })
  wait(m, idle, "the time limit")
  eq(last_message():find("took more than 1 s", 1, true) ~= nil, true, "a time limit: " .. last_message())

  client.unix_socket = T.scratch .. "/t3k-mock/nobody-listens.sock"
  search.search(d.id, { words = "plexi" })
  wait(nil, idle, "the search ends")
  eq(last_message():find("offline", 1, true) ~= nil, true, "no connection: " .. last_message())
end)

test(
  "plugstate: TONE3000 tokens from the environment, a file of mode 600, the keyring, and the plugin's session when asked",
  function()
    load()
    local m = mock()
    setup(m)
    fill(m)
    fresh()
    local d = fake_device()
    local function auth_of_search()
      local n = #m.requests
      search.search(d.id, { words = "plexi" })
      wait(m, idle, "the search ends")
      paw.ui.close()
      local req = m.requests[n + 1]
      return req and req.auth
    end

    client.env = { TONE3000_TOKEN = "token-of-env" }
    eq(auth_of_search(), "token-of-env", "TONE3000_TOKEN first")

    client.env = { TONE3000_TOKEN = "" }
    local file = T.scratch .. "/t3k-token"
    T.write_file(file, "token-of-file\n")
    os.execute("chmod 644 '" .. file .. "'")
    paw.opt.plugstate_tone3000_token_file = file
    local n = #m.requests
    search.search(d.id, { words = "plexi" })
    wait(m, idle, "the search ends")
    eq(#m.requests, n, "a token file that others can read is not used, and nothing is sent")
    eq(last_message():find("mode 644", 1, true) ~= nil, true, "it says why: " .. last_message())
    os.execute("chmod 600 '" .. file .. "'")
    eq(auth_of_search(), "token-of-file", "a file of mode 600 is used")
    paw.opt.plugstate_tone3000_token_file = T.scratch .. "/no-such-token"
    search.search(d.id, { words = "plexi" })
    wait(m, idle, "the search ends")
    eq(last_message():find("no token file", 1, true) ~= nil, true, "a token file that is not there: " .. last_message())
    paw.opt.plugstate_tone3000_token_file = ""

    local tool = T.scratch .. "/fake-secret-tool"
    T.write_file(tool, '#!/bin/sh\n[ "$*" = "lookup application paw service tone3000" ] && printf token-of-keyring\n')
    os.execute("chmod 700 '" .. tool .. "'")
    client.secret_tool = tool
    eq(auth_of_search(), "token-of-keyring", "then the keyring through secret-tool")
    client.secret_tool = ""

    -- The session of the plugin, as JUCE keeps its settings: only when asked.
    local settings = T.scratch .. "/ui-preferences.settings"
    local function session(expires)
      T.write_file(
        settings,
        '<?xml version="1.0" encoding="UTF-8"?>\n\n<PROPERTIES>\n'
          .. '  <VALUE name="t3k_show_hints" val="1"/>\n'
          .. '  <VALUE name="t3k_tokens" val="{&quot;access_token&quot;: &quot;token-of-plugin&quot;, '
          .. "&quot;refresh_token&quot;: &quot;r&quot;, &quot;expires_at&quot;: "
          .. string.format("%.0f", expires)
          .. '}"/>\n</PROPERTIES>\n'
      )
    end
    client.plugin_settings = function() return settings end
    session(os.time() * 1000 + 3600000)
    eq(auth_of_search(), nil, "the plugin's session is not used unless the option is on")
    paw.opt.plugstate_tone3000_plugin_session = true
    eq(auth_of_search(), "token-of-plugin", "the option on: the plugin's session")
    session(os.time() * 1000 - 1000)
    local token, why = client.plugin_token()
    eq(token, nil, "an expired session is not used")
    eq(why:find("expired", 1, true) ~= nil, true, "and says so: " .. why)
  end
)

-- --- with plugins ---------------------------------------------------------------------

local function kind_of(format, pattern)
  for _, info in ipairs(paw.device_types()) do
    if info.format == format and info.name:find(pattern) then return info.kind end
  end
end

test("plugstate: a model from TONE3000's library plays in Neural Amp Modeler and in the project", function()
  local kind = kind_of("lv2", "^Neural Amp Modeler$")
  local models = os.getenv("PAW_TEST_NAM_MODELS")
  if not kind or not models then return "skipped: Neural Amp Modeler and its models not found" end
  load()
  local m = mock()
  local cache = setup(m)
  fill(m)
  m.files[1201] = T.read_file(models .. "/BossLSTM-1x16.nam")
  client.env = { TONE3000_TOKEN = "a-token" }
  fresh()
  local track = T.tone("guitar", 2, "A2")
  paw.cursor.set_track(track.id)
  local amp = track:add_device(kind)
  paw.flush()
  api.undo_checkpoint()
  paw.ui.focus("devices")
  paw.fx.select(amp.id)

  keys(":plugstate.search clean<CR>")
  wait_picker(m, "“clean”")
  eq(m.requests[1].args.format, "nam", "Neural Amp Modeler takes models only: format=nam")
  keys("<CR>")
  local want = cache .. "/1201/Plexi Clean.nam"
  wait(m, function() return idle() and plugstate.slot(amp.id).value == want end, "the model loads")
  eq(m.requests[#m.requests].auth, "a-token", "the download has the token")
  local dry_free = T.render({ tail = 0 })
  eq(#T.read_file(dry_free.path) > 0, true, "it renders")

  local path = paw.project.save(T.scratch .. "/t3k-nam.json")
  fresh()
  paw.project.load(path)
  local loaded = paw.tracks()[1]:devices()[2]
  -- The plugin tells what it holds once it has read the state.
  wait(nil, function()
    paw.flush()
    return plugstate.slot(loaded.id).value == want
  end, "the plugin tells its model")
  eq(plugstate.slot(loaded.id).value, want, "the project keeps the file")
  eq(api.device_get(loaded.id).meta.plugstate.tone3000.model.tone, "Plexi Clean", "and the tone's name")
end)

test("plugstate: a model from TONE3000's library goes into a block of the TONE3000 plugin", function()
  if (os.getenv("PAW_TEST_TONE3000") or "") == "" then return "skipped: PAW_TEST_TONE3000 names no package" end
  local kind = kind_of("clap", "^TONE3000$")
  local models = os.getenv("PAW_TEST_NAM_MODELS")
  if not kind or not models then return "skipped: TONE3000 or the test models not found" end
  load()
  local m = mock()
  local cache = setup(m)
  fill(m)
  m.files[1201] = T.read_file(models .. "/BossLSTM-1x16.nam")
  client.env = { TONE3000_TOKEN = "a-token" }
  fresh()
  local track = T.tone("guitar", 2, "A2")
  paw.cursor.set_track(track.id)
  local amp = track:add_device(kind)
  paw.flush()
  api.undo_checkpoint()
  paw.ui.focus("devices")
  paw.fx.select(amp.id)

  keys(":plugstate.search clean<CR>")
  wait_picker(m, "“clean”")
  eq(m.requests[1].args.architecture, "2", "for TONE3000: the models of its architecture, as its own browser asks")
  keys("<CR>")
  local want = cache .. "/1201/Plexi Clean.nam"
  local key
  wait(m, function()
    local kept = ((api.device_get(amp.id).meta or {}).plugstate or {}).tone3000
    key = kept and next(kept)
    return idle() and key ~= nil
  end, "the model loads")
  eq(key:match("^block%d$") ~= nil, true, "into a block: " .. tostring(key))
  local slot = plugstate.slot(amp.id, key)
  eq(slot.value, want, "the block holds the file")
  eq(slot.label:find("Plexi Clean", 1, true) ~= nil, true, "under the name of the model: " .. slot.label)
  paw.ui.focus("devices")
  keys("u")
  eq(((api.device_get(amp.id).meta or {}).plugstate or {}).tone3000, nil, "u takes it back")
end)
