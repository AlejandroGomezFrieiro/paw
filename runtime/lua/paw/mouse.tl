-- The pointer in the terminal: what the views share to take it, and what
-- happens before an event reaches the view under the pointer.
--
-- A terminal reports a press, a release, the pointer moving with a button
-- held (a drag) or without (a move, for what is under it), and the wheel,
-- each in cells with the modifiers held (`mods`: any of `C`, `A`, `S`).
-- `paw.ui.mouse` gives each one first to what floats over the views (a menu,
-- the command line's list), then to a gesture that holds the pointer, then
-- to the view under it, with coordinates relative to the view.
--
-- What a gesture means is the window's: views turn cells into beats,
-- pitches, tracks and values and call `paw.frontend.act`, so both frontends
-- do the same with the same gesture.
--
--   function view:on_mouse(e)
--     if e.kind == "down" then
--       paw.mouse.grab(e, {
--         drag = function(d) ... d.x, d.y, d.dx, d.dy, d.moved ... end,
--         up = function(u) ... end,
--       })
--     end
--   end
--
-- `paw.opt.mouse = false` leaves the pointer to the terminal's own selection.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local type registry = require("paw.registry")
local seats = require("paw.seats")
local limit = require("paw.limit")
local options = require("paw.options")
local type contracts = require("paw.contracts")
local type layout = require("paw.layout")

local type View = contracts.View
local type MouseEvent = contracts.MouseEvent
local type PointerEvent = contracts.PointerEvent
local opt = options.opt

--- What a gesture does with the pointer it holds (`grab`): `drag` for
--- each move, `up` at the release, `cancel` when another button is pressed.
--- A view's gesture can keep more of its own (`record X is Handlers`), and
--- read them back from `gesture()`.
local interface Handlers
  drag: function(e: MouseEvent)
  up: function(e: MouseEvent)
  cancel: function()
end

--- A gesture under way: its handlers, the button and the cell of the
--- press, the corner of the view of the press, and whether it moved.
local record Gesture
  handlers: Handlers
  button: string
  x0: number
  y0: number
  ox: number
  oy: number
  moved: boolean
end

--- The last press, for a double click.
local record Press
  button: string
  x: integer
  y: integer
  time: number
  double: boolean
end

--- Each seat's: the gesture under way, the last press, what the status
--- line says about the pointer and the shape it gives it, whether a view
--- said something about the pointer this time, and the surface a drag
--- holds.
local record State
  gesture: Gesture
  last: Press
  hint: string
  shape: string
  hinted: boolean
  surface: string
end

--- What floats over the views and takes the pointer first.
local type Overlay = function(e: MouseEvent): boolean

-- The parts of paw/ui.tl and paw/canvas.tl that this module calls: those
-- modules name this one's types, so this one cannot name theirs.
local record Ui
  views: registry.Registry<View>
  rects: layout.Arrangement
  pressed: string
end
local record Canvas
  view_pointer: function(view: View, e: PointerEvent)
end
local record Paw
  ui: Ui
  canvas: Canvas
end
local paw = (_G as {string: Paw}).paw

local record M
  type Handlers = Handlers
  type Gesture = Gesture
  type Overlay = Overlay
  --- Two presses of a button on one cell within this many milliseconds are
  --- a double click, which a terminal does not report itself.
  double_ms: number
  --- What floats over the views and takes the pointer first, while it is
  --- there: functions given the event in screen cells, returning true when
  --- they took it.
  overlays: {Overlay}
  mark_double: function(event: MouseEvent)
  wheel: function(event: MouseEvent): integer, boolean
end
M.double_ms = 400
M.overlays = {}

-- Each seat has its own: the gesture under way, the last press, what the
-- status line says about the pointer.
local state: State = {}
seats.keep(
  "mouse", function(): State return state end, function(s: State) state = s end, function(): State return {} end
)

--- A copy of an event with other fields laid over it.
local function merged(event: MouseEvent, extra: MouseEvent): MouseEvent
  local out: MouseEvent = {}
  for k, v in pairs(event as {string: MouseEvent}) do
    (out as {string: MouseEvent})[k] = v
  end
  for k, v in pairs(extra as {string: MouseEvent}) do
    (out as {string: MouseEvent})[k] = v
  end
  return out
end

--- True if a press is the second press of a double click. That is the same
--- button on the same cell soon after the first press, which was not a
--- second press itself. For the pointer of a window, in fractions of a
--- cell, the cell that contains it counts.
local function mark_double(event: MouseEvent)
  if event.kind ~= "down" then
    return
  end
  local now, last = api.now(), state.last
  local x, y = math.floor(event.x), math.floor(event.y)
  local double = last
    and not last.double
    and last.button == event.button
    and last.x == x
    and last.y == y
    and now - last.time <= M.double_ms
  event.double = double or nil
  state.last = {button = event.button, x = x, y = y, time = now, double = double}
end
M.mark_double = mark_double

--- True if the modifiers of an event contain `letter` ("C", "A" or "S").
function M.has(event: MouseEvent, letter: string): boolean
  return (event.mods or ""):find(letter, 1, true) ~= nil
end

--- How a click with modifiers chooses: "toggle" with Ctrl, "add" with
--- Shift, else "only".
function M.mode(event: MouseEvent): string
  if M.has(event, "C") then
    return "toggle"
  end
  if M.has(event, "S") then
    return "add"
  end
  return "only"
end

--- Hold the pointer from a press (`down`, as the view got it) until its
--- button is released. Each drag goes to `handlers.drag(e)` and the release
--- to `handlers.up(e)`, at any pointer position. `x` and `y` are relative
--- to the view of the press, and `dx` and `dy` are the cells from the press.
--- `moved` tells if the pointer left the cell of the press. A press of a
--- different button calls `handlers.cancel()` and stops the gesture.
function M.grab(down: MouseEvent, handlers: Handlers)
  state.gesture = {
    handlers = handlers,
    button = down.button,
    x0 = down.x,
    y0 = down.y,
    ox = down.view_x or 0,
    oy = down.view_y or 0,
    moved = false,
  }
end

--- Forget the last press and any gesture under way: the next press is
--- not the second of a double click.
function M.forget()
  state.last, state.gesture = nil, nil
end

--- The gesture under way, if any: what was handed to `grab`.
function M.gesture(): Handlers
  return state.gesture and state.gesture.handlers
end

local function feed_gesture(event: MouseEvent)
  local g = state.gesture
  local e = merged(event, {x = event.x - g.ox, y = event.y - g.oy})
  e.dx, e.dy = e.x - g.x0, e.y - g.y0
  -- A window's pointer comes in fractions of a cell (`fine`): half of one
  -- away is away, so that a click that wavers a pixel stays a click.
  local away: boolean
  if event.fine then
    away = math.abs(e.dx) >= 0.5 or math.abs(e.dy) >= 0.5
  else
    away = e.dx ~= 0 or e.dy ~= 0
  end
  g.moved = g.moved or away
  e.moved = g.moved
  if event.kind == "up" then
    -- What the drag said is over; the next move says what is under the pointer.
    state.gesture, state.hint, state.shape = nil, nil, nil
    -- Whatever the view saw of the press is over too.
    paw.ui.pressed = nil
    if g.handlers.up then
      g.handlers.up(e)
    end
  elseif g.handlers.drag then
    g.handlers.drag(e)
  end
  api.ui_redraw()
end

--- Show on the status line what is under the pointer, or what it would do.
--- nil shows nothing. A view calls it while the pointer moves over it.
--- `shape` is the shape a window gives the pointer there: `"resize_h"` over
--- an edge dragged sideways, `"resize_v"` over one dragged up or down.
function M.hint(text: string, shape?: string)
  state.hinted = true
  if text ~= state.hint or shape ~= state.shape then
    state.hint, state.shape = text, shape
    api.ui_redraw()
  end
end

--- What the status line says about the pointer, if anything; and the
--- shape of the pointer, if it has one.
function M.hint_text(): string, string
  return state.hint, state.shape
end

--- Called by `paw.ui.mouse` first: true when the event was taken here and
--- goes no further.
function M.take(event: MouseEvent): boolean
  if opt.mouse == false then
    return true
  end
  event.mods = event.mods or ""
  mark_double(event)
  local g = state.gesture
  if g then
    if
      (event.kind == "drag" or event.kind == "up")
      and (event.button == g.button or event.button == "" or not event.button)
    then
      feed_gesture(event)
      return true
    elseif event.kind == "down" then
      state.gesture = nil
      if g.handlers.cancel then
        g.handlers.cancel()
      end
      api.ui_redraw()
    end
  end
  for i = #M.overlays, 1, -1 do
    if M.overlays[i](event) then
      return true
    end
  end
  state.hinted = false
  return false
end

--- Give an event in the cells of a view to the view, for a view drawn in a
--- separate window (`paw.canvas.pointer`). A gesture in progress gets it
--- first, as in the terminal.
function M.to_view(view: View, event: MouseEvent): boolean
  event.mods = event.mods or ""
  mark_double(event)
  local g = state.gesture
  if g and (event.kind == "drag" or event.kind == "up") then
    feed_gesture(event)
    return
  end
  if g and event.kind == "down" then
    state.gesture = nil
    if g.handlers.cancel then
      g.handlers.cancel()
    end
  end
  if view.on_mouse then
    view:on_mouse(merged(event, {view_x = 0, view_y = 0}))
  end
end

--- `paw.ui.mouse` calls this for the view that gets an event. Over the
--- pixels that the view shows (`buf:surface`), the event goes to the
--- `pointer` function of the view, in pixels of its drawing. A window gives
--- it the same way (`paw.canvas`). Where the terminal reports the pointer in pixels,
--- the position is exact. In other terminals, it is the middle of the cell.
--- `kind` is "down", "up", "move" (with a button held), "hover", "double"
--- (after the second press) or "wheel" (`dx`, `dy`). The modifiers are
--- `ctrl`, `shift` and `alt`. `col` and `row` are the screen cell under the
--- pointer, where a menu opens. A drag and its release go to the surface of
--- the press, at any pointer position. True when the event went there.
function M.to_surface(target: contracts.ScreenRect, event: MouseEvent): boolean
  -- A view's own drawing (`buf:surface`) in the window the event is in, or
  -- for a drag the one the press was on; a strip drawn by a view under its
  -- cells (`buf:strip`) leaves the pointer to the view's `on_mouse`.
  local surface: layout.Surface
  local held = (event.kind == "drag" or event.kind == "up") and state.surface
  for _, s in ipairs(paw.ui.rects.surfaces or {}) do
    if s.paint and (held and s.key == held or not held and s.name == target.name and s.win == target.win) then
      surface = s
    end
  end
  local view = surface and paw.ui.views:get(surface.name)
  if not (view and (view.pointer or view.hits)) then
    state.surface = nil
    return false
  end
  local s, kind = surface, event.kind
  local inside = event.x >= s.x and event.x < s.x + s.w and event.y >= s.y and event.y < s.y + s.h
  if kind == "down" then
    state.surface = inside and s.key or nil
  elseif kind == "drag" or kind == "up" then
    inside = state.surface == s.key
    if kind == "up" then
      state.surface = nil
    end
  end
  if not inside then
    return false
  end
  local cw, ch = s.cell.w, s.cell.h
  local e: PointerEvent = {
    x = event.px and event.px - s.x * cw or (event.x - s.x + 0.5) * cw,
    y = event.py and event.py - s.y * ch or (event.y - s.y + 0.5) * ch,
    ctrl = M.has(event, "C"),
    shift = M.has(event, "S"),
    alt = M.has(event, "A"),
    button = event.button ~= "" and event.button or nil,
    col = event.x,
    row = event.y,
  }
  if kind == "drag" then
    e.kind = "move"
  elseif kind == "move" then
    e.kind = "hover"
  elseif kind:match("^scroll") then
    -- A notch of the wheel is three rows, up and left positive, as a window has it.
    local step, sideways = M.wheel(event)
    local d = -step * 3 * ch
    e.kind, e.dx, e.dy = "wheel", sideways and d or 0, sideways and 0 or d
  else
    e.kind = kind
  end
  limit.named("the mouse", function() paw.canvas.view_pointer(view, e) end)
  if kind == "down" and event.double then
    local double: PointerEvent = {}
    for k, v in pairs(e as {string: PointerEvent}) do
      (double as {string: PointerEvent})[k] = v
    end
    double.kind = "double"
    limit.named("the mouse", function() paw.canvas.view_pointer(view, double) end)
  end
  api.ui_redraw()
  return true
end

--- Called by `paw.ui.mouse` last: a move over nothing that says what it is
--- under the pointer clears what the status line said.
function M.done(event: MouseEvent)
  if event.kind == "move" and not state.hinted and state.hint then
    state.hint, state.shape = nil, nil
    api.ui_redraw()
  end
end

--- A wheel event as a step: 1 down or right, -1 up or left. The second
--- value tells if it goes to the side.
function M.wheel(event: MouseEvent): integer, boolean
  local kind = event.kind
  if kind == "scroll_down" then
    return 1, false
  end
  if kind == "scroll_up" then
    return -1, false
  end
  if kind == "scroll_right" then
    return 1, true
  end
  if kind == "scroll_left" then
    return -1, true
  end
end

return M
