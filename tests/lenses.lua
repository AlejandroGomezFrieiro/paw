-- Language servers over things other than notes: a server for the mix
-- (tests/fixtures/mix_lint.py, LSP's own shapes), a one-shot check of
-- renders (tests/fixtures/peak_check.py), a Lua server in this process on
-- an address kind and a subject an extension adds, and diagnostics drawn
-- where they belong in every view of the terminal. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local eq, fresh = T.eq, T.fresh
local api = paw.api
local A = paw.address

local function test(name, fn)
  T.test(name, function()
    local result = { xpcall(fn, debug.traceback) }
    paw.lsp.stop()
    paw.diagnostic.reset()
    paw.annotation.reset()
    while paw.ui.float do paw.ui.close() end
    paw.ui.views.pianoroll.clip_id = nil
    for _, v in ipairs({ "pianoroll", "mixer", "devices" }) do paw.ui.hide(v) end
    paw.ui.focus("arrange")
    if not result[1] then error(result[2], 0) end
    return result[2]
  end)
end

local function python()
  local found = io.popen("command -v python3 2>/dev/null"):read("*l")
  return found and found ~= "" and found or nil
end

local until_ = T.until_

local function screen(w, h) return table.concat(api.ui_snapshot(w or 140, h or 50), "\n") end

local function has(text, part, what)
  if not text:find(part, 1, true) then error(string.format("%s: %q is not in\n%s", what, part, text), 2) end
end

local function start()
  fresh()
  paw.lsp.stop()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do paw.ui.close() end
  paw.ui.focus("arrange")
end

test("lenses: a server for the mix marks a hot fader in every view, says what it is, and fixes it", function()
  if not python() then return "no python3" end
  start()
  local bass = paw.add_track({ name = "Bass", volume = 3 })
  local pad = paw.add_track({ name = "Pad", volume = -6 })
  paw.flush()
  paw.lsp.config("mix", { cmd = { python(), "tests/fixtures/mix_lint.py" } })
  paw.lsp.enable("mix")
  until_(function() return #paw.diagnostic.get(A.track(bass.id)) == 1 end, "the hot fader")
  local d = paw.diagnostic.get(A.track(bass.id))[1]
  eq(paw.diagnostic.kind(d), "track", "about a track")
  eq(d.message, "Bass's fader is at +3.0 dB: it may clip", "what it says")
  eq(#paw.diagnostic.get(A.track(pad.id)), 0, "a quiet track is left alone")
  eq(paw.lsp.clients()[1].subjects[1], "mix", "attached to the mix, as it asked")
  eq(paw.lsp.clients()[1].documents[1], "paw://project#mix", "holding the mix")

  -- The terminal: the header, the status line, the mixer's strip and its label.
  local text = screen()
  has(text, " 1 !", "the track column signs the hot track")
  has(text, "W1", "the status line counts it")
  paw.ui.show("mixer")
  text = screen()
  has(text, "+3.0 dB", "the mixer shows the server's label on the strip")

  -- In the mixer, ]d goes to the strip.
  paw.ui.focus("mixer")
  paw.cursor.set_track(pad.id)
  paw.keymap.feed("]d")
  eq(paw.cursor.track_id(), bass.id, "]d goes to the hot track")

  -- In the arrange view, gK says what is known about the track under the cursor.
  paw.ui.focus("arrange")
  paw.keymap.feed("gK")
  until_(function() return paw.ui.float and paw.ui.float.name == "pager" end, "the hover float")
  text = screen()
  has(text, "it may clip", "the diagnostic, in the float")
  has(text, "Bass: fader +3.0 dB, pan +0.00", "and the server's hover")
  paw.ui.close()

  -- ,ca offers the diagnostic's fix and the server's own action; each is one undo step.
  api.undo_checkpoint()
  paw.keymap.feed("<leader>la")
  until_(function() return paw.pick.state() end, "the actions, once the server has answered")
  local matches = paw.pick.state().matches
  eq(#matches, 2, "a fix and an action")
  has(matches[1], "Bring Bass to 0 dB", "the fix")
  has(matches[2], "Lower Bass by 6 dB", "the action")
  paw.keymap.feed("<CR>")
  api.undo_checkpoint()
  eq(api.track_get(bass.id).volume, 0, "fixed")
  until_(function() return #paw.diagnostic.get(A.track(bass.id)) == 0 end, "the warning to go once the server is told")
  paw.undo()
  eq(api.track_get(bass.id).volume, 3, "one undo takes it back")
  until_(function() return #paw.diagnostic.get(A.track(bass.id)) == 1 end, "the warning back")
  paw.cmd("diagnostics")
  until_(function() return paw.pick.state() end, "the list")
  eq(paw.pick.state().matches[1], "── Tracks", "listed under what they are about")
end)

test("lenses: a one-shot server checks each render, and says when it fails", function()
  if not python() then return "no python3" end
  start()
  local t = paw.add_track({ name = "Tone" })
  t:add_device("synth")
  t:add_clip({ start = 0, length = 2, notes = { { pitch = 69, start = 0, length = 2, velocity = 120 } } })
  paw.lsp.config("peaks", { kind = "oneshot", cmd = { python(), "tests/fixtures/peak_check.py", "--over", "{over}", "{input}" },
    attach = { subjects = { "render" } }, settings = { over = -40 }, timeout_ms = 20000 })
  paw.lsp.enable("peaks")
  eq(paw.lsp.clients()[1].status, "ready", "a one-shot server is ready, with nothing running")
  local path = T.scratch .. "/lenses.wav"
  paw.render(path, { tail = 0 })
  until_(function() return #paw.diagnostic.get(A.render(path)) == 1 end, "the check of the render")
  local d = paw.diagnostic.get(A.render(path))[1]
  eq(paw.diagnostic.kind(d), "render", "about the render")
  has(d.message, "lenses.wav peaks at", "what the command printed")
  eq(d.location.selector.seconds[1], 0.5, "at the time it gave")
  eq(#paw.diagnostic.get(A.render(path), { namespace = "peaks" }), 1, "a finding of severity off is left out")
  has(paw.diagnostic.where(d), "lenses.wav", "named by its file")
  eq(paw.lsp.clients()[1].status, "ready", "ready again")
  -- A command that prints what is not JSON fails, and says so.
  paw.lsp.config("peaks", { cmd = { python(), "tests/fixtures/peak_check.py", "--garbage", "{input}" } })
  paw.render(path, { tail = 0 })
  until_(function() return paw.lsp.clients()[1].status == "failed" end, "the failure")
  has(paw.lsp.clients()[1].error, "not JSON", "why")
  local info = {}
  for _, l in ipairs(paw.lsp.info_lines()) do info[#info + 1] = type(l) == "table" and l.text or l end
  has(table.concat(info, "\n"), "one-shot command", ":lsp info says how it runs")
end)

test("lenses: an extension's addresses and subject, and a Lua server in this process that speaks of them", function()
  start()
  local words = { "la", "lu", "lo" }
  A.scheme("lyric", {
    resolve = function(_, p)
      local i = tonumber(p.segments[2])
      if not i then return { words = words } end
      return words[i] and { text = words[i] } or nil
    end,
    edit = function(change, p) words[tonumber(p.segments[2])] = change.set.text end,
  })
  paw.lsp.subject("lyrics", {
    targets = function() return { "paw://lyric" } end,
    build = function() return { words = words } end,
    depends = { "paw://lyric/**" },
  })
  local seen
  local server = {
    initialize = function() return { capabilities = { hoverProvider = true, paw = { subjects = { "lyrics" } } } } end,
    ["textDocument/didOpen"] = function(params, ctx)
      seen = params.textDocument
      local list = {}
      for i, w in ipairs(params.textDocument.data.words) do
        if w == "lu" then
          list[#list + 1] = { severity = 3, message = "say it longer", code = "vowel",
            data = { location = { uri = "paw://lyric/" .. i }, fixes = { { title = "Make it loo", edit = { { uri = "paw://lyric/" .. i, set = { text = "loo" } } } } } } }
        end
      end
      ctx.notify("textDocument/publishDiagnostics", { uri = params.textDocument.uri, diagnostics = list })
    end,
    ["textDocument/hover"] = function(params) return { contents = "a word: " .. params.paw.location.uri } end,
    -- It asks for an edit of its own.
    ["workspace/executeCommand"] = function(params, ctx)
      return ctx.request("workspace/applyEdit", { edit = { paw = { { uri = "paw://lyric/3", set = { text = params.arguments[1] } } } } })
    end,
  }
  paw.lsp.config("lyrics", { server = server })
  paw.lsp.enable("lyrics")
  eq(seen.languageId, "paw-lyrics", "sent the subject, as a table")
  eq(seen.uri, "paw://lyric#lyrics", "named by its address and subject")
  local d = paw.diagnostic.get("paw://lyric/2")[1]
  eq(d and d.message, "say it longer", "about a word")
  eq(paw.diagnostic.kind(d), "lyric", "of the extension's kind")
  eq(paw.diagnostic.apply(d), true, "its fix")
  eq(words[2], "loo", "made by the extension")
  local hover
  paw.lsp.hover_at({ uri = "paw://lyric/1" }, function(s) hover = s end)
  eq(hover[1].lines[1], "a word: paw://lyric/1", "asked about a word")
  local answer
  paw.lsp.request("lyrics", "workspace/executeCommand", { command = "set", arguments = { "li" } }, function(_, r) answer = r end)
  eq(answer.applied, true, "a server's edit is made")
  eq(words[3], "li", "as it asked")
  local info = {}
  for _, l in ipairs(paw.lsp.info_lines()) do info[#info + 1] = type(l) == "table" and l.text or l end
  has(table.concat(info, "\n"), "in-process Lua", ":lsp info says how it runs")
  A.schemes.lyric = nil
  paw.lsp.subjects.lyrics = nil
end)

test("lenses: diagnostics on devices, parameters and stretches of time are drawn where they belong", function()
  start()
  local t = paw.add_track({ name = "Keys" })
  local synth = t:add_device("synth")
  paw.flush()
  paw.diagnostic.set("lint", "lint", {
    { location = { uri = A.param(synth.id, "cutoff") }, severity = "warning", message = "cutoff is very low",
      fixes = { { title = "Open the cutoff", edit = { { uri = A.param(synth.id, "cutoff"), set = { value = 4000 } } } } } },
    { location = { uri = A.device(synth.id) }, severity = "info", message = "no preset" },
    { location = { uri = A.project(), selector = { time = { 8, 12 } } }, severity = "error", message = "too busy here" },
  })
  paw.cursor.set_track(t.id)
  paw.ui.show("devices")
  local text = screen()
  has(text, "no preset", "the device says what is said of it")
  -- The ruler marks the stretch, on the left edge of its first cell.
  local ruler
  for _, line in ipairs(api.ui_snapshot(140, 50)) do
    if line:find("cur", 1, true) then ruler = line break end
  end
  has(ruler or "", paw.draw.g.mark, "the ruler marks the stretch of time")
  -- ]d in the device panel goes to the parameter.
  paw.ui.focus("devices")
  paw.keymap.feed("]d")
  local row = paw.ui.views.devices:rows()[paw.ui.views.devices.row]
  eq(row.param and row.param.key, "cutoff", "]d goes to the parameter")
  api.undo_checkpoint()
  paw.keymap.feed("<leader>la")
  has(paw.pick.state().matches[1], "Open the cutoff", "its fix is offered there")
  paw.keymap.feed("<CR>")
  eq(api.device_get(synth.id).params.cutoff, 4000, "and made")
  -- In the arrange view, ]d goes to the stretch.
  paw.ui.focus("arrange")
  paw.cursor.set_beat(2)
  local found
  for _ = 1, 3 do
    paw.keymap.feed("]d")
    if paw.cursor.beat == 8 then found = true break end
  end
  eq(found, true, "the cursor goes to where the stretch starts")
end)

test("lenses: every clip the piano roll edits is shown to the servers and marked, and the mouse's menus offer the lens", function()
  start()
  local a = paw.add_track({ name = "Upper" }):add_clip({ start = 0, length = 4, notes = { { pitch = 72, start = 0, length = 1 } } })
  local b = paw.add_track({ name = "Lower" }):add_clip({ start = 4, length = 4, notes = { { pitch = 48, start = 1, length = 1 } } })
  paw.flush()
  paw.ui.views.pianoroll:edit(a)
  paw.roll_clips.open({ a.id, b.id }, a.id)
  -- Shown to a server attached to clips: both, by focus.
  local opened = {}
  paw.lsp.config("seen", { server = {
    initialize = function() return { capabilities = { paw = { subjects = { "clip" } } } } end,
    ["textDocument/didOpen"] = function(p) opened[#opened + 1] = p.textDocument.uri end,
  } })
  paw.lsp.enable("seen")
  table.sort(opened)
  local want = { A.clip(a.id), A.clip(b.id) }
  table.sort(want)
  eq(table.concat(opened, " "), table.concat(want, " "), "the active clip and the other one edited")
  -- A diagnostic on the other clip's note is drawn at its place in the roll.
  local nid = b:notes()[1].id
  paw.diagnostic.set("lint", "lint", { { location = { uri = A.note(b.id, nid) }, severity = 2, message = "low" } })
  local painted = {}
  local cells = { width = 80, fill = function(_, x, y, w, h, ch, style) painted[#painted + 1] = x .. "," .. y .. " " .. tostring(style) end,
    text = function() end }
  paw.diagnostic.paint_roll({ roll = cells, ruler = cells, clip = a, parts = paw.roll_clips.parts(),
    x = function(beat) return beat * 4 end, row = function(pitch) return 100 - pitch end })
  eq(painted[1], "20,52 DiagnosticUnderlineWarn", "at beat 5 of the roll, the note's row")
  -- The mouse's menus: on the note, on the track.
  local menus = require("paw.mouse_menus")
  local labels = {}
  for _, item in ipairs(menus.note(b.id, 1)) do if type(item) == "table" then labels[#labels + 1] = item.label end end
  eq(table.concat(labels, "|"):find("Fixes and actions…|What the language servers say about it", 1, true) ~= nil, true, table.concat(labels, "|"))
  labels = {}
  for _, item in ipairs(menus.track(b:get().track)) do if type(item) == "table" then labels[#labels + 1] = item.label end end
  eq(table.concat(labels, "|"):find("Fixes and actions…", 1, true) ~= nil, true, "on the track too")
end)
