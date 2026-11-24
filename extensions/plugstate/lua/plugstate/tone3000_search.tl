-- Search TONE3000's library from paw: `:plugstate.search <words>` (and
-- `<localleader>t` in the inspector) lists the tones that TONE3000
-- finds, a page at a time; Enter on a tone lists its models; Enter on a
-- model downloads it once into paw's cache and loads it into the device
-- through its adapter (a block of TONE3000, the model of Neural Amp
-- Modeler, the impulse response of a convolver), as one undo step. The
-- project keeps the file as the adapter does, and the tone's id, name,
-- author and license in `meta.plugstate.tone3000` of the device.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local plugstate = require("plugstate")
local client = require("plugstate.tone3000_api")
local type contracts = require("paw.contracts")

local api = paw.api

local type Tone = client.Tone
local type Model = client.Model
local type Result = client.Result
local type Slot = plugstate.Slot
local type Context = contracts.CommandContext

local record M
  --- A search for a device: the slot to load into (none: the first that
  --- takes the file), the words and the query of the API, and the page
  --- that TONE3000 gave last.
  record Job
    device: integer
    slot: string
    words: string
    params: client.Params
    tones: {Tone}
    page: integer
    pages: integer
    total: integer
  end

  --- What `search` takes: the words, and `gear`, `format`, `by`
  --- (creators), `sort`, `slot`, `architecture`.
  record SearchOptions
    words: string
    gear: string
    format: string
    by: string
    sort: string
    slot: string
    architecture: string
  end

  client: client
  PAGE_SIZE: integer
  --- The last search, for `:plugstate.search_more`.
  last: Job
  --- Ask for a page of a search and show it.
  page: function(job: Job, n: integer)
  --- Called after a model was loaded (tests).
  on_loaded: function(id: integer, slot_key: string, path: string)
end

local type Job = M.Job

M.client = client
M.PAGE_SIZE = 25

local function device_name(id: integer): string
  return api.device_get(id).name
end

local function say(text: string, level?: string)
  paw.notify("TONE3000: " .. text, level)
end

local function takes(slot: Slot, ext: string): boolean
  for _, t in ipairs(slot.types or {}) do
    if t:lower() == ext then
      return true
    end
  end
  return false
end

--- The slot of a device that a file of `ext` goes into: the one named by
--- `key`; else the first slot of a file of that kind ("model" for .nam,
--- "impulse response" for .wav); else the first that takes the file.
function M.slot_for(id: integer, ext: string, key?: string): Slot
  if key and key ~= "" then
    return plugstate.slot(id, key)
  end
  local slots = plugstate.slots(id)
  local want = ext == "nam" and "model" or "impulse response"
  for _, s in ipairs(slots) do
    if s.kind == "file" and takes(s, ext) and s.what == want then
      return s
    end
  end
  for _, s in ipairs(slots) do
    if s.kind == "file" and takes(s, ext) then
      return s
    end
  end
end

--- The formats of TONE3000 that a device takes: "nam", "ir".
function M.formats(id: integer): {string}
  local out: {string} = {}
  local seen: {string: boolean} = {}
  for _, s in ipairs(plugstate.slots(id)) do
    if s.kind == "file" then
      if takes(s, "nam") and not seen.nam then
        out[#out + 1], seen.nam = "nam", true
      end
      if takes(s, "wav") and not seen.ir then
        out[#out + 1], seen.ir = "ir", true
      end
    end
  end
  return out
end

-- --- lines ------------------------------------------------------------------------

local function author(tone: Tone): string
  local u: client.User = type(tone.user) == "table" and tone.user or {}
  local name = u.username or u.display_name
  return type(name) == "string" and name or "?"
end

local function names(list: {string | client.Named}): string
  local out: {string} = {}
  for _, x in ipairs(type(list) == "table" and list or {}) do
    local n: string
    if x is string then
      n = x
    elseif type(x) == "table" then
      n = x.name
    end
    if type(n) == "string" then
      out[#out + 1] = n
    end
  end
  return table.concat(out, ", ")
end

local function cut(value: string | number, n: integer): string
  local text = tostring(value or "")
  if #text <= n then
    return text
  end
  return text:sub(1, n - 1) .. "…"
end

local LOADS: {string: boolean} = {nam = true, ir = true}

--- A tone as a line of the picker: its title, author, gear, format, sizes
--- and number of models.
function M.tone_line(tone: Tone): string
  local fmt = tostring(tone.format or "")
  return string.format(
    "%-38s %-18s %-8s %-6s %-14s %3s models%s",
    cut(tone.title, 38),
    cut(author(tone), 18),
    cut(tone.gear, 8),
    fmt,
    cut(names(tone.sizes), 14),
    tostring(tone.models_count or "?"),
    LOADS[fmt] and "" or "  (paw cannot load " .. fmt .. ")"
  )
end

local POWERED: contracts.PageLine = {text = "Powered by TONE3000 · https://www.tone3000.com", style = "Dim"}

local function tone_preview(tone: Tone): {string | contracts.PageLine}
  local lines: {string | contracts.PageLine} = {
    {text = tostring(tone.title), style = "Title"} as contracts.PageLine,
    "by " .. author(tone),
  }
  lines[#lines + 1] = string.format(
    "%s · %s · %s", tostring(tone.gear or "?"), tostring(tone.format or "?"), names(tone.sizes)
  )
  lines[#lines + 1] = string.format(
    "%s models · %s downloads · %s favorites",
    tostring(tone.models_count or "?"),
    tostring(tone.downloads_count or "?"),
    tostring(tone.favorites_count or "?")
  )
  if tone.license then
    lines[#lines + 1] = "license: " .. tostring(tone.license)
  end
  local makes, tags = names(tone.makes), names(tone.tags)
  if makes ~= "" then
    lines[#lines + 1] = "makes: " .. makes
  end
  if tags ~= "" then
    lines[#lines + 1] = "tags: " .. tags
  end
  if tone.url then
    lines[#lines + 1] = tostring(tone.url)
  end
  if type(tone.description) == "string" and tone.description ~= "" then
    lines[#lines + 1] = ""
    for para in tone.description:gmatch("[^\n]+") do
      lines[#lines + 1] = para
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = POWERED
  return lines
end

-- --- loading --------------------------------------------------------------------------

--- Keep what the device plays of TONE3000, by slot, in its meta: the
--- project then names the tone and its author without the network.
local function remember(id: integer, slot_key: string, tone: Tone, model: Model)
  local meta = api.device_get(id).meta or {}
  local data: plugstate.Data = type(meta.plugstate) == "table" and meta.plugstate as plugstate.Data or {}
  data.tone3000 = type(data.tone3000) == "table" and data.tone3000 or {}
  data.tone3000[slot_key] = {
    tone_id = tone.id,
    tone = tone.title,
    model_id = model.id,
    model = model.name,
    author = author(tone),
    license = tone.license,
    url = tone.url,
  }
  meta.plugstate = data
  api.device_set(id, {meta = meta})
end

-- Load a downloaded model into the device of the job, and say so.
local function load_file(job: Job, tone: Tone, model: Model, ext: string, path: string, cached: boolean)
  local id = job.device
  if not pcall(api.device_get, id) then
    say("the device is gone; the model is in " .. path, "warn")
    return
  end
  local slot = M.slot_for(id, ext, job.slot)
  if not slot then
    say(device_name(id) .. " has no place for a ." .. ext .. " file (the model is in " .. path .. ")", "warn")
    return
  end
  local ok, why = plugstate.set(id, slot.key, path)
  if not ok then
    say(device_name(id) .. ": " .. tostring(why), "error")
    return
  end
  remember(id, slot.key, tone, model)
  paw.notify(
    string.format(
      "%s: %s %s from TONE3000 (%s by %s%s)%s",
      device_name(id),
      slot.what or "file",
      tostring(model.name),
      tostring(tone.title),
      author(tone),
      tone.license and (", " .. tone.license) or "",
      cached and ", from the cache" or ""
    )
  )
  if M.on_loaded then
    M.on_loaded(id, slot.key, path)
  end
end

--- Download a model (or take it from the cache) and load it into the
--- device. `job`: `{ device, slot }` from the search.
function M.load_model(job: Job, tone: Tone, model: Model)
  local ext = client.extension(model, tone)
  if not ext then
    say("paw cannot load a model of the format " .. tostring(tone.format), "warn")
    return
  end
  say("downloading " .. tostring(model.name) .. " …")
  client.download(
    model,
    tone,
    function(path: string, err: string, cached: boolean)
      if not path then
        say(tostring(err), "error")
        return
      end
      load_file(job, tone, model, ext, path, cached)
    end
  )
end

-- The models of a tone in a picker.
local function pick_from(job: Job, tone: Tone, models: {Model})
  local source: contracts.PickSource<Model> = {
    title = "TONE3000 · " .. tostring(tone.title) .. " · " .. #models .. " models",
    items = models,
    format = function(m: Model): string
      return string.format(
        "%-44s %-10s %s",
        cut(m.name, 44),
        tostring(m.size or ""),
        m.architecture_version and ("A" .. tostring(m.architecture_version)) or ""
      )
    end,
    primary = function(m: Model): string return tostring(m.name) end,
    on_choose = function(m: Model) M.load_model(job, tone, m) end,
    preview = function(m: Model): {string | contracts.PageLine}
      return {
        {text = tostring(m.name), style = "Title"} as contracts.PageLine,
        tostring(tone.title) .. " by " .. author(tone),
        "size: " .. tostring(m.size or "?"),
        "license: " .. tostring(tone.license or "?"),
        {text = "Powered by TONE3000", style = "Dim"} as contracts.PageLine,
      }
    end,
  }
  paw.pick(source)
end

--- Choose one of the models of a tone (none to choose when it has one).
function M.pick_model(job: Job, tone: Tone)
  say("the models of " .. tostring(tone.title) .. " …")
  local params: client.Params = {page_size = 100}
  if job.params.architecture then
    params.architecture = job.params.architecture
  end
  client.models(
    tone.id,
    params,
    function(result: Result)
      if not result.ok then
        say(result.message, "error")
        return
      end
      local page = result.data as client.Page<Model>
      local models = type(page.data) == "table" and page.data or {}
      if #models == 0 then
        say(tostring(tone.title) .. " has no models that this device can load", "warn")
      elseif #models == 1 then
        M.load_model(job, tone, models[1])
      else
        pick_from(job, tone, models)
      end
    end
  )
end

--- A line of the picker of tones: a tone, or the page after or before.
local record Item
  tone: Tone
  --- 1: the next page; -1: the page before.
  more: integer
end

local function item_line(job: Job, t: Item): string
  if t.more then
    return t.more > 0 and string.format("▸ the next page (%d of %d)", job.page + 1, job.pages)
      or string.format("◂ the page before (%d of %d)", job.page - 1, job.pages)
  end
  return M.tone_line(t.tone)
end

local function choose_item(job: Job, t: Item)
  if t.more then
    M.page(job, job.page + t.more)
    return
  end
  if not LOADS[tostring(t.tone.format)] then
    say("paw cannot load a tone of the format " .. tostring(t.tone.format), "warn")
    return
  end
  M.pick_model(job, t.tone)
end

local function pick_tones(job: Job)
  local items: {Item} = {}
  for _, t in ipairs(job.tones) do
    items[#items + 1] = {tone = t}
  end
  if job.page < job.pages then
    items[#items + 1] = {more = 1}
  end
  if job.page > 1 then
    items[#items + 1] = {more = -1}
  end
  local function page(n: integer): function(item: Item, query: string)
    return function() M.page(job, job.page + n) end
  end
  local source: contracts.PickSource<Item> = {
    title = string.format(
      "TONE3000 · %s · page %d of %d · %d tones",
      job.words ~= "" and ("“" .. job.words .. "”") or "trending",
      job.page,
      job.pages,
      job.total
    ),
    items = items,
    format = function(t: Item): string return item_line(job, t) end,
    primary = function(t: Item): string return t.more and "" or tostring(t.tone.title) end,
    empty = "TONE3000 finds no tones" .. (job.words ~= "" and (" with “" .. job.words .. "”") or ""),
    on_choose = function(t: Item) choose_item(job, t) end,
    actions = {
      ["<A-n>"] = {fn = page(1), desc = "next page"},
      ["<A-p>"] = {fn = page(-1), desc = "page before"},
    },
    preview = function(t: Item): {string | contracts.PageLine}
      if t.more then
        return {"Enter asks TONE3000 for that page"}
      end
      return tone_preview(t.tone)
    end,
  }
  paw.pick(source)
end

--- Ask for page `n` of a search and show it.
function M.page(job: Job, n: integer)
  if n < 1 or (job.pages and n > job.pages) then
    say("no page " .. n, "warn")
    return
  end
  local params: client.Params = {}
  for k, v in pairs(job.params) do
    params[k] = v
  end
  params.page, params.page_size = n, M.PAGE_SIZE
  say(string.format("searching%s (page %d) …", job.words ~= "" and (" “" .. job.words .. "”") or "", n))
  client.search(
    params,
    function(result: Result)
      if not result.ok then
        say(result.message, "error")
        return
      end
      local data = result.data as client.Page<Tone>
      job.tones = type(data.data) == "table" and data.data or {}
      job.page = math.tointeger(tonumber(data.page)) or n
      job.pages = math.max(1, math.tointeger(tonumber(data.total_pages)) or 1)
      job.total = math.tointeger(tonumber(data.total)) or #job.tones
      M.last = job
      pick_tones(job)
    end
  )
end

-- The format of TONE3000 to search for: the one asked ("model" is "nam"),
-- else the one the device takes when it takes one. Nil and why when the
-- device does not take the one asked.
local function format_for(id: integer, asked: string, formats: {string}): string, string
  local format = asked
  if format == "model" then
    format = "nam"
  end
  if format and format ~= "" then
    for _, f in ipairs(formats) do
      if f == format then
        return format
      end
    end
    return nil, device_name(id) .. " does not load " .. format .. " files"
  end
  if #formats == 1 then
    return formats[1]
  end
  return format
end

--- Search for a device. `opts`: `words`, `gear`, `format`, `by` (creators),
--- `sort`, `slot`, `architecture`.
function M.search(id: integer, opts?: M.SearchOptions)
  opts = opts or {}
  local formats = M.formats(id)
  if #formats == 0 then
    say(device_name(id) .. " takes no file that TONE3000 has (models, impulse responses)", "warn")
    return
  end
  local format, why = format_for(id, opts.format, formats)
  if why then
    say(why, "warn")
    return
  end
  local a = plugstate.adapter_of(id)
  -- The TONE3000 plugin plays the models of the second architecture, as its
  -- own browser asks for; the API leaves them out unless asked.
  local architecture: client.Param = opts.architecture or (a and a.name == "tone3000" and 2 or nil)
  local job: Job = {
    device = id,
    slot = opts.slot,
    words = opts.words or "",
    params = {
      query = opts.words,
      gears = opts.gear,
      format = format,
      creators = opts.by,
      sort = opts.sort,
      architecture = architecture,
    },
  }
  M.page(job, 1)
end

-- --- the command and the key ------------------------------------------------------------

local function named_arg(ctx: Context, name: string): string
  local v = ctx.args[name]
  return v ~= nil and tostring(v) or nil
end

paw.command(
  "plugstate.search",
  function(ctx: Context)
    local id, why = plugstate.target()
    if not id then
      paw.notify(why, "warn")
      return
    end
    local words: {string} = {}
    for _, w in ipairs(ctx.args) do
      words[#words + 1] = tostring(w)
    end
    M.search(
      id,
      {
        words = table.concat(words, " "),
        gear = named_arg(ctx, "gear"),
        format = named_arg(ctx, "type"),
        by = named_arg(ctx, "by"),
        sort = named_arg(ctx, "sort"),
        slot = named_arg(ctx, "slot"),
        architecture = named_arg(ctx, "arch"),
      }
    )
  end,
  {
    desc = "Search TONE3000's library for a model or an impulse response for the plugin: `plugstate.search plexi`; "
      .. "`gear=amp|pedal|cab|...`, `type=nam|ir`, `by=<user>`, `sort=newest|trending|...`, `slot=<key>`",
  }
)

paw.command(
  "plugstate.search_more",
  function(ctx: Context)
    local job = M.last
    if not job then
      paw.notify("no TONE3000 search yet: `:plugstate.search <words>`", "warn")
      return
    end
    M.page(job, job.page + (ctx.count or 1))
  end,
  {desc = "The next page of the last TONE3000 search (a count skips more)"}
)

--- What `paw.ui.input` takes, as far as this prompt gives it.
local record InputOptions
  prompt: string
end

--- `paw.ui.input`, as far as this prompt calls it.
local type Input = function(opts: InputOptions, cb: function(text: string))

paw.command(
  "plugstate.search_prompt",
  function()
    local id, why = plugstate.target()
    if not id then
      paw.notify(why, "warn")
      return
    end
    local input = paw.ui.input as Input
    input({prompt = "TONE3000 search: "}, function(text: string) paw.commands.exec("plugstate.search " .. text) end)
  end,
  {desc = "Ask for words, then search TONE3000's library for the plugin"}
)

paw.keymap.set(
  "<localleader>t",
  "plugstate.search_prompt",
  {view = "inspector", desc = "Search TONE3000's library for a model or an impulse response"}
)

--- `paw.health.executable`: the path of a program on the PATH, or nil.
local executable = paw.health.executable as function(name: string): string

-- Where a token can come from, the first first.
local function token_sources(): {string}
  local sources: {string} = {}
  if (os.getenv("TONE3000_TOKEN") or "") ~= "" then
    sources[#sources + 1] = "TONE3000_TOKEN"
  end
  local file = client.token_file()
  if file ~= "" then
    sources[#sources + 1] = "the token file " .. file
  end
  if executable(client.secret_tool) then
    sources[#sources + 1] = "the keyring (secret-tool), if it has an entry"
  end
  if client.auth then
    sources[#sources + 1] = "the sign-in of :plugstate.tone3000_login, if there is one"
  end
  if client.plugin_session() then
    sources[#sources + 1] = "the session of the TONE3000 plugin"
  end
  return sources
end

paw.health.register(
  "plugstate.tone3000",
  function(h: contracts.Health)
    local curl = executable("curl")
    if curl then
      h.ok("curl: " .. curl)
    else
      h.error("no curl on the PATH", "paw asks TONE3000 through curl")
    end
    local auth = client.auth
    if auth then
      local cid = auth.client_id()
      if cid then
        h.ok("client_id for the sign-in: " .. cid)
      else
        h.info("no client_id: set paw.opt.plugstate_tone3000_client_id to sign in with :plugstate.tone3000_login")
      end
    end
    local sources = token_sources()
    if #sources > 0 then
      h.ok("a token from (the first that has one): " .. table.concat(sources, ", "))
    else
      h.info("no token: the search works only where TONE3000 lets it without one; a download needs one")
    end
    h.info("downloads in " .. client.cache_dir())
  end,
  {desc = "TONE3000's library: curl, where the token comes from, the cache"}
)

return M
