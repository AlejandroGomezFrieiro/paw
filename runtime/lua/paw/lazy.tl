-- Extensions that wait for their first use, as lazy.nvim does.
--
-- `paw.ext.use(name, spec)` reads the triggers of an extension from its
-- manifest and from `spec` (the user's, which win field by field):
--
--   cmd    commands       { "undotree", { "checkpoint", desc = "..." }, "notation.*" }
--   keys   keys           { { "<leader>pu", desc = "Undo tree", mode = "n", view = "arrange" } }
--   event  events         { "transport.play" }
--   kind   keys of        { "drums", { registry = "pickers", key = "film" } }
--          registries     (a name alone: a kind of part or of clip)
--   view   views          { "undotree" }
--   lazy   false loads it now, true waits even with no trigger
--
-- An extension with a trigger waits, unless `lazy` is false. While it
-- waits, each trigger is a stub in the registry of its kind, owned by the
-- extension: a command in `paw.commands.specs`, a key in the keymap with
-- `ext` set, a view in `paw.ui.views`, a hook. The lists of commands and
-- keys, completion and which-key show the stubs with their descriptions.
-- The first use takes all the stubs of the extension away, loads it, and
-- then runs what was typed again: the command line, or the keys with
-- their count and register, inside the same command (one undo step).
-- An extension that fails to load gets its stubs back, and the message of
-- the failure is the only one.
--
-- A kind loads its extension when a part of paw asks its registry for the
-- key (`registry.missing`): the clips of a project that opens ask for
-- their kinds, and a part header asks for the kind of its part. Before
-- that, the project plays as it is saved: a part keeps its kind in
-- `meta.kind`, and a clip of a kind keeps what the kind compiled.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local registry = require("paw.registry")
local type CommandsModule = require("paw.commands")
local type KeymapModule = require("paw.keymap")

--- `paw.ext` (paw/ext.lua, in Lua), the part of it that this module calls.
local record Ext
  loaded: {string: contracts.ExtEntry}
  load: function(path: string, why?: string): contracts.ExtEntry
  manifest: function(path: string, name: string): contracts.Manifest, string
  name_of: function(path: string): string
  bundled_dir: function(): string
  missing_needs: function(manifest: contracts.Manifest): string
end

--- `paw.ex` (paw/ex.tl, which requires paw.commands): the range at the
--- start of a command line, and the text after it.
local record Ex
  range: function(line: string): contracts.CommandRange, string, string
end

local record Ui
  views: registry.Registry<contracts.View>
end

local record Paw is partial.Paw
  commands: CommandsModule
  keymap: KeymapModule
  ex: Ex
  ui: Ui
end
local paw = (_G as {string: Paw}).paw

--- The triggers of one extension, each as a list.
local record Triggers
  cmd: {contracts.CmdTrigger}
  keys: {contracts.KeyTrigger}
  event: {string}
  kind: {contracts.KindTrigger}
  view: {string}
end

--- An extension that waits for a trigger: where it is, its manifest, its
--- triggers, and the handles of the hooks that wait for its events.
local record Waiting
  name: string
  path: string
  manifest: contracts.Manifest
  triggers: Triggers
  hooks: {integer}
  --- One that the program was built with (`paw.ext.load_packaged`).
  packaged: boolean
  --- True after a load that failed: a kind no longer loads it, so that
  --- each frame does not try again. A command or a key still does.
  failed: boolean
end

local record M
  type Waiting = Waiting
  type Triggers = Triggers
  --- The extensions that wait for a trigger, by name.
  waiting: {string: Waiting}
  load: function(name: string, why: string): contracts.ExtEntry
end
M.waiting = {}

-- Triggers ---------------------------------------------------------------------

--- One value or a list as a list; nil as an empty list.
local function list_of<T>(value: T | {T}): {T}
  if value == nil then
    return {}
  end
  if value is {T} then
    return value
  end
  return {value as T}
end

--- A command trigger as a record, from its name alone or from a record.
local function as_cmd(item: string | contracts.CmdTrigger): contracts.CmdTrigger
  if item is string then
    return {item}
  end
  return item
end

local function as_key(item: string | contracts.KeyTrigger): contracts.KeyTrigger
  if item is string then
    return {item}
  end
  return item
end

--- The triggers of `manifest`, with each field that `spec` gives in place
--- of the manifest's.
local function triggers_of(manifest: contracts.Manifest, spec: contracts.Triggers): Triggers
  local function field<T>(get: function(contracts.Triggers): T): T
    local own = get(spec)
    if own ~= nil then
      return own
    end
    return get(manifest)
  end
  local out: Triggers = {cmd = {}, keys = {}}
  local cmd = field(function(t: contracts.Triggers): string | {string | contracts.CmdTrigger} return t.cmd end)
  if cmd is string then
    out.cmd[1] = {cmd}
  elseif cmd then
    for _, item in ipairs(cmd) do
      out.cmd[#out.cmd + 1] = as_cmd(item)
    end
  end
  local keys = field(function(t: contracts.Triggers): string | {string | contracts.KeyTrigger} return t.keys end)
  if keys is string then
    out.keys[1] = {keys}
  elseif keys then
    for _, item in ipairs(keys) do
      out.keys[#out.keys + 1] = as_key(item)
    end
  end
  out.event = list_of(field(function(t: contracts.Triggers): string | {string} return t.event end))
  -- A kind as a name alone has no registry: a kind of part or of clip.
  out.kind = {}
  local kind = field(function(t: contracts.Triggers): string | {string | contracts.KindTrigger} return t.kind end)
  if kind is string then
    out.kind[1] = {key = kind}
  elseif kind then
    for _, item in ipairs(kind) do
      out.kind[#out.kind + 1] = item is string and {key = item} or item as contracts.KindTrigger
    end
  end
  out.view = list_of(field(function(t: contracts.Triggers): string | {string} return t.view end))
  return out
end

local function any_trigger(t: Triggers): boolean
  return #t.cmd + #t.keys + #t.event + #t.kind + #t.view > 0
end

--- The triggers of a waiting extension in words, for `:extensions`,
--- `:help` and the picker: `{ ":undotree", "<leader>pu", "view undotree" }`.
--- Nil for one that does not wait.
function M.describe(name: string): {string}
  local w = M.waiting[name]
  if not w then
    return nil
  end
  local t = w.triggers
  local out: {string} = {}
  for _, c in ipairs(t.cmd) do
    out[#out + 1] = ":" .. c[1]
  end
  for _, k in ipairs(t.keys) do
    out[#out + 1] = k[1]
  end
  for _, e in ipairs(t.event) do
    out[#out + 1] = "event " .. e
  end
  for _, k in ipairs(t.kind) do
    out[#out + 1] = "kind " .. (k.registry and k.registry .. " " or "") .. k.key
  end
  for _, v in ipairs(t.view) do
    out[#out + 1] = "view " .. v
  end
  if #out == 0 then
    out[1] = ":ext.load " .. name
  end
  return out
end

-- Stubs ------------------------------------------------------------------------

-- The commands of the stubs, by name -> the extension; the prefixes of the
-- commands (`notation.`), by prefix -> the extension.
local stub_commands: {string: string} = {}
local stub_prefixes: {string: string} = {}
-- The keys of registries that load an extension: "<registry>\0<key>" -> the extension.
local kind_index: {string: string} = {}

--- The keys of `kind_index` of a kind trigger. A name alone is a kind of
--- part or of clip.
local function index_keys(k: contracts.KindTrigger): {string}
  if k.registry then
    return {k.registry .. "\0" .. k.key}
  end
  return {"part_kinds\0" .. k.key, "clip_kinds\0" .. k.key}
end

local load_waiting: function(name: string, why: string): contracts.ExtEntry

--- The modes of a key trigger: `mode`, or normal mode.
local function modes_of(k: contracts.KeyTrigger): {string}
  local modes = list_of(k.mode)
  if #modes == 0 then
    return {"n"}
  end
  return modes
end

--- The keys that the stub of `key` types again after the load: the
--- register and the count that came before it, then its own keys.
local function typed_again(key: string, ctx: contracts.KeyContext): string
  local prefix = ""
  if ctx and ctx.register then
    prefix = '"' .. ctx.register
  end
  if ctx and ctx.count then
    prefix = prefix .. tostring(ctx.count)
  end
  return prefix .. key
end

--- Put the stubs of the extension `w` in the registries, each owned by it.
local function install(w: Waiting)
  local name = w.name
  local description = w.manifest.description
  for _, c in ipairs(w.triggers.cmd) do
    local cname = c[1]
    if cname:sub(-1) == "*" then
      stub_prefixes[cname:sub(1, -2)] = name
    else
      stub_commands[cname] = name
      paw.commands.specs:put(
        cname,
        {
          name = cname,
          desc = c.desc or description or ("Load " .. name),
          ext = name,
          range = true,
          -- Run from Lua (`paw.commands.run`) with its arguments: the
          -- command line comes through the line handler below.
          run = function(ctx: contracts.CommandContext): contracts.CommandResult
            local entry = load_waiting(name, ":" .. cname)
            if not (entry and entry.ok) then
              return
            end
            if paw.commands.specs:get(cname) == nil then
              error(name .. " loaded, and it has no command `" .. cname .. "`", 0)
            end
            return paw.commands.run(cname, ctx.args, ctx)
          end,
        },
        name
      )
    end
  end
  for _, k in ipairs(w.triggers.keys) do
    local lhs = k[1]
    paw.keymap.set(
      lhs,
      function(ctx: contracts.KeyContext)
        local entry = load_waiting(name, lhs)
        if entry and entry.ok then
          paw.keymap.normal(typed_again(lhs, ctx))
        end
      end,
      {mode = modes_of(k) as {KeymapModule.Mode}, view = k.view, desc = k.desc or description, ext = name}
    )
  end
  for _, view in ipairs(w.triggers.view) do
    paw.ui.views:put(
      view,
      {
        name = view,
        title = view,
        render = function(_: contracts.View, buf?: contracts.Buf)
          if buf then
            buf:text(1, 0, name .. " loads", "Dim")
          end
          -- Not while the frame draws: on the next turn of the loop.
          api.timer_start(
            0,
            false,
            function()
              if M.waiting[name] then
                load_waiting(name, "view " .. view)
                api.ui_redraw()
              end
            end
          )
        end,
      },
      name
    )
  end
  for _, k in ipairs(w.triggers.kind) do
    for _, at in ipairs(index_keys(k)) do
      kind_index[at] = name
    end
  end
  w.hooks = {}
  for _, event in ipairs(w.triggers.event) do
    -- The handlers of the extension for this event come after the load,
    -- when the emit that runs this one has its list of handlers already:
    -- they get this event here. A handler of another pattern (a family,
    -- `*`) is in a list that the emit takes later, and gets it from there.
    w.hooks[#w.hooks + 1] = events.on(
      events.pattern(event),
      function(payload: events.Payload, sent: string)
        local from = events.next_handle()
        load_waiting(name, "event " .. sent)
        events.emit_since(from, event, sent, payload)
      end
    )
  end
end

--- Take the stubs of the extension `w` away.
local function take_away(w: Waiting)
  local name = w.name
  for _, c in ipairs(w.triggers.cmd) do
    local cname = c[1]
    stub_commands[cname] = nil
    stub_prefixes[cname:gsub("%*$", "")] = nil
  end
  for _, k in ipairs(w.triggers.kind) do
    for _, at in ipairs(index_keys(k)) do
      kind_index[at] = nil
    end
  end
  -- The entries of the registries that it owns now are its stubs.
  paw.commands.specs:unload(name)
  paw.ui.views:unload(name)
  for _, k in ipairs(w.triggers.keys) do
    pcall(paw.keymap.del, k[1], {mode = modes_of(k) as {KeymapModule.Mode}, view = k.view})
  end
  for _, id in ipairs(w.hooks or {}) do
    events.off(id)
  end
  w.hooks = {}
end

-- Loading ----------------------------------------------------------------------

--- Load the waiting extension `name` now: its stubs go, and paw loads it.
--- `why` says what loaded it (`:undotree`, `<leader>pu`). Failed, it
--- waits again with its stubs. Gives the entry of `paw.ext.loaded`.
load_waiting = function(name: string, why: string): contracts.ExtEntry
  local w = M.waiting[name]
  local ext = paw.ext as Ext
  if not w then
    return ext.loaded[name]
  end
  local entry = ext.load(w.path, why)
  if w.packaged then
    entry.packaged = true
  end
  if not entry.ok and not M.waiting[name] then
    w.failed = true
    M.waiting[name] = w
    install(w)
  end
  return entry
end

M.load = load_waiting

--- Stop waiting for `name`: its stubs go. paw/ext.lua calls it when the
--- extension loads by any other way (`:ext.load`, a requirement), and to
--- unload one that waits. Gives true when it waited.
function M.forget(name: string): boolean
  local w = M.waiting[name]
  if not w then
    return false
  end
  M.waiting[name] = nil
  take_away(w)
  return true
end

-- The command line: a command of a stub, or under a prefix of one, loads its
-- extension, and the whole line (with its range) runs again.
table.insert(
  paw.commands.line_handlers,
  1,
  function(line: string, ctx: contracts.CommandContext): boolean
    if next(stub_commands) == nil and next(stub_prefixes) == nil then
      return false
    end
    local _, rest = paw.ex.range(line)
    local cname = rest and rest:match("^%s*:?([^%s!]+!?)")
    if not cname then
      return false
    end
    local name = stub_commands[cname]
    if not name then
      for prefix, owner in pairs(stub_prefixes) do
        if cname:sub(1, #prefix) == prefix then
          name = owner
        end
      end
    end
    if not name then
      return false
    end
    local entry = load_waiting(name, ":" .. cname)
    if entry and entry.ok then
      paw.commands.exec(line, ctx)
    end
    return true
  end
)

--- Loads the extension that waits for `key` of `reg` (its `kind`
--- trigger), and gives true when it loaded, so that `reg:get(key)` gives
--- the entry that the extension put. The kind of a part loads its
--- extension when the part header asks for it, and the kind of a clip
--- loads its extension when the project opens.
registry.missing = function(reg: registry.Owned, key: string): boolean
  local name = kind_index[reg.kind .. "\0" .. key]
  if not name or M.waiting[name].failed then
    return false
  end
  -- The words of `describe`: a kind of part or of clip by its name alone.
  local plain = reg.kind == "part_kinds" or reg.kind == "clip_kinds"
  load_waiting(name, "kind " .. (plain and "" or reg.kind .. " ") .. key)
  return true
end

--- True when an extension waits for a key of `reg`.
registry.waiting = function(reg: registry.Owned): boolean
  local prefix = reg.kind .. "\0"
  for at in pairs(kind_index) do
    if at:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

-- Use ---------------------------------------------------------------------------

--- Where the extension `which` is: a path as it is, or the name of a
--- bundled extension.
local function path_of(which: string): string
  if which:find("/", 1, true) then
    return which
  end
  local dir = (paw.ext as Ext).bundled_dir()
  return dir and dir .. "/" .. which or which
end

--- Use an extension as lazy.nvim does: it loads on its first command, key,
--- event, kind or view (`spec`, then its manifest), or now when it has no
--- trigger or `spec.lazy` is false. `which` is a path or the name of a
--- bundled extension. `why` says what loads it now ("at start"). Gives the
--- entry of `paw.ext.loaded` when it loaded, or nil when it waits.
function M.use(which: string, spec?: contracts.Triggers, why?: string): contracts.ExtEntry
  local ext = paw.ext as Ext
  local path = path_of(which)
  local name = ext.name_of(path)
  spec = spec or {}
  local known = ext.loaded[name]
  if known and known.ok then
    return known
  end
  local manifest = ext.manifest(path, name)
  -- A manifest that does not read, or a build that lacks what it needs,
  -- fails now, with its message.
  if not manifest or ext.missing_needs(manifest) then
    M.forget(name)
    return ext.load(path, why)
  end
  local triggers = triggers_of(manifest, spec)
  local lazy = spec.lazy
  if lazy == nil then
    lazy = manifest.lazy
  end
  if lazy == nil then
    lazy = any_trigger(triggers)
  end
  M.forget(name)
  if not lazy then
    return ext.load(path, why)
  end
  local w: Waiting = {name = name, path = path, manifest = manifest, triggers = triggers}
  M.waiting[name] = w
  install(w)
  return nil
end

--- The waiting extensions, sorted by name.
function M.list(): {Waiting}
  local out: {Waiting} = {}
  for _, w in pairs(M.waiting) do
    out[#out + 1] = w
  end
  table.sort(out, function(a: Waiting, b: Waiting): boolean return a.name < b.name end)
  return out
end

return M
