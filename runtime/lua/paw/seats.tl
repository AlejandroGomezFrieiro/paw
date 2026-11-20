-- Seats: everyone working in one instance has a view of their own. The
-- project is one and shared; what a person is looking at and in the middle
-- of is theirs: the focused view and what is open, the edit cursor, the
-- mode, the selection, keys half typed, registers, marks, a prompt, where
-- each view is scrolled to.
--
-- Seat 0 is the instance's own: its terminal, if it has one, and every
-- connection that has not taken a seat of its own (`paw ctl`, scripts).
-- A terminal attached with `paw attach` gets a seat, and so does a window
-- unless it asks to share the instance's (as one that started its kernel
-- itself does). The kernel says whose turn it is (`paw._kernel.seat`)
-- before it hands over a key, a call or a screen to draw.
--
-- Modules keep their state where they always have (in locals and fields);
-- they name it here with `keep`, and when another seat's turn comes, what
-- is there is put away and that seat's is put back. With one seat nothing
-- ever moves.
--
--   local pending, count = {}, nil
--   paw.seats.keep("mine",
--     function() return pending, count end,
--     function(p, c) pending, count = p, c end,
--     function() return {}, nil end)
--
-- The last function gives what a new seat starts with; it is passed seat
-- 0's state, to start from a copy of some of it.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua. `keep` and
-- `within` take values of one type: a module in Teal that keeps more puts
-- them in a record.
local api = require("paw.api")

--- A value this module keeps for a seat and never reads.
local record Value
end

--- Values as `pack` keeps them: with their count, nils included.
local record Packed
  {Value}
  n: integer
end

--- State that each seat has its own of.
local record Keep
  name: string
  get: function(): Value...
  set: function(...: Value)
  fresh: function(...: Value): Value...
end

--- Why a seat is open: `terminal`, `window`, `instance`.
local record Seat
  values: {string:Packed}
  why: {string:boolean}
end

-- Lua 5.1's function that Teal's library leaves out.
local record Lua51
  unpack: function<T>({T}, ? integer, ? integer): T...
end
local unpack = (_G as Lua51).unpack

--- The payload of `seat.opened` and `seat.closing`.
local record SeatEvent
  seat: integer
end

-- What this module reads of `paw`, which paw/init.lua makes. A module of the
-- runtime in Teal does not see the global `paw`: runtime/types/paw.d.tl
-- declares it from these modules.
local record Paw
  emit: function(string, SeatEvent)
end
local paw = (_G as {string:Paw}).paw

local record M
  current: integer
  copy: function<T>(T): T
end
M.current = 0

local keeps: {Keep} = {}   -- { name, get, set, fresh }, in the order kept
local seats: {integer:Seat} = {}   -- seat -> { values = name -> packed state, why = { reason = true } }

local function pack(...: Value): Packed
  local out: Packed = { ... }
  out.n = select("#", ...)
  return out
end

--- Name some state that each seat has its own of. See the top of the file.
function M.keep<T>(name: string, get: function(): (T...), set: function(T...), fresh: function(T...): (T...))
  -- What the module holds now is the current seat's; every other seat
  -- starts afresh when its turn comes.
  keeps[#keeps + 1] = { name = name, get = get as function(): Value..., set = set as function(...: Value),
    fresh = fresh as function(...: Value): Value... }
end

--- Keep fields of a table (a view's scroll, say) for each seat: `keys`
--- names them, `start` gives what a new seat starts with (nil if absent).
---   paw.seats.fields("mixer", view, { "scroll", "geometry" }, { scroll = 0 })
function M.fields<V>(name: string, tbl: {string:V}, keys: {string}, start?: {string:V})
  M.keep(name,
    function(): V...
      local out: {V} = {}
      for i, key in ipairs(keys) do out[i] = tbl[key] end
      return unpack(out, 1, #keys)
    end,
    function(...: V)
      local values: {V} = { ... }
      for i, key in ipairs(keys) do tbl[key] = values[i] end
    end,
    function(): V...
      local out: {V} = {}
      for i, key in ipairs(keys) do out[i] = M.copy((start or {})[key]) end
      return unpack(out, 1, #keys)
    end)
end

local function stow(id: integer)
  local values = seats[id].values
  for _, k in ipairs(keeps) do values[k.name] = pack(k.get()) end
end

local function restore(id: integer)
  local values, zero = seats[id].values, seats[0].values
  for _, k in ipairs(keeps) do
    local packed = values[k.name]
    if not packed then
      local base = zero[k.name] or pack()
      packed = pack(k.fresh(unpack(base, 1, base.n)))
      values[k.name] = packed
    end
    k.set(unpack(packed, 1, packed.n))
  end
end

seats[0] = { values = {}, why = { instance = true } }

--- Make `id`'s seat the current one: an open seat, else the instance's.
--- Returns the seat entered.
function M.enter(id: integer): integer
  if not seats[id] then id = 0 end
  if id == M.current then return id end
  stow(M.current)
  restore(id)
  M.current = id
  -- The screen is as big as this seat's terminal.
  api.ui_seat(id)
  return id
end

--- Run `fn` in seat `id` (in the seat of the instance, if that seat closed),
--- then return to the current seat.
function M.within<A, R>(id: integer, fn: function(A...): (R...), ...: A): R...
  local before = M.current
  M.enter(id)
  local result = pack((pcall as function(function(A...): (R...), A...): Value...)(fn, ...))
  M.enter(before)
  if not result[1] then error(result[2], 0) end
  return (unpack as function(Packed, integer, integer): R...)(result, 2, result.n)
end

--- A deep copy of a value. A new seat starts from the values of seat 0 with
--- it, and does not share them.
M.copy = require("paw.util").copy

--- True if `id` has its own seat.
function M.has(id: integer): boolean
  return id ~= 0 and seats[id] ~= nil
end

--- The seats there are, the instance's first.
function M.list(): {integer}
  local out: {integer} = {}
  for id in pairs(seats) do out[#out + 1] = id end
  table.sort(out)
  return out
end

--- What kind of seat `id` is, as a name that stays from one run to the
--- next: "window" for the graphical window, "terminal" for a terminal
--- (the instance's own, or one attached with `paw attach`). The seat of
--- the instance with no terminal is the window that started it.
function M.kind(id?: integer): string
  id = id or M.current
  local seat = seats[id]
  if id ~= 0 and seat then
    if seat.why.window then return "window" end
    return "terminal"
  end
  return api.ui_attached() and "terminal" or "window"
end

--- Give connection `id` its own seat, for a reason (`terminal`, `window`).
--- The seat stays while a reason stays.
function M.open(id: integer, why: string)
  if id == 0 then return end
  local seat = seats[id]
  if not seat then
    seat = { values = {}, why = {} }
    seats[id] = seat
    paw.emit("seat.opened", { seat = id })
  end
  seat.why[why] = true
end

--- Let go of a reason for `id`'s seat (or of all of them, with none): the
--- seat closes with its last one.
function M.close(id: integer, why?: string)
  local seat = seats[id]
  if id == 0 or not seat then return end
  if why then seat.why[why] = nil else seat.why = {} end
  if next(seat.why) then return end
  -- Whatever was half done there ends with it.
  M.within(id, function() paw.emit("seat.closing", { seat = id }) end)
  seats[id] = nil
  if M.current == id then
    restore(0)
    M.current = 0
    api.ui_seat(0)
  end
end

-- A timer runs in the seat that started it: a key that waits for the next
-- (`timeoutlen`), a message to clear, a deferred redraw.
local start = api.timer_start
-- The kernel calls a timer with no arguments, and does not read what it
-- returns.
api.timer_start = function(ms: number, repeat_: boolean, fn: function()): integer
  local seat = M.current
  if seat ~= 0 and fn is function then
    local inner = fn
    fn = function() M.within(seat, inner) end
  end
  return start(ms, repeat_, fn)
end

return M
