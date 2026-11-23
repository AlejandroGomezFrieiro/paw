-- Publish/subscribe. The kernel reports project changes here, and extensions
-- can emit and listen for events of their own.
--
-- A handler name is an exact event (`track.added`), a family (`track.*`), or
-- `*` for everything. Handlers receive `(payload, event_name)`.
--
-- In Teal, an event is a descriptor: its name and the type of its payload.
-- paw.events.kernel has one for each event of the kernel; a module makes
-- one for its own events with `paw.events.event`:
--
--   local kernel = require("paw.events.kernel")
--   paw.on(kernel.project_saved, function(p: kernel.Saved) print(p.path) end)
--
-- Lua gives the name as text, and Teal does too for `paw.emit`.
--
-- Each event has one owner: the module that sends it exports its
-- descriptor, and the other modules use that one. `paw.events.event`
-- declares the name. A subscription by text to a name or a family
-- (`undo.*`) that matches no declared event is a typo or an event that
-- nobody sends: paw writes it once in the log, and `:checkhealth events`
-- lists it. tools/apidoc.lua writes the
-- rows of docs/reference/events.md from the descriptors that the modules
-- export.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local registry = require("paw.registry")

--- What an event carries: a table that this module passes on and never reads.
local record Payload
end

--- A handler as it is kept: it may answer `false, reason` to refuse.
local type Listener = function(Payload, string): boolean, string

--- A handler of `paw.on`, by its handle.
local record Handler
  id: integer
  fn: function(Payload, string)
  once: boolean
  pattern: string
end

--- What `paw.on` takes besides the event and the function.
local record OnOptions
  once: boolean
end

local record M
  type Handler = Handler
  type OnOptions = OnOptions
  type Payload = Payload
  --- An event by its name, with the type `P` of its payload (`paw.events.event`).
  record Event<P>
    name: string
  end
  --- The event `startup`: the runtime, the extensions and the configuration
  --- loaded.
  startup: Event<Payload>
  --- The event `exit`: the program will stop.
  exit: Event<Payload>
  --- Every handler by its handle (as text), with the extension that added
  --- it. `paw.on` puts one, and `paw.off` removes it.
  hooks: registry.Registry<Handler>
end

local type Named = function(string, Listener, Payload, string): boolean, string
local type Try = function(Named, string, Listener, Payload, string): boolean, boolean, string

-- What this module reads of `paw`, which paw/init.lua makes. A module of the
-- runtime in Teal does not see the global `paw`: runtime/types/paw.d.tl
-- declares it from these modules.
-- `paw.try` and `paw.limit.named` as this module calls them.
local record Limit
  named: Named
end
-- `paw.api.log` and `paw.api.project_get("edits")`: paw/api.d.tl requires
-- this module, so it cannot be required here.
local record Api
  log: function(string)
  project_get: function(string): integer
end
local record Paw
  try: Try
  limit: Limit
  api: Api
end
local paw = (_G as {string: Paw}).paw

-- The handlers of `M.hooks` by pattern, in the order they came: what
-- `M.emit` reads.
local handlers: {string: {Handler}} = {}
M.hooks = registry.new(
  "hooks",
  "hooks",
  {
    label = function(_: string, h: Handler): string return h.pattern end,
    changed = function(_: string, h: Handler, old: Handler)
      if old then
        local list = handlers[old.pattern] or {}
        for i = #list, 1, -1 do
          if list[i] == old then
            table.remove(list, i)
          end
        end
      end
      if h then
        handlers[h.pattern] = handlers[h.pattern] or {}
        table.insert(handlers[h.pattern], h)
      end
    end,
  }
)
local next_id = 0
-- The events sent since paw started. `M.stamp` changes when this does.
local sent = 0
-- `M.stamp`: the number that it gives, and the edits of the project and the
-- events sent when that number last changed. The number only goes up.
local stamp, stamp_edits, stamp_sent = 0, -1, -1

-- The names of the events that a descriptor declared (`M.event`, and the
-- kernel's descriptors in paw/events/kernel.tl). A name is never removed.
local declared: {string: boolean} = {}
-- The names that `M.on` got as text and that no module declared when they
-- were checked: each one is in the log one time.
local logged: {string: boolean} = {}
-- The names that `M.on` got as text before `M.check_names` ran. At that
-- time, not all the modules that declare names are loaded.
local early: {string} = {}
local checking = false

--- The descriptor of an event whose payload is a `P`: Teal checks the
--- handlers that `paw.on` is given for it, and what `paw.emit` sends. It
--- also declares the name, so `paw.on` with this name as text is not a typo.
---   local filled: paw.events.Event<Filled> = paw.events.event("fill.done")
function M.event<P>(name: string): M.Event<P>
  declared[name] = true
  return {name = name}
end

M.startup = M.event("startup")
M.exit = M.event("exit")

-- The family of an event, as `M.emit` finds the handlers of a pattern: the
-- name before its last dot (`clip` of `clip.changed`). nil for a name
-- without a dot.
local function family_of(name: string): string
  return name:match("^(.-)%.[^.]*$")
end

-- Whether `M.emit` can call a handler of `pattern` for a declared event.
-- `*` gets every event. A family (`track.*`) needs one declared event of
-- that family. Any other text is a name, which must be declared itself:
-- this includes text with a `*` in another place (`undo*`), which
-- `M.emit` never matches.
local function matches_declared(pattern: string): boolean
  if pattern == "*" or declared[pattern] then
    return true
  end
  local family = pattern:match("^(.-)%.%*$")
  if not family then
    return false
  end
  for name in pairs(declared) do
    if family_of(name) == family then
      return true
    end
  end
  return false
end

-- Log a name or a pattern that `M.on` got as text when it matches no
-- declared event: one line for each text.
local function check_name(name: string)
  if logged[name] or matches_declared(name) then
    return
  end
  logged[name] = true
  paw.api.log("paw.on: `" .. name .. "` matches no event that a module declares: a typo, or an event that nobody sends")
end

--- Check the names of events that `paw.on` got as text. paw calls it when
--- it has started: the runtime, the extensions and the configuration have
--- declared their events then. After that, `paw.on` checks each name as it
--- gets it.
function M.check_names()
  checking = true
  for _, name in ipairs(early) do
    check_name(name)
  end
  early = {}
end

--- The names and patterns (`undo.*`) of events that `paw.on` got as text
--- and that match no event that a part of paw declares, sorted.
--- `:checkhealth events` lists them.
function M.undeclared(): {string}
  local out: {string} = {}
  for name in pairs(logged) do
    -- An extension that loaded later can declare a name after its check.
    if not matches_declared(name) then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

--- The descriptor of a pattern of events (`track.*`, `*`): its handlers
--- read nothing of the payload without a cast.
function M.pattern(pattern: string): M.Event<Payload>
  return {name = pattern}
end

-- The name of an event as Lua gives it (text) or Teal does (a descriptor).
local function name_of<P>(event: string | M.Event<P>): string
  if event is string then
    return event
  end
  return event.name
end

--- Listen for an event: in Lua its name or a pattern as text, in Teal its
--- descriptor (`paw.events.event`). Returns a handle for `paw.off`. A name
--- or a pattern as text that matches no event that a part of paw declares
--- goes in the log (`:checkhealth events`).
function M.on<P>(event: M.Event<P>, fn: function(P, string), opts?: OnOptions): integer
  local given = event as string | M.Event<P>
  local pattern = name_of(given)
  assert(pattern is string and fn is function, "usage: paw.on(event, function)")
  -- A descriptor declared its name. A name as text can be a typo: check it
  -- now, or at the end of startup when the modules declared their names.
  if given is string then
    if checking then
      check_name(pattern)
    else
      early[#early + 1] = pattern
    end
  end
  next_id = next_id + 1
  M.hooks:put(
    tostring(next_id),
    {id = next_id, fn = fn as function(Payload, string), once = opts and opts.once, pattern = pattern}
  )
  return next_id
end

--- Listen for an event once: the handler is removed after its first call.
function M.once<P>(event: M.Event<P>, fn: function(P, string)): integer
  return M.on(event, fn, {once = true})
end

--- Stop a listener: `id` is the value that `paw.on` or `paw.once` returned.
function M.off(id: integer)
  if id ~= nil then
    M.hooks:remove(tostring(id))
  end
end

--- True if a handler listens for `name` by its name or its family (not
--- `*`). Use it for events that are expensive to make.
function M.listened(name: string): boolean
  local family = family_of(name)
  return (handlers[name] and #handlers[name] > 0)
    or (family and handlers[family .. ".*"] and #handlers[family .. ".*"] > 0)
    or false
end

-- The first refusal: a handler that returned false, and why.
local refused: boolean
local reason: string

local function run(list: {Handler}, name: string, payload: Payload)
  if not list then
    return
  end
  -- Copy, so handlers may add or remove handlers while running.
  local copy: {Handler} = {}
  for i = 1, #list do
    copy[i] = list[i]
  end
  for _, h in ipairs(copy) do
    if h.once then
      M.off(h.id)
    end
    local ok, answer, why = paw.try(paw.limit.named, "a handler of `" .. name .. "`", h.fn as Listener, payload, name)
    if ok and answer == false and not refused then
      refused, reason = true, why
    end
  end
end

--- The handle that the next `paw.on` gives. A handler made later has this
--- handle or a larger one.
function M.next_handle(): integer
  return next_id + 1
end

--- Run the handlers that listen by `pattern` (a name, `family.*` or `*`)
--- and have the handle `from` or a larger one, with the event `name`, as
--- `emit` runs them. An emit takes its list of handlers when it starts:
--- paw/lazy.tl gives the event that loaded an extension to the handlers
--- that the extension made.
function M.emit_since(from: integer, pattern: string, name: string, payload: Payload)
  local list: {Handler} = {}
  for _, h in ipairs(handlers[pattern] or {}) do
    if h.id >= from then
      list[#list + 1] = h
    end
  end
  run(list, name, payload)
end

--- Call each handler for `event` (a name, or a descriptor). paw reports a handler that fails, and goes
--- to the next. Returns true, or false and the reason when a handler
--- returned `false, reason`. So a handler refuses the request of an event
--- (`edit.before`, `project.saving`, `key.pre`).
function M.emit<P>(event: string | M.Event<P>, payload?: P): boolean, string
  sent = sent + 1
  local name = name_of(event)
  local data: Payload = payload as Payload or {}
  local outer, outer_reason = refused, reason
  refused, reason = nil, nil
  run(handlers[name], name, data)
  local family = family_of(name)
  if family then
    run(handlers[family .. ".*"], name, data)
  end
  run(handlers["*"], name, data)
  local no, why = refused, reason
  refused, reason = outer, outer_reason
  if no then
    return false, why
  end
  return true
end

--- How many events paw has sent since it started. A number that is the
--- same as before means that no event came in between.
function M.emitted(): integer
  return sent
end

--- A number that changes when the project changes or paw sends an event.
--- A value that is read from the project, or that an event can change, can
--- be kept while this number is the same. An edit counts at once, before
--- its event is sent at the end of the turn.
function M.stamp(): integer
  local edits = paw.api.project_get("edits")
  if edits ~= stamp_edits or sent ~= stamp_sent then
    stamp, stamp_edits, stamp_sent = stamp + 1, edits, sent
  end
  return stamp
end

return M
