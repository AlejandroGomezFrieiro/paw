-- The track column (paw/trackcolumn.tl) and the bar labels of the ruler
-- (paw/ruler.tl): the numbers say what the counts of the motions reach.
local T = ...
local test, eq, fresh, after = T.test, T.eq, T.fresh, T.after
local paw = require("paw")
local api = paw.api

local function lines() return api.ui_snapshot(120, 30) end

--- The line of the screen with the track named `name`.
local function row(name, screen)
  for _, line in ipairs(screen or lines()) do
    if line:find(" " .. name .. " ", 1, true) then return line end
  end
end

--- What the column shows between a track's number and its header's stripe.
local function after_number(line)
  local rest = line:gsub("^ *%d+ ", "", 1)
  local stop = rest:find("▌", 1, true) or rest:find("█", 1, true)
  return rest:sub(1, stop - 1)
end

--- Strings (Violins, Low (Cellos, Violas)), between Drums and Bass, Keys.
local function orchestra()
  fresh()
  local t = {}
  for i, n in ipairs({ "Drums", "Violins", "Cellos", "Violas", "Bass", "Keys" }) do
    t[i] = paw.add_track({ name = n })
  end
  paw.groups.make({ t[2], t[3], t[4] }, "Strings")
  local low = paw.groups.make({ t[3], t[4] }, "Low")
  paw.opt.track_height = 1
  after(function()
    paw.opt.track_height = "auto"
    paw.opt.relativenumber = false
    paw.opt.relativebar = false
  end)
  paw.cursor.set_track(t[1])
  paw.flush()
  return t, low
end

test("track column: with rnu, each track shows the count of j or k that reaches it, a folded group one row", function()
  local _, low = orchestra()
  paw.keymap.feed(":set rnu<CR>jj")
  eq(paw.cursor.track().name, "Violins", "jj from Drums goes to the group's first member")
  paw.groups.fold(low, true)
  paw.flush()
  eq(tonumber(row("Violins"):match("^ *(%d+)")), 3, "the cursor's track keeps its own number")
  for i, id in ipairs(paw.groups.rows()) do
    local name = api.track_get(id).name
    if name ~= "Violins" then
      local n = row(name):match("^ *(%d+)")
      local key = n .. (i < 3 and "k" or "j")
      paw.keymap.feed(key)
      eq(paw.cursor.track().name, name, key .. " lands on the track marked " .. n)
      paw.keymap.feed("3G")
    end
  end
end)

test("track column: open and folded groups as a tree, nested", function()
  local _, low = orchestra()
  local screen = lines()
  eq(after_number(row("Strings", screen)), "▾ ", "an open group has ▾")
  eq(after_number(row("Low", screen)), "│▾", "a group inside one, a column in")
  eq(after_number(row("Cellos", screen)), "││", "a guide down the members")
  eq(after_number(row("Violas", screen)), "╰╰", "the last member closes both groups")
  paw.groups.fold(low, true)
  paw.flush()
  eq(after_number(row("Low")), "╰▸", "a folded group has ▸")
  eq(row("Low"):find("Low +2", 1, true) ~= nil, true, "and says how many it holds")
end)

test("track column: an extension's part shows in its order, and set moves a built-in one", function()
  orchestra()
  paw.trackcolumn.add("ext", {
    order = 15,
    width = 1,
    render = function(_, ctx)
      if ctx.line == 0 then return { { "E", "TrackSign" } } end
    end,
  })
  local fold = paw.trackcolumn.components.fold
  after(function()
    paw.trackcolumn.remove("ext")
    paw.trackcolumn.add("fold", fold)
  end)
  paw.flush()
  eq(after_number(row("Strings")), "E▾ ", "after the number (10), before the fold (30)")
  paw.trackcolumn.set("fold", { order = 5, glyphs = { open = "-" } })
  paw.flush()
  eq(row("Strings"):match("^%- +2 E") ~= nil, true, "the fold moved to the left, with its own glyph")
end)

test("relative bars: 4W lands on the bar marked 4, 4B on the one behind marked 4", function()
  orchestra()
  paw.cursor.set_beat(paw.time.bar_start(3) + 1)
  paw.keymap.feed(":set relativebar<CR>")
  --- The label of a bar on the ruler, read cell by cell.
  local function label_at(bar)
    local cells = {}
    for ch in lines()[1]:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      cells[#cells + 1] = ch
    end
    local view = paw.ui.views.arrange
    local x = view.geometry.hw + math.floor((paw.time.bar_start(bar) - view.scroll) * view.geometry.zoom + 0.5)
    local digits = ""
    while cells[x + 1] and cells[x + 1]:match("^%d$") do
      digits, x = digits .. cells[x + 1], x + 1
    end
    return tonumber(digits)
  end
  eq(label_at(3), 3, "the cursor's bar keeps its number")
  eq(label_at(7), 4, "four bars ahead")
  paw.keymap.feed("4W")
  eq(paw.time.bar_of(paw.cursor.beat), 7, "4W lands there")
  paw.cursor.set_beat(paw.time.bar_start(7) + 1)
  paw.flush()
  eq(label_at(4), 4, "from inside bar 7, the start of bar 4 is four B behind")
  paw.keymap.feed("4B")
  eq(paw.time.bar_of(paw.cursor.beat), 4, "4B lands there")
end)
