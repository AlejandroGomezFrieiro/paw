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
--- With `folder`, `name` is a path, and the project is saved as a project
--- folder there.
local function fixture(name, folder)
  fresh()
  local lead = paw.add_part({ name = "Lead" })
  local synth = lead:add_device("synth", { cutoff = 800 })
  local riff = lead:add_clip({ name = "riff", start = 0, length = 4 })
  riff:add_note({ pitch = 60, start = 0, length = 1 })
  riff:add_note({ pitch = 64, start = 1, length = 1 })
  riff:add_note({ pitch = 67, start = 2, length = 1 })
  local fade = lead:automate("volume")
  fade:add(0, -12)
  fade:add(8, 0)
  local bass = paw.add_part({ name = "Bass" })
  bass:add_clip({ name = "line", start = 4, length = 4 })
  paw.add_part({ name = "Drums" })
  paw.markers.add(8, "Chorus")
  api.undo_checkpoint()
  local path = folder and name or (scratch .. "/" .. name .. ".json")
  api.project_save(path)
  assert(synth)
  return path
end

--- An empty list as the model reads one: a plain empty table is an object.
local function list() return api.json_decode("[]") end

--- A part id that the kernel has not given to anything in a file saved
--- before: the kernel never gives an id twice. A literal id could be the id
--- of a device or a clip of the fixture, as the kernel counts ids across tests.
local function unused_part_id() return paw.add_part({ name = "unused" }).id end

local function decode(path)
  local doc, err = projdiff.file(path)
  assert(doc, err)
  return doc
end

local function part(doc, name)
  for _, t in ipairs(doc.project.parts) do
    if t.name == name then return t end
  end
end

local function lines(from, to)
  return table.concat(projdiff.diff.lines(projdiff.diff.diff(from.project, to.project)), "\n")
end

local function has(text, part, what)
  if not text:find(part, 1, true) then error((what or "text") .. " lacks `" .. part .. "`:\n" .. text, 2) end
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
  "projdiff: a diff names parts added, removed and renamed, devices, clips, notes, lanes, tempo and markers",
  function()
    load()
    local path = fixture("diff")
    local base, now = decode(path), decode(path)
    local lead, bass = part(now, "Lead"), part(now, "Bass")
    lead.name = "Keys"
    lead.volume = -3
    lead.devices[1].params.cutoff = 1200
    lead.clips[1].start = 8
    lead.clips[1].content.notes[2].pitch = 65
    table.remove(lead.clips[1].content.notes, 3)
    table.insert(lead.clips[1].content.notes, { id = 9, pitch = 72, start = 3, length = 1, velocity = 100 })
    lead.lanes[1].points[2][2] = -6
    table.insert(lead.lanes[1].points, { 4, -9 })
    for i, t in ipairs(now.project.parts) do
      if t == bass then
        table.remove(now.project.parts, i)
        break
      end
    end
    local pad = unused_part_id()
    table.insert(now.project.parts, {
      id = pad,
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
    has(text, ('part %d "Lead" -> "Keys"'):format(lead.id), "the rename")
    has(text, "volume: 0 -> -3", "the fader")
    has(text, "cutoff: 800 -> 1200", "the parameter")
    has(text, "start: 0 -> 8", "the clip moved")
    has(text, "notes +1 -1 ~1", "notes summarised per clip")
    has(text, "note 2 F4: pitch E4 -> F4", "a note changed")
    has(text, "note 9 C5 at 3", "a note added")
    has(text, "points +1 ~1", "automation")
    has(text, "- part " .. bass.id .. ' "Bass"', "a part removed")
    has(text, "+ part " .. pad .. ' "Pad"', "a part added")
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
  local lead = part(now, "Lead")
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
  eq(by[2], "paw://part/" .. lead.id .. "/device/" .. lead.devices[1].id .. "/param/cutoff", "the parameter")
  start()
  local n = projdiff.to_quickfix(tree, "test diff")
  eq(n, 2, "sent")
  eq(#paw.qf.current().entries, 2, "in the list")
  eq(paw.qf.current().entries[1].location.uri:match("^paw://") ~= nil, true, "each goes somewhere")
end)

-- Merging --------------------------------------------------------------------

local function sides()
  load()
  local path = fixture("merge")
  return decode(path), decode(path), decode(path)
end

local function names(doc)
  local out = {}
  for _, t in ipairs(doc.project.parts) do
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

test("projdiff: changes to different parts, clips, notes and parameters merge without a conflict", function()
  local base, ours, theirs = sides()
  -- An id that nothing in the fixture has (parts, devices, clips and lanes
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
  part(ours, "Lead").volume = -3
  part(ours, "Lead").devices[1].params.cutoff = 1500
  part(ours, "Lead").clips[1].content.notes[1].start = 0.5
  table.insert(part(ours, "Lead").clips, {
    id = added,
    name = "ours",
    start = 8,
    length = 4,
    muted = false,
    content = { kind = "midi", notes = list() },
    meta = {},
  })
  part(theirs, "Bass").pan = 0.5
  part(theirs, "Lead").devices[1].params.resonance = 0.4
  part(theirs, "Lead").clips[1].content.notes[2].velocity = 70
  table.insert(part(theirs, "Bass").clips, {
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
  local lead, bass = part(merged, "Lead"), part(merged, "Bass")
  eq(lead.volume, -3, "ours: the fader")
  eq(lead.devices[1].params.cutoff, 1500, "ours: a parameter")
  eq(lead.devices[1].params.resonance, 0.4, "theirs: another parameter")
  eq(lead.clips[1].content.notes[1].start, 0.5, "ours: a note moved")
  eq(lead.clips[1].content.notes[2].velocity, 70, "theirs: another note")
  eq(bass.pan, 0.5, "theirs: another part")
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
  eq(#paw.parts(), 3, "the merged project opens")
end)

test("projdiff: parts, notes and markers both sides added keep both, with new numbers where they clash", function()
  local base, ours, theirs = sides()
  local function new_part(id, name, output)
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
  local added, feeds_id = unused_part_id(), unused_part_id()
  table.insert(ours.project.parts, new_part(added, "Ours", nil))
  table.insert(theirs.project.parts, new_part(added, "Theirs", nil))
  table.insert(theirs.project.parts, new_part(feeds_id, "Feeds", added))
  table.insert(part(ours, "Lead").clips[1].content.notes, { id = 4, pitch = 72, start = 3, length = 1, velocity = 100 })
  table.insert(
    part(theirs, "Lead").clips[1].content.notes,
    { id = 4, pitch = 74, start = 3.5, length = 1, velocity = 100 }
  )
  table.insert(ours.project.meta.markers, { id = 2, beat = 16, name = "A" })
  table.insert(theirs.project.meta.markers, { id = 2, beat = 24, name = "B" })
  local merged, conflicts = projdiff.merge.files(base, ours, theirs)
  eq(#conflicts, 0, "no conflicts")
  eq(names(merged), "Lead,Bass,Drums,Theirs,Feeds,Ours", "all the parts")
  local theirs_id, feeds = part(merged, "Theirs").id, part(merged, "Feeds")
  eq(part(merged, "Ours").id, added, "ours keeps its number")
  eq(theirs_id ~= added, true, "theirs has another")
  eq(feeds.output, theirs_id, "what pointed at theirs follows it")
  local notes = part(merged, "Lead").clips[1].content.notes
  eq(#notes, 5, "both notes")
  local seen = {}
  for i, n in ipairs(notes) do
    eq(seen[n.id], nil, "note ids differ")
    seen[n.id] = true
    if i > 1 then eq(notes[i - 1].start <= n.start, true, "in order of time") end
  end
  eq(#merged.project.meta.markers, 3, "both markers")
  reopen(merged)
  eq(#paw.parts(), 6, "the merged project opens")
end)

test("projdiff: the same thing changed two ways is a conflict that holds ours and says what it was", function()
  local base, ours, theirs = sides()
  part(ours, "Lead").devices[1].params.cutoff = 1500
  part(theirs, "Lead").devices[1].params.cutoff = 300
  part(ours, "Lead").clips[1].content.notes[1].velocity = 90
  part(theirs, "Lead").clips[1].content.notes[1].velocity = 80
  part(ours, "Bass").volume = -6
  for i, t in ipairs(theirs.project.parts) do
    if t.name == "Bass" then
      table.remove(theirs.project.parts, i)
      break
    end
  end
  local merged, conflicts = projdiff.merge.files(base, ours, theirs)
  eq(#conflicts, 3, "three conflicts")
  eq(part(merged, "Lead").devices[1].params.cutoff, 1500, "ours holds")
  eq(part(merged, "Lead").clips[1].content.notes[1].velocity, 90, "ours holds in the note")
  eq(part(merged, "Bass").volume, -6, "ours holds the part that theirs removed")
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
  part(ours, "Lead").devices[1].params.cutoff = 1500
  part(theirs, "Lead").devices[1].params.cutoff = 300
  part(ours, "Bass").volume = -6
  for i, t in ipairs(theirs.project.parts) do
    if t.name == "Bass" then
      table.remove(theirs.project.parts, i)
      break
    end
  end
  local merged = projdiff.merge.files(base, ours, theirs)
  local list = projdiff.merge.conflicts(merged)
  eq(#list, 2, "two")
  for _, c in ipairs(list) do
    if c.theirs == 300 then projdiff.merge.resolve(merged, c, "theirs") end
  end
  eq(part(merged, "Lead").devices[1].params.cutoff, 300, "theirs taken")
  eq(#projdiff.merge.conflicts(merged), 1, "one left")
  projdiff.merge.resolve(merged, projdiff.merge.conflicts(merged)[1], "theirs")
  eq(part(merged, "Bass"), nil, "theirs removed the part, and now it is gone")
  eq(merged.project.meta.merge_conflicts, nil, "none left, none recorded")
  eq(names(merged), "Lead,Drums", "the parts")
end)

-- The views -------------------------------------------------------------------

test("projdiff: :Pdiff compares with the saved file, an undo state and a snapshot, and folds", function()
  start()
  local path = fixture("views")
  api.project_load(path)
  local lead = paw.parts()[1]
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
  eq(#view.rows < open, true, "zc folds the part")
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

-- Subprojects --------------------------------------------------------------------

--- A song whose row Bridge places the subproject Bridge, whose part Inner
--- places the subproject Verse; Keys of Bridge and Strings of Verse have a
--- clip of one note each. Saved as `name`; returns the path and the ids.
--- With `folder`, `name` is a path, and the project is saved as a project
--- folder there.
local function nested(name, folder)
  fresh()
  local row = paw.add_part({ name = "Bridge" })
  local bridge = api.nest_add({ name = "Bridge", length = 16 })
  local verse = api.nest_add({ name = "Verse", length = 8 })
  local keys = api.part_add({ name = "Keys", nest = bridge })
  local inner = api.part_add({ name = "Inner", nest = bridge })
  local strings = api.part_add({ name = "Strings", nest = verse })
  local ids = {
    bridge = bridge,
    verse = verse,
    keys = keys,
    inner = inner,
    strings = strings,
    keys_clip = api.clip_add(
      keys,
      { name = "chords", start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } }
    ),
    strings_clip = api.clip_add(
      strings,
      { name = "pad", start = 0, length = 4, notes = { { pitch = 64, start = 0, length = 1 } } }
    ),
  }
  api.clip_add(inner, { nest = verse, start = 0 })
  api.clip_add(row.id, { nest = bridge, start = 0 })
  api.undo_checkpoint()
  local path = folder and name or (scratch .. "/" .. name .. ".json")
  api.project_save(path)
  return path, ids
end

test("projdiff: <Space>gd shows an edit inside a subproject under the subproject's name", function()
  start()
  local path, ids = nested("nest-edit")
  api.project_load(path)
  api.clip_add_notes(ids.keys_clip, { { pitch = 67, start = 2, length = 1 } })
  api.part_set(paw.nest.get(ids.bridge).master, { volume = -6 })
  T.keys("<Space>gd")
  local view = require("projdiff.view")
  T.after(function() paw.ui.close() end)
  eq(view.title_text:find("saved → now: 2 changes", 1, true) ~= nil, true, view.title_text)
  local text = table.concat(projdiff.diff.lines(view.tree), "\n")
  eq(
    text,
    table.concat({
      ('~ subproject %d "Bridge"'):format(ids.bridge),
      "  ~ master",
      "    ~ volume: 0 -> -6",
      ('  ~ part %d "Keys"'):format(ids.keys),
      ('    ~ clip %d "chords"'):format(ids.keys_clip),
      "      ~ notes +1",
      "        + note 2 G4 at 2, 1 long, velocity 100",
    }, "\n"),
    "the edits, under Bridge, with its master part named so"
  )
end)

test("projdiff: an edit inside a subproject of a subproject shows under both names", function()
  load()
  local path, ids = nested("nest-deep")
  local before = decode(path)
  api.clip_add_notes(ids.strings_clip, { { pitch = 71, start = 1, length = 1 } })
  local now = projdiff.state(nil)
  eq(
    lines(before, now),
    table.concat({
      ('~ subproject %d "Bridge"'):format(ids.bridge),
      ('  ~ subproject %d "Verse"'):format(ids.verse),
      ('    ~ part %d "Strings"'):format(ids.strings),
      ('      ~ clip %d "pad"'):format(ids.strings_clip),
      "        ~ notes +1",
      "          + note 2 B4 at 1, 1 long, velocity 100",
    }, "\n"),
    "the edit, under Bridge and Verse"
  )
  local entries = projdiff.diff.entries(projdiff.diff.diff(before.project, now.project))
  local trail = ('subproject %d "Bridge" › subproject %d "Verse" › part %d "Strings"'):format(
    ids.bridge,
    ids.verse,
    ids.strings
  )
  eq(entries[1].text:sub(1, #trail), trail, "the quickfix entry names both subprojects")
end)

--- The scopes of the window in front, from the song in: `nest 3 > nest 5`.
local function scope_path()
  local out = {}
  for _, s in ipairs(paw.scope.path()) do
    out[#out + 1] = s.kind .. " " .. tostring(s.id)
  end
  return table.concat(out, " > ")
end

test("projdiff: Enter on a change inside a subproject goes inside it, with the cursor on the changed part", function()
  start()
  T.after(function() paw.scope.widen(true) end)
  local path, ids = nested("nest-go")
  api.project_load(path)
  api.part_set(ids.keys, { volume = -6 })
  api.undo_checkpoint()
  T.keys("<Space>gd")
  eq(
    table.concat(projdiff.diff.lines(require("projdiff.view").tree), "\n"),
    table.concat({
      ('~ subproject %d "Bridge"'):format(ids.bridge),
      ('  ~ part %d "Keys"'):format(ids.keys),
      "    ~ volume: 0 -> -6",
    }, "\n"),
    "the change, under Bridge"
  )
  T.keys("j<CR>")
  eq(paw.ui.float, nil, "the window closes")
  eq(scope_path(), "nest " .. ids.bridge, "the window shows Bridge")
  eq(paw.cursor.part_id(), ids.keys, "the cursor is on Keys")
end)

test(
  "projdiff: Enter goes two levels deep for a change there, and stays in the song for a change of the song",
  function()
    start()
    T.after(function()
      paw.ui.close()
      paw.scope.widen(true)
    end)
    local path, ids = nested("nest-go-deep")
    api.project_load(path)
    local row = paw.parts()[1]
    eq(row.name, "Bridge", "the song's row of the subproject")
    row.volume = -3
    api.part_set(ids.strings, { volume = -6 })
    api.undo_checkpoint()
    T.keys("<Space>gd")
    eq(
      table.concat(projdiff.diff.lines(require("projdiff.view").tree), "\n"),
      table.concat({
        ('~ part %d "Bridge"'):format(row.id),
        "  ~ volume: 0 -> -3",
        ('~ subproject %d "Bridge"'):format(ids.bridge),
        ('  ~ subproject %d "Verse"'):format(ids.verse),
        ('    ~ part %d "Strings"'):format(ids.strings),
        "      ~ volume: 0 -> -6",
      }, "\n"),
      "a change of the song, and one two levels down"
    )
    T.keys("G<CR>")
    eq(scope_path(), ("nest %d > nest %d"):format(ids.bridge, ids.verse), "the window shows Verse inside Bridge")
    eq(paw.cursor.part_id(), ids.strings, "the cursor is on Strings")
    T.keys("<Space>gdj<CR>")
    eq(scope_path(), "", "a change of the song goes back to the song")
    eq(paw.cursor.part_id(), row.id, "the cursor is on the song's row")
  end
)

test("projdiff: a quickfix entry of :Pdiff.qf goes inside the subproject of its change, as Enter does", function()
  start()
  T.after(function()
    paw.qf.set({})
    paw.scope.widen(true)
  end)
  local path, ids = nested("nest-qf")
  api.project_load(path)
  -- Inner is the second part of Bridge: the window enters on the first.
  api.part_set(ids.inner, { volume = -6 })
  api.part_set(ids.strings, { volume = -3 })
  api.undo_checkpoint()
  T.keys(":Pdiff.qf<CR>")
  eq(#paw.qf.current().entries, 2, "two changes")
  T.keys(":cnext<CR>")
  eq(scope_path(), "nest " .. ids.bridge, "the window shows Bridge")
  eq(paw.cursor.part_id(), ids.inner, "the cursor is on Inner")
  T.keys("]q")
  eq(scope_path(), ("nest %d > nest %d"):format(ids.bridge, ids.verse), "the window shows Verse inside Bridge")
  eq(paw.cursor.part_id(), ids.strings, "the cursor is on Strings")
end)

-- Git ----------------------------------------------------------------------------

local function run(command)
  local p = io.popen(command .. " 2>&1")
  local out = p:read("*a")
  p:close()
  return out
end

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
    local t = paw.add_part({ name = "Audio" })
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
    paw.parts()[1]:add_clip({ name = "odd", start = 16, length = 0.1 + 0.7 })
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

-- Project folders ----------------------------------------------------------------

local function part_named(name)
  for _, t in ipairs(paw.parts()) do
    if t.name == name then return t end
  end
end

--- The title and the text of the view of `:Pdiff`.
local function shown()
  local view = require("projdiff.view")
  return view.title_text .. "\n" .. table.concat(projdiff.diff.lines(view.tree), "\n")
end

test("projdiff: :Pdiff compares the project now with its saved folder and with another project folder", function()
  start()
  T.after(function() paw.ui.close() end)
  local dir = scratch .. "/pdiff-folders"
  os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
  local first = fixture(dir .. "/first", true)
  -- A clip of audio: the folder names its media relative to itself.
  local s = {}
  for i = 1, 4800 do
    s[i] = 0.1
  end
  part_named("Bass"):add_clip({ file = T.write_wav(dir .. "/tone.wav", s), start = 8, length = 2 })
  api.undo_checkpoint()
  api.project_save()
  api.project_load(first)
  T.keys(":Pdiff<CR>")
  eq(
    paw.ui.message and paw.ui.message.text,
    "saved → now: 0 changes (nothing differs)",
    "the folder reads as it opens"
  )
  api.project_save(dir .. "/second")
  part_named("Lead").volume = -5
  api.undo_checkpoint()
  T.keys(":Pdiff " .. first .. "<CR>")
  has(shown(), "first → now: 1 change", "the title")
  has(shown(), "~ volume: 0 -> -5", "the change")
  T.keys("q")
  local from = mark()
  T.keys(":Pdiff " .. dir .. "<CR>")
  eq(
    since(from)[1] and since(from)[1].text,
    dir .. " is a folder with no project.toml, so it is not a project",
    "a folder that is not a project is said plainly"
  )
end)

test(
  "projdiff: :Pdiff HEAD~1 reads the project folder at that revision of git, and leaves the files as they are",
  function()
    start()
    T.after(function() paw.ui.close() end)
    if os.execute("command -v git >/dev/null 2>&1") ~= 0 and os.execute("command -v git >/dev/null 2>&1") ~= true then
      return "no git"
    end
    local root = scratch .. "/pdiff-git"
    os.execute("rm -rf '" .. root .. "' && mkdir -p '" .. root .. "'")
    local function git(args) return run("cd '" .. root .. "' && git -c user.name=t -c user.email=t@t " .. args) end
    git("init -q -b main")
    local song = fixture(root .. "/song", true)
    api.project_load(song)
    git("add -A")
    git("commit -q -m base")
    part_named("Bass").volume = -9
    api.undo_checkpoint()
    api.project_save()
    git("commit -qam quieter")
    part_named("Lead"):add_clip({ name = "added", start = 16, length = 2 })
    api.undo_checkpoint()
    T.keys(":Pdiff HEAD~1<CR>")
    has(shown(), "HEAD~1 → now: 2 changes", "the title")
    has(shown(), "~ volume: 0 -> -9", "the change of the last commit")
    has(shown(), '"added"', "the edit not saved")
    T.keys("q")
    T.keys(":Pdiff HEAD~1 HEAD<CR>")
    has(shown(), "HEAD~1 → HEAD: 1 change", "between two revisions, only the commit")
    eq(git("status --porcelain"), "", "the files of the folder are as the last commit")
  end
)

test("projdiff: a snapshot kept beside a saved project folder compares with the project now", function()
  start()
  T.after(function() paw.ui.close() end)
  local song = fixture(scratch .. "/pdiff-snap", true)
  api.project_load(song)
  part_named("Lead").volume = -5
  api.undo_checkpoint()
  T.keys(":Psnapshot loud<CR>")
  local snaps = projdiff.snapshots()
  eq(snaps[#snaps].name, "loud", "the snapshot")
  eq(snaps[#snaps].file:find(song .. "/", 1, true), 1, "kept in the folder of the project")
  part_named("Lead"):add_clip({ name = "added", start = 16, length = 2 })
  api.undo_checkpoint()
  T.keys(":Pdiff snap:loud<CR>")
  has(shown(), "loud → now: 1 change", "the title")
  has(shown(), '"added"', "the clip added after the snapshot")
end)

-- Merges of project folders ------------------------------------------------------

local function no_git()
  local found = os.execute("command -v git >/dev/null 2>&1")
  return found ~= 0 and found ~= true
end

--- A new git repository at `root`, and a function that runs git in it.
local function repository(root)
  os.execute("rm -rf '" .. root .. "' && mkdir -p '" .. root .. "'")
  local function git(args) return run("cd '" .. root .. "' && git -c user.name=t -c user.email=t@t " .. args) end
  git("init -q -b main")
  return git
end

--- The id of the part named `name`, of the song or of a subproject.
local function part_id(name)
  for _, id in ipairs(api.part_list({ all = true })) do
    if api.part_get(id, "name") == name then return id end
  end
end

local function conflicts_now() return #projdiff.merge.conflicts(projdiff.state(nil)) end

test(
  "projdiff: :Pmerge on a project folder that a git merge stopped on settles its conflicts, one undo step each",
  function()
    start()
    T.after(function() paw.ui.close() end)
    if no_git() then return "no git" end
    local root = scratch .. "/pmerge-song"
    local git = repository(root)
    local song = fixture(root .. "/song", true)
    git("add -A")
    git("commit -q -m base")
    local riff = api.clip_list(part_id("Lead"))[1].id
    local function pitches(one, two)
      api.clip_note_set(riff, 1, { pitch = one })
      api.clip_note_set(riff, 2, { pitch = two })
      api.undo_checkpoint()
      api.project_save()
    end
    local function pitch(n) return api.clip_notes(riff)[n].pitch end
    git("checkout -q -b theirs")
    pitches(62, 65)
    git("commit -qam theirs")
    api.project_new()
    git("checkout -q main")
    api.project_load(song)
    pitches(61, 66)
    git("commit -qam ours")
    local from = mark()
    T.keys(":Pmerge<CR>")
    eq(since(from)[1] and since(from)[1].text, "git has no merge conflict in song", "no merge yet")
    -- A clip file is not text: git keeps ours in the folder, which opens.
    git("merge -q theirs")
    has(git("status --porcelain"), "UU song/parts/Lead/clips/riff.midi2", "git stopped on the clip")
    T.keys(":Pmerge<CR>")
    eq(paw.ui.float and paw.ui.float.name, "projmerge", "the conflicts show")
    has(T.screen(), "song: 2 conflicts", "the title")
    T.keys("ct")
    eq(pitch(1), 62, "ct took theirs")
    eq(conflicts_now(), 1, "one left")
    T.keys("co")
    eq(pitch(2), 66, "co kept ours")
    eq(paw.ui.float, nil, "the window closes when none is left")
    eq(conflicts_now(), 0, "none left")
    T.keys("u")
    eq(conflicts_now(), 1, "one u takes back one choice")
    eq(pitch(1), 62, "the first choice stays")
    T.keys("u")
    eq({ conflicts_now(), pitch(1) }, { 2, 61 }, "the next u takes back the first choice")
  end
)

test(
  "projdiff: :Pmerge shows a conflict inside a subproject under its name, two levels deep too, and settles it there",
  function()
    start()
    T.after(function() paw.ui.close() end)
    if no_git() then return "no git" end
    local root = scratch .. "/pmerge-nest"
    local git = repository(root)
    local song, ids = nested(root .. "/song", true)
    git("add -A")
    git("commit -q -m base")
    local function volumes(v)
      api.part_set(ids.keys, { volume = v })
      api.part_set(ids.strings, { volume = v })
      api.undo_checkpoint()
      api.project_save()
    end
    git("checkout -q -b theirs")
    volumes(-2)
    git("commit -qam theirs")
    api.project_new()
    git("checkout -q main")
    api.project_load(song)
    volumes(-6)
    git("commit -qam ours")
    api.project_new()
    -- The files of the parts are text: git marks the conflicts in them, so
    -- the folder does not open, and :Pmerge opens the merge.
    git("merge -q theirs")
    T.keys(":Pmerge " .. song .. "<CR>")
    eq(paw.ui.float and paw.ui.float.name, "projmerge", "the conflicts show")
    local view = require("projdiff.mergeview")
    local rows = {}
    for _, row in ipairs(view.rows) do
      local text = row.heading or projdiff.merge.describe(view.doc, row.conflict.path)
      rows[#rows + 1] = string.rep("  ", row.depth) .. text
    end
    eq(
      table.concat(rows, "\n"),
      table.concat({
        ('subproject %d "Bridge"'):format(ids.bridge),
        ('  part %d "Keys" › volume'):format(ids.keys),
        ('  subproject %d "Verse"'):format(ids.verse),
        ('    part %d "Strings" › volume'):format(ids.strings),
      }, "\n"),
      "each conflict under its subproject"
    )
    T.keys("ct")
    eq(api.part_get(part_id("Keys"), "volume"), -2, "theirs, in Bridge")
    T.keys("co")
    eq(api.part_get(part_id("Strings"), "volume"), -6, "ours, in Verse")
    eq(paw.ui.float, nil, "none left")
    eq(api.project_get("path"), song .. "/project.toml", "the open project is the folder")
  end
)

--- A git merge of the project folder `song` under `root` that stopped on
--- conflicts, where the two sides gave different things the same ids:
--- `base(path)` makes and saves the project, `theirs()` edits it on the
--- branch theirs, and `ours()` edits what theirs saved on the branch main.
--- The kernel never gives an id twice, so ours starts from the files of
--- theirs. Ours stays open. Returns the path of the song.
local function same_ids(root, base, theirs, ours)
  local git = repository(root)
  local song = root .. "/song"
  base(song)
  git("add -A")
  git("commit -q -m base")
  git("checkout -q -b theirs")
  theirs()
  api.undo_checkpoint()
  api.project_save()
  git("add -A")
  git("commit -q -m theirs")
  api.project_new()
  git("checkout -q main")
  git("checkout theirs -- song")
  api.project_load(song)
  ours()
  api.undo_checkpoint()
  api.project_save()
  git("add -A")
  git("commit -q -m ours")
  git("merge -q theirs")
  return song
end

--- The names of the subprojects of the open project, in order.
local function nest_names()
  local out = {}
  for _, n in ipairs(paw.nest.list()) do
    out[#out + 1] = n.name
  end
  return table.concat(out, ",")
end

--- The names of the parts of subproject `nest`, in order.
local function nest_parts(nest)
  local out = {}
  for _, id in ipairs(api.part_list({ nest = nest })) do
    out[#out + 1] = api.part_get(id, "name")
  end
  return table.concat(out, ",")
end

--- Add to the open project the subproject Bridge, whose part Keys plays
--- a note at its start, placed at beat 0 by the song's part Bridge.
local function add_bridge()
  local row = paw.add_part({ name = "Bridge" })
  local bridge = api.nest_add({ name = "Bridge", length = 4 })
  local keys = api.part_add({ name = "Keys", nest = bridge })
  paw.part(keys):add_device("synth")
  api.clip_add(keys, { name = "chords", start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  api.clip_add(row.id, { nest = bridge, start = 0 })
end

--- A project folder at `path` with a song part Drums, and with the
--- subproject Bridge when `bridge` is true.
local function song_at(path, bridge)
  fresh()
  paw.add_part({ name = "Drums" })
  if bridge then add_bridge() end
  api.undo_checkpoint()
  api.project_save(path)
end

test(
  "projdiff: :Pmerge keeps two subprojects that both sides added with the same id, and the merge saves, opens and plays",
  function()
    start()
    T.after(function() paw.ui.close() end)
    if no_git() then return "no git" end
    local song = same_ids(scratch .. "/pmerge-same-nest", song_at, add_bridge, function()
      -- Ours has the same ids as theirs: the subproject Verse with the part Pads, at beat 8.
      local nest = paw.nest.list()[1]
      api.nest_set(nest.id, "name", "Verse")
      local row = part_named("Bridge")
      row.name = "Verse"
      api.clip_set(api.clip_list(row.id)[1].id, "start", 8)
      api.part_set(part_id("Keys"), { name = "Pads" })
    end)
    eq(nest_names(), "Verse", "ours is open")
    T.keys(":Pmerge<CR>")
    eq(paw.ui.float, nil, "no conflict to settle")
    eq(nest_names(), "Verse,Bridge", "both subprojects")
    local verse, bridge = paw.nest.list()[1], paw.nest.list()[2]
    eq(verse.id ~= bridge.id, true, "with two ids")
    eq({ nest_parts(verse.id), nest_parts(bridge.id) }, { "Pads", "Keys" }, "each with its parts")
    T.keys("u")
    eq(nest_names(), "Verse", "one u takes back the merge")
    T.keys("<C-r>")
    api.project_save()
    api.project_new()
    api.project_load(song)
    eq(nest_names(), "Verse,Bridge", "both subprojects after the project opens again")
    local info = T.render({ tail = 0, bits = 16, ["end"] = 12 })
    eq(T.channel_peaks(info, 0, 0.4) > 0, true, "Bridge plays at beat 0")
    eq(T.channel_peaks(info, 4, 4.4) > 0, true, "Verse plays at beat 8")
  end
)

test("projdiff: :Pmerge keeps two parts that both sides added with the same id to one subproject", function()
  start()
  T.after(function() paw.ui.close() end)
  if no_git() then return "no git" end
  local song = same_ids(scratch .. "/pmerge-same-part", function(path) song_at(path, true) end, function()
    local bells = api.part_add({ name = "Bells", nest = paw.nest.list()[1].id })
    api.clip_add(bells, { name = "hit", start = 0, length = 1, notes = { { pitch = 72, start = 0, length = 1 } } })
  end, function()
    -- Ours renames the part only: its clip is the same as theirs, with the same id.
    api.part_set(part_id("Bells"), { name = "Choir" })
  end)
  T.keys(":Pmerge<CR>")
  local bridge = paw.nest.list()[1].id
  eq(nest_parts(bridge), "Keys,Bells,Choir", "both parts, in Bridge")
  local bells, choir = api.clip_list(part_id("Bells"))[1].id, api.clip_list(part_id("Choir"))[1].id
  eq({ part_id("Choir") ~= part_id("Bells"), bells ~= choir }, { true, true }, "two parts and two clips")
  api.project_save()
  api.project_new()
  api.project_load(song)
  eq(nest_parts(paw.nest.list()[1].id), "Keys,Bells,Choir", "both parts after the project opens again")
end)
