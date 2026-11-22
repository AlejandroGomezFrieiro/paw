-- Searching and opening, as Telescope, fzf-lua and Tree-sitter do in
-- Neovim: the pickers' modes and the keys every picker has (split, tab,
-- quickfix, delete, history, resume), the sources over the project, the
-- project grep (`:vimgrep`), structural queries (`paw.query`, `:select`)
-- and the motions and text objects of the tree. Loaded by tests/suite.lua
-- with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local pick = paw.pick

local function screen(w, h) return table.concat(api.ui_snapshot(w or 120, h or 30), "\n") end

local function has(text, part, what)
  if not text:find(part, 1, true) then error(string.format("%s: %q is not in\n%s", what or "text", part, text), 2) end
end

--- Strings, Violins pizz (two clips), Violas, a Piano with a lyric and an
--- articulation, a marker, a region; groups Strings ⊃ { Violins, Violas }.
local function song()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  T.after(function()
    if paw.ui.float then paw.ui.close() end
    paw.keymap.feed("<Esc><Esc>")
    -- The lists made here are not left for the tests after.
    paw.qf.close()
    local s = paw.qf.stack()
    s.lists, s.at = {}, 0
    paw.layout.only()
    while #paw.ui.tabs > 1 do
      paw.layout.tab_close()
    end
    paw.ui.views.pianoroll.clip_id = nil
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
  end)
  local violins = paw.add_track({ name = "Violins" })
  local violas = paw.add_track({ name = "Violas" })
  local piano = paw.add_track({ name = "Piano" })
  local strings = paw.groups.make({ violins, violas }, "Strings")
  local p1 = violins:add_clip({
    name = "pizz",
    start = 0,
    length = 4,
    notes = { { "C5", 0, 1 }, { "G4", 1, 1 }, { "E5", 2, 1, 120 } },
  })
  local p2 = violins:add_clip({ name = "arco", start = 4, length = 4, notes = { { "C6", 0, 2 } } })
  local p3 = violins:add_clip({ name = "pizz 2", start = 8, length = 4, notes = { { "D5", 0, 1 }, { "A3", 1, 1 } } })
  local va = violas:add_clip({ name = "pizz", start = 0, length = 4, notes = { { "C4", 0, 1 } } })
  local pc = piano:add_clip({
    name = "Verse",
    start = 0,
    length = 8,
    notes = {
      { pitch = "C4", start = 0, length = 1, meta = { lyric = "la", notation = { art = { staccato = true } } } },
      { pitch = "E4", start = 1, length = 1, meta = { lyric = "lo" } },
      { pitch = "G4", start = 2, length = 1 },
    },
  })
  paw.markers.add(0, "Intro")
  paw.markers.add(8, "Pizzicato", { length = 4 })
  paw.flush()
  api.undo_checkpoint()
  return {
    violins = violins,
    violas = violas,
    piano = piano,
    strings = strings,
    p1 = p1,
    p2 = p2,
    p3 = p3,
    va = va,
    pc = pc,
  }
end

-- Regular expressions -----------------------------------------------------------------

test("search: regular expressions become Lua patterns", function()
  local function find(re, s) return (paw.regex.compile(re):find(s)) end
  eq(find("pizz|spicc", "Violins spicc"), 9, "alternatives")
  eq(find("(pizz|spicc)ato", "pizzato"), 1, "a group of alternatives")
  eq(find("^la$", "la"), 1, "anchors")
  eq(find("^la$", "lala"), nil, "anchors hold")
  eq(find("\\d+ bars", "in 12 bars"), 4, "\\d and +")
  eq(find("colou?r", "color"), 1, "?")
  eq(find("a{2,3}", "baaa"), 2, "{n,m}")
  eq(find("[a-c]x", "zbx"), 2, "a class")
  eq(find("1.5", "1x5"), 1, "a dot is any character")
  eq(find("1\\.5", "1x5"), nil, "an escaped dot is a dot")
  eq(find("a-b", "a-b"), 1, "a dash is a dash")
  eq(find("verse", "VERSE"), 1, "lower case ignores case")
  eq(find("Verse", "VERSE"), nil, "a capital matches case")
  eq(find("\\D", "1a"), 2, "an upper-case class is not a capital")
  local re, err = paw.regex.try("(ab)+")
  eq(re, nil, "a group cannot repeat")
  has(err, "cannot repeat", "and says so")
  eq(paw.regex.try("[ab"), nil, "an open class is an error")
end)

-- The picker's modes ---------------------------------------------------------------------

test("search: fuzzy terms as fzf's, exact mode and regex mode", function()
  local function ranked(query, list, mode)
    local out = {}
    for i, r in ipairs(pick.filter(query, list, nil, nil, mode)) do
      out[i] = r.text
    end
    table.sort(out)
    return table.concat(out, ",")
  end
  local list = { "Bass Synth", "Brass", "Synth Pad", "bass drum" }
  eq(ranked("'ass", list), "Bass Synth,Brass,bass drum", "'word is found as written")
  eq(ranked("^syn", list), "Synth Pad", "^word starts the line")
  eq(ranked("synth$", list), "Bass Synth", "word$ ends it")
  eq(ranked("'bass !drum", list), "Bass Synth", "!word is not in it")
  eq(ranked("bss", list, "exact"), "", "exact mode takes the letters as they are")
  eq(ranked("ass syn", list, "exact"), "Bass Synth", "each word anywhere")
  eq(ranked("^(bass|brass)", list, "regex"), "Bass Synth,Brass,bass drum", "regex mode")
  eq(ranked("[", list, "regex"), "", "a bad expression matches nothing")
end)

test("search: Ctrl-r steps the mode, remembered for the picker; a bad regex says why", function()
  song()
  paw.state["pick.mode.tracks"] = nil
  T.after(function() paw.state["pick.mode.tracks"] = nil end)
  paw.pick("tracks")
  eq(pick.state().mode, "fuzzy", "fuzzy first")
  paw.keymap.feed("vls")
  eq(#pick.state().matches, 2, "fuzzy: v-l-s is in Violins and Violas")
  paw.keymap.feed("<C-r>")
  eq(pick.state().mode, "exact", "Ctrl-r: exact")
  eq(#pick.state().matches, 0, "vls is in no name as written")
  has(screen(), "exact", "the mode is shown")
  paw.keymap.feed("<C-r>")
  eq(pick.state().mode, "regex", "then regex")
  paw.keymap.feed("<C-u>Vio(lins|las)$")
  eq(#pick.state().matches, 2, "a regex matches")
  paw.keymap.feed("<C-u>(ab)+")
  has(screen(), "cannot repeat", "a bad one says why")
  paw.keymap.feed("<Esc>")
  paw.pick("tracks")
  eq(pick.state().mode, "regex", "the mode is kept for the picker")
  paw.keymap.feed("<C-r>")
  eq(pick.state().mode, "fuzzy", "and steps round")
  paw.keymap.feed("<Esc>")
end)

-- Keys every picker has --------------------------------------------------------------------

test("search: Ctrl-q sends what matches, or what is marked, to the quickfix list", function()
  song()
  paw.pick("clips")
  paw.keymap.feed("pizz<C-q>")
  eq(pick.state(), nil, "the picker closes")
  local list = paw.qf.current()
  eq(list.title, "Clips · pizz", "titled by the picker and the query")
  eq(#list.entries, 3, "every clip that matches")
  eq(list.entries[1].address:match("^paw://clip/%d+$") ~= nil, true, "with its address")
  paw.qf.close()
  paw.pick("tracks")
  paw.keymap.feed("<Tab><Tab><C-q>")
  list = paw.qf.current()
  eq(#list.entries, 2, "Tab marks; the marked go")
  paw.qf.close()
  paw.pick("tracks")
  paw.keymap.feed("<C-a>")
  eq(#pick.state().marked, 4, "Ctrl-a marks every line")
  paw.keymap.feed("<C-a>")
  eq(#pick.state().marked, 0, "and again none")
  paw.keymap.feed("<Esc>")
end)

test("search: Ctrl-v, Ctrl-x and Ctrl-t open what is chosen beside, below, in a tab", function()
  local s = song()
  local windows = #paw.layout.windows()
  paw.pick("clips")
  paw.keymap.feed("arco<C-v>")
  eq(paw.ui.focused, "pianoroll", "a MIDI clip opens in the piano roll")
  eq(paw.ui.views.pianoroll.clip_id, s.p2.id, "on that clip")
  eq(#paw.layout.windows() > windows, true, "in a new window")
  paw.layout.only()
  local tabs = #paw.ui.tabs
  paw.pick("tracks")
  paw.keymap.feed("Piano<C-t>")
  eq(#paw.ui.tabs, tabs + 1, "Ctrl-t: a tab")
  eq(paw.cursor.track_id(), s.piano.id, "with the cursor on the track")
  paw.layout.tab_close()
  paw.pick("help")
  paw.keymap.feed("pickers<C-x>")
  local cur = paw.layout.current()
  eq(paw.help.is_help(paw.layout.buf_of(cur)), true, "help opens below")
  paw.layout.only()
end)

test("search: Alt-d deletes in the picker, which stays open, as one undo step", function()
  local s = song()
  paw.pick("clips")
  paw.keymap.feed("arco<A-d>")
  api.undo_checkpoint()
  eq(pick.state() ~= nil, true, "the picker stays")
  eq(pcall(api.clip_get, s.p2.id), false, "the clip is gone")
  eq(#pick.state().matches, 0, "and from the list")
  paw.keymap.feed("<Esc>")
  paw.undo()
  eq(pcall(api.clip_get, s.p2.id), true, "u brings it back")
  paw.markers.add(4, "Verse")
  paw.pick("markers")
  paw.keymap.feed("<Tab><Tab><A-d><Esc>")
  eq(#paw.markers.list(), 1, "marked markers go together; the region stays")
end)

test("search: Ctrl-Up and Ctrl-Down step through what was typed before; resume as it was", function()
  song()
  paw.state["pick.history.tracks"] = nil
  paw.pick("tracks")
  paw.keymap.feed("vio<CR>")
  paw.pick("tracks")
  paw.keymap.feed("pia<CR>")
  paw.pick("tracks")
  paw.keymap.feed("st<C-Up>")
  eq(pick.state().query, "pia", "the last query")
  paw.keymap.feed("<C-Up>")
  eq(pick.state().query, "vio", "the one before")
  paw.keymap.feed("<C-Down><C-Down>")
  eq(pick.state().query, "st", "back to what was typed")
  paw.keymap.feed("<C-u>vio<C-r><C-n><Esc>")
  paw.commands.exec("pick resume")
  local st = pick.state()
  eq(st.query .. " " .. st.mode .. " " .. st.selected, "vio exact 2", "`:pick resume`: the query, the mode, the line")
  paw.keymap.feed("<C-r><C-r><Esc>")
end)

test("search: every picker opens and draws", function()
  song()
  for name in pairs(pick.sources) do
    if name ~= "presets" and not name:match("^_") then
      pick(name)
      eq(pick.state() ~= nil, true, name .. " opens")
      screen()
      paw.keymap.feed("<Esc>")
    end
  end
end)

-- Sources over the project --------------------------------------------------------------

test("search: notes by lyric and articulation, drawn in a small piano roll", function()
  local s = song()
  paw.pick("notes")
  paw.keymap.feed("staccato")
  eq(#pick.state().matches, 1, "one staccato note")
  has(screen(), "“la”", "its line has its lyric")
  has(screen(), "█", "the preview draws the notes")
  has(screen(), "▓", "the note chosen apart")
  paw.keymap.feed("<CR>")
  eq(paw.ui.focused, "pianoroll", "Enter goes to it")
  eq(paw.ui.views.pianoroll.clip_id, s.pc.id, "in its clip")
end)

test("search: regions, help tags, the Lua API and the undo history as pickers", function()
  song()
  paw.pick("regions")
  paw.keymap.feed("pizzicato<CR>")
  eq(paw.cursor.beat, 8, "a region's start")
  paw.pick("symbols")
  paw.keymap.feed("paw.query.run")
  has(screen(), "paw.query.run(q)", "a function with its parameters")
  has(screen(), "Every node", "and the comment above it")
  paw.keymap.feed("<Esc>")
  paw.pick("undo")
  eq(#pick.state().matches > 1, true, "the states of the history")
  paw.keymap.feed("<Esc>")
  paw.pick("extensions")
  eq(#pick.state().matches > 0, true, "the extensions")
  paw.keymap.feed("<Esc>")
end)

-- The project's text -------------------------------------------------------------------

test("search: :vimgrep fills the quickfix list from every kind of text, and :cdo acts on it", function()
  local s = song()
  paw.commands.exec("vimgrep /pizz/j")
  local list = paw.qf.current()
  eq(list.title, "vimgrep /pizz/", "titled by the pattern")
  local fields = {}
  for _, e in ipairs(list.entries) do
    fields[#fields + 1] = e.text:match("^(%a+):")
  end
  eq(table.concat(fields, " "), "clip clip clip region", "clips and the region")
  paw.commands.exec("vimgrep /^l[ao]$/j lyric")
  eq(#paw.qf.current().entries, 2, "only lyrics")
  paw.commands.exec("vimgrep /^staccato$/ art")
  eq(paw.ui.focused, "pianoroll", "the first is gone to")
  paw.commands.exec("vimgrep /^Viol/j track")
  paw.commands.exec("cdo track.mute")
  eq(s.violins.mute and s.violas.mute and not s.piano.mute, true, ":cdo mutes the tracks found")
  paw.commands.exec("vimgrep /nothing at all/")
  eq(paw.qf.current().title, "vimgrep /^Viol/", "nothing found leaves the list")
end)

test("search: the live grep picker finds any text, and goes there", function()
  local s = song()
  paw.pick("grep")
  paw.keymap.feed("lo")
  eq(pick.state().mode, "exact", "exact by default")
  local lines = pick.state().matches
  eq(#lines, 1, "one text holds lo")
  has(lines[1], "lyric", "a lyric")
  paw.keymap.feed("<CR>")
  eq(paw.ui.views.pianoroll.clip_id, s.pc.id, "Enter goes to the note")
end)

test("search: the notation extension's text and dynamics are text to search", function()
  local s = song()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  api.clip_set(
    s.pc.id,
    "meta",
    {
      notation = {
        version = 1,
        marks = { { kind = "text", at = 4, value = "Allegro" }, { kind = "dynamic", at = 0, value = "mf" } },
      },
    }
  )
  paw.commands.exec("vimgrep /allegro|^mf$/j")
  local texts = {}
  for _, e in ipairs(paw.qf.current().entries) do
    texts[#texts + 1] = e.text
  end
  eq(table.concat(texts, ", "), "text: Allegro, dynamic: mf", "both, with what they are")
end)

-- Structural queries ------------------------------------------------------------------------

local function names(nodes)
  local out = {}
  for i, n in ipairs(nodes) do
    out[i] = n.kind == "note" and paw.music.name(n.data.pitch) or n.data.name or tostring(n.id)
  end
  return table.concat(out, " ")
end

test("search: queries find nodes by kind, fields and where they sit", function()
  song()
  eq(names(paw.query("clip[name~=pizz] > note[pitch>=C5]")), "C5 E5 D5", "the example")
  eq(names(paw.query("group[name=Strings] track")), "Violins Violas", "tracks inside a group")
  eq(names(paw.query("track[name^=vio] clip")), "pizz arco pizz 2 pizz", "a track's clips")
  eq(names(paw.query("note[lyric=la|lo]")), "C4 E4", "either value")
  eq(names(paw.query("note[art=staccato]")), "C4", "articulations")
  eq(names(paw.query("clip:has(note[vel>110])")), "pizz", ":has")
  eq(names(paw.query("note[pitch=c]")), "C5 C6 C4 C4", "a pitch in any octave")
  eq(names(paw.query("clip[name*=pizz][!muted], region")), "pizz pizz 2 pizz Pizzicato", "a list of queries")
  eq(names(paw.query("note[len>1/4]")), "C6", "a note value as a length")
  eq(
    names(paw.query({ { "clip", name = "~= ^pizz$" }, ">", { "note", function(n) return n.data.pitch > 72 end } })),
    "E5",
    "the table form"
  )
  local ok, err = pcall(paw.query, "clip[name~~x]")
  eq(ok, false, "a bad test is an error")
  has(err, "needs an operator", "that says what is wrong")
  ok, err = pcall(paw.query, "chord")
  has(err, "no kind `chord`", "and an unknown kind")
end)

test("search: :select chooses the notes or clips found; :query only lists them", function()
  local s = song()
  paw.commands.exec("select clip[name=pizz] > note[pitch>=C5]")
  eq(table.concat(paw.frontend.chosen_notes(s.p1.id), ","), "1,3", "the notes, chosen")
  eq(#paw.qf.current().entries, 2, "and in the quickfix list")
  eq(paw.ui.focused, "pianoroll", "the first is shown")
  paw.ui.focus("arrange")
  paw.commands.exec("select clip[name^=pizz]")
  local chosen = paw.frontend.chosen_clips()
  eq(#chosen, 3, "the clips, chosen")
  paw.keymap.feed("<Esc>")
  paw.commands.exec("query track[name=Piano]")
  eq(paw.qf.current().title, "query track[name=Piano]", ":query lists")
  eq(paw.qf.current().entries[1].text, "track Piano", "in words")
end)

-- The tree's motions and text objects -------------------------------------------------------

test("search: ]c and [c go to the clips of the same kind, ]s [s [u ]u through groups", function()
  local s = song()
  paw.cursor.set_track(s.violins.id)
  paw.cursor.set_beat(0)
  local pan = s.violins.pan
  paw.keymap.feed("]c")
  eq(paw.cursor.beat, 8, "]c passes arco for pizz 2")
  eq(s.violins.pan, pan, "the pan that ] made at once is taken back")
  paw.keymap.feed("[c")
  eq(paw.cursor.beat, 0, "[c back")
  paw.keymap.feed("]s")
  eq(paw.cursor.track_id(), s.violas.id, "]s the next track of the group")
  paw.keymap.feed("[s")
  eq(paw.cursor.track_id(), s.violins.id, "[s the one before")
  paw.keymap.feed("[u")
  eq(paw.cursor.track_id(), s.strings.id, "[u up to the group")
  paw.keymap.feed("]s")
  eq(paw.cursor.track_id(), s.piano.id, "]s on the group: the next at its level")
  paw.cursor.set_track(s.strings.id)
  paw.keymap.feed("]u")
  eq(paw.cursor.track_id(), s.violins.id, "]u into it")
  paw.keymap.feed("yig")
  eq(#paw.keymap.registers['"'].tracks, 2, "yig yanks the group's tracks")
  paw.keymap.feed("yag")
  eq(#paw.keymap.registers['"'].tracks, 3, "yag with the group")
end)

test("search: ]n and [n in the piano roll go to the notes of the same pitch", function()
  fresh()
  local t = paw.add_track({ name = "T" })
  local c =
    t:add_clip({ start = 0, length = 8, notes = { { "C4", 0, 1 }, { "D4", 1, 1 }, { "C4", 3, 1 }, { "C4", 6, 1 } } })
  local roll = paw.ui.views.pianoroll
  roll:edit(c)
  T.after(function()
    roll.clip_id = nil
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
  end)
  paw.ui.focus("pianoroll")
  roll:set(60, 0)
  paw.keymap.feed("]n")
  eq(roll.beat, 3, "the next C4")
  eq(c:notes()[1].velocity, 100, "the velocity that ] changed at once is put back")
  paw.keymap.feed("2]n")
  eq(roll.beat, 6, "a count goes on")
  paw.keymap.feed("[n")
  eq(roll.beat, 3, "back")
end)

-- Size ---------------------------------------------------------------------------------------

test("search: a hundred tracks of a hundred notes each stay quick to search", function()
  fresh()
  for i = 1, 100 do
    local notes = {}
    for k = 1, 100 do
      notes[k] = { 48 + (k % 24), (k - 1) * 0.25, 0.25, 90, meta = k % 10 == 0 and { lyric = "la" .. k } or nil }
    end
    paw.add_track({ name = "Track " .. i }):add_clip({ name = "clip " .. i, start = 0, length = 32, notes = notes })
  end
  local t0 = api.now()
  local found = paw.query("track[name$=7] > clip > note[pitch>=C4][vel>80]")
  local query_ms = api.now() - t0
  eq(#found > 0, true, "found some")
  t0 = api.now()
  local records = paw.grep.search("la1", { mode = "exact" })
  local grep_ms = api.now() - t0
  eq(#records > 0, true, "and some lyrics")
  t0 = api.now()
  paw.pick("notes")
  paw.keymap.feed("C5 la")
  local pick_ms = api.now() - t0
  eq(#pick.state().matches > 0, true, "the notes picker narrows")
  paw.keymap.feed("<Esc>")
  -- Generous, for a loaded machine: the 1000-track measure is in the report.
  eq(
    query_ms < 2000 and grep_ms < 2000 and pick_ms < 4000,
    true,
    string.format("query %d ms, grep %d ms, notes picker %d ms", query_ms, grep_ms, pick_ms)
  )
end)
