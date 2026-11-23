-- Tests for the columnplus extension; run by tests/suite.lua.
local T = ...
local test, eq, after = T.test, T.eq, T.after
local paw = require("paw")
local api = paw.api

--- Drums with two clips, Strings (Violins, Cellos), Keys with a clip that
--- has two takes. The extension loaded, unloaded after the test.
local function song()
  T.fresh()
  local t = {}
  for i, n in ipairs({ "Drums", "Violins", "Cellos", "Keys" }) do
    t[i] = paw.add_track({ name = n })
  end
  paw.groups.make({ t[2], t[3] }, "Strings")
  t[1]:add_clip({ start = 0, length = 4 })
  t[1]:add_clip({ start = 8, length = 4 })
  local keys = t[4]:add_clip({ start = 0, length = 4 })
  api.clip_set(keys.id, { meta = { takes = { active = 1, list = { { name = "take 1" }, { name = "take 2" } } } } })
  paw.opt.track_height = 1
  paw.cursor.set_track(t[1])
  paw.ext.load("extensions/columnplus")
  after(function()
    if paw.ext.loaded.columnplus then paw.ext.unload("columnplus") end
    paw.opt.track_height = "auto"
  end)
  paw.flush()
  return t
end

--- The track column of the line with the track named `name`: what is
--- before its header's stripe.
local function column(name, screen)
  for _, line in ipairs(screen or api.ui_snapshot(100, 24)) do
    if line:find(" " .. name .. " ", 1, true) then
      local stop = line:find("▌", 1, true) or line:find("█", 1, true)
      return line:sub(1, stop - 1)
    end
  end
end

test("columnplus: a strip, arrow folds, the clip counts and a sign for takes, and \\z changes the folds", function()
  local t = song()
  local screen = api.ui_snapshot(100, 24)
  eq(column("Drums", screen), "▎  1  2 ", "the strip, the number, no sign, two clips")
  eq(column("Strings", screen), "▎▿ 2    ", "the folds at the left, with arrows")
  eq(column("Cellos", screen), "▎└ 4    ", "the last member")
  eq(column("Keys", screen), "▎  5 ≡1 ", "the sign of takes")
  paw.keymap.feed("\\z")
  eq(column("Strings"), "▎- 2    ", "\\z: the next look, plus")
  paw.keymap.feed("\\z")
  eq(column("Strings"), "▎▾ 2    ", "then paw's own glyphs")
  paw.keymap.feed("\\#")
  eq(column("Drums"), "▎  1  ", "\\# hides the clip counts")
  paw.cursor.set_track(t[4])
  paw.keymap.feed("K")
  local text = table.concat(api.ui_snapshot(100, 30), "\n")
  while paw.ui.float do
    paw.ui.close()
  end
  eq(text:find("takes on 1 clip", 1, true) ~= nil, true, "K says what the sign means:\n" .. text)
end)

test("columnplus: a frozen track has its sign, which K explains", function()
  local t = song()
  api.track_set(t[1].id, { meta = { frozen = { file = "drums.wav" } } })
  paw.flush()
  eq(column("Drums"), "▎  1 ∗2 ", "the frozen sign")
  paw.keymap.feed("K")
  local text = table.concat(api.ui_snapshot(100, 30), "\n")
  while paw.ui.float do
    paw.ui.close()
  end
  eq(text:find("frozen: it plays its file", 1, true) ~= nil, true, "K says it:\n" .. text)
end)

test("columnplus: :ext.unload puts the column back as it was", function()
  T.fresh()
  local before = api.ui_snapshot(100, 24)
  local parts, signs = {}, {}
  for k, v in pairs(paw.trackcolumn.components:entries()) do
    parts[k] = v
  end
  for k, v in pairs(paw.trackcolumn.signs:entries()) do
    signs[k] = v
  end
  local shown = table.concat(paw.opt.trackcolumn, ",")
  paw.ext.load("extensions/columnplus")
  paw.keymap.feed(":set columnplus_foldfirst=false<CR>:columnplus.folds plus<CR>")
  paw.keymap.feed(":ext.unload columnplus<CR>")
  for k, v in pairs(parts) do
    eq(paw.trackcolumn.components:get(k), v, "the part " .. k)
  end
  for k in pairs(paw.trackcolumn.components:entries()) do
    eq(parts[k] ~= nil, true, "no part left: " .. k)
  end
  for k in pairs(paw.trackcolumn.signs:entries()) do
    eq(signs[k] ~= nil, true, "no sign left: " .. k)
  end
  eq(table.concat(paw.opt.trackcolumn, ","), shown, "paw.opt.trackcolumn")
  -- The screen, but for the message line at the bottom.
  local now = api.ui_snapshot(100, 24)
  for i = 1, 22 do
    eq(now[i], before[i], "the line " .. i .. " of the screen")
  end
end)
