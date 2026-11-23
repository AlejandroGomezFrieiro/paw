-- Tests of the snippet engine, `paw.snippet`, with snippets defined here:
-- expanding, choices stepped through within one undo step, how a snippet
-- ends, the picker, counts, loading from files, and the keys falling back
-- to what they otherwise do. Loaded by tests/suite.lua with its helpers.
local T = ...
local eq, fresh = T.eq, T.fresh
local api = paw.api
local S = paw.snippet

-- The snippets made here are taken away after each test, so that they are
-- not offered to the tests that follow (they would be suggestions too).
local function test(name, fn)
  T.test(name, function()
    local ok, err = xpcall(fn, debug.traceback)
    S.finish()
    for _, n in ipairs({ "stack", "walk", "nothing", "where" }) do
      S.remove(n)
    end
    if not ok then error(err, 0) end
  end)
end

local keys = T.keys

--- A clip's notes: "60@0+1 61@1+1".
local function melody(clip)
  local notes = clip:notes()
  table.sort(notes, function(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.pitch < b.pitch
  end)
  for i, n in ipairs(notes) do
    notes[i] = string.format("%d@%g+%g", n.pitch, n.start, n.length)
  end
  return table.concat(notes, " ")
end

--- Two snippets to test with: `stack` writes a chord of the cursor's pitch
--- and those `interval` and twice it above, a beat long or as `length`
--- says; `walk` a note on each beat of its count, going up.
local function define()
  S.add({
    name = "stack",
    desc = "a stacked chord at the cursor",
    choices = {
      { name = "interval", values = { "3", "4", "5" } },
      { name = "length", values = { "1", "2" } },
    },
    expand = function(ctx)
      local i = tonumber(ctx.values.interval)
      local len = tonumber(ctx.values.length)
      local notes = {}
      for k = 0, 2 do
        notes[#notes + 1] = { pitch = ctx.pitch + k * i, start = ctx.at, length = len }
      end
      return { notes = notes }
    end,
  })
  S.add({
    name = "walk",
    desc = "one note a beat, going up",
    expand = function(ctx)
      return { notes = { { pitch = ctx.pitch + math.floor(ctx.at - ctx.start), start = ctx.at, length = 1 } } }
    end,
  })
  S.add({
    name = "nothing",
    desc = "never fits",
    expand = function() return nil, "nothing fits here" end,
  })
end

--- A track with an empty four-bar clip open in the piano roll, the cursor
--- on C4 at its start.
local function open(start)
  fresh()
  api.engine_restart({})
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  define()
  local track = paw.add_track({ name = "Keys" })
  local clip = track:add_clip({ start = start or 0, length = 16, notes = {} })
  paw.flush()
  api.undo_checkpoint()
  local roll = paw.ui.views:get("pianoroll")
  roll:edit(clip)
  roll:set(60, 0)
  return clip, roll
end

test("snippet: expanding writes the notes as one undo step and makes the snippet active", function()
  local clip = open()
  keys(":snippet stack<CR>")
  eq(melody(clip), "60@0+1 63@0+1 66@0+1", "the notes, from the first value of each choice")
  local state = S.active()
  eq(state and state.name, "stack", "active")
  eq(state.current, 0, "no choice yet")
  paw.undo()
  eq(melody(clip), "", "one undo takes it away")
  eq(S.active(), nil, "and ends it")
end)

test("snippet: Tab goes to a choice, C-n and C-p step it, all within the one undo step", function()
  local clip = open()
  keys(":snippet stack<CR>")
  keys("<Tab>")
  eq(S.active().current, 1, "Tab: the first choice")
  keys("<C-n>")
  eq(melody(clip), "60@0+1 64@0+1 68@0+1", "C-n: the interval's next value")
  keys("<C-n>")
  eq(melody(clip), "60@0+1 65@0+1 70@0+1", "and the next")
  keys("<C-n>")
  eq(melody(clip), "60@0+1 63@0+1 66@0+1", "round to the first")
  keys("<C-p>")
  eq(melody(clip), "60@0+1 65@0+1 70@0+1", "C-p: back to the last")
  keys("<Tab>")
  eq(S.active().current, 2, "Tab: the length")
  keys("<C-n>")
  eq(melody(clip), "60@0+2 65@0+2 70@0+2", "a choice keeps the others' values")
  keys("<S-Tab>")
  eq(S.active().current, 1, "S-Tab: back")
  keys("<Tab><Tab>")
  eq(S.active().current, 1, "Tab past the last goes round")
  paw.undo()
  eq(melody(clip), "", "one undo takes the whole snippet away")
  paw.redo()
  eq(melody(clip), "60@0+2 65@0+2 70@0+2", "redo brings it back as it was left")
end)

test("snippet: C-n with no choice chosen steps the first", function()
  local clip = open()
  keys(":snippet stack<CR>")
  keys("<C-n>")
  eq(melody(clip), "60@0+1 64@0+1 68@0+1", "the first choice stepped")
  eq(S.active().current, 1, "and it is the current one")
end)

test("snippet: it ends on C-y, Escape, leaving its span, or another edit", function()
  local clip, roll = open()
  keys(":snippet stack<CR>")
  keys("<C-y>")
  eq(S.active(), nil, "C-y ends it")
  eq(melody(clip), "60@0+1 63@0+1 66@0+1", "keeping its notes")
  paw.undo()
  keys(":snippet stack<CR>")
  keys("<Esc>")
  eq(S.active(), nil, "Escape ends it")
  paw.undo()
  keys(":snippet stack<CR>")
  keys("l")
  eq(S.active() ~= nil, true, "moving inside the span keeps it")
  roll:set(nil, 3)
  eq(S.active(), nil, "leaving the span ends it")
  paw.undo()
  roll:set(60, 0)
  keys(":snippet stack<CR>")
  clip:add_note({ pitch = 40, start = 2, length = 1 })
  paw.flush()
  eq(S.active(), nil, "another edit ends it")
  keys("<C-n>")
  eq(melody(clip), "60@0+1 63@0+1 66@0+1 40@2+1", "and C-n no longer changes it")
end)

test("snippet: the keys do what they otherwise do when no snippet is active", function()
  local clip = open()
  paw.ui.focus("pianoroll")
  keys("<Tab>")
  eq(paw.ui.focused ~= "pianoroll", true, "Tab goes to the next view")
  paw.ui.focus("pianoroll")
  clip:add_note({ pitch = 50, start = 0, length = 1 })
  paw.flush()
  api.undo_checkpoint()
  paw.undo()
  eq(melody(clip), "", "undone")
  keys("<C-y>")
  eq(melody(clip), "50@0+1", "C-y redoes")
end)

test("snippet: a count repeats the snippet one after another", function()
  local clip = open()
  keys(":3snippet walk<CR>")
  eq(melody(clip), "60@0+1 61@1+1 62@2+1", ":3snippet: three, each where the last ended")
  paw.undo()
  keys("2<C-s>")
  eq(paw.pick.state() ~= nil, true, "the picker is open")
  keys("walk<CR>")
  eq(melody(clip), "60@0+1 61@1+1", "2<C-s>: two")
end)

test("snippet: one that does not fit says why and writes nothing", function()
  local clip = open()
  keys(":snippet nothing<CR>")
  eq(melody(clip), "", "nothing written")
  eq(paw.ui.message and paw.ui.message.text, "nothing fits here", "the reason")
  eq(S.active(), nil, "nothing active")
  keys(":snippet nosuch<CR>")
  eq(paw.ui.message.text, "no snippet nosuch", "an unknown name")
end)

test("snippet: the picker lists the snippets of the view, previews them and expands the one chosen", function()
  local clip = open()
  paw.ui.focus("pianoroll")
  keys("<C-s>")
  local state = paw.pick.state()
  eq(state ~= nil, true, "open")
  local names = {}
  for _, line in ipairs(state.matches) do
    names[#names + 1] = line:match("^(%S+)")
  end
  eq(table.concat(names, " "), "nothing stack walk", "the snippets, by name")
  keys("sta")
  eq(paw.pick.state().matches[1]:match("^(%S+)"), "stack", "filtered")
  -- The preview pane: the notes it would write, and the ghosts in the roll.
  api.ui_snapshot(120, 40)
  local ghosts = S.preview_marks(clip.id)
  eq(ghosts and #ghosts, 3, "three ghost notes")
  local screen = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(screen:find("C4 D#4 F#4", 1, true) ~= nil, true, "the preview names them")
  eq(melody(clip), "", "nothing written while choosing")
  keys("<CR>")
  eq(melody(clip), "60@0+1 63@0+1 66@0+1", "Enter expands it")
  eq(S.preview_marks(clip.id), nil, "no more ghosts")
  eq(S.active().name, "stack", "active")
  keys("<C-y>")
  keys("<C-s>")
  keys("<Esc>")
  eq(paw.pick.state(), nil, "Escape closes it")
  eq(melody(clip), "60@0+1 63@0+1 66@0+1", "writing nothing")
end)

test("snippet: works on a clip that starts later in the song, in project beats", function()
  local clip, roll = open(8)
  roll:set(62, 2)
  local seen
  S.add({
    name = "where",
    expand = function(ctx)
      seen = ctx.at
      return { notes = { { pitch = ctx.pitch, start = ctx.at, length = 0.5 } } }
    end,
  })
  keys(":snippet where<CR>")
  eq(seen, 10, "ctx.at is in project beats")
  eq(melody(clip), "62@2+0.5", "written in the clip's beats")
end)

test("snippet: notes past the clip's end make it longer", function()
  local clip, roll = open()
  roll:set(60, 15)
  keys(":snippet stack<CR>")
  keys("<Tab><Tab><C-n>")
  eq(melody(clip), "60@15+2 63@15+2 66@15+2", "written")
  eq(clip.length, 20, "the clip grew to the next bar")
  paw.undo()
  eq(clip.length, 16, "and undo shrinks it")
end)

test("snippet: the active snippet is drawn in the terminal and told to the window", function()
  local clip = open()
  paw.ui.focus("pianoroll")
  keys(":snippet stack<CR><Tab>")
  local screen = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(screen:find("stack · interval: 3 (1/3)", 1, true) ~= nil, true, "its choice along the bottom")
  local m = S.marks(clip.id)
  eq(#m.notes, 3, "its notes")
  eq(m.label, "stack · interval: 3 (1/3)", "and its choice, named")
  -- A window is sent what the terminal shows, in cells over the notes.
  api.scene_forget(0)
  paw.ui.render_scene("pianoroll", 120, 40, { w = 8, h = 16 })
  api.scene_end(0, "snippet")
  local text = ""
  for _, row in ipairs(api.scene_cells(0, "snippet").rows) do
    for _, run in ipairs(row) do
      text = text .. run.text
    end
  end
  api.scene_forget(0)
  eq(text:find("stack · interval: 3 (1/3)", 1, true) ~= nil, true, "in the scene a window is sent")
  keys("<C-y>")
  eq(S.marks(clip.id), nil, "nothing once it ends")
end)

test("snippet: an extension's snippet does not replace the user's", function()
  define()
  S.add({ name = "stack", source = "extension", desc = "theirs", expand = function() end })
  eq(S.get("stack").desc, "a stacked chord at the cursor", "the user's stays")
  S.add({ name = "theirs", source = "extension", desc = "theirs", expand = function() end })
  S.add({ name = "theirs", desc = "mine", expand = function() end })
  eq(S.get("theirs").desc, "mine", "the user's replaces an extension's")
  S.remove("theirs")
  eq(S.get("theirs"), nil, "removed")
end)

test("snippet: files in a snippets directory are loaded, one set each", function()
  local dir = T.scratch .. "/snippets"
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(
    dir .. "/one.lua",
    [[
return {
  { name = "file-a", desc = "from a list", expand = function(ctx) return { notes = {} } end },
  { name = "file-b", desc = "another", views = { "pianoroll", "arrange" }, expand = function(ctx) return { notes = {} } end },
}
]]
  )
  T.write_file(dir .. "/two.lua", [[paw.snippet.add({ name = "file-c", expand = function() end })]])
  S.load_dir(dir, "config")
  eq(S.get("file-a").desc, "from a list", "a file returning a list")
  eq(S.get("file-c") ~= nil, true, "a file calling add")
  eq(S.get("file-a").source, "config", "from the configuration")
  local arrange = {}
  for _, s in ipairs(S.offered("arrange")) do
    arrange[#arrange + 1] = s.name
  end
  eq(table.concat(arrange, " "), "file-b", "offered where its views say")
  for _, n in ipairs({ "file-a", "file-b", "file-c" }) do
    S.remove(n)
  end
end)

test("snippet: the command completes the names", function()
  open()
  local found = {}
  for _, c in ipairs(paw.commands.complete("snippet st")) do
    found[#found + 1] = c.text or c
  end
  eq(table.concat(found, " "):find("stack") ~= nil, true, "stack: " .. table.concat(found, " "))
end)
