-- Commands and keys for the full score and the parts (`notation.parts`):
--
--   :part.score            -- the full score in the notation view, to edit (`notation.staves`)
--   :part.condense         -- two players of an instrument on one staff, or not
--   :part Flute 1          -- an instrument's part (by name or place); alone, the open clip's track's
--   :part.next, :part.prev -- the next, previous part
--   :part off              -- the clip alone again
--   :part.transpose Bb     -- the part written for an instrument in B flat (`Eb up`, `Bb octave`, `off`)
--   :5,8part.cue Oboe      -- the oboe's notes as a cue in this part's rests of bars 5 to 8 (`off`)
--   :part.break, :part.join, :part.bars-per-system 4   -- the part's own system breaks
--   :part.name Flute 1 | Fl. 1   -- the names the score and the part give it
--   :part.export parts.pdf all   -- a PDF of each part; `score`, the full score; .musicxml / .mxl, every part
--
-- Keys on `<localleader>P` in the notation view: `s` score, `c` condensed,
-- `p` this track's part, `n` `N` next and previous part, `o` back to the
-- clip, `b` `j` a break in the part, `e` export.
local api = paw.api
local view = require("notation")
local P = require("notation.parts")
local page = require("notation.page")
local keymap, command = paw.keymap, paw.command

local EPS = 1e-6

--- The notation view open on a clip, opened on the target clip when it is
--- not. Returns whether there is one.
local function opened()
  if view:clip() then return true end
  local clip = view.target()
  if not clip then
    paw.notify("no MIDI clip to show the score from", "warn")
    return false
  end
  view:edit(clip)
  return view:clip() ~= nil
end

--- Show the score or a part in the view.
local function show(parts)
  if not opened() then return end
  -- The cursor at the start, on the middle line of the first staff.
  view.parts, view.cache, view.first = parts, nil, 1
  -- The part's track is the active staff; in the score, the open clip's.
  if parts.track then
    for _, e in ipairs(P.instruments()) do
      if e.id == parts.track then view:activate(e.clip.id) end
    end
  end
  local F = view:frame()
  if not view.parts then return end
  local layout = F and F.layout
  paw.ui.focus("notation")
  -- In the graphical frontend, the notation's window.
  if paw.canvas and not paw.canvas.open_views.notation then
    paw.canvas.open("notation", { title = "Notation", width = 1100, height = 560 })
  end
  api.ui_redraw()
  return layout
end

--- The track whose part is meant: the part shown, else the open clip's.
local function part_track()
  if view.parts and view.parts.kind == "part" then return view.parts.track end
  local clip = view:clip() or view.target()
  return clip and clip:get().track
end

--- An instrument by its name (or the start of it, any case) or its place
--- in the score.
local function instrument(words)
  local list = P.instruments()
  local n = tonumber(words)
  if n then return list[n], list end
  local want = tostring(words or ""):lower()
  for _, e in ipairs(list) do
    if e.name:lower() == want then return e, list end
  end
  for _, e in ipairs(list) do
    if e.name:lower():sub(1, #want) == want then return e, list end
  end
  return nil, list
end

local function names(list)
  local out = {}
  for i, e in ipairs(list) do
    out[i] = e.name
  end
  return out
end

local function complete_names() return names(P.instruments()) end

command(
  "part.score",
  function()
    local condensed = view.parts and view.parts.condensed or false
    if show({ kind = "score", condensed = condensed }) then
      paw.notify(
        "the full score at concert pitch"
          .. (condensed and ", condensed" or "")
          .. ": the cursor's staff is the track edited; :part off for the clip alone"
      )
    end
  end,
  {
    desc = "Show the full score to edit: every track with MIDI as an instrument, in orchestral order, the cursor's staff the track edited",
  }
)

command(
  "part.condense",
  function(ctx)
    local word = ctx.args[1]
    local was = view.parts and view.parts.kind == "score" and view.parts.condensed or false
    local on = word == "on" or (word ~= "off" and not was)
    if show({ kind = "score", condensed = on }) then
      paw.notify(
        on and "condensed: two players of an instrument share a staff (a2, 1., 2.)"
          or "every player on a staff of their own"
      )
    end
  end,
  {
    desc = "Condense the full score: two players of one instrument on one staff, with a2, 1. and 2. (`on`, `off`, or again to switch)",
    complete = function() return { "on", "off" } end,
  }
)

local function show_part(e)
  if show({ kind = "part", track = e.id }) then
    paw.notify(
      "part: "
        .. e.name
        .. (e.transpose and (" (written in " .. e.transpose.name .. ")") or "")
        .. ", to edit; :part off for the clip alone"
    )
  end
end

command(
  "part",
  function(ctx)
    local words = ctx.args[1]
    if words == "off" then
      view.parts, view.cache = nil, nil
      api.ui_redraw()
      return paw.notify("notation: the clip alone, to edit")
    end
    if not words or words == "" then
      local id = part_track()
      local list = P.instruments()
      for _, e in ipairs(list) do
        if e.id == id then return show_part(e) end
      end
      if list[1] then return show_part(list[1]) end
      return paw.notify("no track has MIDI to make a part of", "warn")
    end
    local e, list = instrument(words)
    if not e then return paw.notify("no part '" .. words .. "': " .. table.concat(names(list), ", "), "warn") end
    show_part(e)
  end,
  {
    raw = true,
    desc = "Show a part to play from, to edit as it is written: `part Flute 1` (by name or place in the score), alone the open clip's track's, `part off` the clip alone again",
    complete = complete_names,
  }
)

local function step(by)
  local list = P.instruments()
  if #list == 0 then return paw.notify("no track has MIDI to make a part of", "warn") end
  local id = part_track()
  local at = 0
  for i, e in ipairs(list) do
    if e.id == id then at = i end
  end
  if not (view.parts and view.parts.kind == "part") and at > 0 then by = 0 end
  show_part(list[(at - 1 + by) % #list + 1])
end
command("part.next", function() step(1) end, { desc = "Show the next instrument's part, in score order" })
command("part.prev", function() step(-1) end, { desc = "Show the previous instrument's part, in score order" })

command(
  "part.transpose",
  function(ctx)
    local id = part_track()
    if not id then return paw.notify("no track", "warn") end
    local spec = ctx.args[1]
    if not spec or spec == "" then
      local iv = P.transposition(id)
      return paw.notify(
        iv and ("written in " .. iv.name .. ": " .. iv.semis .. " semitones from how it sounds")
          or "written as it sounds"
      )
    end
    if spec ~= "off" and spec ~= "default" and not P.interval(spec) then
      return paw.notify(
        "a transposition is a key: `Bb`, `A`, `F`, `Eb`, `Eb up` (sounding higher), `Bb octave`, `C octave`, `off`",
        "warn"
      )
    end
    P.keep(id, function(_, own) own.transpose = spec ~= "default" and spec or nil end)
    view.cache = nil
    local iv = P.transposition(id)
    paw.notify(
      iv and ("written in " .. iv.name .. " (" .. (iv.semis > 0 and "+" or "") .. iv.semis .. " semitones)")
        or "written as it sounds"
    )
  end,
  {
    raw = true,
    desc = 'How a track\'s part is written: `part.transpose Bb` (clarinet, trumpet), `F` (horn), `Eb` (alto sax), `Eb up` (E flat clarinet), `Bb octave` (tenor sax), `off`, `default` (from "in Bb" in its name)',
    complete = function()
      return {
        "Bb",
        "A",
        "F",
        "Eb",
        "Eb up",
        "D up",
        "G",
        "Bb octave",
        "Eb octave",
        "C octave",
        "C up octave",
        "off",
        "default",
      }
    end,
  }
)

--- The stretch of the song a command works on, in song beats: its range,
--- else the visual selection, else the cursor's bar.
local function stretch(ctx)
  local range = ctx.range
  if range and range.from then return range.from, range.to end
  local start = view:clip() and view:clip():get().start or 0
  local sel = view:selection()
  if sel then return start + sel.c0, start + sel.c1 end
  local m = view:measure_at(view.beat)
  if m then return start + m.start, start + m.start + m.length end
end

command(
  "part.cue",
  function(ctx)
    local id = part_track()
    if not id then return paw.notify("no track", "warn") end
    local words = ctx.args[1]
    local from, to = stretch(ctx)
    if words == "off" then
      local gone = 0
      P.keep(id, function(part)
        local keep = {}
        for _, cue in ipairs(part.cues or {}) do
          if from and (cue.to <= from + EPS or cue.at >= to - EPS) then
            keep[#keep + 1] = cue
          else
            gone = gone + 1
          end
        end
        part.cues = #keep > 0 and keep or nil
      end)
      view.cache = nil
      return paw.notify(gone .. (gone == 1 and " cue" or " cues") .. " taken away")
    end
    local e = instrument(words)
    if not e then return paw.notify("cue from which instrument? " .. table.concat(complete_names(), ", "), "warn") end
    if e.id == id then return paw.notify("a cue is another instrument's notes", "warn") end
    if not from then return paw.notify("no bars to cue: give a range (`:5,8part.cue Oboe`) or select them", "warn") end
    P.keep(id, function(part)
      part.cues = part.cues or {}
      table.insert(part.cues, { from = e.id, at = from, to = to })
    end)
    view.cache = nil
    paw.notify("cue from " .. e.name .. " in the rests there")
  end,
  {
    range = true,
    raw = true,
    desc = "Another instrument's notes written small in this part's rests, to come in by: `:5,8part.cue Oboe`, on a selection, `part.cue off`",
    complete = complete_names,
  }
)

--- The bar number of the cursor in the part shown.
local function cursor_bar()
  local m = view:measure_at(view.beat)
  return m and m.number
end

local function toggle(list_name, other)
  return function()
    if not (view.parts and view.parts.kind == "part") then return paw.notify("show a part first (`:part`)", "warn") end
    local bar = cursor_bar()
    if not bar then return end
    local on
    P.keep(view.parts.track, function(part)
      local list, kept = part[list_name] or {}, {}
      on = true
      for _, b in ipairs(list) do
        if b == bar then
          on = false
        else
          kept[#kept + 1] = b
        end
      end
      if on then kept[#kept + 1] = bar end
      part[list_name] = #kept > 0 and kept or nil
      -- A bar is not both broken before and joined.
      if on and part[other] then
        local rest = {}
        for _, b in ipairs(part[other]) do
          if b ~= bar then rest[#rest + 1] = b end
        end
        part[other] = #rest > 0 and rest or nil
      end
    end)
    view.cache = nil
    api.ui_redraw()
    paw.notify(
      (list_name == "breaks" and "a system starts at bar " or "bar " .. bar .. " kept on the system before")
        .. (list_name == "breaks" and bar or "")
        .. (on and "" or ": taken away")
        .. ", in this part"
    )
  end
end
command(
  "part.break",
  toggle("breaks", "joins"),
  { desc = "In the part shown: start a system at the cursor's bar, or take that break away" }
)
command(
  "part.join",
  toggle("joins", "breaks"),
  { desc = "In the part shown: keep the cursor's bar on the system before, or not" }
)
command("part.bars-per-system", function(ctx)
  if not (view.parts and view.parts.kind == "part") then return paw.notify("show a part first (`:part`)", "warn") end
  local n = tonumber(ctx.args[1])
  P.keep(view.parts.track, function(part) part.per_system = n end)
  view.cache = nil
  api.ui_redraw()
  paw.notify(n and (n .. " bars to a system in this part") or "as many bars to a system as fit, in this part")
end, { desc = "In the part shown: that many bars to every system, or without a number as they fit" })

command(
  "part.name",
  function(ctx)
    local id = part_track()
    if not id then return paw.notify("no track", "warn") end
    local full, short = tostring(ctx.args[1] or ""):match("^%s*(.-)%s*|%s*(.-)%s*$")
    full = full or tostring(ctx.args[1] or ""):match("^%s*(.-)%s*$")
    P.keep(id, function(part)
      part.name = full ~= "" and full or nil
      part.short = short ~= "" and short or nil
    end)
    view.cache = nil
    paw.notify(
      full ~= "" and ("named " .. full .. (short and short ~= "" and (", " .. short) or "")) or "named as the track"
    )
  end,
  {
    raw = true,
    desc = "The names a track's instrument has in the score and its part: `part.name Flute 1 | Fl. 1` (full, short), alone the track's name",
  }
)

-- Export ----------------------------------------------------------------------------------------

local function safe(text) return (tostring(text):gsub("[^%w%-_]+", "_")) end

local function heading(part)
  local title, composer = page.heading(view:clip() and view:clip():get().name)
  return { title = title, composer = composer, part = part }
end

--- Every part as MusicXML: written as each is played (with what takes it
--- to concert pitch), the families bracketed.
function P.musicxml(path)
  local mx = require("notation.musicxml")
  local list = P.instruments()
  if #list == 0 then error("no track has MIDI", 0) end
  -- Each made of every clip of its track.
  local parts = P.scores(list)
  local groups = 0
  for i, p in ipairs(parts) do
    local e = list[i]
    p.name, p.short, p.transpose = e.name, e.short, e.transpose
    if e.transpose then p.fifths = (p.fifths or 0) + P.transpose_score(p.score, e.transpose, p.fifths) end
    local before, after = list[i - 1], list[i + 1]
    if e.family <= #P.FAMILIES then
      if not (before and before.family == e.family) then
        groups = groups + 1
        p.group = { name = P.FAMILIES[e.family]:gsub("^%l", string.upper), number = groups }
      end
      if not (after and after.family == e.family) then p.group_end = groups end
    end
  end
  local text = mx.write(parts, heading())
  if path:lower():match("%.mxl$") then text = mx.mxl(text, (path:match("([^/]+)%.%w+$") or "score")) end
  local f, err = io.open(path, "wb")
  if not f then error((tostring(err):gsub("^[^:]*: ", "")), 0) end
  f:write(text)
  f:close()
  return #parts
end

command(
  "part.export",
  function(ctx)
    local path, what = ctx.args[1] and tostring(ctx.args[1]), ctx.args[2]
    local kinds = { pdf = true, svg = true, png = true }
    local stem = safe(heading().title ~= "" and heading().title or "score")
    if not path or kinds[path] then path = stem .. "." .. (path or "pdf") end
    local ext = (path:match("%.(%w+)$") or ""):lower()
    if ext == "musicxml" or ext == "xml" or ext == "mxl" then
      local ok, n = pcall(P.musicxml, path)
      if not ok then return paw.notify("could not write " .. path .. ": " .. tostring(n), "error") end
      return paw.notify("wrote " .. n .. " parts to " .. path)
    end
    if not kinds[ext] then return paw.notify("export a .pdf, .svg, .png, .musicxml or .mxl", "warn") end
    local shown = view.parts and view.parts.kind
    local jobs = {}
    if what == "all" then
      for _, e in ipairs(P.instruments()) do
        jobs[#jobs + 1] = { track = e.id, path = path:gsub("%.(%w+)$", "-" .. safe(e.name) .. ".%1") }
      end
    elseif what == "score" or (shown == "score" and what ~= "part") then
      jobs[1] = { score = true, path = path }
    else
      jobs[1] = { track = part_track(), path = path }
    end
    local wrote, pages = {}, 0
    for _, job in ipairs(jobs) do
      local layout, err
      if job.score then
        layout, err = P.score_layout({ condensed = view.parts and view.parts.condensed })
      else
        layout, err = P.part_layout(job.track)
      end
      if not layout then return paw.notify(err or "nothing to write", "warn") end
      local ok, files, n = pcall(page.export, layout, job.path, ext, heading(layout.part_name))
      if not ok then return paw.notify("could not write " .. job.path .. ": " .. tostring(files), "error") end
      for _, f in ipairs(files) do
        wrote[#wrote + 1] = f
      end
      pages = pages + n
    end
    paw.notify(
      "wrote "
        .. (#jobs == 1 and (jobs[1].score and "the score" or "the part") or (#jobs .. " parts"))
        .. " to "
        .. table.concat(wrote, ", ")
        .. ", "
        .. pages
        .. (pages == 1 and " page" or " pages")
    )
    return wrote, pages
  end,
  {
    desc = "Write the part shown (or the score) as engraved pages: `part.export flute.pdf`, `part.export parts.pdf all` (a file for each part), `part.export score.pdf score`; `part.export score.musicxml` every part, transposed, in one file",
    complete = { "files", function() return { "all", "score", "part" } end },
  }
)

-- Keys ------------------------------------------------------------------------------------------

local function key(lhs, rhs, desc) keymap.set("<localleader>P" .. lhs, rhs, { view = "notation", desc = desc }) end
keymap.group("<localleader>P", "score and parts", { view = "notation" })
key("s", "part.score", "The full score, to edit")
key("c", "part.condense", "The full score condensed, or not")
key("p", "part", "This track's part")
key("n", "part.next", "The next part")
key("N", "part.prev", "The previous part")
key("o", "part off", "Back to the clip alone")
key("b", "part.break", "In the part: a system starts at this bar, or not")
key("j", "part.join", "In the part: this bar on the system before, or not")
key("e", function() keymap.feed(":part.export ") end, "Export the part or score: a PDF, or MusicXML")

return P
