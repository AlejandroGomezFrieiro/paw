-- The how-to guides of the user guide about projects and files, each driven
-- with the keys and commands that it gives (docs/how-to/save-and-open-projects.md,
-- import-audio-and-midi-files.md, use-track-templates.md). Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local keys = T.keys

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

local function dir(name)
  local d = T.scratch .. "/" .. name
  os.execute("mkdir -p '" .. d .. "'")
  return d
end

test("guide: save, back up and open projects", function()
  start()
  local d = dir("projects")
  paw.recent.use(d .. "/recent.json")
  T.after(function() paw.recent.use() end)
  T.tone("Lead", 8)
  paw.ui.focus("arrange")
  keys(":w " .. d .. "/song<CR>")
  eq(exists(d .. "/song/project.toml"), true, ":w song saves the project as the folder song")
  eq(paw.project.unsaved(), false, "with nothing left to save")
  keys("3-")
  eq(paw.project.unsaved(), true, "an edit is not saved")
  keys(":w<CR>")
  eq(paw.project.unsaved(), false, ":w saves the edit")
  keys(":new<CR>")
  eq(#paw.tracks() .. " " .. tostring(paw.project.path), "0 nil", ":new starts an empty project")
  T.tone("Bass", 4)
  keys(":w " .. d .. "/second<CR>")
  keys("<Space>pr")
  eq(paw.ui.float ~= nil, true, "Space pr lists the recent projects")
  keys("song<CR>")
  eq(paw.project.path, d .. "/song/project.toml", "and opens the one chosen")
  keys(":recent 2<CR>")
  eq(paw.project.path, d .. "/second/project.toml", ":recent 2 opens the second newest")
  keys(":e " .. d .. "/song<CR>")
  eq(paw.project.path, d .. "/song/project.toml", ":e opens a project by its folder")
  keys("3-")
  keys(":e " .. d .. "/second<CR>")
  eq(paw.project.path, d .. "/song/project.toml", ":e refuses to drop work that is not saved")
  keys(":e! " .. d .. "/second<CR>")
  eq(paw.project.path, d .. "/second/project.toml", ":e! drops it and opens the other project")
  keys("3-")
  keys(":e!<CR>")
  eq(
    paw.project.path .. " " .. tostring(paw.project.unsaved()),
    d .. "/second/project.toml false",
    ":e! alone opens the project again as saved"
  )
  -- A name alone goes next to the project's folder.
  keys(":w guide-save-test<CR>")
  eq(exists(d .. "/guide-save-test/project.toml"), true, ":w name saves next to the project's folder")
  keys(":pwd<CR>")
  eq(paw.ui.message.text:find(d .. "/guide-save-test", 1, true) ~= nil, true, ":pwd shows the project's folder")
  local other = dir("projects-other")
  keys(":cd " .. other .. "<CR>")
  T.after(function() paw.files.cd(false) end)
  keys(":w moved<CR>")
  eq(exists(other .. "/moved/project.toml"), true, ":cd sets the folder for a name alone")
  keys(":cd -<CR>")
  eq(paw.files.here(), d .. "/guide-save-test", ":cd - returns to the folder before")
  -- A name that ends in .json is a folder too: one JSON file is only paw's own safety copy.
  keys(":w " .. d .. "/third.json<CR>")
  eq(
    exists(d .. "/third/project.toml") and not exists(d .. "/third.json"),
    true,
    ":w third.json saves the folder third"
  )
  eq(
    paw.ui.message.text,
    "a project is a folder: saved it in third/, not in third.json: " .. d .. "/third/project.toml",
    "and says where"
  )
  keys(":set autosave 30<CR>")
  eq(paw.opt.autosave, 30, ":set autosave 30 makes a safety copy every 30 seconds")
  paw.opt.autosave = 0
end)

-- paw started in a folder, as the shell's PWD says.
local ffi = require("ffi")
pcall(ffi.cdef, "int setenv(const char *name, const char *value, int overwrite);")

local function started_in(folder)
  local old_pwd = os.getenv("PWD")
  ffi.C.setenv("PWD", folder, 1)
  T.after(function() ffi.C.setenv("PWD", old_pwd or "/", 1) end)
end

test("guide: a new project is saved in the folder paw started in, as in Neovim", function()
  start()
  local started, home = dir("started/here"), T.home(dir("started/home"))
  os.execute("mkdir -p '" .. home .. "/sub'")
  started_in(started)
  T.after(function() paw.files.cd(false) end)
  paw.frontend.polled = paw.api.now()
  T.tone("Lead", 4)
  keys(":w<CR>")
  local cmdline = require("paw.views.cmdline")
  local state = cmdline.state()
  eq(
    state ~= nil and state.prompt:find("Save as (" .. started .. ")", 1, true) ~= nil,
    true,
    ":w on a new project asks for a name, in the folder paw started in"
  )
  eq(state and state.before, "untitled", "the prompt holds the name of the project")
  keys("<CR>")
  eq(exists(started .. "/untitled/project.toml"), true, "the name alone goes to that folder")
  -- Every file list starts there too.
  keys(":import<CR>")
  eq(
    table.concat(paw.api.ui_snapshot(140, 30), "\n"):find(started, 1, true) ~= nil,
    true,
    ":import lists the folder paw started in"
  )
  keys("<Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  -- `..` and `~` go elsewhere.
  paw.project.new()
  T.tone("Lead", 4)
  keys(":w ../other<CR>")
  eq(exists(dir("started") .. "/other/project.toml"), true, ":w ../other goes to the folder above")
  keys(":w ~/sub/mine<CR>")
  eq(exists(home .. "/sub/mine/project.toml"), true, ":w ~/sub/mine goes to the home folder")
  eq(paw.commands.complete("w ~")[1].text, "w ~/", "Tab completes ~ and ..")
  eq(paw.commands.complete("w ..")[1].text, "w ../", "and ..")
end)

test("guide: import audio and MIDI files", function()
  start()
  local lib = dir("library")
  -- A sound file and a MIDI file to bring in.
  T.tone("Source", 4)
  paw.render(lib .. "/loop.wav", { tail = 0, bits = 16 })
  paw.midifile.export(lib .. "/riff.mid")
  start()
  local d = dir("importing")
  paw.project.save(d .. "/song")
  keys(":import " .. lib .. "/loop.wav<CR>")
  eq(#paw.tracks(), 1, ":import puts a sound file on a new track")
  eq(paw.tracks()[1]:clips()[1].kind, "audio", "as an audio clip")
  eq(paw.tracks()[1].name, "loop", "named after the file")
  keys("3|")
  keys(":import " .. lib .. "/loop.wav<CR>")
  eq(paw.tracks()[2]:clips()[1].start, 8, "a clip that starts at the cursor")
  keys("u")
  keys("o")
  keys("5|")
  keys(":clip.import " .. lib .. "/loop.wav<CR>")
  local t2 = paw.tracks()[2]
  eq(
    #t2:clips() .. "@" .. t2:clips()[1].start,
    "1@16",
    ":clip.import puts it on the track of the cursor, at the cursor"
  )
  keys(":import " .. lib .. "/riff.mid<CR>")
  eq(#paw.tracks(), 3, ":import adds the tracks of a MIDI file")
  eq(paw.tracks()[3]:clips()[1].kind, "midi", "with their notes")
  keys(":files " .. lib .. "<CR>")
  eq(table.concat(api.ui_snapshot(100, 30), "\n"):find("loop.wav", 1, true) ~= nil, true, ":files shows the folder")
  keys("/loop<CR>")
  keys("go")
  eq(#paw.tracks(), 4, "go puts the file on a new track")
  keys(":files " .. lib .. "<CR>")
  keys("/loop<CR>")
  keys("<CR>")
  eq(#paw.tracks(), 4, "Enter puts it on the track of the cursor")
  eq(#paw.tracks()[4]:clips(), 2, "beside the other clip")
  paw.ui.focus("arrange")
  keys(":media.collect<CR>")
  for _, t in ipairs(paw.tracks()) do
    for _, c in ipairs(t:clips()) do
      if c.kind == "audio" then
        eq(c:get().file, d .. "/song/media/loop.wav", ":media.collect copies the files into media")
      end
    end
  end
end)

T.last("guide: make and use track templates", function()
  start()
  paw.opt.templates_dir = T.scratch .. "/guide-templates"
  T.after(function() paw.opt.templates_dir = T.scratch .. "/templates" end)
  keys(":ext.load templates<CR>")
  local vocal = paw.add_track({ name = "Vocal" })
  vocal:add_device("eq")
  vocal:add_device("compressor")
  vocal.volume = -4
  paw.flush()
  paw.ui.focus("arrange")
  paw.cursor.set_track(vocal)
  keys("<localleader>TsLead vocal<CR>")
  eq(require("templates").list("track")[1].name, "Lead vocal", "\\Ts saves the track as a template")
  keys("<localleader>TfVocal chain<CR>")
  eq(require("templates").list("fx")[1] ~= nil, true, "\\Tf saves the devices as a chain")
  start()
  paw.add_track({ name = "Guitar" })
  paw.flush()
  paw.ui.focus("arrange")
  paw.cursor.set_track(paw.tracks()[1])
  keys("<localleader>Tllead<CR>")
  eq(#paw.tracks(), 2, "\\Tl makes the track again")
  local made = paw.tracks()[2]
  eq(made.name .. " " .. made.volume, "Vocal -4", "below the cursor track, with its level")
  eq(made:devices()[1].kind .. " " .. made:devices()[2].kind, "eq compressor", "and its devices")
  paw.cursor.set_track(paw.tracks()[1])
  keys("<localleader>Tlvocal chain<CR>")
  eq(#paw.tracks()[1]:devices(), 2, "a chain goes onto the devices of the cursor track")
  keys(":templates<CR>")
  eq(table.concat(api.ui_snapshot(100, 20), "\n"):find("Lead vocal", 1, true) ~= nil, true, ":templates lists them")
end)
