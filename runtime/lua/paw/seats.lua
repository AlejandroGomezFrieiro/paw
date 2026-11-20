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
local api = paw.api
local M = { current = 0 }

local keeps = {}   -- { name, get, set, fresh }, in the order kept
local seats = {}   -- seat -> { values = name -> packed state, why = { reason = true } }

local function pack(...) return { n = select("#", ...), ... } end

--- Name some state that each seat has its own of. See the top of the file.
function M.keep(name, get, set, fresh)
  -- What the module holds now is the current seat's; every other seat
  -- starts afresh when its turn comes.
  keeps[#keeps + 1] = { name = name, get = get, set = set, fresh = fresh }
end

--- Keep fields of a table (a view's scroll, say) for each seat: `keys`
--- names them, `start` gives what a new seat starts with (nil if absent).
---   paw.seats.fields("mixer", view, { "scroll", "geometry" }, { scroll = 0 })
function M.fields(name, tbl, keys, start)
  M.keep(name,
    function()
      local out = {}
      for i, key in ipairs(keys) do out[i] = tbl[key] end
      return unpack(out, 1, #keys)
    end,
    function(...)
      local values = { ... }
      for i, key in ipairs(keys) do tbl[key] = values[i] end
    end,
    function()
      local out = {}
      for i, key in ipairs(keys) do out[i] = M.copy((start or {})[key]) end
      return unpack(out, 1, #keys)
    end)
end

local function stow(id)
  local values = seats[id].values
  for _, k in ipairs(keeps) do values[k.name] = pack(k.get()) end
end

local function restore(id)
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
function M.enter(id)
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
function M.within(id, fn, ...)
  local before = M.current
  M.enter(id)
  local result = pack(pcall(fn, ...))
  M.enter(before)
  if not result[1] then error(result[2], 0) end
  return unpack(result, 2, result.n)
end

--- A deep copy of a value. A new seat starts from the values of seat 0 with
--- it, and does not share them.
M.copy = require("paw.util").copy

--- True if `id` has its own seat.
function M.has(id)
  return id ~= 0 and seats[id] ~= nil
end

--- The seats there are, the instance's first.
function M.list()
  local out = {}
  for id in pairs(seats) do out[#out + 1] = id end
  table.sort(out)
  return out
end

--- What kind of seat `id` is, as a name that stays from one run to the
--- next: "window" for the graphical window, "terminal" for a terminal
--- (the instance's own, or one attached with `paw attach`). The seat of
--- the instance with no terminal is the window that started it.
function M.kind(id)
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
function M.open(id, why)
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
function M.close(id, why)
  local seat = seats[id]
  if id == 0 or not seat then return end
  if why then seat.why[why] = nil else seat.why = {} end
  if next(seat.why) then return end
  -- Whatever was half done there ends with it.
  M.within(id, paw.emit, "seat.closing", { seat = id })
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
api.timer_start = function(ms, ...)
  local args = pack(...)
  local fn = args[args.n]
  local seat = M.current
  if seat ~= 0 and type(fn) == "function" then
    args[args.n] = function(...) return M.within(seat, fn, ...) end
  end
  return start(ms, unpack(args, 1, args.n))
end

return M
