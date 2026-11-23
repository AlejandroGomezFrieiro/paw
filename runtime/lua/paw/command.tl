-- The command registry: each command by its name, with the extension that
-- defined it. `paw.command(name, fn, opts)` defines one, and every module
-- can do so: this module is in a low layer (tools/layers.txt), and reads
-- no module above it.
--
-- To run commands and command lines, see paw/commands.tl (the input
-- layer). That module gives `run` and `exec` to this one when it loads, so
-- that a lower module can run a command too (a callback, as
-- .claude/skills/paw-code/layers.md tells).
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local type contracts = require("paw.contracts")
local registry = require("paw.registry")

-- The types that a command's function and options have are contracts
-- (paw/contracts.tl), so that `paw.command` is typed for the modules in
-- Lua as well.
local type Context = contracts.CommandContext
local type Result = contracts.CommandResult

--- A candidate of completion: `text`, and what it is (`desc`).
local record Item
  text: string
  desc: string
end

local type Completer = function(string, ?contracts.CompleteInfo): {Item}

--- A command, as `paw.command` makes it. `ex` marks a command of Ex,
--- which takes its text whole after a range, and `items` one that also
--- works on the matches that `:g` hands it (paw/ex.tl).
local record Spec
  name: string
  run: function(Context): Result
  desc: string
  raw: boolean
  complete: contracts.Complete
  label: string
  range: boolean
  alias_of: string
  ext: string
  ex: boolean
  items: boolean
  adjust: {contracts.AdjustParam}
end

--- A completion of a command line: the whole line it makes (`text`), the
--- part shown (`label`), and what it is.
local record Entry
  text: string
  label: string
  desc: string
end

local record M
  type Arg = contracts.CommandArg
  type Args = contracts.CommandArgs
  type Range = contracts.CommandRange
  type Context = Context
  type Result = Result
  type Item = Item
  type Info = contracts.CompleteInfo
  type Candidate = contracts.CompleteCandidate
  type Completer = Completer
  type Spec = Spec
  type Options = contracts.CommandOptions
  type Entry = Entry

  --- The commands by name, with the extension that defined each one.
  --- `paw.command` and `alias` put one, and `specs:remove(name)` takes
  --- one away.
  specs: registry.Registry<Spec>
  --- The completers of arguments by name, with the extension that added
  --- each one. `paw.commands.completers:put(name, fn)` adds one, and
  --- paw/commands.tl adds those of paw.
  completers: registry.Registry<Completer>
  --- Run a command by name, and run a command line as typed after `:`.
  --- paw/commands.tl sets them when it loads: `paw.commands.run` and
  --- `paw.commands.exec`.
  run: function(name: string, args?: M.Args, ctx?: Context): Result
  exec: function(line: string, ctx?: Context): Result...

  --- `paw.command(name, fn, opts)`: `define`, where `fn` need not give
  --- a result (contracts.Command).
  metamethod __call: function<C is Context>(self: M, name: string, run: function(C), opts?: M.Options)
end

-- The commands of `M.specs` sorted by name, or nil when it changed since
-- (`M.list`). Completion asks for the list after each typed character.
local sorted: {Spec}
M.specs = registry.new(
  "commands",
  "commands",
  {
    label = function(name: string): string return ":" .. name end,
    changed = function() sorted = nil end,
  }
)
local specs = M.specs
M.completers = registry.new("completers", "completers")

--- The extension that paw loads now, or whose code registers these commands
--- and keys later. `:help` goes to its page for them, and an unload removes them.
function M.owner(): string
  return registry.owner and registry.owner()
end

--- Define or replace a command.
---   paw.command("track.mute", function(ctx) ... end, { desc = "Mute the track" })
--- The handler gets `ctx` with `ctx.args` (positional and named arguments)
--- and `ctx.count` (the number typed before a key mapping, or nil). With
--- `opts.raw`, the command line gives its text as one string in
--- `ctx.args[1]`. With `opts.range`, it accepts a range of bars before it
--- (`:5,8name`) as `ctx.range`. See Ranges below.
function M.define<C is Context>(name: string, run: function(C): (Result), opts?: M.Options)
  assert(name is string and run is function, "usage: paw.command(name, function, opts)")
  opts = opts or {}
  specs:put(
    name,
    {
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
  )
end

--- Make `alias` another name for `target`.
function M.alias(alias: string, target: string)
  local spec = assert(specs:get(target), "no command " .. target)
  specs:put(
    alias,
    {
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
  )
end

--- The command of a name: `{ name, run, desc, ... }` as `paw.command` made it, or nil.
function M.get(name: string): Spec
  return specs:get(name)
end

--- Every command, sorted by name.
function M.list(): {Spec}
  if not sorted then
    sorted = {}
    for _, spec in pairs(specs:entries()) do
      sorted[#sorted + 1] = spec
    end
    table.sort(sorted, function(a: Spec, b: Spec): boolean return a.name < b.name end)
  end
  -- A copy: the caller may change its list.
  local out: {Spec} = {}
  for i = 1, #sorted do
    out[i] = sorted[i]
  end
  return out
end

-- `paw.command(name, fn, opts)` is `define`.
setmetatable(
  M,
  {
    __call = function<C is Context>(_: M, name: string, run: function(C), opts?: M.Options)
      M.define(name, run as function(C): (Result), opts)
    end,
  } as metatable<M>
)

return M
