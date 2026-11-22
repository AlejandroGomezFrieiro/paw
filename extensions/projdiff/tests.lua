-- Tests for the project diff and merge extension, run by tests/suite.lua.
local T = ...
local test, eq, fresh, scratch = T.test, T.eq, T.fresh, T.scratch
local api = paw.api

--- The messages shown since `mark` (the last one when it was taken): the
--- list keeps the last 500, so it is followed by the message, not counted.
local function since(mark)
  local out, after = {}, mark == nil
  for _, m in ipairs(paw.ui.messages) do
    if after then out[#out + 1] = m end
    if m == mark then after = true end
  end
  return out
end
local function mark() return paw.ui.messages[#paw.ui.messages] end

local projdiff

local function load()
  if not paw.ext.loaded.projdiff then paw.ext.load("extensions/projdiff") end
  projdiff = require("projdiff")
  return projdiff
end

local function start()
  load()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.close()
end

--- A project with a lead (a synth, a clip of three notes, a volume lane), a
--- bass, a tempo change and a marker, saved as `name`; returns its path.
local function fixture(name)
  fresh()
  local lead = paw.add_track({ name = "Lead" })
  local synth = lead:add_device("synth", { cutoff = 800 })
  local riff = lead:add_clip({ name = "riff", start = 0, length = 4 })
  riff:add_note({ pitch = 60, start = 0, length = 1 })
  riff:add_note({ pitch = 64, start = 1, length = 1 })
  riff:add_note({ pitch = 67, start = 2, length = 1 })
  local fade = lead:automate("volume")
  fade:add(0, -12)
  fade:add(8, 0)
  local bass = paw.add_track({ name = "Bass" })
  bass:add_clip({ name = "line", start = 4, length = 4 })
  paw.add_track({ name = "Drums" })
  paw.markers.add(8, "Chorus")
  api.undo_checkpoint()
  local path = scratch .. "/" .. name .. ".json"
  api.project_save(path)
  assert(synth)
  return path
end

--- An empty list as the model reads one: a plain empty table is an object.
local function list() return api.json_decode("[]") end

local function decode(path)
  local doc, err = projdiff.file(path)
  assert(doc, err)
  return doc
end

local function track(doc, name)
  for _, t in ipairs(doc.project.tracks) do
    if t.name == name then return t end
  end
end

local function lines(from, to)
  return table.concat(projdiff.diff.lines(projdiff.diff.diff(from.project, to.project)), "\n")
end

local function has(text, part, what)
  if not text:find(part, 1, true) then error((what or "text") .. " lacks `" .. part .. "`:\n" .. text, 2) end
end

local function lacks(text, part, what)
  if text:find(part, 1, true) then error((what or "text") .. " holds `" .. part .. "`:\n" .. text, 2) end
end

test(
  "projdiff: a project file saved again is the same bytes, and the model writes it the way the merge does",
  function()
    load()
    local path = fixture("stable")
    local first = projdiff.read(path)
    api.project_save(path)
    eq(projdiff.read(path), first, "saved twice")
    local doc = decode(path)
    eq(api.project_file_text(doc), first, "decoded and written by the model")
  end
)

test(
  "projdiff: a diff names tracks added, removed and renamed, devices, clips, notes, lanes, tempo and markers",
  function()
    load()
    local path = fixture("diff")
    local base, now = decode(path), decode(path)
    local lead, bass = track(now, "Lead"), track(now, "Bass")
    lead.name = "Keys"
    lead.volume = -3
    lead.devices[1].params.cutoff = 1200
    lead.clips[1].start = 8
    lead.clips[1].content.notes[2].pitch = 65
    table.remove(lead.clips[1].content.notes, 3)
    table.insert(lead.clips[1].content.notes, { id = 9, pitch = 72, start = 3, length = 1, velocity = 100 })
    lead.lanes[1].points[2][2] = -6
    table.insert(lead.lanes[1].points, { 4, -9 })
    for i, t in ipairs(now.project.tracks) do
      if t == bass then
        table.remove(now.project.tracks, i)
        break
      end
    end
    table.insert(now.project.tracks, {
      id = 90,
      name = "Pad",
      volume = 0,
      pan = 0,
      mute = false,
      solo = false,
      armed = false,
      sends = list(),
      devices = list(),
      clips = list(),
      meta = {},
      monitor = false,
    })
    now.project.tempo_changes = { { beat = 16, bpm = 90 } }
    now.project.meta.markers[1].beat = 12
    table.insert(now.project.meta.markers, { id = 7, beat = 20, name = "Outro" })
    local text = lines(base, now)
    has(text, ('track %d "Lead" -> "Keys"'):format(lead.id), "the rename")
    has(text, "volume: 0 -> -3", "the fader")
    has(text, "cutoff: 800 -> 1200", "the parameter")
    has(text, "start: 0 -> 8", "the clip moved")
    has(text, "notes +1 -1 ~1", "notes summarised per clip")
    has(text, "note 2 F4: pitch E4 -> F4", "a note changed")
    has(text, "note 9 C5 at 3", "a note added")
    has(text, "points +1 ~1", "automation")
    has(text, "- track " .. bass.id .. ' "Bass"', "a track removed")
    has(text, '+ track 90 "Pad"', "a track added")
    has(text, "tempo at beat 16: 90 bpm", "the tempo map")
    has(text, 'marker 1 "Chorus": beat 8 -> 12', "a marker moved")
    has(text, 'marker 7 "Outro" at beat 20', "a marker added")
    eq(projdiff.diff.diff(base.project, base.project).count, 0, "no difference from itself")
  end
)

test("projdiff: changes have addresses to go to, and become quickfix entries", function()
  load()
  local path = fixture("qf")
  local base, now = decode(path), decode(path)
  local lead = track(now, "Lead")
  lead.clips[1].content.notes[1].velocity = 80
  lead.devices[1].params.cutoff = 900
  local tree = projdiff.diff.diff(base.project, now.project)
  local entries = projdiff.diff.entries(tree)
  eq(#entries, 2, "two changes")
  local by = {}
  for _, e in ipairs(entries) do
    by[#by + 1] = e.address
  end
  table.sort(by)
  eq(by[1], "paw://clip/" .. lead.clips[1].id .. "/note/1", "the note")
  eq(by[2], "paw://track/" .. lead.id .. "/device/" .. lead.devices[1].id .. "/param/cutoff", "the parameter")
  start()
  local n = projdiff.to_quickfix(tree, "test diff")
  eq(n, 2, "sent")
  eq(#paw.qf.current().entries, 2, "in the list")
  eq(paw.qf.current().entries[1].location.uri:match("^paw://") ~= nil, true, "each goes somewhere")
end)

test("projdiff: the text form puts each thing on a line, so one change is one line", function()
  load()
  local path = fixture("text")
  local base, now = decode(path), decode(path)
  local a = projdiff.text.lines(base.project)
  eq(table.concat(a, "\n"), table.concat(projdiff.text.lines(decode(path).project), "\n"), "stable")
  now.project.tracks[1].clips[1].content.notes[2].velocity = 50
  local b = projdiff.text.lines(now.project)
  eq(#a, #b, "the same lines")
  local differ = 0
  for i = 1, #a do
    if a[i] ~= b[i] then differ = differ + 1 end
  end
  eq(differ, 1, "one line differs")
  has(table.concat(a, "\n"), "note id=2 length=1 start=1 velocity=100 pitch=64(E4)", "a note's line")
  has(table.concat(a, "\n"), "clip id=", "a clip's line")
  has(table.concat(a, "\n"), "point beat=8 value=0", "a lane's points")
end)

-- Merging --------------------------------------------------------------------

local function sides()
  load()
  local path = fixture("merge")
  return decode(path), decode(path), decode(path)
end

local function names(doc)
  local out = {}
  for _, t in ipairs(doc.project.tracks) do
    out[#out + 1] = t.name
  end
  return table.concat(out, ",")
end

--- The merged project written out, and opened again.
local function reopen(doc)
  local path = scratch .. "/merged.json"
  local file = assert(io.open(path, "wb"))
  file:write(api.project_file_text(doc))
  file:close()
  api.project_load(path)
  return path
end

test("projdiff: changes to different tracks, clips, notes and parameters merge without a conflict", function()
  local base, ours, theirs = sides()
  -- An id that nothing in the fixture has (tracks, devices, clips and lanes
  -- share them): the kernel's ids go on across tests.
  local added = 1
  local function above(v)
    if type(v) ~= "table" then return end
    if type(v.id) == "number" then added = math.max(added, v.id + 1) end
    for _, x in pairs(v) do
      above(x)
    end
  end
  above(base.project)
  track(ours, "Lead").volume = -3
  track(ours, "Lead").devices[1].params.cutoff = 1500
  track(ours, "Lead").clips[1].content.notes[1].start = 0.5
  table.insert(track(ours, "Lead").clips, {
    id = added,
    name = "ours",
    start = 8,
    length = 4,
    muted = false,
    content = { kind = "midi", notes = list() },
    meta = {},
  })
  track(theirs, "Bass").pan = 0.5
  track(theirs, "Lead").devices[1].params.resonance = 0.4
  track(theirs, "Lead").clips[1].content.notes[2].velocity = 70
  table.insert(track(theirs, "Bass").clips, {
    id = added,
    name = "theirs",
    start = 8,
    length = 4,
    muted = false,
    content = { kind = "midi", notes = list() },
    meta = {},
  })
  theirs.project.tempo = 100
  ours.project.tempo_changes = { { beat = 16, bpm = 90 } }
  theirs.project.tempo_changes = { { beat = 32, bpm = 140 } }
  local merged, conflicts = projdiff.merge.files(base, ours, theirs)
  eq(#conflicts, 0, "no conflicts")
  local lead, bass = track(merged, "Lead"), track(merged, "Bass")
  eq(lead.volume, -3, "ours: the fader")
  eq(lead.devices[1].params.cutoff, 1500, "ours: a parameter")
  eq(lead.devices[1].params.resonance, 0.4, "theirs: another parameter")
  eq(lead.clips[1].content.notes[1].start, 0.5, "ours: a note moved")
  eq(lead.clips[1].content.notes[2].velocity, 70, "theirs: another note")
  eq(bass.pan, 0.5, "theirs: another track")
  eq(merged.project.tempo, 100, "theirs: the tempo")
  eq(#merged.project.tempo_changes, 2, "both tempo changes")
  eq(#lead.clips, 2, "ours added a clip")
  eq(#bass.clips, 2, "theirs added a clip")
  local ids = {}
  for _, t in ipairs({ lead, bass }) do
    for _, c in ipairs(t.clips) do
      eq(ids[c.id], nil, "clip ids are the project's: " .. c.id .. " once")
      ids[c.id] = true
    end
  end
  eq(merged.project.meta.merge_conflicts, nil, "nothing recorded")
  reopen(merged)
  eq(#paw.tracks(), 3, "the merged project opens")
end)

test("projdiff: tracks, notes and markers both sides added keep both, with new numbers where they clash", function()
  local base, ours, theirs = sides()
  local function new_track(id, name, output)
    return {
      id = id,
      name = name,
      volume = 0,
      pan = 0,
      mute = false,
      solo = false,
      armed = false,
      output = output,
      sends = list(),
      devices = list(),
      clips = list(),
      meta = {},
      monitor = false,
    }
  end
  table.insert(ours.project.tracks, new_track(50, "Ours", nil))
  table.insert(theirs.project.tracks, new_track(50, "Theirs", nil))
  table.insert(theirs.project.tracks, new_track(51, "Feeds", 50))
  table.insert(
    track(ours, "Lead").clips[1].content.notes,
    { id = 4, pitch = 72, start = 3, length = 1, velocity = 100 }
  )
  table.insert(
    track(theirs, "Lead").clips[1].content.notes,
    { id = 4, pitch = 74, start = 3.5, length = 1, velocity = 100 }
  )
  table.insert(ours.project.meta.markers, { id = 2, beat = 16, name = "A" })
  table.insert(theirs.project.meta.markers, { id = 2, beat = 24, name = "B" })
  local merged, conflicts = projdiff.merge.files(base, ours, theirs)
  eq(#conflicts, 0, "no conflicts")
  eq(names(merged), "Lead,Bass,Drums,Theirs,Feeds,Ours", "all the tracks")
  local theirs_id, feeds = track(merged, "Theirs").id, track(merged, "Feeds")
  eq(track(merged, "Ours").id, 50, "ours keeps its number")
  eq(theirs_id ~= 50, true, "theirs has another")
  eq(feeds.output, theirs_id, "what pointed at theirs follows it")
  local notes = track(merged, "Lead").clips[1].content.notes
  eq(#notes, 5, "both notes")
  local seen = {}
  for i, n in ipairs(notes) do
    eq(seen[n.id], nil, "note ids differ")
    seen[n.id] = true
    if i > 1 then eq(notes[i - 1].start <= n.start, true, "in order of time") end
  end
  eq(#merged.project.meta.markers, 3, "both markers")
  reopen(merged)
  eq(#paw.tracks(), 6, "the merged project opens")
end)

test("projdiff: the same thing changed two ways is a conflict that holds ours and says what it was", function()
  local base, ours, theirs = sides()
  track(ours, "Lead").devices[1].params.cutoff = 1500
  track(theirs, "Lead").devices[1].params.cutoff = 300
  track(ours, "Lead").clips[1].content.notes[1].velocity = 90
  track(theirs, "Lead").clips[1].content.notes[1].velocity = 80
  track(ours, "Bass").volume = -6
  for i, t in ipairs(theirs.project.tracks) do
    if t.name == "Bass" then
      table.remove(theirs.project.tracks, i)
      break
    end
  end
  local merged, conflicts = projdiff.merge.files(base, ours, theirs)
  eq(#conflicts, 3, "three conflicts")
  eq(track(merged, "Lead").devices[1].params.cutoff, 1500, "ours holds")
  eq(track(merged, "Lead").clips[1].content.notes[1].velocity, 90, "ours holds in the note")
  eq(track(merged, "Bass").volume, -6, "ours holds the track that theirs removed")
  local recorded = projdiff.merge.conflicts(merged)
  eq(#recorded, 3, "recorded in the project")
  local cutoff
  for _, c in ipairs(recorded) do
    if c.ours == 1500 then cutoff = c end
  end
  eq(cutoff.theirs, 300, "theirs")
  eq(cutoff.base, 800, "before")
  eq(
    projdiff.merge.describe(merged, cutoff.path):find("params › cutoff", 1, true) ~= nil,
    true,
    "in words: " .. projdiff.merge.describe(merged, cutoff.path)
  )
  local text = api.project_file_text(merged)
  local again = decode(reopen(merged))
  eq(#projdiff.merge.conflicts(again), 3, "still recorded in the file")
  eq(api.project_file_text(again), text, "and the file is stable")
  eq(paw.api.project_get().meta.merge_conflicts ~= nil, true, "the open project holds them")
end)

test("projdiff: conflicts are settled one by one, ours, theirs or what it was", function()
  local base, ours, theirs = sides()
  track(ours, "Lead").devices[1].params.cutoff = 1500
  track(theirs, "Lead").devices[1].params.cutoff = 300
  track(ours, "Bass").volume = -6
  for i, t in ipairs(theirs.project.tracks) do
    if t.name == "Bass" then
      table.remove(theirs.project.tracks, i)
      break
    end
  end
  local merged = projdiff.merge.files(base, ours, theirs)
  local list = projdiff.merge.conflicts(merged)
  eq(#list, 2, "two")
  for _, c in ipairs(list) do
    if c.theirs == 300 then projdiff.merge.resolve(merged, c, "theirs") end
  end
  eq(track(merged, "Lead").devices[1].params.cutoff, 300, "theirs taken")
  eq(#projdiff.merge.conflicts(merged), 1, "one left")
  projdiff.merge.resolve(merged, projdiff.merge.conflicts(merged)[1], "theirs")
  eq(track(merged, "Bass"), nil, "theirs removed the track, and now it is gone")
  eq(merged.project.meta.merge_conflicts, nil, "none left, none recorded")
  eq(names(merged), "Lead,Drums", "the tracks")
end)

test("projdiff: :Pmerge shows the conflicts and co, ct settle them in the file", function()
  start()
  local base, ours, theirs = sides()
  track(ours, "Lead").devices[1].params.cutoff = 1500
  track(theirs, "Lead").devices[1].params.cutoff = 300
  track(ours, "Lead").volume = -6
  track(theirs, "Lead").volume = -2
  local merged = projdiff.merge.files(base, ours, theirs)
  local path = scratch .. "/conflicted.json"
  local file = assert(io.open(path, "wb"))
  file:write(api.project_file_text(merged))
  file:close()
  paw.cmd("Pmerge", { path })
  eq(paw.ui.float and paw.ui.float.name, "projmerge", "the conflict view is open")
  paw.keymap.feed("ct")
  eq(#projdiff.merge.conflicts(decode(path)), 1, "one settled")
  paw.keymap.feed("co")
  eq(paw.ui.float, nil, "closed when the last is settled")
  local settled = decode(path)
  eq(#projdiff.merge.conflicts(settled), 0, "none left")
  eq(
    track(settled, "Lead").devices[1].params.cutoff,
    300,
    "theirs for the first (the conflicts are in order of the file)"
  )
end)

-- The views -------------------------------------------------------------------

test("projdiff: :Pdiff compares with the saved file, an undo state and a snapshot, and folds", function()
  start()
  local path = fixture("views")
  api.project_load(path)
  local lead = paw.tracks()[1]
  paw.cmd("Pdiff")
  eq(paw.ui.float, nil, "nothing differs from the saved file")
  lead.volume = -5
  api.undo_checkpoint()
  local state = api.undo_current()
  paw.cmd("Psnapshot", { "loud" })
  lead:add_clip({ name = "added", start = 16, length = 2 })
  api.undo_checkpoint()
  paw.cmd("Pdiff")
  eq(paw.ui.float and paw.ui.float.name, "projdiff", "the view is open")
  local view = require("projdiff.view")
  eq(view.title_text:find("saved → now: 2 changes", 1, true) ~= nil, true, view.title_text)
  eq(#view.rows >= 3, true, "a heading and its changes")
  -- Folding takes the lines under a heading away; unfolding brings them back.
  local open = #view.rows
  paw.keymap.feed("zc")
  eq(#view.rows < open, true, "zc folds the track")
  paw.keymap.feed("za")
  eq(#view.rows, open, "za opens it again")
  -- `]c` goes to a change, and Enter to where it is.
  paw.keymap.feed("]c")
  eq(view.rows[view.sel].node.change, true, "on a change")
  paw.keymap.feed("Q")
  eq(#paw.qf.current().entries, 2, "the quickfix list holds both")
  paw.keymap.feed("<CR>")
  eq(paw.ui.float, nil, "the view closes to go there")
  -- Against an undo state and a snapshot.
  paw.cmd("Pdiff", { "#" .. state })
  eq(view.title_text:find("#" .. state .. " → now: 1 change", 1, true) ~= nil, true, view.title_text)
  paw.keymap.feed("q")
  paw.cmd("Pdiff", { "snap:loud" })
  eq(view.title_text:find("loud → now: 1 change", 1, true) ~= nil, true, view.title_text)
  paw.keymap.feed("q")
  paw.cmd("Pdiff", { path, "snap:loud" })
  eq(view.title_text:find("→ loud: 1 change", 1, true) ~= nil, true, view.title_text)
  paw.keymap.feed("q")
  paw.cmd("Pdiff.qf", { "snap:loud" })
  eq(#paw.qf.current().entries, 1, "the added clip, in quickfix")
end)

-- Git ----------------------------------------------------------------------------

local function run(command)
  local p = io.popen(command .. " 2>&1")
  local out = p:read("*a")
  p:close()
  return out
end

test("projdiff: git shows a project as text and merges two branches that changed it apart", function()
  load()
  if os.execute("command -v git >/dev/null 2>&1") ~= 0 and os.execute("command -v git >/dev/null 2>&1") ~= true then
    return "no git"
  end
  local bin = (os.getenv("PAW_TEST_BIN") or "target/release") .. "/paw"
  local root = scratch .. "/repo"
  local script = io.popen("pwd"):read("*l") .. "/extensions/projdiff/git.lua"
  local paw_cmd = bin:sub(1, 1) == "/" and bin or (io.popen("pwd"):read("*l") .. "/" .. bin)
  local driver = paw_cmd .. " --clean --no-plugins --no-listen --audio null -l " .. script
  os.execute("rm -rf '" .. root .. "' && mkdir -p '" .. root .. "'")
  local function git(args) return run("cd '" .. root .. "' && git -c user.name=t -c user.email=t@t " .. args) end
  git("init -q -b main")
  git("config diff.paw.textconv '" .. driver .. " textconv'")
  git("config merge.paw.name paw")
  git("config merge.paw.driver '" .. driver .. " merge %O %A %B %L %P'")
  local f = assert(io.open(root .. "/.gitattributes", "w"))
  f:write("song.json diff=paw merge=paw\n")
  f:close()
  local path = fixture("song")
  os.execute("cp '" .. path .. "' '" .. root .. "/song.json'")
  git("add -A")
  git("commit -q -m base")
  local function edit(fn)
    local doc = decode(root .. "/song.json")
    fn(doc)
    local file = assert(io.open(root .. "/song.json", "wb"))
    file:write(api.project_file_text(doc))
    file:close()
  end
  -- A branch changes the bass; main changes the lead.
  git("checkout -q -b bass")
  edit(function(doc) track(doc, "Bass").volume = -9 end)
  git("commit -qam bass")
  git("checkout -q main")
  edit(function(doc) track(doc, "Lead").clips[1].content.notes[1].pitch = 62 end)
  git("commit -qam lead")
  local shown = git("diff HEAD~1 HEAD")
  has(shown, "-    note id=1 length=1 start=0 velocity=100 pitch=60(C4)", "git diff shows the note's line")
  has(shown, "+    note id=1 length=1 start=0 velocity=100 pitch=62(D4)", "and its new one")
  lacks(shown, '"pitch"', "not JSON")
  local merged = git("merge bass -m merge")
  eq(git("status --porcelain"), "", "the merge went through: " .. merged)
  local doc = decode(root .. "/song.json")
  eq(track(doc, "Bass").volume, -9, "the bass branch's change")
  eq(track(doc, "Lead").clips[1].content.notes[1].pitch, 62, "main's change")
  -- Both change the same parameter: a conflict, in the file as a project.
  git("checkout -q -b one")
  edit(function(d) track(d, "Lead").devices[1].params.cutoff = 100 end)
  git("commit -qam one")
  git("checkout -q main")
  edit(function(d) track(d, "Lead").devices[1].params.cutoff = 200 end)
  git("commit -qam two")
  git("merge one -m clash")
  local conflicted = decode(root .. "/song.json")
  local list = projdiff.merge.conflicts(conflicted)
  eq(#list, 1, "one conflict")
  eq(list[1].ours, 200, "ours")
  eq(list[1].theirs, 100, "theirs")
  eq(git("status --porcelain"):find("UU song.json", 1, true) ~= nil, true, "git says it is unmerged")
  os.execute("rm -rf '" .. root .. "'")
end)

test(
  "projdiff: a reopened project with audio differs in nothing, edits not yet an undo step count, and #0 and odd lengths read well",
  function()
    start()
    local dir = scratch .. "/pdiff-media"
    os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "/media'")
    local s = {}
    for i = 1, 4800 do
      s[i] = 0.1
    end
    local wav = T.write_wav(dir .. "/media/tone.wav", s)
    local t = paw.add_track({ name = "Audio" })
    t:add_clip({ file = wav, start = 0, length = 2 })
    api.undo_checkpoint()
    local path = dir .. "/song.json"
    api.project_save(path)
    eq(T.read_file(path):find('"media/tone.wav"', 1, true) ~= nil, true, "the file names its media relative to itself")
    api.project_load(path)
    paw.cmd("Pdiff")
    eq(
      paw.ui.message and paw.ui.message.text,
      "saved → now: 0 changes (nothing differs)",
      "nothing differs after reopening"
    )
    -- An edit from Lua that no key made an undo step of.
    paw.tracks()[1]:add_clip({ name = "odd", start = 16, length = 0.1 + 0.7 })
    paw.cmd("Pdiff")
    local view = require("projdiff.view")
    eq(
      view.title_text:find("saved → now: 1 change", 1, true) ~= nil,
      true,
      "the edit is seen: " .. tostring(view.title_text)
    )
    local found
    for _, row in ipairs(view.rows) do
      if row.node.text:find("odd", 1, true) then found = row.node.text end
    end
    eq(
      found and found:match('"odd", .*'),
      '"odd", at beat 16, 0.8 beats long, 0 notes',
      "a length reads without floating point's noise"
    )
    paw.keymap.feed("q")
    local from = mark()
    paw.cmd("Pdiff", { "#0" })
    local levels = {}
    for _, m in ipairs(since(from)) do
      levels[#levels + 1] = m.level .. ": " .. m.text
    end
    eq(
      table.concat(levels, "; "),
      "warn: there is no undo state #0: the states are numbered from 1, as the undo tree shows them",
      "#0 is said plainly"
    )
    if paw.ui.float then paw.keymap.feed("q") end
  end
)
