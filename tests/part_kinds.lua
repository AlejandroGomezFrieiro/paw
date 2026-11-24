-- Tests of kinds of part (paw.part_kinds): how one is defined, made, shown,
-- opened, saved, and what is left of it without its extension. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local function screen() return table.concat(api.ui_snapshot(120, 30), "\n") end

--- A kind of part for the test: a synth on it, and its clips opened by
--- the kind's editor, which says so.
local function define()
  local opened = {}
  paw.part_kinds.define("bleep", {
    title = "Bleep part",
    letter = "B",
    desc = "a synth that bleeps",
    create = function(part, args)
      part:add_device("synth")
      if args.words[1] then part.name = "Bleep " .. args.words[1] end
    end,
    editor = function(clip)
      opened[#opened + 1] = clip.id
      return true
    end,
    describe = function(id) return "bleeping on " .. #paw.part(id):devices() .. " device" end,
  })
  return opened
end

test("a kind of part is made by part.add and from the list of kinds, and says what it is", function()
  fresh()
  local opened = define()
  paw.ui.focus("arrange")
  local part = paw.cmd("part.add", { "bleep", "loud" })
  eq(part.name, "Bleep loud", "made by the kind, with the words after it")
  eq(part:devices()[1].kind, "synth", "and its device")
  eq(paw.part_kinds.of(part.id), "bleep", "the part is of the kind")
  eq(part.meta.kind, "bleep", "kept on the part")
  eq(paw.cursor.part_id(), part.id, "the cursor goes to it")
  eq(
    screen():find(" B Bleep loud", 1, true) ~= nil,
    true,
    "the header shows the kind's letter before the name, a column clear of it"
  )
  -- K says what it is.
  paw.cmd("info")
  eq(screen():find("kind    Bleep part · bleeping on 1 device", 1, true) ~= nil, true, "K says the kind")
  paw.keymap.feed("<Esc>")
  -- Enter on its clips is the kind's editor; other parts' go to the piano roll.
  local clip = part:add_clip({ start = 0, length = 4 })
  paw.cursor.set_beat(1)
  paw.ui.focus("arrange")
  paw.cmd("clip.edit")
  eq(opened[1], clip.id, "clip.edit opens the kind's editor")
  paw.frontend.act.open_clip(clip.id)
  eq(opened[2], clip.id, "and so does a double click in the window")
  -- The list of kinds.
  paw.ui.focus("arrange")
  paw.cmd("part.new")
  eq(paw.ui.float and paw.ui.float.name, "pick", "part.new offers a list")
  paw.keymap.feed("bleep<CR>")
  eq(paw.part_kinds.of(paw.cursor.part_id()), "bleep", "and makes the kind chosen")
  -- The window's menus that make a part offer it.
  local found
  for _, entry in ipairs(paw.frontend.menus.timeline) do
    if entry.label == "New bleep part" then found = entry end
  end
  eq(found and found.command, "part.add kind=bleep", "the window offers a new bleep part")
  local frontend_part
  for _, t in ipairs(paw.frontend.state(-1).parts or {}) do
    if t.id == part.id then frontend_part = t end
  end
  eq(frontend_part and frontend_part.kind, "Bleep part · bleeping on 1 device", "and shows the kind in the header")
end)

test("a kind of part is saved with the part, and without its extension the part is an ordinary one", function()
  fresh()
  local opened = define()
  local part = paw.part_kinds.add("bleep", { words = {} })
  part:add_clip({ start = 0, length = 4 })
  local path = paw.project.save(T.scratch .. "/kinds.json")
  fresh()
  paw.project.load(path)
  part = paw.parts()[1]
  eq(paw.part_kinds.of(part.id), "bleep", "the kind comes back with the project")
  -- As if the extension that defines it were not loaded.
  local spec = paw.part_kinds.kinds:remove("bleep")
  eq(paw.part_kinds.describe(part.id), "bleep (no extension here defines it)", "K says what it was")
  paw.cursor.set_part(part)
  paw.cursor.set_beat(1)
  paw.ui.focus("arrange")
  paw.cmd("clip.edit")
  eq(paw.ui.focused, "pianoroll", "its clips open in the piano roll")
  eq(#opened, 0, "not in the kind's editor")
  paw.part_kinds.kinds:put("bleep", spec)
  paw.ui.focus("arrange")
  paw.part_kinds.clear(part)
  eq(paw.part_kinds.of(part.id), nil, "a part made ordinary again")
  T.fails(function() paw.part_kinds.add("nothing") end, "no kind of part `nothing`", "an unknown kind")
end)
