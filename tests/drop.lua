-- Files from outside the window: dropped on it, or chosen in the desktop's
-- own dialog. What either means is decided here, for the window to pass on.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local act = paw.frontend.act

--- A folder whose name has a space in it, made if it is not there.
local function some_where()
  local dir = T.scratch .. "/some where"
  os.execute("mkdir -p '" .. dir .. "'")
  return dir
end

--- A short sound file called `name` in the folder with a space.
local function sound(name)
  local s = {}
  for i = 1, 4800 do
    s[i] = 0.25
  end
  return T.write_wav(some_where() .. "/" .. name, s)
end

local function start()
  fresh()
  paw.opt.grid = 1
  paw.add_part({ name = "a" })
  paw.add_part({ name = "b" })
  paw.flush()
end

test("a sound file dropped on a part's lane is a clip there, at the beat on the grid", function()
  start()
  local path = sound("kick.wav")
  local out = act.drop({ path }, 2, 3.4)
  eq(#out.clips, 1, "one clip")
  local clip = paw.clip(out.clips[1])
  eq(clip:part().id, paw.parts()[2].id, "on the second part")
  eq(clip.start, 3, "at the beat under the pointer, snapped")
  eq(#paw.parts(), 2, "and no part made")
end)

test("several sound files dropped on a lane go one after another on that part", function()
  start()
  local out = act.drop({ sound("one.wav"), sound("two.wav") }, 1, 8)
  eq(#out.clips, 2, "two clips")
  local first, second = paw.clip(out.clips[1]), paw.clip(out.clips[2])
  eq(first:part().id, second:part().id, "on the same part")
  eq(second.start, first.start + first.length, "the second where the first ends")
  eq(#paw.parts(), 2, "no part made")
end)

test("sound files dropped below the parts, or where the window cannot tell, get parts of their own", function()
  start()
  local out = act.drop({ sound("one.wav"), sound("two.wav") }, 3, 4)
  eq(#out.clips, 2, "two clips")
  eq(#paw.parts(), 4, "each on a new part")
  eq(paw.clip(out.clips[1]).start, 4, "at the beat")
  act.drop({ sound("three.wav") })
  eq(#paw.parts(), 5, "a drop with no place is a new part too")
end)

test("a dropped project is handed back to be opened, and anything else is refused in words", function()
  start()
  local out = act.drop({ "/x/song.json", sound("kick.wav") })
  eq(out.open, "/x/song.json", "the project is to be opened")
  eq(#out.clips, 0, "and the sound dropped with it waits")
  eq(#paw.parts(), 2, "nothing was added")
  out = act.drop({ "/x/notes.txt" })
  eq(out.refused, 1, "one refused")
  eq(paw.ui.message.text:find("notes.txt", 1, true) ~= nil, true, "the status line names it")
  eq(paw.ui.message.text:find("not a sound file, a MIDI file or a project", 1, true) ~= nil, true, "and says why")
end)

test("a file chosen in the desktop's dialog is imported or saved to as it is, spaces and all", function()
  start()
  local path = sound("take one.wav")
  act.chosen("import", path)
  eq(#paw.parts(), 3, "a part for the sound file")
  eq(paw.parts()[paw.cursor.index()]:clips()[1].file, path, "playing that file, on the part the cursor went to")
  local project = T.scratch .. "/some where/my song"
  act.chosen("saveas", project)
  eq(#T.read_file(project .. "/project.toml") > 10, true, "saved as the folder of that name")
end)

test("a project chosen in the dialog opens through the leave question", function()
  start()
  local path = some_where() .. "/other.json"
  paw.project.save(path)
  paw.add_part({ name = "c" })
  paw.project.new()
  eq(#paw.parts(), 0, "an empty project")
  act.leave("go", "open:" .. path)
  eq(#paw.parts(), 2, "the project with a space in its path opened")
end)

test("the dialog option and where to start are what the window is told", function()
  start()
  eq(paw.frontend.dialog_info().native, true, "on by default")
  eq(paw.frontend.dialog_info().render[1], "flac", "with the endings a render can write")
  paw.opt.native_dialogs = false
  eq(paw.frontend.dialog_info().native, false, "and off when asked")
  paw.opt.native_dialogs = true
  eq(paw.frontend.dialog_info().dir, paw.files.here(), "starting in the folder for relative names")
end)
