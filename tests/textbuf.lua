-- Tests of the listings edited as text (paw/textbuf.tl and
-- paw/views/tracklist.lua): reading and writing lines, each kind of edit,
-- the plan `:w` shows, one undo step, and buffers that fall behind the
-- project. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local L = paw.layout
local tb = paw.textbuf

local W, H = 160, 48
local initial = L.capture()

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  L.restore(initial)
  paw.ui.focus("arrange")
  -- Buffers of an earlier test are forgotten, so that each reads afresh.
  for _, buf in ipairs(L.buffers_list()) do
    if buf.type == "textbuf" then L.buf_delete(buf) end
  end
end

local keys = T.keys

local function screen() return table.concat(api.ui_snapshot(W, H), "\n") end

local function lines()
  local out = {}
  for i, l in ipairs(tb.buf().state.text.lines) do
    out[i] = l.text
  end
  return out
end

local function line(n) return lines()[n] end

local function names()
  local out = {}
  for i, id in ipairs(api.track_list()) do
    out[i] = api.track_get(id).name
  end
  return table.concat(out, " ")
end

--- `:w` and `y`: the plan shown, then applied.
local function write()
  keys(":w<CR>")
  eq(paw.ui.focused, "textbuf.plan", "the plan is shown")
  local shown = {}
  for _, step in ipairs(paw.ui.views["textbuf.plan"].shown) do
    shown[#shown + 1] = step.text
  end
  keys("y")
  return table.concat(shown, "\n")
end

local function band()
  local drums = paw.add_track({ name = "Drums", volume = -3 })
  drums:add_device("synth")
  local bass = paw.add_track({ name = "Bass", volume = -6, pan = -0.1 })
  local pad = paw.add_track({ name = "Pad" })
  paw.flush()
  api.undo_checkpoint()
  return drums, bass, pad
end

-- Reading and writing lines -----------------------------------------------------

test("a track list reads as aligned lines that read back as the same fields", function()
  start()
  band()
  keys(":e paw://tracks<CR>")
  eq(L.current().view, "textbuf", "the buffer is in this window")
  eq(tb.buf().name, "paw://tracks", "named by its address")
  local text = lines()
  eq(#text, 3, "a line a track")
  eq(
    text[1]:match("^Drums%s+vol %-3%.0  pan C%s+%-%-%-  .*▸ ") ~= nil,
    true,
    "name, volume, pan, flags, devices: " .. text[1]
  )
  eq(text[2]:match("^Bass%s+vol %-6%.0  pan L10") ~= nil, true, "pan to the left: " .. text[2])
  -- Columns line up.
  eq(text[1]:find("vol", 1, true), text[3]:find("vol", 1, true), "the volumes line up")
  -- Every line reads back as the fields it was written from.
  local buf = tb.buf()
  for i, l in ipairs(buf.state.text.lines) do
    local f = buf.state.kind.parse(l.text)
    eq(f ~= nil, true, "line " .. i .. " reads")
    eq(tb.same(f, buf.state.fields[l.id]), true, "line " .. i .. " reads as it was written")
  end
  eq(tb.buf().state.text:modified(), false, "nothing changed")
  eq(screen():find("paw://tracks", 1, true) ~= nil, true, "the window shows it")
end)

test("a line that does not read says why and stops the write", function()
  start()
  band()
  keys(":e paw://tracks<CR>")
  keys("A  vol loud<Esc>")
  local text = screen()
  eq(text:find("vol is in dB", 1, true) ~= nil, true, "the error is shown under the line")
  keys(":w<CR>")
  eq(paw.ui.focused ~= "textbuf.plan", true, "no plan")
  eq(names(), "Drums Bass Pad", "nothing changed")
  keys("jA  bogus<Esc>:w<CR>")
  eq(L.current().state.row, 1, "the cursor goes to the first line that does not read")
end)

-- Edits ------------------------------------------------------------------------

test("cw renames a track, Ctrl-a changes its volume, and :w applies both as one undo step", function()
  start()
  local _, bass = band()
  keys(":e paw://tracks<CR>")
  keys("jcwBassline<Esc>")
  eq(line(2):match("^Bassline  ") ~= nil, true, "cw leaves the spaces after the word: " .. line(2))
  keys("fv3<C-a>")
  eq(line(2):find("vol -3.0", 1, true) ~= nil, true, "Ctrl-a with a count adds to the number: " .. line(2))
  eq(tb.buf().state.text:modified(), true, "modified")
  eq(screen():find("[+]", 1, true) ~= nil, true, "the title says so")
  local plan = write()
  eq(plan:find("rename Bass → Bassline", 1, true) ~= nil, true, "the plan renames: " .. plan)
  eq(plan:find("volume -6.0 → -3.0 dB", 1, true) ~= nil, true, "and sets the volume")
  eq(bass.name, "Bassline", "renamed")
  eq(bass.volume, -3, "louder")
  eq(tb.buf().state.text:modified(), false, "read again, unmodified")
  paw.undo()
  paw.flush()
  eq(bass.name, "Bass", "one undo takes the name back")
  eq(bass.volume, -6, "and the volume")
  eq(line(2):match("^Bass ") ~= nil, true, "the buffer follows the undo")
end)

test("dd deletes a track, yyp copies one with its devices, and moving lines orders them", function()
  start()
  local drums = band()
  keys(":e paw://tracks<CR>")
  keys("Gdd")
  keys("ggyyp")
  keys("cwBeat<Esc>")
  -- Bass to the top.
  keys("Gddggp")
  eq(
    table.concat(lines(), "|"):gsub("%s+", " "):match("^Drums.-|Bass.-|Beat") ~= nil,
    true,
    "Bass after Drums, then the copy"
  )
  local plan = write()
  eq(plan:find("delete Pad", 1, true) ~= nil, true, "the plan deletes: " .. plan)
  eq(plan:find("copy Drums as Beat (1 device", 1, true) ~= nil, true, "copies with the devices")
  eq(plan:find("move Bass from 2", 1, true) == nil, true, "Bass stays second")
  eq(names(), "Drums Bass Beat", "deleted, copied and in order")
  local beat = paw.track("Beat")
  eq(#beat:devices(), 1, "the copy has the devices")
  eq(beat.volume, drums.volume, "and the volume")
  paw.undo()
  eq(names(), "Drums Bass Pad", "one undo puts it all back")
end)

test("a line moved is the track moved, not deleted and made again", function()
  start()
  local _, bass = band()
  local id = bass.id
  keys(":e paw://tracks<CR>")
  keys("jddp")
  eq(line(3):match("^Bass") ~= nil, true, "Bass last")
  local plan = write()
  eq(plan, "move Bass from 2 to 3", "a move alone")
  eq(names(), "Drums Pad Bass", "moved")
  eq(api.track_list()[3], id, "the same track")
end)

test("new lines make tracks, with devices named on them", function()
  start()
  band()
  keys(":e paw://tracks<CR>")
  keys("GoLead  vol -12  ▸ synth<Esc>")
  local plan = write()
  eq(plan:find("add Lead with synth", 1, true) ~= nil, true, "the plan adds: " .. plan)
  local lead = paw.track("Lead")
  eq(lead.volume, -12, "at its volume")
  eq(#lead:devices(), 1, "with its device")
  eq(api.track_list()[4], lead.id, "where the line is")
end)

test("flags, outputs and groups are fields of the line", function()
  start()
  local drums, bass = band()
  keys(":e paw://tracks<CR>")
  -- Mute the bass with `r`, and send it out through the drums.
  keys("j0/---<CR>")
  keys("rM")
  keys("A  out Drums<Esc>")
  local plan = write()
  eq(plan:find("Bass: mute on", 1, true) ~= nil, true, "mute: " .. plan)
  eq(plan:find("Bass: output → Drums", 1, true) ~= nil, true, "output")
  eq(bass.mute, true, "muted")
  eq(api.track_get(bass.id).output, drums.id, "routed")
  eq(line(2):find("out Drums", 1, true) ~= nil, true, "the line says so after reading again")
  -- An output to a track that is not there.
  keys("j$a  out Nowhere<Esc>:w<CR>")
  eq(paw.ui.focused ~= "textbuf.plan", true, "no plan")
end)

test("visual block and :s edit several lines at once", function()
  start()
  band()
  keys(":e paw://tracks<CR>")
  keys(":%s/vol %-?%d+%.%d/vol -9.0/<CR>")
  eq(
    line(1):find("vol -9.0", 1, true) ~= nil and line(3):find("vol -9.0", 1, true) ~= nil,
    true,
    ":% s changes every line"
  )
  keys("u")
  eq(line(1):find("vol -3.0", 1, true) ~= nil, true, "u takes it back")
  -- Ctrl-v down the flag column and `r` mutes all three.
  local col = line(1):find("---", 1, true) - 1
  keys("gg0" .. col .. "l<C-v>jjrM")
  eq(
    line(1):sub(col + 1, col + 1) .. line(2):sub(col + 1, col + 1) .. line(3):sub(col + 1, col + 1),
    "MMM",
    "a block of flags replaced"
  )
  -- And `I` in a block types on every line.
  keys("gg0<C-v>jjIX<Esc>")
  eq(line(1):sub(1, 1) .. line(2):sub(1, 1) .. line(3):sub(1, 1), "XXX", "typed on every line of the block")
  keys("u")
  local plan = write()
  eq(
    plan:find("Drums: mute on", 1, true) ~= nil and plan:find("Pad: mute on", 1, true) ~= nil,
    true,
    "the plan mutes all: " .. plan
  )
end)

test(":sort orders the lines and so the tracks", function()
  start()
  band()
  keys(":e paw://tracks<CR>")
  keys(":sort<CR>")
  eq(lines()[1]:match("^Bass") ~= nil, true, "sorted")
  write()
  eq(names(), "Bass Drums Pad", "the tracks are in the lines' order")
  keys(":sort!<CR>")
  write()
  eq(names(), "Pad Drums Bass", "and the other way")
end)

test(". repeats a change to the text, and u and Ctrl-r undo and redo it", function()
  start()
  band()
  keys(":e paw://tracks<CR>")
  keys("fv<C-a>")
  keys("j.")
  eq(line(2):find("vol -5.0", 1, true) ~= nil, true, ". repeats Ctrl-a: " .. line(2))
  keys("A  color #ff0000<Esc>j.")
  eq(line(3):find("color #ff0000", 1, true) ~= nil, true, ". repeats an insert")
  keys("u")
  eq(line(3):find("color", 1, true), nil, "u undoes it")
  keys("<C-r>")
  eq(line(3):find("color #ff0000", 1, true) ~= nil, true, "Ctrl-r redoes it")
  keys("uuuu")
  eq(tb.buf().state.text:modified(), false, "undone to what was read")
end)

-- Other buffers -------------------------------------------------------------------

test("the sends buffer adds, changes and removes sends", function()
  start()
  local drums, bass, pad = band()
  local verb = paw.add_track({ name = "Verb" })
  drums:send(verb, -12)
  paw.flush()
  api.undo_checkpoint()
  keys(":e paw://sends<CR>")
  eq(#lines(), 1, "a line a send")
  eq(line(1):match("^Drums  → Verb  %-12%.0 dB  post$") ~= nil, true, "from, to, level, post: " .. line(1))
  keys("yyp0cwBass<Esc>")
  keys("k0f-3<C-a>")
  local plan = write()
  eq(plan:find("add a send Bass → Verb at -12.0 dB", 1, true) ~= nil, true, "a send added: " .. plan)
  eq(plan:find("Drums → Verb: -12.0 → -9.0 dB", 1, true) ~= nil, true, "a level changed")
  eq(api.track_get(bass.id).sends[1].target, verb.id, "the bass sends")
  eq(api.track_get(drums.id).sends[1].level, -9, "the drums' level")
  keys("ggdd")
  plan = write()
  eq(#api.track_get(drums.id).sends, 0, "a send removed: " .. plan)
  eq(pad.name, "Pad", "the other tracks are left alone")
end)

test("a track's devices buffer orders, bypasses, copies and adds devices", function()
  start()
  local drums = band()
  drums:add_device("eq")
  paw.flush()
  api.undo_checkpoint()
  keys(":e paw://tracks<CR>")
  keys("<CR>")
  eq(tb.buf().name, "paw://track/1/devices", "Enter opens the track's devices")
  eq(#lines(), 2, "a line a device")
  local first = lines()[1]
  eq(first:find("  on  wet 100%", 1, true) ~= nil, true, "on, and the wet share: " .. first)
  -- The second device first, the first bypassed, a copy of it, a new one.
  keys("jddkP")
  keys("j0/on<CR>cwoff<Esc>")
  keys("yyp")
  keys("Goreverb<Esc>")
  local plan = write()
  eq(plan:find("off (bypassed)", 1, true) ~= nil, true, "bypass: " .. plan)
  eq(plan:find("add reverb", 1, true) ~= nil, true, "add")
  eq(plan:find("put the chain in the order", 1, true) ~= nil, true, "order")
  local list = drums:devices()
  eq(#list, 4, "four devices")
  eq(list[1]:get().kind, "eq", "the eq first")
  eq(list[2]:get().bypass and list[3]:get().bypass, true, "the synth and its copy bypassed")
  eq(list[4]:get().kind, "reverb", "the new one last")
  keys("-")
  eq(tb.buf().name, "paw://tracks", "- goes up to the tracks")
  paw.undo()
  eq(#drums:devices(), 2, "one undo")
end)

test("the markers buffer moves, renames and adds markers and regions", function()
  start()
  paw.markers.add(0, "Intro")
  paw.markers.add(16, "Verse", { length = 16 })
  paw.flush()
  api.undo_checkpoint()
  keys(":e paw://markers<CR>")
  eq(line(1), "1.1  Intro", "a marker: where and its name")
  eq(line(2), "5.1  Verse  to 9.1", "a region: where it ends")
  keys("j<C-a>")
  eq(line(2), "6.1  Verse  to 9.1", "Ctrl-a moves it a bar")
  keys("oChorus<Esc>0i9.1  <Esc>")
  keys("$a  to 13.1<Esc>")
  local plan = write()
  eq(plan:find("change the region Verse at 5.1 to region Verse at 6.1", 1, true) ~= nil, true, "moved: " .. plan)
  eq(plan:find("add the region Chorus at 9.1", 1, true) ~= nil, true, "added")
  local chorus = paw.markers.find("Chorus")
  eq(chorus.beat, 32, "at bar 9")
  eq(chorus.length, 16, "four bars long")
  eq(paw.markers.find("Verse").beat, 20, "Verse a bar later")
end)

-- Conflicts ------------------------------------------------------------------------

test("an unmodified buffer follows the project, and a modified one will not overwrite it unasked", function()
  start()
  local drums, bass = band()
  keys(":e paw://tracks<CR>")
  bass.name = "Low"
  paw.flush()
  screen()
  eq(line(2):match("^Low") ~= nil, true, "read again when the project changes")
  keys("ggcwKick<Esc>")
  bass.volume = -1
  paw.flush()
  screen()
  eq(tb.buf().state.conflict, true, "behind the project")
  eq(screen():find("changed elsewhere", 1, true) ~= nil, true, "and says so")
  keys(":w<CR>")
  eq(paw.ui.focused ~= "textbuf.plan", true, ":w does not write over it")
  eq(drums.name, "Drums", "nothing written")
  keys(":w!<CR>")
  eq(paw.ui.focused, "textbuf.plan", ":w! does")
  keys("y")
  eq(drums.name, "Kick", "the change made")
  eq(bass.volume, -1, "and the change made elsewhere kept: only what the lines changed is written")
  keys("cwSnare<Esc>:e!<CR>")
  eq(line(1):match("^Kick") ~= nil, true, ":e! reads it again")
end)

test("a buffer with changes asks before it is closed", function()
  start()
  band()
  keys(":e paw://tracks<CR>")
  keys(":vs paw://markers<CR>")
  keys("<C-w>h")
  keys("dd:q<CR>")
  eq(L.current().view, "textbuf", ":q with changes does not close")
  keys(":q!<CR>")
  eq(tb.buf() and tb.buf().name, "paw://markers", ":q! does, throwing the changes away")
end)

-- Round trips, extensions and the window -------------------------------------------

test("names that would not read back are quoted, and every kind reads back what it writes", function()
  start()
  local odd = paw.add_track({ name = "Lead  Vox" })
  paw.add_track({ name = "vol" })
  local verb = paw.add_track({ name = "Verb" })
  odd:send(verb, -120, { pre = true })
  odd:add_device("synth")
  paw.markers.add(0.5, "")
  paw.markers.add(6, "Bridge  B", { length = 2.25, color = "#9ece6a" })
  paw.flush()
  api.undo_checkpoint()
  for _, name in ipairs({ "paw://tracks", "paw://sends", "paw://track/1/devices", "paw://markers" }) do
    keys(":e " .. name .. "<CR>")
    local buf = tb.buf()
    eq(buf.name, name, "shown")
    for i, l in ipairs(buf.state.text.lines) do
      local f, err = buf.state.kind.parse(l.text, { args = buf.state.args })
      eq(err, nil, name .. " line " .. i .. " reads: " .. l.text)
      eq(tb.same(f, buf.state.fields[l.id]), true, name .. " line " .. i .. " reads as written")
    end
    eq(#tb.plan(buf), 0, name .. ": nothing to change, nothing to plan")
  end
  keys(":e paw://tracks<CR>")
  eq(line(1):match('^"Lead  Vox"') ~= nil, true, "two spaces in a name are quoted: " .. line(1))
  keys(":e paw://sends<CR>")
  eq(line(1):find("-inf dB  pre", 1, true) ~= nil, true, "silence and before the fader: " .. line(1))
  keys(":e paw://markers<CR>")
  eq(line(1), "1.1.50", "a marker without a name, half a beat in")
  eq(line(2), '2.3     "Bridge  B"  to 3.1.25  color #9ece6a', "a region with a colour, ending part way through a beat")
end)

test("cells, alignment and Ctrl-a on numbers", function()
  eq(tb.align({ { "a", "vol 1" }, { "long", "vol 2", "x" } })[1], "a     vol 1", "padded to the widest")
  local cells = tb.cells("Lead Vox  vol -3.0    pan C")
  eq(
    #cells .. " " .. cells[1].text .. "|" .. cells[2].text .. "|" .. cells[3].col,
    "3 Lead Vox|vol -3.0|22",
    "single spaces stay inside a cell"
  )
  eq(tb.add_number("vol -6.0", 0, 1), "vol -5.0", "the number after the cursor, with its sign and decimals")
  eq(tb.add_number("vol -0.5", 5, 1), "vol 0.5", "across zero")
  eq(tb.add_number("pan L10", 0, 5), "pan L15", "a number in a word")
  eq(tb.add_number("5.1  Verse", 0, 2), "7.1  Verse", "a bar of a position: the whole number under the cursor")
  eq(tb.add_number("take 007", 0, 1), "take 008", "leading zeros kept")
  eq(tb.add_number("no number", 0, 1), nil, "nothing to add to")
end)

test("text objects, :m and :d work on the lines", function()
  start()
  band()
  keys(":e paw://tracks<CR>")
  keys("fvcif-12<Esc>")
  eq(line(1):find("vol -12  pan", 1, true) ~= nil, true, "cif changes the field's value: " .. line(1))
  keys("u:1m$<CR>")
  eq(line(3):match("^Drums") ~= nil, true, ":m moves a line")
  keys(":2,3d<CR>")
  eq(#lines(), 1, ":d deletes a range")
  keys("p")
  eq(#lines(), 3, "and puts it back")
  keys("2G0fvdaf")
  eq(line(2):find("vol", 1, true), nil, "daf deletes a whole field: " .. line(2))
end)

test("a step that fails takes back the steps before it", function()
  start()
  local drums, bass = band()
  keys(":e paw://tracks<CR>")
  keys("cwKick<Esc>")
  -- Bass plays into Drums, and Drums into Bass: a loop the project refuses.
  keys("jA  out Kick<Esc>kA  out Bass<Esc>")
  write()
  eq(drums.name, "Drums", "the rename before the failing step is taken back")
  eq(api.track_get(bass.id).output, nil, "and the output")
  eq(tb.buf().state.text:modified(), true, "the buffer keeps its changes")
  eq(paw.ui.message.text:find("loop", 1, true) ~= nil, true, "the message says why: " .. paw.ui.message.text)
end)

test("an extension adds a kind of text buffer of its own", function()
  start()
  local drums = band()
  drums:add_clip({ start = 0, length = 4, name = "Fill" })
  drums:add_clip({ start = 8, length = 4, name = "Break" })
  paw.flush()
  api.undo_checkpoint()
  -- The example of docs/reference/lua-views.md.
  paw.textbuf.kind("clips", {
    pattern = "^paw://track/(%d+)/clips$",
    title = function(ctx) return "Clips of track " .. ctx.args[1] end,
    read = function(ctx)
      local out = {}
      for i, clip in ipairs(paw.api.clip_list(paw.api.track_list()[tonumber(ctx.args[1])])) do
        out[i] = { id = clip.id, clip = clip }
      end
      return out
    end,
    format = function(item) return { paw.textbuf.quote(item.clip.name), "at " .. item.clip.start } end,
    parse = function(text)
      local cells = paw.textbuf.cells(text)
      local at = cells[2] and tonumber(cells[2].text:match("^at (%S+)$"))
      if not at then return nil, "a clip is a name and `at` a beat" end
      return { name = paw.textbuf.unquote(cells[1].text), start = at }
    end,
    plan = function(changes)
      local steps = {}
      for _, e in ipairs(changes.changed) do
        steps[#steps + 1] = {
          text = "move " .. e.fields.name .. " to " .. e.fields.start,
          run = function() paw.api.clip_set(e.id, "start", e.fields.start) end,
        }
      end
      for _, d in ipairs(changes.deleted) do
        steps[#steps + 1] = { text = "delete " .. d.base.name, run = function() paw.api.clip_remove(d.id) end }
      end
      return steps
    end,
    keywords = { at = true },
  })
  T.after(function() paw.textbuf.kinds.clips = nil end)
  keys(":e paw://track/1/clips<CR>")
  eq(L.buf_of(L.current()).name, "paw://track/1/clips", "shown")
  eq(table.concat(lines(), "|"), "Fill   at 0|Break  at 8", "its lines")
  keys("$<C-a>jdd")
  local plan = write()
  eq(plan, "move Fill to 1\ndelete Break", "its plan")
  local list = api.clip_list(drums.id)
  eq(#list, 1, "a clip deleted")
  eq(list[1].start, 1, "a clip moved")
end)

test("a text buffer in a window of its own is drawn and edited with the same keys", function()
  start()
  local _, bass = band()
  T.after(function() paw.canvas.close("textbuf") end)
  keys(":textbuf.open tracks window<CR>")
  eq(paw.canvas.open_views.textbuf ~= nil, true, "a window of its own")
  eq(paw.ui.focused, "textbuf", "with the keyboard")
  local text = {}
  for _, row in ipairs(api.ui_view_snapshot("textbuf", 100, 10).rows) do
    local parts = {}
    for _, run in ipairs(row) do
      parts[#parts + 1] = run.text
    end
    text[#text + 1] = table.concat(parts)
  end
  local drawn = table.concat(text, "\n")
  eq(drawn:find("Bass", 1, true) ~= nil, true, "the lines are drawn: " .. drawn)
  paw.canvas.key("textbuf", "jcwLow<Esc>:w<CR>")
  eq(paw.canvas.open_views["textbuf.plan"] ~= nil and paw.ui.float == nil, true, "the plan opens in a window too")
  paw.canvas.key("textbuf.plan", "y")
  eq(bass.name, "Low", "keys typed in it edit it, and :w applies")
  eq(paw.canvas.open_views["textbuf.plan"], nil, "the plan's window closes")
  eq(paw.ui.focused, "textbuf", "and the keyboard is back in the buffer's")
end)
