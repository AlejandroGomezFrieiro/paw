-- Commands: everything a user can do has a name. Key mappings, the command
-- line and the RPC socket all run commands by that name.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local type contracts = require("paw.contracts")
local options = require("paw.options")
local util = require("paw.util")

-- The types that a command's function and options have are contracts
-- (paw/contracts.tl), so that `paw.command` is typed for the modules in
-- Lua as well.
local type Arg = contracts.CommandArg
local type Args = contracts.CommandArgs
local type Range = contracts.CommandRange
local type Context = contracts.CommandContext
local type Result = contracts.CommandResult

--- A candidate of completion: `text`, and what it is (`desc`).
local record Item
  text: string
  desc: string
end

local type Info = contracts.CompleteInfo
local type Candidate = contracts.CompleteCandidate

--- What a function of `complete` gives: candidates, and `ranked = true`
--- when they are in their order already.
local record Candidates is {string | Candidate}
  ranked: boolean
end

local type Completer = function(string, ?Info): {Item}
local type CompleteFn = contracts.CompleteFn
local type Complete = contracts.Complete

--- A command, as `paw.command` makes it. `ex` marks a command of Ex,
--- which takes its text whole after a range, and `items` one that also
--- works on the matches that `:g` hands it (paw/ex.tl).
local record Spec
  name: string
  run: function(Context): Result
  desc: string
  raw: boolean
  complete: Complete
  label: string
  range: boolean
  alias_of: string
  ext: string
  ex: boolean
  items: boolean
  adjust: {contracts.AdjustParam}
end

local type Options = contracts.CommandOptions

--- A completion of a command line: the whole line it makes (`text`), the
--- part shown (`label`), and what it is.
local record Entry
  text: string
  label: string
  desc: string
end

local record M
  type Arg = Arg
  type Args = Args
  type Range = Range
  type Context = Context
  type Result = Result
  type Item = Item
  type Info = Info
  type Candidate = Candidate
  type Candidates = Candidates
  type Spec = Spec
  type Options = Options
  type Entry = Entry
  type Completer = Completer

  owner: function(): string
  line_handlers: {function(string, Context): boolean}
  completers: {string: Completer}
end

-- What this module reads of `paw`, which paw/init.lua makes. A module of the
-- runtime in Teal does not see the global `paw`: runtime/types/paw.d.tl
-- declares it from these modules. The modules in Lua type their parts in
-- their doc comments (`partial.Paw`); the rest is here.
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type LimitModule = require("paw.limit")
local type FormatsModule = require("paw.formats")
local type CursorModule = require("paw.cursor")
local type Registries = require("paw.registry")
local record State
  command_uses: {string: integer}
end
--- The payload of `command.pre` and `command.post`.
local record Ran
  name: string
  command: string
  args: Args
end
local command_pre: events.Event<Ran> = events.event("command.pre")
local command_post: events.Event<Ran> = events.event("command.post")
--- paw/ex.tl, as far as this module calls it: paw/ex.tl requires this
--- module, so this one names only the part it calls.
local record Ex
  range: function(string): Range, string
  exec: function(string, Context): Result...
  complete_range: function(string): {Entry}
  complete_pattern: function(string): {Entry}
end
-- paw/ui.tl names this module's types (through paw/layout.tl), so this
-- one declares only the part of it that it reads.
local record Ui
  views: {string: contracts.View}
end

--- `paw.pick` (paw/pick.tl, which requires this module): the pickers
--- by name, which `:pick` completes.
local record Pick
  sources: Registries.Registry<contracts.PickEntry>
end

local record Paw is partial.Paw
  keymap: KeymapModule
  ui: Ui
  pick: Pick
  state: State
  limit: LimitModule
  ex: Ex
  formats: FormatsModule
  cursor: CursorModule
end
local paw = (_G as {string: Paw}).paw

local registry: {string: Spec} = {}

--- The last command that can be adjusted, as it ran: what `adjust` runs
--- again. `before` is the undo state that it started from.
local record Adjustable
  name: string
  args: Args
  ctx: Context
  before: integer
  line: string
  about: string
end
local last: Adjustable
local about: string -- what the command that runs says it worked on
local running = 0 -- how many commands run inside each other

--- Define or replace a command.
---   paw.command("track.mute", function(ctx) ... end, { desc = "Mute the track" })
--- The handler gets `ctx` with `ctx.args` (positional and named arguments)
--- and `ctx.count` (the number typed before a key mapping, or nil). With
--- `opts.raw`, the command line gives its text as one string in
--- `ctx.args[1]`. With `opts.range`, it accepts a range of bars before it
--- (`:5,8name`) as `ctx.range`. See Ranges below.
function M.define<C is Context>(name: string, run: function(C): (Result), opts?: Options)
  assert(name is string and run is function, "usage: paw.command(name, function, opts)")
  opts = opts or {}
  registry[name] = {
    name = name,
    run = run as function(Context): (Result),
    desc = opts.desc or "",
    raw = opts.raw,
    complete = opts.complete,
    label = opts.label,
    range = opts.range,
    adjust = opts.adjust,
    ext = opts.ext or M.owner(),
  }
end

--- The extension that paw loads now, or whose code registers these commands
--- and keys later. `:help` goes to its page for them, and an unload removes them.
function M.owner(): string
  local ext = rawget(paw as {string: partial.Ext}, "ext")
  if not ext then
    return nil
  end
  -- While it loads, or later from code of its own files.
  return ext.current and ext.current.name or ext.caller()
end

--- What an undo step made by a command is called: its `label`, or the
--- start of its description, before any example or alternative.
function M.label(spec: Spec): string
  if spec.label then
    return spec.label
  end
  local text = spec.desc or ""
  text = text:match("^[^\n]*"):gsub(":? `.*$", ""):gsub(":.*$", ""):gsub(";.*$", ""):gsub(", or .*$", "")
  text = text:gsub("%s+$", "")
  return text ~= "" and text or spec.name
end

--- Make `alias` another name for `target`.
function M.alias(alias: string, target: string)
  local spec = assert(registry[target], "no command " .. target)
  registry[alias] = {
    name = alias,
    run = spec.run,
    desc = spec.desc,
    raw = spec.raw,
    complete = spec.complete,
    label = spec.label,
    range = spec.range,
    adjust = spec.adjust,
    alias_of = target,
    ext = spec.ext,
  }
end

--- The command of a name: `{ name, run, desc, ... }` as `paw.command` made it, or nil.
function M.get(name: string): Spec
  return registry[name]
end

--- Put a command back as `spec` (a command that `get` or `list` gave), or
--- remove it with nil. An extension that unloads does this with the
--- commands that it made.
function M.put(name: string, spec: Spec)
  registry[name] = spec
end

--- Count a use of a command selected by name (typed, or selected in a
--- picker). Pickers then show the commands used most first. paw keeps the
--- count in `paw.state`.
function M.used(name: string)
  local spec = registry[name]
  name = spec and spec.alias_of or name
  if not registry[name] then
    return
  end
  local uses = paw.state.command_uses or {}
  uses[name] = math.min((uses[name] or 0) + 1, 1000)
  paw.state.command_uses = uses
end

--- The number of times that `used` counted a command.
function M.uses(name: string): integer
  local uses = paw.state.command_uses
  return uses is {string: integer} and uses[name] or 0
end

--- Every command, sorted by name.
function M.list(): {Spec}
  local out: {Spec} = {}
  for _, spec in pairs(registry) do
    out[#out + 1] = spec
  end
  table.sort(out, function(a: Spec, b: Spec): boolean return a.name < b.name end)
  return out
end

--- What a bare extension name (`:notation`) stands for: its `.open` or
--- `.show` command, where it has one.
function M.main(name: string): Spec
  for _, main in ipairs({".open", ".show"}) do
    if registry[name .. main] then
      return registry[name .. main]
    end
  end
end

--- What to say about a name that is no command: the commands that start
--- with it, if there are any.
function M.unknown(name: string): string
  name = tostring(name)
  local ext = paw.ext
  local stem = name:match("^[^.]+")
  if ext and stem and not ext.loaded[stem] then
    for _, bundled in ipairs(ext.bundled()) do
      if bundled == stem then
        return stem
          .. " is a bundled extension that isn't loaded: `:ext.load "
          .. stem
          .. "` loads it now, `paw.ext.load` in init.lua keeps it"
      end
    end
  end
  local near: {string} = {}
  for _, other in ipairs(M.list()) do
    if #near < 5 and #name >= 2 and other.name:sub(1, #name) == name then
      near[#near + 1] = ":" .. other.name
    end
  end
  return "no command `"
    .. name
    .. "`"
    .. (
      #near > 0 and ": did you mean " .. table.concat(near, ", ") .. "?"
      or ": `" .. (paw.keymap.human("<leader>f:") as string) .. "` or `:` and Tab find one"
    )
end

--- Run a command. `args` is a table of arguments. `ctx` adds fields such as `count`.
function M.run<C is Context>(name: string, args?: Args, ctx?: C): Result
  local spec = registry[name]
  if not spec and name is string then
    spec = M.main(name)
    if spec then
      name = spec.name
    end
  end
  if not spec then
    error(M.unknown(name), 0)
  end
  local c: Context = ctx or {}
  c.args, c.name = args or {}, name
  -- Names the undo step this command makes, as its description says it;
  -- the outermost command (or the key that ran it) wins.
  api.undo_label(M.label(spec))
  -- `name` is what was typed, which may be an alias; `command` is the
  -- command it stands for, which is what a listener usually cares about.
  local command = spec.alias_of or name
  -- An outermost command that can be adjusted remembers where it started,
  -- if nothing else changed the project in this turn before it.
  local before: integer
  if running == 0 and spec.adjust then
    about = nil
    if not api.undo_pending() then
      before = api.undo_current()
    end
  end
  events.emit(command_pre, {name = name, command = command, args = c.args})
  running = running + 1
  local ok, result = pcall(paw.limit.named, "the command `" .. name .. "`", spec.run, c) as (boolean, Result)
  running = running - 1
  if not ok then
    error(result, 0)
  end
  if before and api.undo_pending() then
    last = {
      name = name,
      args = util.merge(c.args as {string: Arg}, {}) as Args,
      ctx = c,
      before = before,
      line = c.line,
      about = about,
    }
  end
  events.emit(command_post, {name = name, command = command, args = c.args})
  return result
end

local function convert(text: string): Arg
  if text == "true" then
    return true
  end
  if text == "false" then
    return false
  end
  return tonumber(text) or text
end

--- A word of a command line: its text without quotes, whether it had
--- them, and what came before the first quote.
local record Token
  text: string
  quoted: boolean
  head: string
end

--- Split on spaces, keeping quoted stretches together and dropping the quotes.
local function tokens(text: string): {Token}
  local out: {Token} = {}
  local pos = 1
  while true do
    pos = text:find("%S", pos)
    if not pos then
      break
    end
    local parts, quoted, head: {string}, boolean, string = {}, false, nil
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
    out[#out + 1] = {text = table.concat(parts), quoted = quoted, head = head or ""}
  end
  return out
end

--- Split a command line into a name and arguments:
---   `track.add Bass volume=-6` -> "track.add", { "Bass", volume = -6 }
--- Quotes keep spaces together: `track.add "Lead Guitar"`, `name="Lead Guitar"`.
function M.parse(line: string): string, Args
  local name, rest = line:match("^%s*(%S+)%s*(.-)%s*$")
  if not name then
    return nil
  end
  local spec = registry[name]
  if spec and spec.raw then
    return name, {rest}
  end
  local args: Args = {}
  for _, token in ipairs(tokens(rest)) do
    local key = token.head:match("^([%a_][%w_]*)=")
    local value: Arg = key and token.text:sub(#key + 2) or token.text
    if not token.quoted then
      value = convert(value as string)
    end
    if key then
      args[key] = value
    else
      args[#args + 1] = value
    end
  end
  return name, args
end

-- Adjusting ---------------------------------------------------------------------
--
-- A command lists in `adjust` the parameters that the user can change after
-- it ran (`paw.command("quantize", fn, { adjust = { { name = "grid" } } })`).
-- `:adjust grid=1/8` then runs the last such command again with them: paw
-- puts the project back as it was before the command, runs the command with
-- its first parameters and the new ones, and the result takes the place of
-- the command's undo step.

--- The parameters that a command's arguments hold: the named ones, and the
--- positional ones by the order of the command's `adjust`. A command with
--- `raw` gets its text (`text`), which holds the same words.
local function read_params(spec: Spec, args: Args, text?: boolean): {string: Arg}
  local out: {string: Arg} = {}
  local names = spec.adjust or {}
  local n = 0
  local function positional(value: Arg)
    n = n + 1
    if names[n] then
      out[names[n].name] = value
    end
  end
  if text then
    for word in tostring(args[1] or ""):gmatch("%S+") do
      local key, value = word:match("^([%a_][%w_]*)=(.*)$")
      if key then
        out[key] = convert(value)
      else
        positional(convert(word))
      end
    end
  else
    for i = 1, #args do
      positional(args[i])
    end
    for key, value in pairs(args as {string: Arg}) do
      if type(key) == "string" then
        out[key] = value
      end
    end
  end
  return out
end

--- The arguments that make `params` again: as `name=value` in the text of
--- a command with `raw`, else named.
local function write_params(spec: Spec, params: {string: Arg}): Args
  local args: Args = {}
  if spec.raw then
    local parts: {string} = {}
    for _, p in ipairs(spec.adjust) do
      if params[p.name] ~= nil then
        parts[#parts + 1] = p.name .. "=" .. tostring(params[p.name])
      end
    end
    args[1] = table.concat(parts, " ")
    return args
  end
  for key, value in pairs(params) do
    args[key] = value
  end
  return args
end

--- The parameters of the command that runs: what the user gave, by the
--- names that its `adjust` lists. A parameter not given is not in the table.
---   local p = paw.commands.params(ctx)  -- `:quantize 1/16 strength=50`: { grid = "1/16", strength = 50 }
function M.params(ctx: Context): {string: Arg}
  local spec = registry[ctx.name]
  if not spec then
    return {}
  end
  return read_params(spec, ctx.args, spec.raw)
end

--- The line that runs a command with arguments, as typed after `:`.
local function line_of(spec: Spec, name: string, args: Args, prefix: string): string
  local text: string
  if spec.raw then
    text = tostring(args[1] or "")
  else
    local parts: {string} = {}
    for _, p in ipairs(spec.adjust) do
      if args[p.name] ~= nil then
        parts[#parts + 1] = p.name .. "=" .. tostring(args[p.name])
      end
    end
    text = table.concat(parts, " ")
  end
  return prefix .. name .. (text ~= "" and " " .. text or "")
end

--- The reason why a value is not one that a parameter takes, or nil.
local function check_param(command: string, p: contracts.AdjustParam, value: Arg): string
  if not (p.min or p.max) then
    return nil
  end
  if not (value is number) then
    return string.format("`%s` of `%s` is a number, not `%s`", p.name, command, tostring(value))
  end
  if (p.min and value < p.min) or (p.max and value > p.max) then
    local limits = p.min and p.max and string.format("%g to %g", p.min, p.max)
      or (p.min and "at least " .. p.min or "at most " .. p.max)
    return string.format("`%s` of `%s` is %s, not %s", p.name, command, limits, tostring(value))
  end
  return nil
end

--- The line `adjust a=1 b=2` that holds the parameters of the last
--- command that can be adjusted, as they are now; nil when no command ran
--- that can be adjusted. `<leader>.` puts it on the command line.
function M.adjusting(): string
  local spec = last and registry[last.name]
  if not (last and spec and spec.adjust) then
    return nil
  end
  local params = read_params(spec, last.args, spec.raw)
  local parts: {string} = {}
  for _, p in ipairs(spec.adjust) do
    local value = params[p.name]
    if value == nil then
      value = p.default
    end
    if value ~= nil then
      parts[#parts + 1] = p.name .. "=" .. tostring(value)
    end
  end
  return "adjust " .. table.concat(parts, " ")
end

--- A command that can be adjusted says the range it changed, as the panel
--- of `<leader>.` shows it (`Quantize · 48 notes`). Call it from the handler.
---   paw.commands.about("48 notes")
function M.about(text: string)
  about = text
end

--- What the panel of `<leader>.` shows: the title, the parameters of the
--- last command that can be adjusted, and their values now. Nil when there
--- is no such command.
function M.panel(): contracts.AdjustPanel
  local spec = last and registry[last.name]
  if not (last and spec and spec.adjust) then
    return nil
  end
  local params = read_params(spec, last.args, spec.raw)
  local values: {string: Arg} = {}
  for _, p in ipairs(spec.adjust) do
    local value = params[p.name]
    if value == nil then
      value = p.default
    end
    values[p.name] = value
  end
  local label = M.label(spec) or last.name
  return {
    title = last.about and label .. " · " .. last.about or label,
    params = spec.adjust,
    values = values,
  }
end

local function names_of(spec: Spec): string
  local names: {string} = {}
  for _, p in ipairs(spec.adjust) do
    names[#names + 1] = p.name
  end
  return table.concat(names, ", ")
end

--- Run the last command that has `adjust` again with other parameters, in
--- place of its undo step: `paw.commands.adjust({ grid = "1/8" })`, or
--- positional ones, by the order of its `adjust`. The project goes back to
--- before the command, the command runs again with its first parameters
--- and these laid over them, and the undo step is the new result. It
--- works only on the last change: after `undo`, or another change, it says so.
function M.adjust(given: Args)
  local spec = last and registry[last.name]
  local args: Args
  local line: string
  if last and spec and spec.adjust then
    local params = read_params(spec, last.args, spec.raw)
    local by_name: {string: contracts.AdjustParam} = {}
    for _, p in ipairs(spec.adjust) do
      by_name[p.name] = p
    end
    for key, value in pairs(read_params(spec, given, false)) do
      local p = by_name[key]
      if not p then
        error(string.format("`%s` has no parameter `%s`: it has %s", last.name, key, names_of(spec)), 0)
      end
      local why = check_param(last.name, p, value)
      if why then
        error(why, 0)
      end
      params[key] = value
    end
    args = write_params(spec, params)
    -- The range that the line had stays in front of the command.
    local at = last.line and last.line:find(last.name, 1, true)
    local prefix = at and last.line:sub(1, at - 1):gsub("^:", "") or ""
    line = ":" .. line_of(spec, last.name, args, prefix)
  else
    last = nil
  end
  local start = api.undo_adjust(last and last.before, line)
  if start.status == "old" then
    paw.notify("adjust works on the last change", "warn")
    return
  elseif start.status == "kept" then
    paw.notify("the last change was saved or named, so it cannot change: undo it, then run the command again", "warn")
    return
  elseif start.status == "other" or not last then
    if start.label then
      paw.notify("the last change (" .. start.label:gsub("^:", "") .. ") has nothing to adjust", "warn")
    else
      paw.notify("there is no change to adjust", "warn")
    end
    return
  end
  local ctx = util.merge(last.ctx as {string: util.Data}, {}) as Context
  local name, before, shown = last.name, last.before, last.line
  local ok, err = pcall(M.run, name, args, ctx) as (boolean, string)
  if not ok then
    api.undo_adjust_cancel()
    error(err, 0)
  end
  -- The adjusted command is the one that `.` repeats and the next `adjust` changes.
  last = {name = name, args = args, ctx = ctx, before = before, line = shown, about = about}
  local keys: {string} = {":"}
  for _, key in ipairs(paw.keymap.parse(line:sub(2))) do
    keys[#keys + 1] = key == "<" and "<lt>" or key
  end
  keys[#keys + 1] = "<CR>"
  paw.keymap.repeat_as(keys)
end

--- What `:adjust` suggests: the names of the parameters of the last
--- command, and the values of one.
local function complete_adjust(_: string, info: Info): {Candidate}
  local out: {Candidate} = {}
  local spec = last and registry[last.name]
  if not (last and spec and spec.adjust) then
    return out
  end
  local params = read_params(spec, last.args, spec.raw)
  local name = info.word:match("^([%a_][%w_]*)=")
  for _, p in ipairs(spec.adjust) do
    local now = params[p.name]
    if now == nil then
      now = p.default
    end
    if not name then
      out[#out + 1] = {text = p.name .. "=", desc = now ~= nil and "now " .. tostring(now) or nil}
    elseif p.name == name then
      local seen: {string: boolean} = {}
      local values: {string} = {now ~= nil and tostring(now) or ""}
      for _, v in ipairs(p.values or {}) do
        values[#values + 1] = v
      end
      for _, v in ipairs(values) do
        if v ~= "" and not seen[v] then
          seen[v] = true
          out[#out + 1] = {text = name .. "=" .. v}
        end
      end
    end
  end
  return out
end

-- Ranges ----------------------------------------------------------------------
--
-- A command line may start with a range, as in Vim: of time (`:5,8`, `%`,
-- `.`, `$`, `'a,'b`, `'<,'>`) and of tracks (`:t2,t4`, `t*`, `t/Drums/`).
-- `paw.ex` (runtime/lua/paw/ex.tl) reads them, runs its own commands on
-- them (`:5,8d`, `:%s/c4/d4/`, `:g/vel<20/d`), and gives the range to a
-- command defined with `range = true` as `ctx.range`: `{ bars = { first,
-- last }, from, to }` for time, `from` and `to` in beats of the song, the
-- end not included; `tracks` (ids) for tracks; `{ selection = true, region
-- }` for `'<,'>`, while `paw.keymap.selection()` returns that region. A
-- number right before a command without a range is its count: `:3snippet arp`.

--- Split a range from the start of a command line. Returns the range and
--- the rest. The range is nil when there is no range. When the range names
--- nothing, an error message replaces the rest.
function M.range(line: string): Range, string
  return paw.ex.range(line)
end

--- Functions that may take a whole line before it is read as a command:
--- `fn(line, ctx)` returns true when it ran it. A text buffer takes `:w`,
--- `:s/a/b/` and its ranges of lines this way (paw/textbuf.tl).
M.line_handlers = {}

--- Run a command line, as typed after `:`, with a range in front if it has one.
function M.exec(line: string, ctx?: Context): Result...
  for _, handler in ipairs(M.line_handlers) do
    if handler(line, ctx) then
      return
    end
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

local function item(text: string, desc?: string): Item
  return {text = text, desc = desc}
end

--- Files and directories that start with what is typed, directories ending
--- in `/`. `extensions` (a set) keeps only files with those endings.
local function files(word: string, extensions?: {string: boolean}): {Item}
  local home = os.getenv("HOME") or ""
  local typed_dir, stem = word:match("^(.*/)([^/]*)$")
  typed_dir, stem = typed_dir or "", stem or word
  -- `..` and `~` are folders to go to: they take a slash.
  if typed_dir == "" and (stem == ".." or stem == "~") then
    return {item(stem .. "/", "directory")}
  end
  -- Relative names are in the folder that `:cd` set, or beside the project.
  local here = paw.files and paw.files.here() or "."
  local dir = typed_dir == "" and here or typed_dir:gsub("^~/", home .. "/")
  if dir:sub(1, 1) ~= "/" then
    dir = here .. "/" .. dir
  end
  local ok, entries = pcall(api.read_dir, dir)
  if not ok then
    return {}
  end
  local out: {Item} = {}
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
  table.sort(
    out,
    function(a: Item, b: Item): boolean
      local da, db = a.desc ~= nil, b.desc ~= nil
      if da ~= db then
        return da
      end
      return a.text < b.text
    end
  )
  return out
end

local function set_of(list: {string}): {string: boolean}
  local out: {string: boolean} = {}
  for _, v in ipairs(list) do
    out[v] = true
  end
  return out
end

local function sorted(out: {Item}): {Item}
  table.sort(out, function(a: Item, b: Item): boolean return a.text < b.text end)
  return out
end

M.completers = {
  commands = function(): {Item}
    local out: {Item} = {}
    for _, spec in ipairs(M.list()) do
      out[#out + 1] = item(spec.name, spec.desc)
    end
    return out
  end,
  tracks = function(): {Item}
    local out: {Item} = {}
    for _, id in ipairs(api.track_list()) do
      out[#out + 1] = item(api.track_get(id).name, "track")
    end
    out[#out + 1] = item("master", "the master track")
    return out
  end,
  devices = function(): {Item}
    local out: {Item} = {}
    for _, info in ipairs(paw.device_types()) do
      out[#out + 1] = item(info.kind, info.name ~= info.kind and info.name or info.format)
    end
    return sorted(out)
  end,
  track_devices = function(): {Item}
    local out: {Item} = {}
    local track = paw.cursor.track()
    for _, device in ipairs(track and track:devices() or {}) do
      local d = device:get()
      out[#out + 1] = item(d.kind, d.name)
    end
    return out
  end,
  options = function(): {Item}
    local out: {Item} = {}
    for _, o in ipairs(options.list()) do
      out[#out + 1] = item(o.name, "now " .. options.show(options.opt[o.name]))
    end
    return out
  end,
  views = function(): {Item}
    local out: {Item} = {}
    for name, view in pairs(paw.ui.views) do
      if view.focusable ~= false then
        out[#out + 1] = item(name)
      end
    end
    return sorted(out)
  end,
  pickers = function(): {Item}
    local out: {Item} = {}
    for name, source in pairs(paw.pick.sources:entries()) do
      out[#out + 1] = item(name, source is contracts.PickInfo and source.desc or nil)
    end
    return sorted(out)
  end,
  files = function(word: string): {Item} return files(word) end,
  -- Sound files, and the files of the formats that read (paw/formats.tl).
  audio_files = function(word: string): {Item}
    local ext = set_of({"wav", "wave", "aif", "aiff", "flac", "mp3", "ogg", "oga"})
    for _, e in ipairs(paw.formats.extensions("import")) do
      ext[e] = true
    end
    return files(word, ext)
  end,
  -- What `import` takes: sound files and the files of the formats that read.
  importable = function(word: string): {Item} return M.completers.audio_files(word) end,
  -- What `export` writes: the files of the formats that write.
  exportable = function(word: string): {Item} return files(word, set_of(paw.formats.extensions("export"))) end,
  -- Projects, and the files of formats that hold whole projects.
  projects = function(word: string): {Item}
    local ext = set_of({"json"})
    for _, f in ipairs(paw.formats.list()) do
      if f.project then
        for _, e in ipairs(f.extensions) do
          ext[e] = true
        end
      end
    end
    return files(word, ext)
  end,
  dirs = function(word: string): {Item} return files(word, {}) end,
  -- What `edit` opens: projects, the files of the formats that read (as
  -- projects) and sound files.
  openable = function(word: string): {Item}
    local ext = set_of({"json", "wav", "wave", "aif", "aiff", "flac", "mp3", "ogg", "oga"})
    for _, e in ipairs(paw.formats.extensions("import")) do
      ext[e] = true
    end
    return files(word, ext)
  end,
}

--- Candidates from one completer (a name, a list of names by position, or
--- a function), as items.
local function candidates(spec: Spec, rest: string, info: Info): {Item}, boolean, boolean
  local how = spec.complete
  if how is {string} then
    how = how[info.index]
  end
  if how is string then
    local fn = M.completers[how]
    return fn and fn(info.word, info) or {}, true
  end
  if not (how is CompleteFn) then
    return {}
  end
  local ok, got = pcall(how, rest, info)
  if not ok or not (got is {string | Candidate}) then
    return {}
  end
  local list = got as Candidates
  local out: {Item} = {}
  for i, c in ipairs(list) do
    out[i] = c is Candidate and item(tostring(c.text or c[1]), c.desc) or item(tostring(c))
  end
  -- A completer that ranks what it gives (`ranked = true`) is taken in its order, all of it.
  return out, false, list.ranked
end

local function starts(text: string, stem: string): boolean
  return text:sub(1, #stem):lower() == stem:lower()
end

--- What could finish a command line: a list of `{ text, label, desc }` with
--- `text` the whole line it would become and `label` the part shown.
---   paw.commands.complete("track.co")   --> { { text = "track.color", label = "track.color", desc = ... } }
function M.complete(line: string): {Entry}
  -- Marks after `'`, tracks after `t/`, fields in a pattern.
  local special = paw.ex.complete_range(line) or paw.ex.complete_pattern(line)
  if special then
    return special
  end
  -- A range in front stays as it is; what follows it is completed.
  local range, after = M.range(line)
  if range and after ~= line then
    local head = line:sub(1, #line - #after)
    local out = M.complete(after)
    for _, entry in ipairs(out) do
      entry.text = head .. entry.text
    end
    return out
  end
  local out: {Entry} = {}
  local name, sep, rest = line:match("^(%S+)(%s+)(.*)$")
  if not name then
    -- The command's name: those that start with it, then those that hold it.
    local later: {Entry} = {}
    for _, spec in ipairs(M.list()) do
      local entry: Entry = {
        text = spec.name, label = spec.name, desc = spec.alias_of and "→ " .. spec.alias_of or spec.desc
      }
      if starts(spec.name, line) then
        out[#out + 1] = entry
      elseif line ~= "" and spec.name:lower():find(line:lower(), 1, true) then
        later[#later + 1] = entry
      end
    end
    for _, entry in ipairs(later) do
      out[#out + 1] = entry
    end
    return out
  end
  local spec = registry[name]
  if not spec or not spec.complete then
    return out
  end
  -- The words before the one being typed, and that word.
  local before, word = rest:match("^(.-)(%S*)$")
  local words_before: {string} = {}
  for w in before:gmatch("%S+") do
    words_before[#words_before + 1] = w
  end
  local info: Info = {word = word, index = #words_before + 1, words = words_before, line = line}
  local head = name .. sep
  local whole, part, inside: {Entry}, {Entry}, {Entry} = {}, {}, {}
  local list, by_word, ranked = candidates(spec, rest, info)
  for _, c in ipairs(list) do
    local text = c.text
    if ranked or (not by_word and starts(text, rest)) then
      whole[#whole + 1] = {text = head .. text, label = text, desc = c.desc}
    else
      -- A name with a space in it is quoted, unless the command takes its
      -- text whole.
      local shown = (not spec.raw and text:find(" ")) and '"' .. text .. '"' or text
      local entry: Entry = {text = head .. before .. shown, label = shown, desc = c.desc}
      if starts(text, word) then
        part[#part + 1] = entry
      elseif word ~= "" and text:lower():find(word:lower(), 1, true) then
        inside[#inside + 1] = entry
      end
    end
  end
  -- What starts with the typed text, then what only holds it.
  for _, entries in ipairs({whole, part, inside}) do
    for _, entry in ipairs(entries) do
      out[#out + 1] = entry
    end
  end
  return out
end

M.define(
  "adjust",
  function(ctx: Context): Result M.adjust(ctx.args) end,
  {
    desc = "Do the last command again with other parameters, in place of its undo step: `:adjust grid=1/8`, `:adjust 7`",
    label = "Adjust",
    complete = complete_adjust,
  }
)

return M
