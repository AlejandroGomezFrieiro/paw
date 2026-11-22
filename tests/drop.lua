-- Files from outside the window: dropped on it, or chosen in the desktop's
-- own dialog. What either means is decided here, for the window to pass on.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local act = paw.frontend.act

--- A short sound file called `name` in a folder whose name has a space in it.
local function sound(name)
  os.execute("mkdir -p '" .. T.scratch .. "/some where'")
  local s = {}
  for i = 1, 4800 do s[i] = 0.25 end
  return T.write_wav(T.scratch .. "/some where/" .. name, s)
end

local function start()
  fresh()
  paw.opt.grid = 1
  paw.add_track({ name = "a" })
  paw.add_track({ name = "b" })
  paw.flush()
end

test("a sound file dropped on a track's lane is a clip there, at the beat on the grid", function()
  start()
  local path = sound("kick.wav")
  local out = act.drop({ path }, 2, 3.4)
  eq(#out.clips, 1, "one clip")
  local clip = paw.clip(out.clips[1])
  eq(clip:track().id, paw.tracks()[2].id, "on the second track")
  eq(clip.start, 3, "at the beat under the pointer, snapped")
  eq(#paw.tracks(), 2, "and no track made")
end)

test("several sound files dropped on a lane go one after another on that track", function()
  start()
  local out = act.drop({ sound("one.wav"), sound("two.wav") }, 1, 8)
  eq(#out.clips, 2, "two clips")
  local first, second = paw.clip(out.clips[1]), paw.clip(out.clips[2])
  eq(first:track().id, second:track().id, "on the same track")
  eq(second.start, first.start + first.length, "the second where the first ends")
  eq(#paw.tracks(), 2, "no track made")
end)

test("sound files dropped below the tracks, or where the window cannot tell, get tracks of their own", function()
  start()
  local out = act.drop({ sound("one.wav"), sound("two.wav") }, 3, 4)
  eq(#out.clips, 2, "two clips")
  eq(#paw.tracks(), 4, "each on a new track")
  eq(paw.clip(out.clips[1]).start, 4, "at the beat")
  act.drop({ sound("three.wav") })
  eq(#paw.tracks(), 5, "a drop with no place is a new track too")
end)

test("a dropped project is handed back to be opened, and anything else is refused in words", function()
  start()
  local out = act.drop({ "/x/song.json", sound("kick.wav") })
  eq(out.open, "/x/song.json", "the project is to be opened")
  eq(#out.clips, 0, "and the sound dropped with it waits")
  eq(#paw.tracks(), 2, "nothing was added")
  out = act.drop({ "/x/notes.txt" })
  eq(out.refused, 1, "one refused")
  eq(paw.ui.message.text:find("notes.txt", 1, true) ~= nil, true, "the status line names it")
  eq(paw.ui.message.text:find("not a sound file, a MIDI file or a project", 1, true) ~= nil, true, "and says why")
end)

test("a file chosen in the desktop's dialog is imported or saved to as it is, spaces and all", function()
  start()
  local path = sound("take one.wav")
  act.chosen("import", path)
  eq(#paw.tracks(), 3, "a track for the sound file")
  eq(paw.tracks()[paw.cursor.index()]:clips()[1].file, path, "playing that file, on the track the cursor went to")
  eq(paw.state.pick_dir, T.scratch .. "/some where", "the list picker starts where it was chosen")
  local project = T.scratch .. "/some where/my song"
  act.chosen("saveas", project)
  eq(#T.read_file(project .. "/project.toml") > 10, true, "saved as the folder of that name")
end)

test("a project chosen in the dialog opens through the leave question", function()
  start()
  local path = T.scratch .. "/some where/other.json"
  paw.project.save(path)
  paw.add_track({ name = "c" })
  paw.project.new()
  eq(#paw.tracks(), 0, "an empty project")
  act.leave("go", "open:" .. path)
  eq(#paw.tracks(), 2, "the project with a space in its path opened")
end)

test("the dialog option and where to start are what the window is told", function()
  start()
  eq(paw.frontend.dialog_info().native, true, "on by default")
  eq(paw.frontend.dialog_info().render[1], "flac", "with the endings a render can write")
  paw.opt.native_dialogs = false
  eq(paw.frontend.dialog_info().native, false, "and off when asked")
  paw.opt.native_dialogs = true
  paw.state.pick_dir = "/tmp"
  eq(paw.frontend.dialog_info().dir, "/tmp", "starting where a file was last chosen")
end)
