-- Publish/subscribe. The kernel reports project changes here, and extensions
-- can emit and listen for events of their own.
--
-- A handler name is an exact event (`track.added`), a family (`track.*`), or
-- `*` for everything. Handlers receive `(payload, event_name)`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.

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
local record Paw
  try: Try
  limit: Limit
end
local paw = (_G as {string:Paw}).paw

local handlers: {string:{Handler}} = {} -- pattern -> list of { id, fn, once }
local next_id = 0

--- Listen for an event. Returns a handle for `paw.off`.
function M.on<P>(pattern: string, fn: function(P, string), opts?: OnOptions): integer
  assert(pattern is string and fn is function, "usage: paw.on(event, function)")
  next_id = next_id + 1
  handlers[pattern] = handlers[pattern] or {}
  table.insert(handlers[pattern], { id = next_id, fn = fn as function(Payload, string), once = opts and opts.once, pattern = pattern })
  return next_id
end

--- Listen for an event once: the handler is removed after its first call.
function M.once<P>(pattern: string, fn: function(P, string)): integer
  return M.on(pattern, fn, { once = true })
end

--- Stop a listener: `id` is the value that `paw.on` or `paw.once` returned.
function M.off(id: integer)
  for _, list in pairs(handlers) do
    for i = #list, 1, -1 do
      if list[i].id == id then table.remove(list, i) end
    end
  end
end

--- Every handler, by its handle: `{ pattern, fn }`.
function M.handlers(): {integer:Handler}
  local out: {integer:Handler} = {}
  for _, list in pairs(handlers) do
    for _, h in ipairs(list) do out[h.id] = h end
  end
  return out
end

--- True if a handler listens for `name` by its name or its family (not
--- `*`). Use it for events that are expensive to make.
function M.listened(name: string): boolean
  local family = name:match("^(.-)%.[^.]*$")
  return (handlers[name] and #handlers[name] > 0) or (family and handlers[family .. ".*"] and #handlers[family .. ".*"] > 0) or false
end

-- The first refusal: a handler that returned false, and why.
local refused: boolean
local reason: string

local function run(list: {Handler}, name: string, payload: Payload)
  if not list then return end
  -- Copy, so handlers may add or remove handlers while running.
  local copy: {Handler} = {}
  for i = 1, #list do copy[i] = list[i] end
  for _, h in ipairs(copy) do
    if h.once then M.off(h.id) end
    local ok, answer, why = paw.try(paw.limit.named, "a handler of `" .. name .. "`", h.fn as Listener, payload, name)
    if ok and answer == false and not refused then refused, reason = true, why end
  end
end

--- Call each handler for `name`. paw reports a handler that fails, and goes
--- to the next. Returns true, or false and the reason when a handler
--- returned `false, reason`. So a handler refuses the request of an event
--- (`edit.before`, `project.saving`, `key.pre`).
function M.emit<P>(name: string, payload?: P): boolean, string
  local data: Payload = payload as Payload or {}
  local outer, outer_reason = refused, reason
  refused, reason = nil, nil
  run(handlers[name], name, data)
  local family = name:match("^(.-)%.[^.]*$")
  if family then run(handlers[family .. ".*"], name, data) end
  run(handlers["*"], name, data)
  local no, why = refused, reason
  refused, reason = outer, outer_reason
  if no then return false, why end
  return true
end

return M
