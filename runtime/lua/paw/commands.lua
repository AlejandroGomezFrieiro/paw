-- Commands: everything a user can do has a name. Key mappings, the command
-- line and the RPC socket all run commands by that name.
local M = {}

local registry = {}

--- Define or replace a command.
---   paw.command("track.mute", function(ctx) ... end, { desc = "Mute the track" })
--- The handler gets `ctx` with `ctx.args` (positional and named arguments)
--- and `ctx.count` (the number typed before a key mapping, or nil). With
--- `opts.raw`, the command line gives its text as one string in
--- `ctx.args[1]`. With `opts.range`, it accepts a range of bars before it
--- (`:5,8name`) as `ctx.range`. See Ranges below.
function M.define(name, run, opts)
  assert(type(name) == "string" and type(run) == "function", "usage: paw.command(name, function, opts)")
  opts = opts or {}
  registry[name] = { name = name, run = run, desc = opts.desc or "", raw = opts.raw, complete = opts.complete, label = opts.label, range = opts.range,
    ext = opts.ext or M.owner() }
end

--- The extension that paw loads now, or whose code registers these commands
--- and keys later. `:help` goes to its page for them, and an unload removes them.
function M.owner()
  local ext = rawget(paw, "ext")
  if not ext then return nil end
  -- While it loads, or later from code of its own files.
  return ext.current and ext.current.name or ext.caller()
end

--- What an undo step made by a command is called: its `label`, or the
--- start of its description, before any example or alternative.
function M.label(spec)
  if spec.label then return spec.label end
  local text = spec.desc or ""
  text = text:match("^[^\n]*"):gsub(":? `.*$", ""):gsub(":.*$", ""):gsub(";.*$", ""):gsub(", or .*$", "")
  text = text:gsub("%s+$", "")
  return text ~= "" and text or spec.name
end

--- Make `alias` another name for `target`.
function M.alias(alias, target)
  local spec = assert(registry[target], "no command " .. target)
  registry[alias] = { name = alias, run = spec.run, desc = spec.desc, raw = spec.raw, complete = spec.complete, label = spec.label, range = spec.range, alias_of = target, ext = spec.ext }
end

--- The command of a name: `{ name, run, desc, ... }` as `paw.command` made it, or nil.
function M.get(name)
  return registry[name]
end

--- Put a command back as `spec` (a command that `get` or `list` gave), or
--- remove it with nil. An extension that unloads does this with the
--- commands that it made.
function M.put(name, spec)
  registry[name] = spec
end

--- Count a use of a command selected by name (typed, or selected in a
--- picker). Pickers then show the commands used most first. paw keeps the
--- count in `paw.state`.
function M.used(name)
  local spec = registry[name]
  name = spec and spec.alias_of or name
  if not registry[name] then return end
  local uses = paw.state.command_uses or {}
  uses[name] = math.min((uses[name] or 0) + 1, 1000)
  paw.state.command_uses = uses
end

--- The number of times that `used` counted a command.
function M.uses(name)
  local uses = paw.state.command_uses
  return type(uses) == "table" and uses[name] or 0
end

--- Every command, sorted by name.
function M.list()
  local out = {}
  for _, spec in pairs(registry) do out[#out + 1] = spec end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- What a bare extension name (`:notation`) stands for: its `.open` or
--- `.show` command, where it has one.
function M.main(name)
  for _, main in ipairs({ ".open", ".show" }) do
    if registry[name .. main] then return registry[name .. main] end
  end
end

--- What to say about a name that is no command: the commands that start
--- with it, if there are any.
function M.unknown(name)
  name = tostring(name)
  local ext = paw.ext
  local stem = name:match("^[^.]+")
  if ext and stem and not ext.loaded[stem] then
    for _, bundled in ipairs(ext.bundled()) do
      if bundled == stem then
        return stem .. " is a bundled extension that isn't loaded: `:ext.load " .. stem .. "` loads it now, `paw.ext.load` in init.lua keeps it"
      end
    end
  end
  local near = {}
  for _, other in ipairs(M.list()) do
    if #near < 5 and #name >= 2 and other.name:sub(1, #name) == name then near[#near + 1] = ":" .. other.name end
  end
  return "no command `" .. name .. "`" .. (#near > 0 and ": did you mean " .. table.concat(near, ", ") .. "?" or ": `,fc` or `:` and Tab find one")
end

--- Run a command. `args` is a table of arguments. `ctx` adds fields such as `count`.
function M.run(name, args, ctx)
  local spec = registry[name]
  if not spec and type(name) == "string" then
    spec = M.main(name)
    if spec then name = spec.name end
  end
  if not spec then error(M.unknown(name), 0) end
  ctx = ctx or {}
  ctx.args, ctx.name = args or {}, name
  -- Names the undo step this command makes, as its description says it;
  -- the outermost command (or the key that ran it) wins.
  paw.api.undo_label(M.label(spec))
  -- `name` is what was typed, which may be an alias; `command` is the
  -- command it stands for, which is what a listener usually cares about.
  local command = spec.alias_of or name
  paw.emit("command.pre", { name = name, command = command, args = ctx.args })
  local result = paw.limit.named("the command `" .. name .. "`", spec.run, ctx)
  paw.emit("command.post", { name = name, command = command, args = ctx.args })
  return result
end

local function convert(text)
  if text == "true" then return true end
  if text == "false" then return false end
  return tonumber(text) or text
end

--- Split on spaces, keeping quoted stretches together and dropping the quotes.
local function tokens(text)
  local out, pos = {}, 1
  while true do
    pos = text:find("%S", pos)
    if not pos then break end
    local parts, quoted, head = {}, false, nil
    while pos <= #text and not text:sub(pos, pos):match("%s") do
      local ch = text:sub(pos, pos)
      if ch == '"' or ch == "'" then
        local close = text:find(ch, pos + 1, true) or #text + 1
        parts[#parts + 1], pos, quoted = text:sub(pos + 1, close - 1), close + 1, true
        head = head or ""
      else
        local s, e = text:find("^[^%s\"']+", pos)
        parts[#parts + 1], pos = text:sub(s, e), e + 1
        head = head or parts[#parts]
      end
    end
    out[#out + 1] = { text = table.concat(parts), quoted = quoted, head = head or "" }
  end
  return out
end

--- Split a command line into a name and arguments:
---   `track.add Bass volume=-6` -> "track.add", { "Bass", volume = -6 }
--- Quotes keep spaces together: `track.add "Lead Guitar"`, `name="Lead Guitar"`.
function M.parse(line)
  local name, rest = line:match("^%s*(%S+)%s*(.-)%s*$")
  if not name then return nil end
  local spec = registry[name]
  if spec and spec.raw then return name, { rest } end
  local args = {}
  for _, token in ipairs(tokens(rest)) do
    local key = token.head:match("^([%a_][%w_]*)=")
    local value = key and token.text:sub(#key + 2) or token.text
    if not token.quoted then value = convert(value) end
    if key then args[key] = value else args[#args + 1] = value end
  end
  return name, args
end

-- Ranges ----------------------------------------------------------------------
--
-- A command line may start with a range, as in Vim: of time (`:5,8`, `%`,
-- `.`, `$`, `'a,'b`, `'<,'>`) and of tracks (`:t2,t4`, `t*`, `t/Drums/`).
-- `paw.ex` (runtime/lua/paw/ex.lua) reads them, runs its own commands on
-- them (`:5,8d`, `:%s/c4/d4/`, `:g/vel<20/d`), and gives the range to a
-- command defined with `range = true` as `ctx.range`: `{ bars = { first,
-- last }, from, to }` for time, `from` and `to` in beats of the song, the
-- end not included; `tracks` (ids) for tracks; `{ selection = true, region
-- }` for `'<,'>`, while `paw.keymap.selection()` returns that region. A
-- number right before a command without a range is its count: `:3snippet arp`.

--- Split a range from the start of a command line. Returns the range and
--- the rest. The range is nil when there is no range. When the range names
--- nothing, an error message replaces the rest.
function M.range(line) return paw.ex.range(line) end

--- Functions that may take a whole line before it is read as a command:
--- `fn(line, ctx)` returns true when it ran it. A text buffer takes `:w`,
--- `:s/a/b/` and its ranges of lines this way (paw/textbuf.lua).
M.line_handlers = {}

--- Run a command line, as typed after `:`, with a range in front if it has one.
function M.exec(line, ctx)
  for _, handler in ipairs(M.line_handlers) do
    if handler(line, ctx) then return end
  end
  return paw.ex.exec(line, ctx)
end

-- Completion ------------------------------------------------------------------
--
-- A command says what its arguments are with `complete` in its options:
--
--   complete = "tracks"                      -- every argument is a track's name
--   complete = { "tracks", "devices" }       -- the first a track, the second a device
--   complete = function(text, info) return { "on", "off" } end
--
-- A name is one of `paw.commands.completers` below; a function gets the
-- text after the command's name and `info` with `word` (the word being
-- typed), `index` (which argument it is, from 1) and `words` (those before
-- it), and returns candidates: strings, or `{ text = ..., desc = ... }`.
-- A function's candidates complete the whole text after the name when they
-- start with it, else the word being typed; a completer's, the word.

local function item(text, desc) return { text = text, desc = desc } end

--- A list of strings as candidates.
local function words(list)
  local out = {}
  for i, w in ipairs(list) do out[i] = item(w) end
  return out
end

--- Files and directories that start with what is typed, directories ending
--- in `/`. `extensions` (a set) keeps only files with those endings.
local function files(word, extensions)
  local home = os.getenv("HOME") or ""
  local typed_dir, stem = word:match("^(.*/)([^/]*)$")
  typed_dir, stem = typed_dir or "", stem or word
  -- Relative names are in the folder that `:cd` set, or beside the project.
  local here = paw.files and paw.files.here() or "."
  local dir = typed_dir == "" and here or typed_dir:gsub("^~/", home .. "/")
  if dir:sub(1, 1) ~= "/" then dir = here .. "/" .. dir end
  local ok, entries = pcall(paw.api.read_dir, dir)
  if not ok then return {} end
  local out = {}
  for _, entry in ipairs(entries) do
    local name = entry.name
    if (stem:sub(1, 1) == "." or name:sub(1, 1) ~= ".") and name:sub(1, #stem):lower() == stem:lower() then
      if entry.is_dir then
        out[#out + 1] = item(typed_dir .. name .. "/", "directory")
      elseif not extensions or extensions[(name:match("%.([^.]+)$") or ""):lower()] then
        out[#out + 1] = item(typed_dir .. name)
      end
    end
  end
  table.sort(out, function(a, b)
    local da, db = a.desc ~= nil, b.desc ~= nil
    if da ~= db then return da end
    return a.text < b.text
  end)
  return out
end

local function set_of(list)
  local out = {}
  for _, v in ipairs(list) do out[v] = true end
  return out
end

M.completers = {
  commands = function()
    local out = {}
    for _, spec in ipairs(M.list()) do out[#out + 1] = item(spec.name, spec.desc) end
    return out
  end,
  tracks = function()
    local out = {}
    for _, id in ipairs(paw.api.track_list()) do out[#out + 1] = item(paw.api.track_get(id, "name"), "track") end
    out[#out + 1] = item("master", "the master track")
    return out
  end,
  devices = function()
    local out = {}
    for _, info in ipairs(paw.device_types()) do
      out[#out + 1] = item(info.kind, info.name ~= info.kind and info.name or info.format)
    end
    table.sort(out, function(a, b) return a.text < b.text end)
    return out
  end,
  track_devices = function()
    local out = {}
    local track = paw.cursor.track()
    for _, device in ipairs(track and track:devices() or {}) do
      local d = device:get()
      out[#out + 1] = item(d.kind, d.name)
    end
    return out
  end,
  options = function()
    local out = {}
    for _, o in ipairs(paw.option.list()) do out[#out + 1] = item(o.name, "now " .. paw.option.show(paw.opt[o.name])) end
    return out
  end,
  views = function()
    local out = {}
    for name, view in pairs(paw.ui.views) do
      if view.focusable ~= false then out[#out + 1] = item(name) end
    end
    table.sort(out, function(a, b) return a.text < b.text end)
    return out
  end,
  pickers = function()
    local out = {}
    for name, source in pairs(paw.pick.sources) do
      out[#out + 1] = item(name, type(source) == "table" and source.desc or nil)
    end
    table.sort(out, function(a, b) return a.text < b.text end)
    return out
  end,
  files = function(word) return files(word) end,
  -- Sound files, and the files of the formats that read (paw/formats.lua).
  audio_files = function(word)
    local ext = set_of({ "wav", "wave", "aif", "aiff", "flac", "mp3", "ogg", "oga" })
    for _, e in ipairs(paw.formats.extensions("import")) do ext[e] = true end
    return files(word, ext)
  end,
  -- What `import` takes: sound files and the files of the formats that read.
  importable = function(word) return M.completers.audio_files(word) end,
  -- What `export` writes: the files of the formats that write.
  exportable = function(word) return files(word, set_of(paw.formats.extensions("export"))) end,
  -- Projects, and the files of formats that hold whole projects.
  projects = function(word)
    local ext = set_of({ "json" })
    for _, f in ipairs(paw.formats.list()) do
      if f.project then
        for _, e in ipairs(f.extensions) do ext[e] = true end
      end
    end
    return files(word, ext)
  end,
  dirs = function(word) return files(word, {}) end,
  -- What `edit` opens: projects, the files of the formats that read (as
  -- projects) and sound files.
  openable = function(word)
    local ext = set_of({ "json", "wav", "wave", "aif", "aiff", "flac", "mp3", "ogg", "oga" })
    for _, e in ipairs(paw.formats.extensions("import")) do ext[e] = true end
    return files(word, ext)
  end,
}

--- Candidates from one completer (a name, a list of names by position, or
--- a function), as items.
local function candidates(spec, rest, info)
  local how = spec.complete
  if type(how) == "table" then how = how[info.index] end
  if type(how) == "string" then
    local fn = M.completers[how]
    return fn and fn(info.word, info) or {}, true
  end
  if type(how) ~= "function" then return {} end
  local ok, list = pcall(how, rest, info)
  if not ok or type(list) ~= "table" then return {} end
  local out = {}
  for i, c in ipairs(list) do out[i] = type(c) == "table" and item(tostring(c.text or c[1]), c.desc) or item(tostring(c)) end
  -- A completer that ranks what it gives (`ranked = true`) is taken in its order, all of it.
  return out, false, list.ranked
end

local function starts(text, stem) return text:sub(1, #stem):lower() == stem:lower() end

--- What could finish a command line: a list of `{ text, label, desc }` with
--- `text` the whole line it would become and `label` the part shown.
---   paw.commands.complete("track.co")   --> { { text = "track.color", label = "track.color", desc = ... } }
function M.complete(line)
  -- Marks after `'`, tracks after `t/`, fields in a pattern.
  local special = paw.ex.complete_range(line) or paw.ex.complete_pattern(line)
  if special then return special end
  -- A range in front stays as it is; what follows it is completed.
  local range, rest = M.range(line)
  if range and rest ~= line then
    local head = line:sub(1, #line - #rest)
    local out = M.complete(rest)
    for _, entry in ipairs(out) do entry.text = head .. entry.text end
    return out
  end
  local out = {}
  local name, sep, rest = line:match("^(%S+)(%s+)(.*)$")
  if not name then
    -- The command's name: those that start with it, then those that hold it.
    local later = {}
    for _, spec in ipairs(M.list()) do
      local entry = { text = spec.name, label = spec.name, desc = spec.alias_of and "→ " .. spec.alias_of or spec.desc }
      if starts(spec.name, line) then
        out[#out + 1] = entry
      elseif line ~= "" and spec.name:lower():find(line:lower(), 1, true) then
        later[#later + 1] = entry
      end
    end
    for _, entry in ipairs(later) do out[#out + 1] = entry end
    return out
  end
  local spec = registry[name]
  if not spec or not spec.complete then return out end
  -- The words before the one being typed, and that word.
  local before, word = rest:match("^(.-)(%S*)$")
  local words_before = {}
  for w in before:gmatch("%S+") do words_before[#words_before + 1] = w end
  local info = { word = word, index = #words_before + 1, words = words_before, line = line }
  local head = name .. sep
  local whole, part, inside = {}, {}, {}
  local list, by_word, ranked = candidates(spec, rest, info)
  for _, c in ipairs(list) do
    local text = c.text
    if ranked or (not by_word and starts(text, rest)) then
      whole[#whole + 1] = { text = head .. text, label = text, desc = c.desc }
    else
      -- A name with a space in it is quoted, unless the command takes its
      -- text whole.
      local shown = (not spec.raw and text:find(" ")) and '"' .. text .. '"' or text
      local entry = { text = head .. before .. shown, label = shown, desc = c.desc }
      if starts(text, word) then
        part[#part + 1] = entry
      elseif word ~= "" and text:lower():find(word:lower(), 1, true) then
        inside[#inside + 1] = entry
      end
    end
  end
  -- What starts with the typed text, then what only holds it.
  for _, list in ipairs({ whole, part, inside }) do
    for _, entry in ipairs(list) do out[#out + 1] = entry end
  end
  return out
end

return M
