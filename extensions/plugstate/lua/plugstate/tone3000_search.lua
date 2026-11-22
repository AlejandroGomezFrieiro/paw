-- Search TONE3000's library from paw: `:plugstate.search <words>` (and
-- `<localleader>t` in the device panel) lists the tones that TONE3000
-- finds, a page at a time; Enter on a tone lists its models; Enter on a
-- model downloads it once into paw's cache and loads it into the device
-- through its adapter (a block of TONE3000, the model of Neural Amp
-- Modeler, the impulse response of a convolver), as one undo step. The
-- project keeps the file as the adapter does, and the tone's id, name,
-- author and license in `meta.plugstate.tone3000` of the device.
local api = paw.api
local plugstate = require("plugstate")
local client = require("plugstate.tone3000_api")

local M = { client = client }

paw.option.define("plugstate_tone3000_token_file", "") -- a file with a TONE3000 access token (mode 600)
paw.option.define("plugstate_tone3000_plugin_session", false) -- also use the session of the TONE3000 plugin
paw.option.define("plugstate_tone3000_api", "") -- another address of the API (empty: TONE3000's)

M.PAGE_SIZE = 25

local function device_name(id) return api.device_get(id).name end

local function say(text, level) paw.notify("TONE3000: " .. text, level) end

local function takes(slot, ext)
  for _, t in ipairs(slot.types or {}) do
    if t:lower() == ext then return true end
  end
  return false
end

--- The slot of a device that a file of `ext` goes into: the one named by
--- `key`; else the first slot of a file of that kind ("model" for .nam,
--- "impulse response" for .wav); else the first that takes the file.
function M.slot_for(id, ext, key)
  if key and key ~= "" then return plugstate.slot(id, key) end
  local slots = plugstate.slots(id)
  local want = ext == "nam" and "model" or "impulse response"
  for _, s in ipairs(slots) do
    if s.kind == "file" and takes(s, ext) and s.what == want then return s end
  end
  for _, s in ipairs(slots) do
    if s.kind == "file" and takes(s, ext) then return s end
  end
end

--- The formats of TONE3000 that a device takes: "nam", "ir".
function M.formats(id)
  local out, seen = {}, {}
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

local function author(tone)
  local u = type(tone.user) == "table" and tone.user or {}
  local name = u.username or u.display_name
  return type(name) == "string" and name or "?"
end

local function names(list)
  local out = {}
  for _, x in ipairs(type(list) == "table" and list or {}) do
    local n = type(x) == "table" and x.name or x
    if type(n) == "string" then out[#out + 1] = n end
  end
  return table.concat(out, ", ")
end

local function cut(text, n)
  text = tostring(text or "")
  if #text <= n then return text end
  return text:sub(1, n - 1) .. "…"
end

local LOADS = { nam = true, ir = true }

--- A tone as a line of the picker: its title, author, gear, format, sizes
--- and number of models.
function M.tone_line(tone)
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

local function tone_preview(tone)
  local lines = { { text = tostring(tone.title), style = "Title" }, "by " .. author(tone) }
  lines[#lines + 1] =
    string.format("%s · %s · %s", tostring(tone.gear or "?"), tostring(tone.format or "?"), names(tone.sizes))
  lines[#lines + 1] = string.format(
    "%s models · %s downloads · %s favorites",
    tostring(tone.models_count or "?"),
    tostring(tone.downloads_count or "?"),
    tostring(tone.favorites_count or "?")
  )
  if tone.license then lines[#lines + 1] = "license: " .. tostring(tone.license) end
  local makes, tags = names(tone.makes), names(tone.tags)
  if makes ~= "" then lines[#lines + 1] = "makes: " .. makes end
  if tags ~= "" then lines[#lines + 1] = "tags: " .. tags end
  if tone.url then lines[#lines + 1] = tostring(tone.url) end
  if type(tone.description) == "string" and tone.description ~= "" then
    lines[#lines + 1] = ""
    for para in tone.description:gmatch("[^\n]+") do
      lines[#lines + 1] = para
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = { text = "Powered by TONE3000 · https://www.tone3000.com", style = "Dim" }
  return lines
end

-- --- loading --------------------------------------------------------------------------

--- Keep what the device plays of TONE3000, by slot, in its meta: the
--- project then names the tone and its author without the network.
local function remember(id, slot_key, tone, model)
  local meta = api.device_get(id).meta or {}
  local data = type(meta.plugstate) == "table" and meta.plugstate or {}
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
  api.device_set(id, "meta", meta)
end

--- Download a model (or take it from the cache) and load it into the
--- device. `job`: `{ device, slot }` from the search.
function M.load_model(job, tone, model)
  local ext = client.extension(model, tone)
  if not ext then return say("paw cannot load a model of the format " .. tostring(tone.format), "warn") end
  local id = job.device
  say("downloading " .. tostring(model.name) .. " …")
  return client.download(model, tone, function(path, err, cached)
    if not path then return say(tostring(err), "error") end
    if not pcall(api.device_get, id) then return say("the device is gone; the model is in " .. path, "warn") end
    local slot = M.slot_for(id, ext, job.slot)
    if not slot then
      return say(device_name(id) .. " has no place for a ." .. ext .. " file (the model is in " .. path .. ")", "warn")
    end
    local ok, why = plugstate.set(id, slot.key, path)
    if not ok then return say(device_name(id) .. ": " .. tostring(why), "error") end
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
    if M.on_loaded then M.on_loaded(id, slot.key, path) end
  end)
end

--- Choose one of the models of a tone (none to choose when it has one).
function M.pick_model(job, tone)
  say("the models of " .. tostring(tone.title) .. " …")
  local params = { page_size = 100 }
  if job.params.architecture then params.architecture = job.params.architecture end
  return client.models(tone.id, params, function(result)
    if not result.ok then return say(result.message, "error") end
    local models = type(result.data.data) == "table" and result.data.data or {}
    if #models == 0 then return say(tostring(tone.title) .. " has no models that this device can load", "warn") end
    if #models == 1 then return M.load_model(job, tone, models[1]) end
    paw.pick({
      title = "TONE3000 · " .. tostring(tone.title) .. " · " .. #models .. " models",
      items = models,
      format = function(m)
        return string.format(
          "%-44s %-10s %s",
          cut(m.name, 44),
          tostring(m.size or ""),
          m.architecture_version and ("A" .. tostring(m.architecture_version)) or ""
        )
      end,
      primary = function(m) return tostring(m.name) end,
      on_choose = function(m) M.load_model(job, tone, m) end,
      preview = function(m)
        return {
          { text = tostring(m.name), style = "Title" },
          tostring(tone.title) .. " by " .. author(tone),
          "size: " .. tostring(m.size or "?"),
          "license: " .. tostring(tone.license or "?"),
          { text = "Powered by TONE3000", style = "Dim" },
        }
      end,
    })
  end)
end

local function pick_tones(job)
  local items = {}
  for _, t in ipairs(job.tones) do
    items[#items + 1] = t
  end
  if job.page < job.pages then items[#items + 1] = { more = 1 } end
  if job.page > 1 then items[#items + 1] = { more = -1 } end
  local function page(n)
    return function() M.page(job, job.page + n) end
  end
  paw.pick({
    title = string.format(
      "TONE3000 · %s · page %d of %d · %d tones",
      job.words ~= "" and ("“" .. job.words .. "”") or "trending",
      job.page,
      job.pages,
      job.total
    ),
    items = items,
    format = function(t)
      if t.more then
        return t.more > 0 and string.format("▸ the next page (%d of %d)", job.page + 1, job.pages)
          or string.format("◂ the page before (%d of %d)", job.page - 1, job.pages)
      end
      return M.tone_line(t)
    end,
    primary = function(t) return t.more and "" or tostring(t.title) end,
    empty = "TONE3000 finds no tones" .. (job.words ~= "" and (" with “" .. job.words .. "”") or ""),
    on_choose = function(t)
      if t.more then return M.page(job, job.page + t.more) end
      if not LOADS[tostring(t.format)] then
        return say("paw cannot load a tone of the format " .. tostring(t.format), "warn")
      end
      M.pick_model(job, t)
    end,
    actions = {
      ["<A-n>"] = { fn = page(1), desc = "next page" },
      ["<A-p>"] = { fn = page(-1), desc = "page before" },
    },
    preview = function(t)
      if t.more then return { "Enter asks TONE3000 for that page" } end
      return tone_preview(t)
    end,
  })
end

--- Ask for page `n` of a search and show it.
function M.page(job, n)
  if n < 1 or (job.pages and n > job.pages) then return say("no page " .. n, "warn") end
  local params = {}
  for k, v in pairs(job.params) do
    params[k] = v
  end
  params.page, params.page_size = n, M.PAGE_SIZE
  say(string.format("searching%s (page %d) …", job.words ~= "" and (" “" .. job.words .. "”") or "", n))
  return client.search(params, function(result)
    if not result.ok then return say(result.message, "error") end
    local data = result.data
    job.tones = type(data.data) == "table" and data.data or {}
    job.page = tonumber(data.page) or n
    job.pages = math.max(1, tonumber(data.total_pages) or 1)
    job.total = tonumber(data.total) or #job.tones
    M.last = job
    pick_tones(job)
  end)
end

--- Search for a device. `opts`: `words`, `gear`, `format`, `by` (creators),
--- `sort`, `slot`, `architecture`.
function M.search(id, opts)
  opts = opts or {}
  local formats = M.formats(id)
  if #formats == 0 then
    return say(device_name(id) .. " takes no file that TONE3000 has (models, impulse responses)", "warn")
  end
  local format = opts.format
  if format == "model" then format = "nam" end
  if format and format ~= "" then
    local ok = false
    for _, f in ipairs(formats) do
      ok = ok or f == format
    end
    if not ok then return say(device_name(id) .. " does not load " .. format .. " files", "warn") end
  elseif #formats == 1 then
    format = formats[1]
  end
  local a = plugstate.adapter_of(id)
  -- The TONE3000 plugin plays the models of the second architecture, as its
  -- own browser asks for; the API leaves them out unless asked.
  local architecture = opts.architecture or (a and a.name == "tone3000" and 2 or nil)
  local job = {
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
  return M.page(job, 1)
end

-- --- the command and the key ------------------------------------------------------------

local function arg(ctx, name)
  local v = ctx.args[name]
  return v ~= nil and tostring(v) or nil
end

paw.command("plugstate.search", function(ctx)
  local id, why = plugstate.target()
  if not id then return paw.notify(why, "warn") end
  local words = {}
  for _, w in ipairs(ctx.args) do
    words[#words + 1] = tostring(w)
  end
  M.search(id, {
    words = table.concat(words, " "),
    gear = arg(ctx, "gear"),
    format = arg(ctx, "type"),
    by = arg(ctx, "by"),
    sort = arg(ctx, "sort"),
    slot = arg(ctx, "slot"),
    architecture = arg(ctx, "arch"),
  })
end, {
  desc = "Search TONE3000's library for a model or an impulse response for the plugin: `plugstate.search plexi`; "
    .. "`gear=amp|pedal|cab|...`, `type=nam|ir`, `by=<user>`, `sort=newest|trending|...`, `slot=<key>`",
})

paw.command("plugstate.search_more", function(ctx)
  local job = M.last
  if not job then return paw.notify("no TONE3000 search yet: `:plugstate.search <words>`", "warn") end
  M.page(job, job.page + (ctx.count or 1))
end, { desc = "The next page of the last TONE3000 search (a count skips more)" })

paw.command("plugstate.search_prompt", function()
  if not plugstate.target() then return paw.notify(select(2, plugstate.target()), "warn") end
  paw.ui.input({ prompt = "TONE3000 search: " }, function(text) paw.commands.exec("plugstate.search " .. text) end)
end, { desc = "Ask for words, then search TONE3000's library for the plugin" })

paw.keymap.set(
  "<localleader>t",
  "plugstate.search_prompt",
  { view = "devices", desc = "Search TONE3000's library for a model or an impulse response" }
)

paw.health.register("plugstate.tone3000", function(h)
  if paw.health.executable("curl") then
    h.ok("curl: " .. paw.health.executable("curl"))
  else
    h.error("no curl on the PATH", "paw asks TONE3000 through curl")
  end
  local sources = {}
  if (os.getenv("TONE3000_TOKEN") or "") ~= "" then sources[#sources + 1] = "TONE3000_TOKEN" end
  local file = paw.opt.plugstate_tone3000_token_file or ""
  if file ~= "" then sources[#sources + 1] = "the token file " .. file end
  if paw.health.executable(client.secret_tool) then
    sources[#sources + 1] = "the keyring (secret-tool), if it has an entry"
  end
  local auth = client.auth
  if auth then
    sources[#sources + 1] = "the sign-in of :plugstate.tone3000_login, if there is one"
    if auth.client_id() then
      h.ok("client_id for the sign-in: " .. auth.client_id())
    else
      h.info("no client_id: set paw.opt.plugstate_tone3000_client_id to sign in with :plugstate.tone3000_login")
    end
  end
  if paw.opt.plugstate_tone3000_plugin_session then sources[#sources + 1] = "the session of the TONE3000 plugin" end
  if #sources > 0 then
    h.ok("a token from (the first that has one): " .. table.concat(sources, ", "))
  else
    h.info("no token: the search works only where TONE3000 lets it without one; a download needs one")
  end
  h.info("downloads in " .. client.cache_dir())
end, { desc = "TONE3000's library: curl, where the token comes from, the cache" })

return M
