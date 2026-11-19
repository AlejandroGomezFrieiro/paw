-- Tests of the file manager (paw/views/files.lua): a folder as lines to
-- edit, the plan `:w` shows for renaming, moving, making, copying and
-- deleting (to the trash), the tree, placing sound files and hearing them,
-- and the project's media folder. Only a scratch folder is touched.
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh, after = T.test, T.eq, T.fresh, T.after
local api = paw.api
local L = paw.layout
local tb = paw.textbuf

local W, H = 160, 48
local initial = L.capture()
local root = T.scratch .. "/files"

local function sh(cmd) os.execute(cmd) end

--- The windows and buffers a test opened go when it ends.
local function tidy()
  paw.audition.stop()
  paw.opt.files_hear = false
  while paw.ui.float do paw.ui.close() end
  L.restore(initial)
  for _, buf in ipairs(L.buffers_list()) do
    if buf.type == "textbuf" then L.buf_delete(buf) end
  end
end

local function start()
  fresh()
  after(tidy)
  api.engine_restart({ backend = "null" })
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do paw.ui.close() end
  L.restore(initial)
  paw.ui.focus("arrange")
  for _, buf in ipairs(L.buffers_list()) do
    if buf.type == "textbuf" then L.buf_delete(buf) end
  end
  paw.audition.stop()
  paw.opt.files_hear = false
  paw.opt.files_hidden = false
  sh("rm -rf '" .. root .. "' && mkdir -p '" .. root .. "/songs' '" .. root .. "/samples'")
  sh("cp tests/fixtures/tone-stereo-44k.mp3 '" .. root .. "/samples/pad.mp3'")
  sh("cp tests/fixtures/tone-mono-8k.wav '" .. root .. "/kick.wav'")
  sh("cp tests/fixtures/shape.wav '" .. root .. "/samples/shape.wav'")
  sh("printf 'notes' > '" .. root .. "/notes.txt'")
  sh("printf 'x' > '" .. root .. "/.hidden'")
end

local keys = T.keys

local function screen() return table.concat(api.ui_snapshot(W, H), "\n") end

local function lines()
  local out = {}
  for i, l in ipairs(tb.buf().state.text.lines) do out[i] = l.text end
  return out
end

local function row_of(name)
  for i, text in ipairs(lines()) do
    if text:match("^%s*" .. name:gsub("%p", "%%%0") .. "[/%s]") or text:match("^%s*" .. name:gsub("%p", "%%%0") .. "$") then return i end
  end
  error("no line for " .. name .. ":\n" .. table.concat(lines(), "\n"), 2)
end

--- Change a line's text, as typing would.
local function edit(row, text)
  local t = tb.buf().state.text
  t:begin(row, 0)
  t:set(row, text)
  t:finish()
end

local function exists(path) return api.fs_stat(path) ~= nil end

--- The steps `:w` would take, as text; the plan is not shown or applied.
local function plan_of()
  local steps, err = tb.plan(tb.buf())
  if not steps then return nil, err end
  local out = {}
  for _, s in ipairs(steps) do if not s.quiet then out[#out + 1] = s.text end end
  return table.concat(out, "\n")
end

--- `:w` and `y`: the plan shown, then applied.
local function write()
  keys(":w<CR>")
  eq(paw.ui.focused, "textbuf.plan", "the plan is shown")
  local shown = {}
  for _, step in ipairs(paw.ui.views["textbuf.plan"].shown) do shown[#shown + 1] = step.text end
  keys("y")
  return table.concat(shown, "\n")
end

local function open(dir) keys(":e " .. dir .. "<CR>") end

local function wait_for(cond, ms)
  local limit = api.now() + (ms or 5000)
  while not cond() and api.now() < limit do paw.wait(10) end
  return cond() and true or false
end

local function trash_dir() return os.getenv("XDG_DATA_HOME") .. "/Trash" end

-- Reading ---------------------------------------------------------------------

test("files: a folder is a buffer: folders first, then files, with what a sound file's header says", function()
  start()
  open(root)
  eq(tb.buf().name, "paw://files" .. root, "named by its folder")
  local text = lines()
  eq(text[1]:match("^samples/") ~= nil, true, "folders first: " .. text[1])
  eq(text[2]:match("^songs/") ~= nil, true, "in order: " .. text[2])
  local kick = text[row_of("kick.wav")]
  eq(kick:find("1ch", 1, true) ~= nil and kick:find("8k", 1, true) ~= nil, true, "kick.wav is mono at 8 kHz: " .. kick)
  eq(kick:match("%d+%.%ds") ~= nil, true, "with its length: " .. kick)
  eq(text[row_of("notes.txt")]:find("5B", 1, true) ~= nil, true, "a text file has its size only")
  eq(table.concat(text, "\n"):find(".hidden", 1, true), nil, "files with a dot are left out")
  keys("g.")
  eq(table.concat(lines(), "\n"):find(".hidden", 1, true) ~= nil, true, "`g.` shows them")
  keys("g.")
  eq(table.concat(lines(), "\n"):find(".hidden", 1, true), nil, "and hides them again")
end)

test("files: paw started with a folder that is no project lists it, as `:e` does", function()
  start()
  paw.open(root .. "/samples")  -- what `paw <path>` runs
  eq(tb.buf().name, "paw://files" .. root .. "/samples", "the folder is the buffer")
end)

test("files: a line left alone is no change, and `-` goes up and Enter goes in", function()
  start()
  open(root .. "/samples")
  eq(plan_of(), "", "nothing to do")
  keys("-")
  eq(tb.buf().name, "paw://files" .. root, "up")
  keys("gg<CR>")
  eq(tb.buf().name, "paw://files" .. root .. "/samples", "Enter on a folder goes in")
  eq(screen():find("pad.mp3", 1, true) ~= nil, true, "and shows what is in it")
  eq(lines()[row_of("pad.mp3")]:find("2ch", 1, true) ~= nil, true, "the mp3 is read too")
end)

-- Writing ---------------------------------------------------------------------

test("files: a name changed is a rename, in the plan, and one `y` does it", function()
  start()
  open(root)
  edit(row_of("kick.wav"), "kick-old.wav")
  eq(plan_of(), "rename kick.wav → kick-old.wav", "the plan says what it will do")
  eq(exists(root .. "/kick.wav"), true, "nothing is done before it is applied")
  local shown = write()
  eq(shown, "rename kick.wav → kick-old.wav", "shown")
  eq(exists(root .. "/kick.wav"), false, "the old name is gone")
  eq(exists(root .. "/kick-old.wav"), true, "the new one is there")
  eq(row_of("kick-old.wav") > 0, true, "and the buffer reads it again")
end)

test("files: a path in the name moves the file, making the folders it needs", function()
  start()
  open(root)
  edit(row_of("kick.wav"), "songs/drums/kick.wav")
  eq(plan_of(), "move kick.wav → songs/drums/kick.wav", "a move")
  write()
  eq(exists(root .. "/songs/drums/kick.wav"), true, "moved")
  eq(exists(root .. "/kick.wav"), false, "from where it was")
  open(root .. "/samples")
  edit(row_of("pad.mp3"), "../pad.mp3")
  write()
  eq(exists(root .. "/pad.mp3"), true, "`..` goes up")
end)

test("files: new lines make files and folders, and a copied line copies the file", function()
  start()
  open(root)
  local t = tb.buf().state.text
  t:insert_lines(1, { { text = "fresh.txt" }, { text = "newdir/" }, { text = "newdir/inside.txt" } })
  local k = row_of("kick.wav")
  t:insert_lines(k + 1, { { text = "kick-copy.wav", id = t.lines[k].id } })
  local shown = plan_of()
  eq(shown:find("new file fresh.txt", 1, true) ~= nil, true, "a file: " .. shown)
  eq(shown:find("new folder newdir/", 1, true) ~= nil, true, "a folder")
  eq(shown:find("new file newdir/inside.txt", 1, true) ~= nil, true, "a file in it")
  eq(shown:find("copy kick.wav → kick-copy.wav", 1, true) ~= nil, true, "a copy")
  write()
  eq(exists(root .. "/fresh.txt"), true, "the file is made")
  eq((api.fs_stat(root .. "/newdir") or {}).dir, true, "the folder is made")
  eq(exists(root .. "/newdir/inside.txt"), true, "and what is in it")
  eq((api.fs_stat(root .. "/kick-copy.wav") or {}).size, (api.fs_stat(root .. "/kick.wav") or {}).size, "the copy is the same size")
  eq(exists(root .. "/kick.wav"), true, "and the original stays")
end)

test("files: a deleted line moves the file to the trash, where it can be taken back from", function()
  start()
  -- The trash outlives a run, so what is put in it has a name of its own.
  local name = "gone-" .. T.scratch:match("(%d+-%d+)$")
  sh("cp '" .. root .. "/kick.wav' '" .. root .. "/" .. name .. ".wav'")
  open(root)
  local before = (api.fs_stat(root .. "/kick.wav") or {}).size
  keys(":" .. row_of(name .. ".wav") .. "<CR>dd")
  local shown = write()
  eq(shown, "delete " .. name .. ".wav (to the trash)", "the plan says the trash")
  eq(exists(root .. "/" .. name .. ".wav"), false, "gone from the folder")
  eq((api.fs_stat(trash_dir() .. "/files/" .. name .. ".wav") or {}).size, before, "in the trash")
  local info = io.open(trash_dir() .. "/info/" .. name .. ".wav.trashinfo"):read("*a")
  eq(info:find("[Trash Info]", 1, true) ~= nil, true, "with the record the desktop needs")
  eq(info:find("Path=" .. root .. "/" .. name .. ".wav", 1, true) ~= nil, true, "of where it was")
  -- A second file of the same name does not take the first one's place.
  sh("printf 'again' > '" .. root .. "/" .. name .. ".wav'")
  keys(":e!<CR>")
  keys(":" .. row_of(name .. ".wav") .. "<CR>dd")
  write()
  eq(exists(trash_dir() .. "/files/" .. name .. ".2.wav"), true, "it gets a name of its own")
end)

test("files: nothing is written over: a name taken, two lines for one name, a folder into itself", function()
  start()
  open(root)
  edit(row_of("kick.wav"), "notes.txt")
  local plan, err = plan_of()
  eq(plan, nil, "refused")
  eq(err:find("is there already", 1, true) ~= nil, true, "says why: " .. tostring(err))
  keys(":e!<CR>")
  local t = tb.buf().state.text
  t:insert_lines(1, { { text = "same.txt" }, { text = "same.txt" } })
  plan, err = plan_of()
  eq(plan, nil, "two lines of one name")
  eq(err:find("two lines make", 1, true) ~= nil, true, tostring(err))
  keys(":e!<CR>")
  edit(row_of("samples"), "samples/inner/samples/")
  plan, err = plan_of()
  eq(plan, nil, "a folder cannot go inside itself")
  eq(err:find("inside itself", 1, true) ~= nil, true, tostring(err))
  eq(exists(root .. "/kick.wav") and exists(root .. "/notes.txt"), true, "and nothing was touched")
end)

test("files: two names swapped go by way of a temporary name", function()
  start()
  open(root)
  local a, b = row_of("kick.wav"), row_of("notes.txt")
  edit(a, "notes.txt")
  edit(b, "kick.wav")
  local shown = write()
  eq(shown:find("rename kick.wav → notes.txt", 1, true) ~= nil, true, "the plan has the two renames: " .. shown)
  eq(io.open(root .. "/kick.wav"):read("*a"), "notes", "kick.wav is what notes.txt was")
  eq(#io.open(root .. "/notes.txt"):read("*a") > 5, true, "and the other way")
end)

test("files: a plan that fails partway takes back what it did", function()
  start()
  sh("mkdir -p '" .. root .. "/locked' && chmod 555 '" .. root .. "/locked'")
  open(root)
  edit(row_of("kick.wav"), "kick-new.wav")
  local t = tb.buf().state.text
  t:insert_lines(1, { { text = "locked/inside.txt" } })
  keys(":w<CR>")
  keys("y")
  sh("chmod 755 '" .. root .. "/locked'")
  eq(exists(root .. "/kick.wav"), true, "the rename was taken back")
  eq(exists(root .. "/kick-new.wav"), false, "so the new name is not there")
  eq(exists(root .. "/locked/inside.txt"), false, "and nothing was made")
end)

-- The tree -----------------------------------------------------------------------

test("files: a tree opens folders in place with Enter, and editing it works at each depth", function()
  start()
  keys(":files.tree " .. root .. "<CR>")
  eq(tb.buf().name, "paw://tree" .. root, "a tree buffer")
  local rows = lines()
  eq(rows[row_of("samples")]:match("^samples/") ~= nil, true, "folders closed at first")
  eq(table.concat(rows, "\n"):find("pad.mp3", 1, true), nil, "what is in them is not shown")
  keys(":" .. row_of("samples") .. "<CR><CR>")
  rows = lines()
  eq(rows[row_of("pad.mp3")]:match("^  pad.mp3") ~= nil, true, "opened, and indented: " .. table.concat(rows, "\n"))
  -- Rename what is in the folder, and make a file in it by its indent.
  edit(row_of("pad.mp3"), "  pad-2.mp3")
  local t = tb.buf().state.text
  t:insert_lines(row_of("pad-2.mp3"), { { text = "  made.txt" } })
  local shown = write()
  eq(shown:find("rename samples/pad.mp3 → samples/pad-2.mp3", 1, true) ~= nil, true, "a rename inside: " .. shown)
  eq(shown:find("new file samples/made.txt", 1, true) ~= nil, true, "a file in the folder above it")
  eq(exists(root .. "/samples/pad-2.mp3") and exists(root .. "/samples/made.txt"), true, "done")
  -- A line taken out to the left is moved up a folder.
  keys(":" .. row_of("made.txt") .. "<CR>")
  edit(row_of("made.txt"), "made.txt")
  eq(plan_of():find("move samples/made.txt → made.txt", 1, true) ~= nil, true, "less indent is a move up")
  keys(":e!<CR>zM")
  eq(table.concat(lines(), "\n"):find("pad-2", 1, true), nil, "`zM` closes every folder")
  keys("zR")
  eq(table.concat(lines(), "\n"):find("pad-2", 1, true) ~= nil, true, "`zR` opens them")
end)

-- Placing and hearing -------------------------------------------------------------------

test("files: Enter on a sound file places it at the cursor's track and time, `go` on a new track", function()
  start()
  local lead = paw.add_track({ name = "Lead" })
  paw.flush()
  paw.cursor.set_track(lead)
  paw.cursor.set_beat(8)
  open(root)
  local before = #api.track_list()
  keys(":" .. row_of("kick.wav") .. "<CR><CR>")
  eq(#api.track_list(), before, "no new track")
  local clips = lead:clips()
  eq(#clips, 1, "a clip on the cursor's track")
  eq(clips[1].start, 8, "at the cursor's time")
  eq(clips[1].file:match("kick.wav$") ~= nil, true, "of the file")
  keys("go")
  eq(#api.track_list(), before + 1, "`go` made a track")
  eq(paw.cursor.track().name, "kick", "named after the file")
end)

test("files: a sound file is heard with gh, and as the cursor rests on it when asked", function()
  start()
  open(root)
  keys(":" .. row_of("kick.wav") .. "<CR>gh")
  eq(wait_for(function() local s = paw.audition.state() return s and s.kind == "file" and s.file:match("kick.wav$") end), true, "gh plays it")
  paw.audition.stop()
  paw.opt.files_hear = true
  keys(":" .. row_of("notes.txt") .. "<CR>")
  paw.wait(300)
  eq(paw.audition.state(), nil, "a text file makes no sound")
  keys(":" .. row_of("kick.wav") .. "<CR>")
  eq(wait_for(function() local s = paw.audition.state() return s and s.kind == "file" end), true, "it plays when the cursor has rested")
  keys(":" .. row_of("notes.txt") .. "<CR>")
  eq(wait_for(function() return paw.audition.state() == nil end), true, "and stops when it moves on")
  paw.opt.files_hear = false
end)

-- The project's media folder ---------------------------------------------------------------

test("files: the media folder marks what no clip plays, and `:media.unused` lists only that", function()
  start()
  local song = T.scratch .. "/files-song"
  sh("rm -rf '" .. song .. "' && mkdir -p '" .. song .. "/media'")
  sh("cp tests/fixtures/tone-mono-8k.wav '" .. song .. "/media/used.wav'")
  sh("cp tests/fixtures/shape.wav '" .. song .. "/media/spare-" .. T.scratch:match("(%d+-%d+)$") .. ".wav'")
  local t = paw.add_track({ name = "Take" })
  t:add_clip({ start = 0, file = song .. "/media/used.wav" })
  paw.flush()
  paw.project.save(song .. "/song.json")
  keys(":files media<CR>")
  eq(tb.buf().name, "paw://files" .. song .. "/media", "`:files media` is the project's folder")
  eq(lines()[row_of("spare-" .. T.scratch:match("(%d+-%d+)$") .. ".wav")]:find("unused", 1, true) ~= nil, true, "the spare file is marked")
  eq(lines()[row_of("used.wav")]:find("unused", 1, true), nil, "the one a clip plays is not")
  keys(":media.unused<CR>")
  eq(#lines(), 1, "only the unused file is listed: " .. table.concat(lines(), "\n"))
  keys("dd")
  write()
  local spare = "spare-" .. T.scratch:match("(%d+-%d+)$") .. ".wav"
  eq(exists(song .. "/media/" .. spare), false, "deleted")
  eq(exists(song .. "/media/used.wav"), true, "and the other is not touched")
  eq(exists(trash_dir() .. "/files/" .. spare), true, "to the trash")
end)

test("files: `:help files` is the page that says how the file manager works", function()
  start()
  paw.cmd("help", { "files" })
  local win = L.current()
  local buf = L.buf_of(win)
  eq(buf.name, "help://file-manager.md", "in the file manager's page")
  local _, _, t, st = tb.here()
  eq(t:line(st.row):find("paw shows a folder as text", 1, true) ~= nil, true, "at the first paragraph: " .. t:line(st.row))
end)
