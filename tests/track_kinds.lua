-- Tests of kinds of track (paw.track_kinds): how one is defined, made, shown,
-- opened, saved, and what is left of it without its extension. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local function screen() return table.concat(api.ui_snapshot(120, 30), "\n") end

--- A kind of track for the test: a synth on it, and its clips opened by
--- the kind's editor, which says so.
local function define()
  local opened = {}
  paw.track_kinds.define("bleep", {
    title = "Bleep track",
    letter = "B",
    desc = "a synth that bleeps",
    create = function(track, args)
      track:add_device("synth")
      if args.words[1] then track.name = "Bleep " .. args.words[1] end
    end,
    editor = function(clip)
      opened[#opened + 1] = clip.id
      return true
    end,
    describe = function(id) return "bleeping on " .. #paw.track(id):devices() .. " device" end,
  })
  return opened
end

test("a kind of track is made by track.add and from the list of kinds, and says what it is", function()
  fresh()
  local opened = define()
  paw.ui.focus("arrange")
  local track = paw.cmd("track.add", { "bleep", "loud" })
  eq(track.name, "Bleep loud", "made by the kind, with the words after it")
  eq(track:devices()[1].kind, "synth", "and its device")
  eq(paw.track_kinds.of(track.id), "bleep", "the track is of the kind")
  eq(track.meta.kind, "bleep", "kept on the track")
  eq(paw.cursor.track_id(), track.id, "the cursor goes to it")
  eq(
    screen():find(" B Bleep loud", 1, true) ~= nil,
    true,
    "the header shows the kind's letter before the name, a column clear of it"
  )
  -- K says what it is.
  paw.cmd("info")
  eq(screen():find("kind    Bleep track · bleeping on 1 device", 1, true) ~= nil, true, "K says the kind")
  paw.keymap.feed("<Esc>")
  -- Enter on its clips is the kind's editor; other tracks' go to the piano roll.
  local clip = track:add_clip({ start = 0, length = 4 })
  paw.cursor.set_beat(1)
  paw.ui.focus("arrange")
  paw.cmd("clip.edit")
  eq(opened[1], clip.id, "clip.edit opens the kind's editor")
  paw.frontend.act.open_clip(clip.id)
  eq(opened[2], clip.id, "and so does a double click in the window")
  -- The list of kinds.
  paw.ui.focus("arrange")
  paw.cmd("track.new")
  eq(paw.ui.float and paw.ui.float.name, "pick", "track.new offers a list")
  paw.keymap.feed("bleep<CR>")
  eq(paw.track_kinds.of(paw.cursor.track_id()), "bleep", "and makes the kind chosen")
  -- The window's menus that make a track offer it.
  local found
  for _, entry in ipairs(paw.frontend.menus.timeline) do
    if entry.label == "New bleep track" then found = entry end
  end
  eq(found and found.command, "track.add kind=bleep", "the window offers a new bleep track")
  local frontend_track
  for _, t in ipairs(paw.frontend.state(-1).tracks or {}) do
    if t.id == track.id then frontend_track = t end
  end
  eq(frontend_track and frontend_track.kind, "Bleep track · bleeping on 1 device", "and shows the kind in the header")
end)

test("a kind of track is saved with the track, and without its extension the track is an ordinary one", function()
  fresh()
  local opened = define()
  local track = paw.track_kinds.add("bleep", { words = {} })
  track:add_clip({ start = 0, length = 4 })
  local path = paw.project.save(T.scratch .. "/kinds.json")
  fresh()
  paw.project.load(path)
  track = paw.tracks()[1]
  eq(paw.track_kinds.of(track.id), "bleep", "the kind comes back with the project")
  -- As if the extension that defines it were not loaded.
  local spec = paw.track_kinds.kinds.bleep
  paw.track_kinds.kinds.bleep = nil
  eq(paw.track_kinds.describe(track.id), "bleep (no extension here defines it)", "K says what it was")
  paw.cursor.set_track(track)
  paw.cursor.set_beat(1)
  paw.ui.focus("arrange")
  paw.cmd("clip.edit")
  eq(paw.ui.focused, "pianoroll", "its clips open in the piano roll")
  eq(#opened, 0, "not in the kind's editor")
  paw.track_kinds.kinds.bleep = spec
  paw.ui.focus("arrange")
  paw.track_kinds.clear(track)
  eq(paw.track_kinds.of(track.id), nil, "a track made ordinary again")
  T.fails(function() paw.track_kinds.add("nothing") end, "no kind of track `nothing`", "an unknown kind")
end)
