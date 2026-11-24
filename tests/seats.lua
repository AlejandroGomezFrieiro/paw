-- Tests of seats: every terminal and window attached to an instance has a
-- cursor, mode, selection and keys of its own, while the project is one.
-- The kernel's part (whose turn it is) is played here by calling its entry
-- points the way it does. Loaded by tests/suite.lua with its helpers.
local T = ...
local advance = T.advance
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local K = paw._kernel

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
end

--- Do `fn` as the kernel does a turn for `seat`, and come back to the
--- instance's seat after, as it does.
local function as(seat, fn)
  K.seat(seat)
  local ok, err = xpcall(fn, debug.traceback)
  K.seat(0)
  if not ok then error(err, 0) end
end

--- Type keys in a seat, one turn each.
local function keys(seat, typed)
  for _, key in ipairs(paw.keymap.parse(typed)) do
    as(seat, function() K.key(key) end)
    paw.flush()
    api.undo_checkpoint()
  end
end

local function name_at_cursor(seat)
  local name
  as(seat, function() name = paw.cursor.part().name end)
  return name
end

test("two terminals each have a cursor, a mode and keys of their own, and edit one project", function()
  start()
  for _, name in ipairs({ "Drums", "Bass", "Keys" }) do
    paw.add_part({ name = name })
  end
  paw.cursor.set_part(paw.parts()[1])
  paw.cursor.set_beat(4)
  K.seat_open(7, "terminal")
  local ok, err = pcall(function()
    eq(paw.seats.has(7), true, "the terminal has a seat")
    eq(name_at_cursor(7), "Drums", "a new seat starts where the instance's cursor is")
    keys(7, "jj")
    eq(name_at_cursor(7), "Keys", "it moves its own cursor")
    eq(name_at_cursor(0), "Drums", "and not the instance's")
    eq(paw.cursor.beat, 4, "nor its beat")
    keys(7, "V")
    as(7, function() eq(paw.keymap.mode, "x", "a selection is open in the terminal") end)
    eq(paw.keymap.mode, "n", "and not in the instance's seat")
    keys(0, "g")
    eq(paw.keymap.pending(), "g", "keys half typed in one seat")
    as(7, function() eq(paw.keymap.pending(), "", "are not in another") end)
    keys(7, "<Esc>")
    keys(0, "<Esc>")
    -- One project: what one seat does, the other sees, and undoes.
    keys(7, ":part.add<CR>")
    eq(#paw.parts(), 4, "a part added from the terminal")
    as(7, function() eq(paw.keymap.mode, "n", "its command line closed") end)
    keys(0, "u")
    eq(#paw.parts(), 3, "undone from the instance's seat: one history")
    -- A prompt open in one seat takes that seat's keys only.
    keys(7, ":")
    as(7, function() eq(paw.ui.grabber ~= nil, true, "the terminal has a prompt open") end)
    eq(paw.ui.grabber, nil, "the instance's seat does not")
    keys(0, "j")
    eq(name_at_cursor(0), "Bass", "keys go on working there")
    keys(7, "<Esc>")
    -- Panels and focus are each seat's own.
    keys(7, ":view.toggle mixer<CR>")
    as(7, function()
      eq(paw.ui.visible("mixer"), true, "the mixer opened in the terminal")
      eq(paw.ui.focused, "mixer", "with the keyboard")
    end)
    eq(paw.ui.visible("mixer"), false, "not in the instance's seat")
    eq(paw.ui.focused, "arrange", "which keeps its focus")
  end)
  K.seat_close(7, "terminal")
  if not ok then error(err, 0) end
  eq(paw.seats.has(7), false, "the seat closed with its terminal")
  eq(paw.seats.current, 0, "the instance's seat is the current one")
end)

test("a seat that closes leaves nothing behind, and an unknown one is the instance's", function()
  start()
  paw.add_part({ name = "One" })
  paw.add_part({ name = "Two" })
  paw.cursor.set_part(paw.parts()[1])
  K.seat_open(8, "terminal")
  keys(8, "j")
  keys(8, "g")
  as(8, function() eq(paw.keymap.pending(), "g", "a key waits in the terminal") end)
  K.seat_close(8, "terminal")
  eq(name_at_cursor(8), "One", "a closed seat's turn is the instance's")
  eq(paw.keymap.pending(), "", "and what waited there is gone")
  -- Opened again, it starts afresh.
  K.seat_open(8, "terminal")
  eq(name_at_cursor(8), "One", "from the instance's cursor")
  as(8, function() eq(paw.keymap.pending(), "", "with nothing half typed") end)
  K.seat_close(8, "terminal")
end)

test("a timer started in a seat runs in that seat", function()
  start()
  K.seat_open(9, "terminal")
  local seen
  as(9, function()
    paw.defer(function() seen = paw.seats.current end, 1)
  end)
  advance(30)
  K.seat_close(9, "terminal")
  eq(seen, 9, "the deferred function ran in the terminal's seat")
end)

test("a window watching has a seat of its own unless it shares the instance's", function()
  start()
  paw.add_part({ name = "First" })
  paw.add_part({ name = "Second" })
  paw.cursor.set_part(paw.parts()[1])
  paw.seats.open(11, "window")
  as(11, function() paw.cursor.set_part(paw.parts()[2]) end)
  local state = paw.seats.within(11, paw.frontend.state, -1)
  eq(state.selected, paw.parts()[2].id, "the window's state shows its own cursor")
  eq(paw.frontend.state(-1).selected, paw.parts()[1].id, "the instance's shows its own")
  paw.seats.open(11, "terminal")
  paw.seats.close(11, "window")
  eq(paw.seats.has(11), true, "a seat stays while the connection still has a terminal")
  K.rpc_closed(11)
  eq(paw.seats.has(11), false, "and goes with the connection")
end)

test("a button held down in one terminal is that terminal's drag alone", function()
  start()
  paw.add_part({ name = "One" })
  K.seat_open(13, "terminal")
  as(13, function()
    paw.ui.render(paw.ui.Buf.root(api.ui_size()))
    local r
    for _, rect in ipairs(paw.ui.rects) do
      if rect.name == "arrange" then r = rect end
    end
    K.mouse({ kind = "down", button = "left", x = r.x + r.w - 2, y = r.y + 3, mods = "" })
    eq(paw.ui.pressed, "arrange", "the drag belongs to the arrange view")
  end)
  eq(paw.ui.pressed, nil, "not in the instance's seat")
  as(13, function() K.mouse({ kind = "up", button = "left", x = 1, y = 1, mods = "" }) end)
  as(13, function() eq(paw.ui.pressed, nil, "let go") end)
  K.seat_close(13, "terminal")
end)

test("the project keeps a layout for each kind of seat, and a default", function()
  start()
  local L = paw.layout
  local initial = L.capture()
  T.after(function()
    if paw.seats.has(21) then K.seat_close(21, "terminal") end
    if paw.seats.has(22) then K.seat_close(22, "window") end
    L.restore(initial)
    paw.ui.focus("arrange")
  end)
  local function views(seat)
    local out
    as(seat, function()
      out = {}
      for _, win in ipairs(L.windows(paw.ui.layout)) do
        out[#out + 1] = win.view
      end
      out = table.concat(out, " ")
    end)
    return out
  end
  local mine = paw.seats.kind(0)
  local other = mine == "window" and "terminal" or "window"
  local seat = 21
  K.seat_open(seat, other)
  eq(paw.seats.kind(seat), other, "a seat of the other kind")
  keys(0, ":e mixer<CR>:only<CR>")
  keys(seat, ":e devices<CR>:only<CR>")
  local path = T.scratch .. "/seats-screen"
  keys(0, ":w " .. path .. "<CR>")
  local screen = L.project_screen()
  eq(
    screen.seats[mine] ~= nil and screen.seats[other] ~= nil and screen.default ~= nil,
    true,
    "the project keeps the layout of each seat and a default"
  )
  keys(0, ":e arrange<CR>")
  keys(seat, ":e arrange<CR>")
  keys(0, ":e " .. path .. "<CR>")
  eq(views(0), "mixer", "opening it gives this seat its own")
  eq(views(seat), "devices", "and the other seat its own")
  -- A project saved with one layout (as before) gives it to every seat.
  keys(0, ":set noproject_screen<CR>")
  T.after(function() paw.opt.project_screen = true end)
  api.project_screen_set(screen.seats[mine])
  keys(0, ":w<CR>")
  keys(0, ":set project_screen<CR>")
  keys(0, ":e arrange<CR>")
  keys(seat, ":e arrange<CR>")
  keys(0, ":e " .. path .. "<CR>")
  eq(views(0) .. " / " .. views(seat), "mixer / mixer", "a seat with no layout of its own takes the default")
  K.seat_close(seat, other)
end)

test("a project that another terminal opens leaves this terminal's float with the keys", function()
  start()
  local L = paw.layout
  local initial = L.capture()
  T.after(function()
    if paw.seats.has(23) then K.seat_close(23, "terminal") end
    as(0, function()
      while paw.ui.float do
        paw.ui.close()
      end
    end)
    L.restore(initial)
    paw.ui.focus("arrange")
  end)
  local path = T.scratch .. "/seats-float"
  keys(0, ":w " .. path .. "<CR>")
  K.seat_open(23, "terminal")
  keys(0, ":help all<CR>")
  keys(23, ":e " .. path .. "<CR>")
  as(0, function() eq(paw.ui.focused, "help", "the float still has the keys") end)
  keys(0, "q")
  as(0, function()
    eq(paw.ui.float, nil, "q closed it")
    eq(paw.ui.focused, "arrange", "and the keys went back to the layout the project put under it")
  end)
end)

test("with one seat, nothing is put away or brought back", function()
  start()
  local stowed = 0
  paw.seats.keep("test.counting", function() stowed = stowed + 1 end, function() end, function() end)
  for _ = 1, 5 do
    keys(0, "j")
  end
  eq(stowed, 0, "turns in the instance's seat move no state")
end)
