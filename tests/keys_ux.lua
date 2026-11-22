-- Finding your way with the keys: named groups in the hints, a sequence that
-- matches nothing, the focused view in the status line, the changelist, and
-- the order of the `?` list.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local pick = paw.pick

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
end

local function hint_of(key)
  for _, hint in ipairs(paw.keymap.hints() or {}) do
    if hint.key == key then return hint.desc end
  end
end

test("a named group shows its name in the hints, and an unnamed one how many keys it holds", function()
  start()
  paw.opt.hint_delay = 0
  paw.keymap.set("<leader>yq1", "noop", { desc = "one" })
  paw.keymap.set("<leader>yq2", "noop", { desc = "two" })
  paw.keymap.feed("<leader>")
  eq(hint_of("y"), "+2 more", "counted until it has a name")
  paw.keymap.feed("<Esc>")
  paw.keymap.group("<leader>y", "test group")
  paw.keymap.feed("<leader>")
  eq(hint_of("y"), "+test group", "named")
  paw.keymap.feed("<Esc>")
  paw.keymap.feed("<leader>a")
  eq(hint_of("l"), "Choose what to automate, and show its lane", "the keys inside still say what they do")
  paw.keymap.feed("<Esc><leader>")
  eq(hint_of("a"), "+automation", "the built-in groups have names")
  eq(hint_of("c"), "+clip", "for what the prefix holds in this view")
  paw.keymap.feed("<Esc>")
  paw.keymap.del("<leader>yq1")
  paw.keymap.del("<leader>yq2")
  paw.opt.hint_delay = 500
end)

test("a sequence that matches nothing says so and drops what follows it", function()
  start()
  local ran = {}
  paw.keymap.set("<leader>yz", function() ran.mapped = true end, { desc = "test" })
  paw.keymap.set("Q", function() ran.last = (ran.last or 0) + 1 end, { desc = "test" })
  paw.keymap.feed("<leader>yQ")
  eq(ran.last, nil, "the last key did not run alone")
  eq(ran.mapped, nil, "nor the mapping it was heading for")
  eq(paw.keymap.pending(), "", "nothing is left half typed")
  eq(paw.ui.message and paw.ui.message.text, "Space yQ is not mapped", "the message says what was typed")
  -- A key that is a mapping by itself still runs, then the next key starts afresh.
  paw.keymap.set("wm", function() ran.wm = (ran.wm or 0) + 1 end, { desc = "test" })
  paw.keymap.set("wmm", function() ran.wmm = true end, { desc = "test" })
  paw.keymap.feed("wmQ")
  eq(ran.wm, 1, "a complete mapping that is also a prefix runs")
  eq(ran.last, 1, "and the key after it is a new command")
  eq(ran.wmm, nil, "not the longer one")
  paw.keymap.del("<leader>yz")
  paw.keymap.del("Q")
  paw.keymap.del("wm")
  paw.keymap.del("wmm")
end)

test("the status line names the focused view and shows its grid", function()
  start()
  local function segments()
    local out = {}
    for _, list in pairs(paw.ui.views.status.segments(140)) do
      for _, seg in ipairs(list) do
        for _, piece in ipairs(seg) do
          out[#out + 1] = piece[1]
        end
      end
    end
    return table.concat(out, "|")
  end
  local grid, note_grid = paw.opt.grid, paw.opt.note_grid
  paw.opt.grid, paw.opt.note_grid = 1, 0.5
  local text = segments()
  eq(text:find(" NORMAL·arrange ", 1, true) ~= nil, true, "the pill: " .. text)
  eq(text:find("grid 1/4", 1, true) ~= nil, true, "the arrange grid")
  paw.ui.focus("pianoroll")
  text = segments()
  eq(text:find(" NORMAL·pianoroll ", 1, true) ~= nil, true, "the pill follows focus: " .. text)
  eq(text:find("grid 1/8", 1, true) ~= nil, true, "the roll's own grid")
  paw.ui.focus("arrange")
  paw.opt.grid, paw.opt.note_grid = grid, note_grid
end)

test("g; and g, walk the places the project was edited, and `. goes to the last", function()
  start()
  paw.keymap.feed("ooo")
  paw.cursor.set_track(paw.tracks()[1])
  paw.cursor.set_beat(8)
  paw.keymap.feed("M")
  paw.cursor.set_track(paw.tracks()[3])
  paw.cursor.set_beat(16)
  paw.keymap.feed("M")
  paw.cursor.set_beat(0)
  paw.cursor.set_track(paw.tracks()[2])
  local function where() return paw.cursor.index() .. "@" .. paw.cursor.beat end
  paw.keymap.feed("g;")
  eq(where(), "3@16", "g; goes to the last edit")
  paw.keymap.feed("g;")
  eq(where(), "1@8", "and again to the one before")
  paw.keymap.feed("g,")
  eq(where(), "3@16", "g, goes forward")
  paw.cursor.set_beat(0)
  paw.keymap.feed("`.")
  eq(where(), "3@16", "`. goes to the last edit's track and beat")
  eq(#paw.keymap.changes("arrange") >= 3, true, "the list holds them")
  paw.cmd("changes")
  eq(paw.ui.float and paw.ui.float.name, "pager", ":changes lists them")
  paw.ui.close()
end)

test("the ? list puts the view's own keys first, folds aliases and has no repeats", function()
  start()
  paw.keymap.feed("?")
  local lines = pick.state().matches
  eq(lines[1]:find("arrange", 1, true) ~= nil, true, "the view's own keys come first: " .. lines[1])
  local seen, first_global = {}, nil
  for i, line in ipairs(lines) do
    eq(seen[line], nil, "repeated: " .. line)
    seen[line] = true
    if not first_global and line:find("global%s*$") then first_global = i end
  end
  for i = first_global, #lines do
    eq(lines[i]:find("arrange%s*%a*%s*$"), nil, "a view key after global ones: " .. lines[i])
  end
  local text = table.concat(lines, "\n")
  eq(text:find("Ctrl-z, u", 1, true) ~= nil, true, "aliases are on one line")
  paw.keymap.feed("<Esc>")
end)
