-- Commands and keys of the notation view. The view takes the grammar of the
-- piano roll: motions, operators with any of them, text objects, visual
-- mode, registers, counts and `.`; its rows are pitches, so the runtime's
-- note editing (`paw.edit.roll`) works on it unchanged.
local api = paw.api
local util = paw.util
local model = require("notation.model")
local view = require("notation")
local keymap, edit = paw.keymap, paw.edit
local map, command = keymap.set, paw.command

local EPS = 1e-6

-- Commands --------------------------------------------------------------------------------

command("notation", function()
  local clip = view.target()
  if not clip then return paw.notify("no clip under the cursor", "warn") end
  view:edit(clip)
end, { desc = "Show the clip under the cursor as notation, to read and edit" })
command("notation.open", function() paw.cmd("notation") end, { desc = "Show the clip under the cursor as notation" })

command("notation.clef", function(ctx)
  local want = ctx.args[1] and tostring(ctx.args[1])
  local valid = want and (model.CLEF_BOTTOM[want] or want == "grand" or want == "auto" or want == "off")
  -- On a score's bar after the first: a clef change there.
  if valid and want ~= "grand" and want ~= "auto" and require("notation.write").clef(ctx, want) then return end
  local clip = view.target()
  local track = clip and clip:track() or paw.cursor.track()
  if not track then return paw.notify("no track", "warn") end
  local meta = track.meta or {}
  if not want then
    local fixed = type(meta.notation) == "table" and meta.notation.clef
    return paw.notify("clef: " .. (fixed or "chosen by the notes"))
  end
  if not valid or want == "off" then
    return paw.notify("a clef is treble, treble8 (guitar), bass, bass8, alto, tenor, grand or auto", "warn")
  end
  local own = type(meta.notation) == "table" and meta.notation or {}
  own.clef = want ~= "auto" and want or nil
  meta.notation = next(own) and own or nil
  track.meta = meta
  paw.notify("clef: " .. (own.clef or "chosen by the notes"))
end, { range = true, desc = "Fix the track's clef: `notation.clef bass` (treble, treble8, bass, bass8, alto, tenor, grand, auto); in a score after its first bar, a clef change at the cursor's bar" })

command("notation.key", function(ctx)
  -- In a score open in the view: a key change at the cursor's bar.
  if #ctx.args > 0 and require("notation.write").key(ctx) ~= false then return end
  local words = {}
  for _, a in ipairs(ctx.args) do words[#words + 1] = tostring(a) end
  if #words == 0 then
    local fifths, stored = view.key()
    return paw.notify("key: " .. (stored and (stored.root .. " " .. (stored.scale or "major")) or "none (C major)") .. ", " .. math.abs(fifths) .. (fifths >= 0 and " sharps" or " flats"))
  end
  if words[1] == "off" then
    paw.harmony.set_key(nil)
    return
  end
  local root = words[1]:sub(1, 1):upper() .. words[1]:sub(2)
  if not root:match("^[A-G][#b]?$") then return paw.notify("a key is a root and a scale: `notation.key Bb major`", "warn") end
  local ok, err = pcall(paw.harmony.set_key, root .. " " .. (words[2] or "major"))
  if not ok then return paw.notify(tostring(err):gsub("^[^:]*:%d+: ", ""), "warn") end
end, { range = true, desc = "Set the key: in a score open in the view, from the cursor's bar (`notation.key Eb`, `f#m`, `D dorian`, `off`); else the project's (`paw.harmony.set_key`)" })

--- The clip the settings commands work on.
local function settings_clip()
  local clip = view.target()
  if not clip then paw.notify("no clip under the cursor", "warn") end
  return clip
end

local function parse_value(text, default)
  if text == "on" or text == "true" or text == "yes" then return true end
  if text == "off" or text == "false" or text == "no" then
    if type(default) == "number" then return 0 end
    if type(default) == "string" and default ~= "score" then return "off" end
    return false
  end
  return tonumber(text) or text
end

command("notation.set", function(ctx)
  local clip = settings_clip()
  if not clip then return end
  local score = require("notation.score")
  local name = ctx.args[1] and tostring(ctx.args[1])
  local set = view.settings_of(clip:get())
  if not name then
    -- A page, as `K` shows one: a line a setting, and whether the clip changed it.
    local own = view.own(clip:get()).settings or {}
    local lines = { { text = "Transcription of " .. clip:get().name, style = "Title" } }
    for _, k in ipairs(score.ORDER) do
      local changed = own[k] ~= nil and own[k] ~= score.DEFAULTS[k]
      lines[#lines + 1] = string.format("  %-11s %-8s%s", k, tostring(set[k]), changed and ("  (default " .. tostring(score.DEFAULTS[k]) .. ")") or "")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  :notation.set swing off sets one, swing default forgets it"
    lines[#lines + 1] = "  :notation.reset forgets them all"
    return paw.ui.page("Notation settings", lines)
  end
  if score.DEFAULTS[name] == nil then return paw.notify("no setting " .. name .. "; they are: " .. table.concat(score.ORDER, ", "), "warn") end
  if ctx.args[2] == nil then return paw.notify(name .. " = " .. tostring(set[name])) end
  local value = parse_value(tostring(ctx.args[2]), score.DEFAULTS[name])
  if ctx.args[2] == "default" then value = nil end
  view.keep(clip, function(own)
    own.settings = util.merge(own.settings or {}, {})
    own.settings[name] = value
    if not next(own.settings) then own.settings = nil end
  end)
  paw.notify(name .. " = " .. tostring(view.settings_of(clip:get())[name]))
end, { desc = "Set how the clip is transcribed: `notation.set strum 80`, `notation.set swing off`, `notation.set voices off`; alone, list them" })

-- Marks: articulations, dynamics, hairpins, slurs, text, repeats.
local marks = require("notation.marks")

--- The region a command works on: its range of bars (`:5,8notation.slur`),
--- else the selection, which is also what `:'<,'>` names; nil for neither.
local function ranged(ctx)
  local clip = view:clip()
  local range = ctx and ctx.range
  if clip and range and range.bars then
    local c = clip:get()
    return { view = "notation", kind = "char", r0 = 0, r1 = 127, c0 = math.max(0, range.from - c.start), c1 = math.min(c.length, range.to - c.start) }
  end
  return view:selection()
end

--- The chords a mark goes on, by their ids in the score: the region's (by
--- default the command's range or the selection), or the chord's under the
--- cursor.
local function target_notes(region, ctx)
  local clip = view:editable()
  region = region or ranged(ctx)
  if region and clip then
    local _, places = edit.roll.notes(clip, region)
    return view:events_of(places)
  end
  return view:chord_indices()
end

command("notation.art", function(ctx)
  local kind = tostring(ctx.args[1] or "")
  if not marks.ARTICULATIONS[kind] then return paw.notify("an articulation is staccato, accent, tenuto or marcato", "warn") end
  local on = marks.toggle_art(kind, target_notes(nil, ctx))
  if on ~= nil then paw.notify(kind .. (on and " on" or " off")) end
end, { range = true, desc = "Staccato, accent, tenuto or marcato on the chord under the cursor, or the range: `notation.art accent`" })

--- Where a mark goes: the start and end of the range or the selection, or
--- the cursor's place and the end of its bar.
local function mark_span(ctx)
  local region = ranged(ctx)
  if region then return math.max(0, region.c0), region.c1 end
  local layout = view:layout()
  local m = view:measure_at(view.beat, layout)
  return view.beat, m and (m.start + m.length) or (view.beat + 4)
end

command("notation.dyn", function(ctx)
  local value = tostring(ctx.args[1] or ""):match("^%s*(.-)%s*$")
  if marks.DYNAMICS[value] and view:clip() then
    marks.put(view:clip(), { at = (mark_span(ctx)), kind = "dyn", value = value })
    return paw.notify(value .. ": notes from here as loud as " .. marks.DYNAMICS[value])
  end
  require("notation.write").dynamic(ctx)
end, { range = true, raw = true, desc = "A dynamic at the cursor (or the start of the range), which sets how loud the notes from there play: `notation.dyn mf`; `sfz`, `fp`, `p subito`; a hairpin to the next dynamic `<`, `>`, or `mp<f` over the range" })

for _, kind in ipairs({ "cresc", "dim" }) do
  command("notation." .. kind, function(ctx)
    local clip = view:clip()
    if not clip then return paw.notify("no clip open as notation", "warn") end
    local from, to = mark_span(ctx)
    marks.put(clip, { at = from, to = to, kind = kind })
    paw.notify((kind == "cresc" and "crescendo" or "diminuendo") .. " to " .. paw.time.format(clip.start + to))
  end, { range = true, desc = (kind == "cresc" and "A crescendo" or "A diminuendo") .. " hairpin over the range or selection (or to the end of the bar), ramping the loudness" })
end

command("notation.text", function(ctx)
  local clip = view:clip()
  if not clip then return paw.notify("no clip open as notation", "warn") end
  local text = tostring(ctx.args[1] or ""):match("^%s*(.-)%s*$")
  local region = ranged(ctx)
  marks.put(clip, { at = region and math.max(0, region.c0) or view.beat, kind = "text", value = text ~= "" and text or false })
end, { raw = true, range = true, desc = "Text above the staff at the cursor (or the start of the range): `notation.text Allegro`; with nothing, takes it away" })

command("notation.repeat", function(ctx)
  local clip = view:clip()
  if not clip then return paw.notify("no clip open as notation", "warn") end
  local which = tostring(ctx.args[1] or "")
  -- Over a range: its first bar's start and its last bar's end.
  local region = ranged(ctx)
  local first = view:measure_at(region and math.max(0, region.c0) or view.beat)
  local last = region and view:measure_at(math.max(region.c0, region.c1 - EPS)) or first
  local from, to = first.start, last.start + last.length
  if which == "start" then
    marks.put(clip, { at = from, kind = "repeat", value = "start" })
  elseif which == "end" then
    marks.put(clip, { at = to, kind = "repeat", value = "end" })
  elseif which == "both" or (which == "" and region) then
    marks.put(clip, { at = from, kind = "repeat", value = "start" })
    marks.put(clip, { at = to, kind = "repeat", value = "end" })
  elseif which == "off" then
    marks.put(clip, { at = from, kind = "repeat", value = false })
    marks.put(clip, { at = to, kind = "repeat", value = false })
  else
    return paw.notify("a repeat sign is start, end, both or off", "warn")
  end
end, { range = true, desc = "A repeat sign at the start or end of the cursor's bar, or around the range (written only): `notation.repeat start`, `:5,8notation.repeat`" })

command("notation.slur", function(ctx)
  local clip = view:clip()
  if not clip then return paw.notify("no clip open as notation", "warn") end
  local from, to = mark_span(ctx)
  local on = marks.slur(clip, from, to - 1e-3, view:cursor_staff())
  paw.notify(on and "slurred" or "slur taken away")
end, { range = true, desc = "A slur over the range or selection (written only: the notes keep how they play)" })

--- A region's stretch and pitches, as `quantize` and `retranscribe` take them.
local function bounds(region)
  if not region or region.kind == "line" then return nil, nil, nil, nil end
  if region.kind == "char" then return region.c0, region.c1 end
  return region.c0, region.c1, region.r0, region.r1
end

command("notation.quantize", function(ctx)
  if not view:clip() then return paw.notify("no clip open as notation", "warn") end
  local n = view:quantize(bounds(ranged(ctx)))
  paw.notify(n == 1 and "1 note moved to where it is written" or n .. " notes moved to where they are written")
end, { range = true, desc = "Quantize the clip's notes (or the range's) to the notation: each starts where it is written and lasts as long as it is written" })

command("notation.apply-marks", function(ctx)
  if not view:clip() then return paw.notify("no clip open as notation", "warn") end
  local n = view:apply_marks(bounds(ranged(ctx)))
  paw.notify(n == 0 and "the notes already play as the marks say"
    or (n == 1 and "1 note" or n .. " notes") .. " made to play as the marks say")
end, { range = true, desc = "Make the clip's notes (or the range's) play as the marks say: dynamics and hairpins set the velocity, staccato and tenuto the length. For MIDI that was changed since in the piano roll" })

command("notation.retranscribe", function(ctx)
  if not view:clip() then return paw.notify("no clip open as notation", "warn") end
  view:retranscribe(bounds(ranged(ctx)))
  paw.notify("written again from the playing")
end, { range = true, desc = "Write the clip (or the range's bars) again from what its notes play: what was decided in notation there (voices, spellings, tuplets) is forgotten" })

command("notation.voice", function(ctx)
  -- Over a range or a selection, the chords into that voice.
  if require("notation.write").voice(ctx) then return end
  local v = tonumber(ctx.args[1])
  if not v then return paw.notify("entering in voice " .. (view.voice or 1)) end
  if v < 1 or v > 4 then return paw.notify("a voice is 1 to 4", "warn") end
  view.voice = math.floor(v)
  api.ui_redraw()
  paw.notify("entering in voice " .. view.voice)
end, { range = true, desc = "Choose the voice notes are entered in, on the cursor's staff: `notation.voice 2` (1 to 4); over a range or selection, its chords into that voice" })

command("notation.transpose", function(ctx)
  if not view:clip() then return paw.notify("no clip open as notation", "warn") end
  local by = tonumber(ctx.args[1])
  if not by then return paw.notify("transpose by semitones, or by steps of the key: `notation.transpose -12`, `notation.transpose 2 steps`", "warn") end
  local steps = ctx.args[2] == "steps" or ctx.args[2] == "step"
  local n = view:transpose_events(target_notes(nil, ctx), by, steps)
  paw.notify(n == 1 and "1 note transposed" or n .. " notes transposed")
end, { range = true, desc = "Transpose the chord under the cursor, or the range or selection, by semitones or steps of the key: `:5,8notation.transpose 2`, `notation.transpose -1 steps`" })

command("notation.raw", function()
  local clip = settings_clip()
  if not clip then return end
  local raw = view.settings_of(clip:get()).mode ~= "raw"
  view.keep(clip, function(own)
    own.settings = util.merge(own.settings or {}, {})
    own.settings.mode = raw and "raw" or nil
    if not next(own.settings) then own.settings = nil end
  end)
  paw.notify(raw and "notation: every note as played (raw)" or "notation: as a musician would write it")
end, { desc = "Show the clip note for note as played, or interpreted again" })

command("notation.reset", function()
  local clip = settings_clip()
  if not clip then return end
  view.keep(clip, function(own) own.settings = nil end)
  paw.notify("notation: default transcription")
end, { desc = "Forget the clip's transcription settings" })

command("notation.tab", function(ctx)
  local tab = require("notation.tab")
  local clip = view.target()
  local track = clip and clip:track() or paw.cursor.track()
  if not track then return paw.notify("no track", "warn") end
  local words = {}
  for _, a in ipairs(ctx.args) do words[#words + 1] = tostring(a) end
  if #words == 0 then
    local own = tab.of_track(track.id)
    if not own then return paw.notify("no tablature: `notation.tab guitar`, `bass`, `dropd`, `7string`, `bass5`, or the strings' notes") end
    local names = {}
    for i, p in ipairs(own.tuning) do names[i] = paw.music.name(p) end
    return paw.notify("tablature: " .. table.concat(names, " "))
  end
  local own, err = tab.set(track, words)
  if err then return paw.notify(err, "warn") end
  view.cache = nil
  paw.notify(own and ("tablature: " .. #own.tuning .. " strings") or "no tablature")
end, { desc = "Tablature under the staff for a guitar or bass track: `notation.tab guitar` (bass, dropd, dadgad, 7string, bass5, or `E2 A2 D3 G3 B3 E4`), `notation.tab off`" })

command("notation.tracks", function(ctx)
  local clip = view:clip() or view.target()
  if not clip then return paw.notify("no clip open as notation", "warn") end
  if view.parts and not ctx.args[1] then
    view.parts, view.cache = nil, nil
    api.ui_redraw()
    return paw.notify("notation: this clip alone")
  end
  if not view:clip() then view:edit(clip) end
  local c = clip:get()
  local ids = {}
  for _, t in ipairs(paw.tracks()) do
    for _, other in ipairs(t:clips()) do
      local oc = other:get()
      if oc.kind == "midi" and oc.start < c.start + c.length and oc.start + oc.length > c.start and oc.note_count > 0 then
        ids[#ids + 1] = t.id
        break
      end
    end
  end
  -- The score of those tracks' clips over this one's stretch, to edit.
  view.staves.show(ids, "the score of " .. #ids .. " tracks", { from = c.start, to = c.start + c.length })
  paw.notify("notation: " .. #ids .. " tracks, a staff each, this clip's the active one; :notation.tracks again for the clip alone")
end, { desc = "Show every track's MIDI over this clip's stretch as a score, a staff each, to edit; or this clip alone again" })

command("notation.value", function(ctx)
  local names = { whole = 4, half = 2, quarter = 1, eighth = 0.5, ["16th"] = 0.25, ["32nd"] = 0.125 }
  local v = names[tostring(ctx.args[1] or "")]
  if not v then return paw.notify("a value is whole, half, quarter, eighth, 16th or 32nd", "warn") end
  view:choose(v)
end, { desc = "Choose the value notes are entered with: `notation.value eighth`" })

command("notation.export", function(ctx)
  local export = require("notation.export")
  local clip = view.target()
  if not clip then return paw.notify("no clip under the cursor", "warn") end
  local whole_track = ctx.args.track == "yes" or ctx.args.track == true or ctx.args[2] == "track"
  local c = clip:get()
  local track = clip:track()
  local name = whole_track and track.name or c.name
  -- The message names what was written, so that a clip chosen by the notation
  -- view or the arrange cursor is not a surprise.
  local what = whole_track and ("track '" .. track.name .. "'") or ("'" .. (c.name ~= "" and c.name or "clip") .. "' (" .. track.name .. ")")
  local path = ctx.args[1] and tostring(ctx.args[1]) or (name:gsub("[^%w%-_]+", "_") .. ".musicxml")
  -- `pdf`, `svg` or `png` alone: a file of that kind named after the clip.
  local engraved = { pdf = true, svg = true, png = true }
  if engraved[path] then path = name:gsub("[^%w%-_]+", "_") .. "." .. path end
  local ext = (path:match("%.(%w+)$") or ""):lower()
  local all = ctx.args[2] == "all"
  if (ext == "musicxml" or ext == "xml" or ext == "mxl" or ext == "ly") and not whole_track then
    -- Written from the score itself: every bar, voice and mark it holds.
    local files = require("notation.files")
    local title, composer = require("notation.page").heading(name)
    local clips = all and files.all_clips() or { clip }
    local ok, err = pcall(files.export, path, clips, { title = title, composer = composer })
    if not ok then return paw.notify("could not write " .. path .. ": " .. tostring(err), "error") end
    if all then what = #clips .. (#clips == 1 and " track" or " tracks") end
    return paw.notify("wrote " .. what .. " to " .. path)
  end
  local _, stored = view.key()
  local opts = view.layout_opts(c)
  local layout
  if whole_track then
    opts.bars, opts.tuplets, opts.length, opts.offset = nil, nil, nil, nil
    layout = export.track_layout(track, opts, view.bars)
  else
    layout = require("notation.layout").layout(view.score_of(c), { length = c.length, fifths = opts.fifths,
      number = opts.bars[1] and opts.bars[1].number })
  end
  view.decorate(layout, clip)
  if engraved[ext] then
    -- The engraved pages, as the page view shows them.
    local title, composer = require("notation.page").heading(name)
    local ok, written, pages = pcall(require("notation.page").export, layout, path, ext, { title = title, composer = composer })
    if not ok then return paw.notify("could not write " .. path .. ": " .. tostring(written), "error") end
    return paw.notify("wrote " .. what .. " to " .. table.concat(written, ", ") .. ", " .. pages .. (pages == 1 and " page" or " pages"))
  end
  local text
  if path:match("%.ly$") then
    text = export.lilypond(layout, { title = name, scale = stored and stored.scale })
  else
    text = export.musicxml(layout, { title = name, part = track.name })
  end
  local ok, err = export.write(path, text)
  if not ok then return paw.notify("could not write " .. path .. ": " .. tostring(err), "error") end
  paw.notify("wrote " .. what .. " to " .. path)
end, { desc = "Write the clip's score as MusicXML (`.mxl` zipped), LilyPond, or engraved pages: `notation.export song.musicxml`, `notation.export score.mxl all` (every track), `notation.export lead.ly track`, `notation.export pdf`, `notation.export tune.svg`", complete = { "files", function() return { "all", "track" } end } })

-- Reaching it from the arrange view and the window's clip menu.
map("<localleader>n", "notation", { view = "arrange", desc = "Show the clip as notation" })
map("<localleader>n", "notation", { view = "pianoroll", desc = "Show this clip as notation" })
if paw.frontend and paw.frontend.menus then
  table.insert(paw.frontend.menus.clip, { label = "Open as notation", command = "notation.open", only = "midi" })
end

-- Keys in the view ------------------------------------------------------------------------

local motion, linewise = { motion = true }, { motion = true, linewise = true }
local far = { motion = true, jump = true }
--- Keys do nothing (and say why) when the clip shown is gone: undone or deleted.
local function present(rhs)
  if type(rhs) ~= "function" then return rhs end
  return function(...)
    if not view:clip() then return view.missing() end
    return rhs(...)
  end
end
--- Keys that edit do nothing (and say why) while the pages are shown to check.
local function guarded(rhs)
  if type(rhs) ~= "function" then return rhs end
  return present(function(...)
    if view:readonly() then return end
    return rhs(...)
  end)
end
local READ = { gh = true, gp = true, zi = true, zo = true, zg = true, zp = true, ["]d"] = true, ["[d"] = true, gK = true, ["<Esc>"] = true, ["<localleader>n"] = true, ZZ = true, gd = true, gR = true, zS = true, ["<Tab>"] = true }
-- Keys that leave the view, or open another clip, work with no clip shown.
local ANYWAY = { ["<Esc>"] = true, ["<localleader>n"] = true, zS = true }
local function nmap(lhs, rhs, desc, opts)
  if not (opts and opts.motion) and not READ[lhs] and not lhs:match("^g%d$") then rhs = guarded(rhs)
  elseif not ANYWAY[lhs] then rhs = present(rhs) end
  map(lhs, rhs, util.merge({ view = "notation", desc = desc }, opts))
end

local function move(dvalue, dstep) return function(ctx)
  local n = ctx.count or 1
  view:move(dvalue * n * view:entry_length(), dstep * n)
end end
nmap("h", move(-1, 0), "Back by the chosen value", motion)
nmap("l", move(1, 0), "On by the chosen value", motion)
nmap("<Left>", move(-1, 0), "Back by the chosen value", motion)
nmap("<Right>", move(1, 0), "On by the chosen value", motion)
nmap("j", move(0, -1), "Down a line or space", linewise)
nmap("k", move(0, 1), "Up a line or space", linewise)
nmap("<Down>", move(0, -1), "Down a line or space", linewise)
nmap("<Up>", move(0, 1), "Up a line or space", linewise)
-- An octave is half a page: `Ctrl-d` `Ctrl-u`, as in the piano roll. `K`
-- describes, as in every view.
nmap("<C-d>", move(0, -7), "Down an octave", linewise)
nmap("<C-u>", move(0, 7), "Up an octave", linewise)
keymap.classic("J", present(move(0, -7)), { view = "notation", desc = "Down an octave", motion = true, linewise = true })
keymap.classic("K", present(move(0, 7)), { view = "notation", desc = "Up an octave", motion = true, linewise = true })
nmap("w", function(ctx) view:to_event(1, ctx.count) end, "Next note or rest", motion)
nmap("b", function(ctx) view:to_event(-1, ctx.count) end, "Previous note or rest", motion)
nmap("e", function(ctx)
  for _ = 1, ctx.count or 1 do view:to_event_end() end
end, "End of this note, or the next", motion)
nmap("W", function(ctx) view:to_bar(ctx.count or 1) end, "Next bar", motion)
nmap("B", function(ctx) view:to_bar(-(ctx.count or 1)) end, "Previous bar", motion)
nmap("0", function() view:set(nil, 0) end, "Start of the clip", motion)
nmap("^", function()
  local first = view:starts()[1]
  for _, ev in ipairs(view:starts()) do
    if ev.notes then
      first = ev
      break
    end
  end
  if first then view:set(first.notes and first.notes[1].step or nil, math.max(0, first.start)) end
end, "The first note", motion)
nmap("$", function()
  local clip = view:clip()
  if clip then view:set(nil, clip.length) end
end, "End of the clip", motion)
nmap("gg", function() view:to_extreme(1) end, "The highest note's line", util.merge(far, { linewise = true }))
nmap("G", function() view:to_extreme(-1) end, "The lowest note's line", util.merge(far, { linewise = true }))
nmap("gp", function()
  local clip = view:clip()
  if clip then paw.transport.seek(clip.start + view.beat) end
end, "Playhead to the cursor")

-- Operators on how the score plays, and the loop; the operators that edit
-- what is written are with the grammar below.
local function op(lhs, fn, desc)
  keymap.operator(lhs, function(region, ctx)
    local clip = view:clip()
    if lhs ~= "gl" then
      if view:readonly() then return end
      clip = view:editable()
    end
    if clip then return fn(clip, region, ctx) end
  end, { view = "notation", desc = desc })
end
op("=", function(_, region)
  -- The notes moved to what is written: a MIDI edit like any other.
  local n = view:quantize(bounds(region))
  paw.notify(n == 1 and "1 note played as written" or n .. " notes played as written")
end, "Play as written: the notes start where they are written and last as long (quantize to the notation)")
op("g=", function(_, region)
  local n = view:retranscribe(bounds(region))
  paw.notify("written again from the playing" .. (n > 0 and (" (" .. n .. " notes)") or ""))
end, "Write again from the playing: the bars transcribed afresh from what the notes play")
op("g@", function(_, region)
  -- Asks first, with the change heard and shown as a popover's is.
  view.popover.open("apply-marks", { region = region })
end, "Make the notes play as the marks say (dynamics, hairpins, articulations): a prompt shows the change; Enter writes it")
op("gl", function(clip, region)
  local c0, c1 = region.c0, region.c1
  if region.kind == "line" then c0, c1 = 0, clip.length end
  paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = clip.start + c0, clip.start + c1, true
end, "Loop")

-- Single keys.
local function each_count(fn) return function(ctx)
  for _ = 1, ctx.count or 1 do fn() end
end end
nmap("<CR>", function() view:toggle_note() end, "Add a note of the chosen value, or take away the one here")
local function insert()
  if not view:editable() then return end
  -- Entry goes into the voice of the note the cursor is on, if it is on one.
  view.last, view.chord, view.voice = nil, nil, view:cursor_voice()
  view.push, view.repitch, view.grace, view.pending_grace = nil, nil, nil, nil
  keymap.set_mode("i")
end
nmap("i", insert, "Enter notes by letter name (a to g)")
nmap("a", function()
  local note, index = view:note()
  if note then
    local _, finish = view:written_span(index)
    view:set(nil, finish)
  end
  insert()
end, "Enter notes after this one")
nmap("x", function() view:delete() end, "Delete the note")
nmap("X", function() view:delete_chord() end, "Delete the chord: every note it stands for")
-- `L` `H` move in time, as they move a note in the piano roll and a clip in
-- the arrange view.
local function move_chord(sign) return function(ctx) view:move_chord(sign * (ctx.count or 1) * view:entry_length()) end end
nmap("L", move_chord(1), "Move the chord later by the chosen value, as played")
nmap("H", move_chord(-1), "Move the chord earlier by the chosen value, as played")
keymap.classic("<A-l>", guarded(move_chord(1)), { view = "notation", desc = "Move the chord later by the chosen value, as played" })
keymap.classic("<A-h>", guarded(move_chord(-1)), { view = "notation", desc = "Move the chord earlier by the chosen value, as played" })
nmap("gV", function()
  local v = view:toggle_voice()
  if v then paw.notify("voice " .. v .. "; entering in voice " .. v) end
end, "The note (or chord) into the other voice, and enter in it")
nmap("gH", function()
  local s = view:toggle_staff()
  if s then paw.notify(s == 1 and "right hand" or "left hand") end
end, "The chord onto the other staff (hand)")
nmap("gs", function()
  local mark = view:cycle_strum()
  paw.notify("arpeggio: " .. tostring(mark or "as played"))
end, "Arpeggio sign: up, down, none, as played")
nmap("gG", function() paw.notify(view:toggle_grace() and "grace note" or "not a grace note") end, "The note a grace note, or the chord's grace note not one")
nmap("gb", function() paw.notify(view:toggle_beam() and "beam broken here" or "beam joined") end, "Break the beam before the chord, or join it")
-- `ge` is the plugin window in every view; `g~` (an operator, with the
-- grammar below) changes how notes are written, as Vim's changes the case
-- of letters.
keymap.classic("ge", guarded(function() view:respell() end), { view = "notation", desc = "Respell the note: G sharp, A flat" })
for lhs, kind in pairs({ ["g'"] = "staccato", ["g>"] = "accent", ["g_"] = "tenuto", ["g^"] = "marcato" }) do
  nmap(lhs, function()
    local on = marks.toggle_art(kind, view:chord_indices())
    if on ~= nil then paw.notify(kind .. (on and " on" or " off")) end
  end, kind:sub(1, 1):upper() .. kind:sub(2) .. " on the chord, or off")
end
nmap("D", function() keymap.normal("d$") end, "Delete to the end of the clip")
nmap("Y", function() keymap.normal("y$") end, "Yank to the end of the clip")
-- A note's main value is its pitch, as in the piano roll: `+` `-` and
-- `Ctrl-a` `Ctrl-x` sharpen and flatten. Its length is `Alt-l` `Alt-h`, as a
-- clip's is in the arrange view.
local function lengthen(sign) return function(ctx) view:lengthen(sign * (ctx.count or 1) * view:entry_length()) end end
nmap("<A-l>", lengthen(1), "Lengthen the note by the chosen value")
nmap("<A-h>", lengthen(-1), "Shorten the note by the chosen value")
keymap.classic("+", guarded(lengthen(1)), { view = "notation", desc = "Lengthen the note by the chosen value" })
keymap.classic("-", guarded(lengthen(-1)), { view = "notation", desc = "Shorten the note by the chosen value" })
nmap("g.", function() view:toggle_dot() end, "Dot the note, or take its dot away")
nmap("+", each_count(function() view:inflect(1) end), "Sharpen the note: a semitone up", { role = "main+" })
nmap("-", each_count(function() view:inflect(-1) end), "Flatten the note: a semitone down", { role = "main-" })
nmap("<C-a>", each_count(function() view:inflect(1) end), "Sharpen the note: a semitone up", { role = "main+" })
nmap("<C-x>", each_count(function() view:inflect(-1) end), "Flatten the note: a semitone down", { role = "main-" })
nmap("<A-k>", function(ctx) view:transpose_steps(ctx.count or 1) end, "Move the note up a step of the key")
nmap("<A-j>", function(ctx) view:transpose_steps(-(ctx.count or 1)) end, "Move the note down a step of the key")
nmap("}", function(ctx) view:transpose_octaves(ctx.count or 1) end, "Move the note up an octave")
nmap("{", function(ctx) view:transpose_octaves(-(ctx.count or 1)) end, "Move the note down an octave")
local VALUES = { [2] = 0.125, [3] = 0.25, [4] = 0.5, [5] = 1, [6] = 2, [7] = 4 }
for digit = 2, 7 do
  nmap("g" .. digit, function() view:choose(VALUES[digit]) end, "Enter " .. model.NAMES[VALUES[digit]] .. " notes")
end
nmap("gd", function()
  view.dot = not view.dot
  api.ui_redraw()
end, "Dotted values on or off, for entering")
nmap("gh", function() view:audition() end, "Hear the pitch under the cursor")
nmap("gR", function() paw.cmd("notation.raw") end, "Raw view: every note as played, or interpreted again")
nmap("zS", function() paw.cmd("notation.tracks") end, "Every track over this stretch as a score, or this clip alone")
nmap("zi", function()
  view.zoom = math.min(4, view.zoom + 0.5)
  view.gui.zoom(1)
end, "Spread the notes out; on the engraved page, a larger staff")
nmap("zo", function()
  view.zoom = math.max(0.5, view.zoom - 0.5)
  view.gui.zoom(-1)
end, "Draw the notes closer; on the engraved page, a smaller staff")
nmap("zg", function()
  view.galley = not view.galley
  view.page = view.page and not view.galley
  paw.notify(view.galley and "one long system, scrolled sideways (galley)" or "systems wrapped down the page")
  api.ui_redraw()
end, "The engraved page as one long system (galley), or wrapped")

-- The page's layout: system breaks the score keeps, measures to a
-- system, the page view.
local function bar_break(kind)
  local layout = view:layout()
  if not layout or view:readonly() then return end
  -- In a part, its own breaks: the score's stay as they are.
  if view.parts and view.parts.kind == "part" then return paw.cmd(kind == "break" and "part.break" or "part.join") end
  local _, index = view:measure_at(view.beat, layout)
  if not index or index <= 1 then return paw.notify("the first bar starts the first system", "warn") end
  local now
  view:write(function(sc)
    local m = sc.measures[index]
    if not m then return false end
    local D = require("notation.doc")
    now = D.break_at(sc, m.id) ~= kind and kind or nil
    D.set_break(sc, m.id, now)
  end)
  paw.notify(now == "break" and ("a system starts at bar " .. layout.measures[index].number)
    or now == "join" and ("bar " .. layout.measures[index].number .. " stays on the system before")
    or ("bar " .. layout.measures[index].number .. " goes where it fits"))
end
nmap("zs", function() bar_break("break") end, "Start a system at this bar, or let it go where it fits again")
nmap("zj", function() bar_break("join") end, "Keep this bar on the system before, or let it go where it fits again")
nmap("zp", function()
  -- A score's or a part's pages are the check before export, to read.
  if view.parts then return paw.cmd("score.check") end
  view.page = not view.page
  view.galley = view.galley and not view.page
  paw.notify(view.page and "pages (in the window, or where the terminal shows images)" or "systems without pages")
  api.ui_redraw()
end, "The engraved systems on pages, with the title, or without; in a score, its pages to check before export")
command("notation.bars-per-system", function(ctx)
  local n = tonumber(ctx.args[1])
  if ctx.args[1] and not (n and n >= 0 and n == math.floor(n)) then
    return paw.notify("bars per system is a whole number; 0 or none lets them fit", "warn")
  end
  view:write(function(sc) require("notation.doc").set_per_system(sc, n and n > 0 and n or nil) end)
  paw.notify(n and n > 0 and (n .. " bars to a system") or "bars go where they fit")
end, { desc = "Fix how many bars go on each system: `notation.bars-per-system 4`; without a number they go where they fit" })
-- Escape stays: a Vim hand presses it to be sure it is in normal mode, and
-- the keys after it must not land in the arrange view. Counts, pending
-- operators and selections are dropped by the keymap before this runs.
-- A second one soon after says how to leave.
local escaped_at = -math.huge
nmap("<Esc>", function()
  local now = api.now()
  if now - escaped_at < 2000 then
    paw.notify("normal mode: " .. keymap.human("<localleader>n") .. " goes back to the window before, :q or ZZ closes the notation")
  end
  escaped_at = now
end, "Stay in the view (,n leaves)", { repeatable = false })
nmap("<localleader>n", function()
  if not paw.layout.back() then paw.notify("the notation is the only window here: `:e arrange` shows the arrange view in it", "warn") end
end, "Back to the window before")
nmap("ZZ", "close", "Close the notation")

-- On a selection.
local function vmap(lhs, fn, desc)
  map(lhs, nil, { view = "notation", mode = "x", desc = desc, operator = function(region, ctx)
    if view:readonly() then return end
    local clip = view:editable()
    if clip then fn(clip, region, ctx) end
  end })
end
vmap("x", function(clip, region, ctx) keymap.setreg(edit.roll.delete(clip, region), ctx.register) end, "Delete")
for lhs, kind in pairs({ ["g'"] = "staccato", ["g>"] = "accent", ["g_"] = "tenuto", ["g^"] = "marcato" }) do
  vmap(lhs, function(_, region) marks.toggle_art(kind, target_notes(region)) end, kind:sub(1, 1):upper() .. kind:sub(2) .. " on the selection, or off")
end
vmap("<A-l>", function(clip, region, ctx)
  view:relength_region(region, (ctx.count or 1) * view:entry_length())
end, "Lengthen each chord of the selection by the chosen value")
vmap("<A-h>", function(clip, region, ctx)
  view:relength_region(region, -(ctx.count or 1) * view:entry_length())
end, "Shorten each chord of the selection by the chosen value")
vmap("+", function(clip, region, ctx)
  local by = ctx.count or 1
  edit.roll.each(clip, region, function(n) n.pitch = math.min(127, n.pitch + by) end)
end, "Up a semitone")
vmap("-", function(clip, region, ctx)
  local by = ctx.count or 1
  edit.roll.each(clip, region, function(n) n.pitch = math.max(0, n.pitch - by) end)
end, "Down a semitone")
vmap("gs", function(clip, region)
  local _, places = edit.roll.notes(clip, region)
  local n = view:merge_chords(view:events_of(places))
  if n then paw.notify(n .. " notes as one chord") end
end, "The notes one chord, where the first starts and as long (a strum)")
vmap("<C-a>", function(clip, region, ctx)
  local by = ctx.count or 1
  edit.roll.each(clip, region, function(n) n.pitch = math.min(127, n.pitch + by) end)
end, "Up a semitone")
vmap("<C-x>", function(clip, region, ctx)
  local by = ctx.count or 1
  edit.roll.each(clip, region, function(n) n.pitch = math.max(0, n.pitch - by) end)
end, "Down a semitone")
local function diatonic(by) return function(clip, region, ctx)
  local fifths = view.key()
  local n_by = by * (ctx.count or 1)
  edit.roll.each(clip, region, function(n)
    local sp = model.spell(n.pitch, fifths)
    n.pitch = util.clamp(model.key_pitch(sp.step + n_by, fifths), 0, 127)
    if n.meta then n.meta.notation = nil end
  end)
end end
vmap("<A-k>", diatonic(1), "Up a step of the key")
vmap("<A-j>", diatonic(-1), "Down a step of the key")
vmap("}", function(clip, region, ctx)
  edit.roll.each(clip, region, function(n) n.pitch = math.min(127, n.pitch + 12 * (ctx.count or 1)) end)
end, "Up an octave")
vmap("{", function(clip, region, ctx)
  edit.roll.each(clip, region, function(n) n.pitch = math.max(0, n.pitch - 12 * (ctx.count or 1)) end)
end, "Down an octave")

-- Insert mode: notes by letter name, as notation programs enter them.
local function imap(lhs, rhs, desc) map(lhs, guarded(rhs), { view = "notation", mode = "i", desc = desc }) end
-- (The letters themselves are with the grammar below: they also enter
-- grace notes and re-pitch.)
for digit = 2, 7 do
  imap(tostring(digit), function() view:choose(VALUES[digit]) end, model.NAMES[VALUES[digit]] .. " notes")
end
imap(".", function()
  view.dot = not view.dot
  api.ui_redraw()
end, "Dotted values on or off")
imap("0", function() view:enter_rest() end, "A rest: clear the chosen value and step on")
imap("r", function() view:enter_rest() end, "A rest: clear the chosen value and step on")
imap("<Space>", function() view:step_on(1) end, "Step on, leaving what is there")
imap("<BS>", function() view:backspace() end, "Step back, removing what starts there")
imap("+", function() view:inflect_last(1) end, "Sharpen the note just entered")
imap("#", function() view:inflect_last(1) end, "Sharpen the note just entered")
imap("-", function() view:inflect_last(-1) end, "Flatten the note just entered")
imap("'", function() view:octave_last(1) end, "The note just entered an octave up")
imap(",", function() view:octave_last(-1) end, "The note just entered an octave down")
for interval = 2, 8 do
  local name = ({ "", "second", "third", "fourth", "fifth", "sixth", "seventh", "octave" })[interval]
  imap("<A-" .. interval .. ">", function() view:add_interval(interval) end, "Add a " .. name .. " above the note just entered, to its chord")
end
imap("~", function() view:tie_last() end, "Hold the note just entered on by the chosen value (tied), and step on")
imap("v", function()
  -- On a condensed staff the other voice is the other player.
  if view.staves.player() then return end
  view.voice = (view.voice or 1) == 1 and 2 or 1
  paw.notify("entering in voice " .. view.voice)
  api.ui_redraw()
end, "Enter in the other voice (1 or 2) of the staff")
imap("t", function()
  view.triplets, view.tuplet = not (view.triplets or view.tuplet), nil
  paw.notify(view.triplets and "entering triplets" or "entering plain values")
  api.ui_redraw()
end, "Enter triplets, or plain values again")
imap("R", function() view:repeat_chord() end, "Enter the last chord again and step on")
imap("<Left>", function() view:step_on(-1) end, "Step back")
imap("<Right>", function() view:step_on(1) end, "Step on")
imap("<Up>", function() view:move(0, 1) end, "Up a line or space")
imap("<Down>", function() view:move(0, -1) end, "Down a line or space")

-- What modal editing works on: rows are pitches, counting upwards.
view.grid = {
  down = -1,
  get = function() return view:cursor_pitch(), view.beat end,
  set = function(row, col)
    local step
    if row then step = model.spell(util.clamp(row, 0, 127), (view.key())).step end
    view:set(step, col)
  end,
  step = function() return view:entry_length() end,
  -- Where the note or rest at a place ends: a selection takes in the one
  -- under the cursor, as Vim's takes in the character under it.
  extent = function(row, col)
    local step = model.spell(util.clamp(row, 0, 127), (view.key())).step
    local ev = view:event_at(col, step)
    if ev then return ev.start + ev.length end
  end,
  search = function(text)
    local wanted, hits = text:lower(), {}
    local layout = view:layout()
    for _, ev in ipairs(model.events(layout)) do
      for _, n in ipairs(ev.notes or {}) do
        if not n.tied and model.name(n):lower():find(wanted, 1, true) == 1 then hits[#hits + 1] = { row = n.pitch, col = math.max(0, ev.start) } end
      end
    end
    return hits
  end,
}

-- How Ex lines (`:'<,'>`, `:.`, `:%s/c4/d4/`) read this view: its beats
-- count from the start of its clip (of the score, when one is shown; see
-- `notation.staves` for its staves), and it edits that clip's notes.
paw.ex.view("notation", {
  song = function(col)
    local F = view:frame()
    return (F and F.start or 0) + col
  end,
  clips = function()
    local clip = view:clip()
    return clip and { clip.id } or nil
  end,
  track = function()
    local clip = view:clip()
    return clip and clip.track or nil
  end,
  go = function(beat)
    local clip = view:clip()
    if clip then view:set(nil, beat - clip.start) end
  end,
})

-- Where the view shows things with an address, so that diagnostics, hover
-- and fixes (`]d` `[d`, `gK`, `<leader>ca`) work on what is under its cursor.
if paw.ui.locator and paw.address then
  local A = paw.address
  paw.ui.locator("notation", {
    at = function()
      local clip = view:clip()
      if not clip then return nil end
      local note = view:note()
      if note and note.id then return A.location(A.note(clip.id, note.id)) end
      local pitch = view:cursor_pitch()
      return A.location(A.clip(clip.id), { time = { view.beat, view.beat }, pitch = { pitch, pitch } })
    end,
    position = function() return { view.beat, 127 - view:cursor_pitch() } end,
    place = function(location, anywhere)
      local p = A.parse(location.uri)
      if not p or not p.clip or (p.kind ~= "clip" and p.kind ~= "note") then return nil end
      if p.clip ~= view.clip_id then return anywhere and { 0 } or nil end
      local first
      local ids = p.kind == "note" and { p.note } or (location.selector and location.selector.notes) or {}
      for _, id in ipairs(ids) do
        local n = A.find_note(p.clip, id)
        if n and (not first or n.start < first.start or (n.start == first.start and n.pitch > first.pitch)) then first = n end
      end
      if first then return { first.start, 127 - first.pitch } end
      local t = location.selector and location.selector.time
      return { t and t[1] or 0, 0 }
    end,
    go = function(location)
      local p = A.parse(location.uri)
      if p.clip ~= view.clip_id then view:edit(paw.clip(p.clip)) end
      local at = paw.ui.locators.notation.place(location)
      if at and at[2] and at[2] > 0 then
        local pitch = 127 - at[2]
        view:set(model.spell(pitch, (view.key())).step, at[1])
      else
        view:set(nil, at and at[1] or 0)
      end
    end,
  })
  nmap("]d", function(ctx) paw.diagnostic.jump(1, ctx.count) end, "Next diagnostic here", { jump = true })
  nmap("[d", function(ctx) paw.diagnostic.jump(-1, ctx.count) end, "Previous diagnostic here", { jump = true })
  if paw.lsp then
    nmap("gK", function() paw.lsp.show_hover() end, "What the diagnostics and language servers say about the note")
    nmap("<leader>ca", function() paw.lsp.code_actions() end, "Fixes and actions for the note")
  end
end

-- The grammar for music ---------------------------------------------------------------------
--
-- Text objects over the written score (`notation.objects`), operators that
-- change what is written (`notation.operators`), motions by what is
-- written, and the entry modes. README.md, "The grammar", has them all.
do
  local O = require("notation.objects")
  local P = require("notation.operators")
  local D = require("notation.doc")
  local LETTERS = { c = 0, d = 1, e = 2, f = 3, g = 4, a = 5, b = 6 }
  --- A letter as the clip's notes have it: in a transposed part letters
  --- name notes as written (a C in a B flat part sounds B flat), and the
  --- clip's notes sound.
  local function sounding(letter)
    local F = view:frame()
    local d = F and F.dstep or 0
    if d == 0 or not LETTERS[letter:lower()] then return letter end
    local i = (LETTERS[letter:lower()] - d) % 7
    local out = ("cdefgab"):sub(i + 1, i + 1)
    return letter:lower() == letter and out or out:upper()
  end

  -- Text objects. Each also stays with a visual selection it makes, so
  -- that `viv` then `d` deletes the voice and not every voice there.
  local function sobject(lhs, find, desc)
    keymap.textobject(lhs, function(ctx)
      local sc = O.score()
      local sel = sc and find(sc, ctx.count)
      if not sel then return end
      local region = O.region(sc, sel)
      if sel.notes then
        -- A note is a block of its own pitch, as in the piano roll.
        local low, high = 127, 0
        for _, it in ipairs(O.items(sc, sel)) do
          for _, n in ipairs(it.notes) do low, high = math.min(low, D.pitch(n)), math.max(high, D.pitch(n)) end
        end
        region.kind, region.r0, region.r1 = "block", low, high
      end
      O.visual = { c0 = region.c0, c1 = region.c1, sel = sel }
      return region
    end, { view = "notation", desc = desc })
  end
  sobject("in", function(sc) return O.note(sc, false) end, "The note under the cursor")
  sobject("an", function(sc) return O.note(sc, true) end, "The note and the notes its ties join")
  sobject("ic", function(sc, n) return O.chord(sc, false, n) end, "The chord under the cursor, or N chords from it")
  sobject("ac", function(sc, n) return O.chord(sc, true, n) end, "The chord with its grace notes and ties")
  sobject("i.", function(sc, n) return O.beat_of(sc, false, n) end, "The beat under the cursor, in its voice")
  sobject("a.", function(sc, n) return O.beat_of(sc, true, n) end, "The beat in every staff and voice")
  sobject("ib", function(sc, n) return O.bar(sc, false, n) end, "What the bar holds, or N bars")
  sobject("ab", function(sc, n) return O.bar(sc, true, n) end, "The bar itself: deleting takes it out")
  sobject("ip", function(sc, n) return O.phrase(sc, false, n) end, "The phrase: the notes under the slur, or between rests")
  sobject("ap", function(sc, n) return O.phrase(sc, true, n) end, "The phrase and the rests after it")
  sobject("iv", function(sc, n) return O.voice(sc, false, n) end, "The cursor's voice in the bar, or N bars")
  sobject("av", function(sc) return O.voice(sc, true) end, "The cursor's voice through the score")
  sobject("is", function(sc, n) return O.staff(sc, false, n) end, "Every voice of the staff in the bar, or N bars")
  sobject("as", function(sc) return O.staff(sc, true) end, "The staff through the score")
  sobject("it", function(sc) return O.tuplet(sc, false) end, "The notes of the tuplet")
  sobject("at", function(sc) return O.tuplet(sc, true) end, "The tuplet, rests and all")
  sobject("il", function(sc) return O.slur(sc, false) end, "The notes under the slur")
  sobject("al", function(sc) return O.slur(sc, true) end, "The notes under the slur, and the slur")
  sobject("ie", function(sc) return O.all(sc) end, "The whole clip")
  sobject("ae", function(sc) return O.all(sc) end, "The whole clip")

  -- Operators on what is written.
  local function sop(lhs, fn, desc, opts)
    keymap.operator(lhs, function(region, ctx)
      if view:readonly() then return end
      return fn(region, ctx)
    end, util.merge({ view = "notation", desc = desc }, opts))
  end
  local own = { count = "operator" }
  sop("d", function(region, ctx) P.delete_region(region, ctx.register) end, "Delete: notes, chords, rests, bars")
  sop("y", function(region, ctx) P.yank(region, ctx.register) end, "Yank what is written")
  sop("c", function(region, ctx)
    local sel = region.score
    local voice = sel and sel.voice or view:cursor_voice()
    P.delete_region(region, ctx.register)
    if region.kind ~= "line" then view:set(nil, region.c0) end
    view.last, view.chord, view.voice = nil, nil, voice
    view.push, view.repitch, view.grace, view.pending_grace = nil, nil, nil, nil
    keymap.set_mode("i")
  end, "Change: delete and enter notes")
  local function shift(dir) return function(region, ctx)
    local by = dir * (region.visual and ctx.count or 1) * view:entry_length()
    P.on(region, function(sc, sel)
      local to = P.shift(sc, sel, D.from_beats(by))
      if not to then return false end
      if region.kind ~= "line" then view.beat = math.max(0, O.beat(sc, to)) end
    end)
  end end
  sop(">", shift(1), "Move later by the chosen value, as written")
  sop("<lt>", shift(-1), "Move earlier by the chosen value, as written")
  local function pitches(fn) return function(region, ctx)
    local fifths = view.key()
    local n = 0
    P.on(region, function(sc, sel)
      n = P.repitch(sc, sel, function(note) return fn(note, ctx.op_count or 1, fifths) end)
      return n > 0
    end)
  end end
  sop("gU", pitches(function(n, by, fifths) return P.step_note(n, by, fifths) end), "Up a step of the key (3gU: three steps)", own)
  sop("gu", pitches(function(n, by, fifths) return P.step_note(n, -by, fifths) end), "Down a step of the key (3gu: three steps)", own)
  sop("g+", pitches(function(n, by, fifths) return P.shift_note(n, by, fifths) end), "Up a semitone, spelled as the key has it (a count: semitones)", own)
  sop("g-", pitches(function(n, by, fifths) return P.shift_note(n, -by, fifths) end), "Down a semitone, spelled as the key has it (a count: semitones)", own)
  sop("g~", pitches(function(n) return P.enharmonic(n) end), "Respell: G sharp, A flat, G sharp again (g~in the note)")
  local function slur(region)
    local sc = O.score()
    if not sc then return end
    local sel = O.of_region(sc, region)
    local a, b = sel.from, sel.to
    local items = O.items(sc, sel)
    if #items > 0 then
      a, b = math.huge, -math.huge
      for _, it in ipairs(items) do a, b = math.min(a, it.s), math.max(b, it.e) end
    end
    O.reach = nil
    local staff = sel.staff and D.staff_index(sc, sel.staff) or view:cursor_staff()
    local on = marks.slur(view:clip(), O.beat(sc, a), O.beat(sc, b) - 1e-3, staff)
    paw.notify(on and "slurred: the notes played legato" or "slur taken away")
  end
  -- `s` is solo wherever there is a track; `(` and `)` go by phrase.
  sop("g(", slur, "Slur over the notes (again: taken away)")
  sop("g?", function(region, ctx)
    P.on(region, function(sc, sel)
      if ctx.op_count then return P.invert(sc, sel) > 0 end
      if sel.notes or sel.pitches then
        paw.notify("a retrograde takes whole chords: ic, i., ib, ip, iv", "warn")
        return false
      end
      return P.retrograde(sc, sel)
    end)
  end, "Retrograde: backwards; with a count, inverted about the first note", own)
  sop("gq", function(region) P.on(region, function(sc, sel) P.tidy(sc, sel) end) end,
    "Tidy: spelled in the key, beamed and written as the metre has it")
  sop("!", function(region)
    paw.ui.input({ prompt = "!", history = "notation.filter", label = "Filter",
      complete = function(text)
        local out = {}
        for name, f in pairs(P.filters) do
          if name:sub(1, #text) == text then out[#out + 1] = { text = name, desc = f.desc } end
        end
        table.sort(out, function(x, y) return x.text < y.text end)
        return out
      end,
    }, function(line)
      local why
      P.on(region, function(sc, sel)
        local ok, err = P.run_filter(sc, sel, line)
        if not ok then
          why = err
          return false
        end
      end)
      if why then paw.notify(why, "warn") end
    end)
  end, "Filter through a filter (reverse, transpose, rhythm) or a shell command: !ib tac")

  local function paste(before) return function(ctx) P.paste(keymap.getreg(ctx.register), before, ctx.count) end end
  nmap("p", paste(false), "Paste after the note")
  nmap("P", paste(true), "Paste at the cursor")

  -- Motions by what is written.
  local function near_step(ev, step)
    local best
    for _, n in ipairs(ev.notes or {}) do
      if not best or math.abs(D.diatonic(n) - step) < math.abs(best - step) then best = D.diatonic(n) end
    end
    return best
  end
  local last_find
  local function find(key, dir, till, count)
    local letter = key and LETTERS[sounding(key):lower()]
    local sc = O.score()
    if not (letter and sc) then return end
    last_find = { key = key, dir = dir, till = till }
    local it, note, list = O.find_letter(sc, letter, dir, count)
    if not it then return end
    local land = it
    if till then
      land = O.neighbour(list, it, -dir)
      if not land then return end
    end
    view:set(land == it and D.diatonic(note) or near_step(land.ev, view.step), O.beat(sc, land.s))
    -- An operator reaches over the note found (f), or up to it (t): the
    -- operator this motion is for, not one typed later.
    O.reach = dir > 0 and { at = O.beat(sc, land.s), to = O.beat(sc, till and it.s or it.e) } or nil
    paw.defer(function() O.reach = nil end, 0)
  end
  local function finder(dir, till) return function(ctx) find(ctx.char, dir, till, ctx.count) end end
  local chars = util.merge(motion, { char = true })
  nmap("f", finder(1, false), "To the next note of a letter: fe", chars)
  nmap("F", finder(-1, false), "To the previous note of a letter: Fe", chars)
  nmap("t", finder(1, true), "To the note before the next of a letter", chars)
  nmap("T", finder(-1, true), "To the note after the previous of a letter", chars)
  nmap(";", function(ctx)
    if last_find then find(last_find.key, last_find.dir, last_find.till, ctx.count) end
  end, "The last f, F, t or T again", motion)
  nmap(",", function(ctx)
    if last_find then
      local was = last_find
      find(was.key, -was.dir, was.till, ctx.count)
      last_find = was
    end
  end, "The last f, F, t or T the other way", motion)
  local function phrase(dir) return function(ctx)
    local sc = O.score()
    local it = sc and O.phrase_start(sc, dir, ctx.count)
    if it then view:set(near_step(it.ev, view.step), O.beat(sc, it.s)) end
  end end
  nmap(")", phrase(1), "The next phrase: a note after a rest", motion)
  nmap("(", phrase(-1), "The previous phrase", motion)
  local MIDDLE = { treble = 41, bass = 29, treble8 = 34 }
  --- To a staff and voice: the cursor onto its note at the cursor's beat
  --- nearest the cursor's line, else the middle of its staff.
  local function go_voice(sc, cur, to)
    view.voice = to.voice
    local it = O.item_at(sc, to.staff, to.voice, cur.t)
    local step = it and it.ev.kind == "chord" and near_step(it.ev, view.step)
    if not step and to.staff ~= cur.staff then
      local st = sc.staves[D.staff_index(sc, to.staff)]
      step = MIDDLE[st.clef] or 41
    end
    view:set(step or nil, nil)
    local si = D.staff_index(sc, to.staff)
    paw.notify("voice " .. to.voice .. (#sc.staves > 1 and (si == 1 and ", upper staff" or ", lower staff") or ""))
  end
  local function voices(dir) return function(ctx)
    local sc = O.score()
    if not sc then return end
    local list, cur = O.voices(sc), O.cursor(sc)
    local k = 1
    for i, x in ipairs(list) do
      if x.staff == cur.staff and x.voice == cur.voice then k = i end
    end
    -- On a condensed staff the voices are the two players': their clips.
    if view.staves.player(dir) then return end
    local to = list[util.clamp(k + dir * (ctx.count or 1), 1, #list)]
    if to then go_voice(sc, cur, to) end
  end end
  nmap("]v", voices(1), "The next voice (then the next staff's)", motion)
  nmap("[v", voices(-1), "The previous voice", motion)
  local function staves(dir) return function(ctx)
    local sc = O.score()
    if not sc then return end
    local cur = O.cursor(sc)
    local si = cur.staff_index + dir * (ctx.count or 1)
    -- In a score, on past the instrument's staves into the next one's.
    if (si < 1 or si > #sc.staves) and view.staves.staff(dir, ctx.count) then return end
    si = util.clamp(si, 1, #sc.staves)
    if si == cur.staff_index then return end
    go_voice(sc, cur, { staff = sc.staves[si].id, voice = 1 })
  end end
  nmap("<C-j>", staves(1), "The staff below (in a score, on into the next instrument)", linewise)
  nmap("<C-k>", staves(-1), "The staff above (in a score, on into the instrument before)", linewise)

  -- Entry modes.
  local function enter_mode(push, repitch)
    if not view:editable() then return end

    view.last, view.chord, view.voice = nil, nil, view:cursor_voice()
    view.push, view.repitch, view.grace, view.pending_grace = push, repitch, nil, nil
    keymap.set_mode("i")
  end
  nmap("I", function() enter_mode(true, nil) end, "Enter notes, pushing later music along (push-insert)")
  nmap("R", function() enter_mode(nil, true) end, "Re-pitch: letters change the notes there in turn, the rhythm stays")
  nmap("r", function(ctx)
    if ctx.char and LETTERS[ctx.char:lower()] then P.repitch_letter(sounding(ctx.char):lower(), ctx.count) end
  end, "Re-pitch the note to a letter, keeping its rhythm: rd", { char = true })
  for letter in pairs(LETTERS) do
    local name = letter:upper()
    imap(letter, function()
      local l = sounding(letter)
      if view.grace then return P.grace_enter(l) end
      if view.repitch then return P.repitch_enter(l, false) end
      view:enter(l, true)
    end, "Enter " .. name .. " and step on (a grace note after /, the note there in re-pitch mode)")
    imap(name, function()
      local l = sounding(letter)
      if view.grace then return P.grace_enter(l) end
      if view.repitch then return P.repitch_enter(l, true) end
      view:enter(l, false)
    end, "Enter " .. name .. " and stay, for a chord")
  end
  imap("<Insert>", function()
    if view.repitch then return end
    view.push = not view.push or nil
    paw.notify(view.push and "entering pushes later music along" or "entering writes over what is there")
    api.ui_redraw()
  end, "Push later music along, or write over it")
  imap("/", function()
    view.grace = ({ acciaccatura = "appoggiatura" })[view.grace or ""] or (not view.grace and "acciaccatura") or nil
    paw.notify(view.grace and ("next letter: an " .. view.grace) or "no grace note")
    api.ui_redraw()
  end, "The next letter a grace note (an acciaccatura; // an appoggiatura)")
  imap("<C-o>", function()
    keymap.set_mode("n")
    -- A popover opened now is for entering (`notation.popover`).
    view.once_normal = true
    keymap.after_next(function()
      view.once_normal = nil
      if paw.ui.focused == "notation" and keymap.mode == "n" then keymap.set_mode("i") end
    end)
  end, "One command of normal mode, then back to entering")
  map("<C-r>", guarded(function(ctx)
    local finish = P.paste(keymap.getreg(ctx.char), true, 1)
    if finish then view:set(nil, finish) end
  end), { view = "notation", mode = "i", char = true, desc = "Paste a register at the cursor and step past it: Ctrl-r a" })
  imap("<C-t>", function()
    local tp = view:entry_tuplet()
    paw.ui.input({ prompt = "tuplet (3, 5, 5:4, off): ", text = tp and (tp[1] .. ":" .. tp[2]) or "3" }, function(text)
      keymap.set_mode("i")
      local a, n = text:match("^%s*(%d+)%s*:?%s*(%d*)%s*$")
      a, n = tonumber(a), tonumber(n)
      if not a or a < 2 then
        view.tuplet, view.triplets = nil, false
        return paw.notify("entering plain values")
      end
      if not n then
        n = 1
        while n * 2 < a do n = n * 2 end
        if a == 2 then n = 3 end
      end
      view.tuplet, view.triplets = { a, n }, false
      paw.notify("entering " .. a .. " in the time of " .. n)
    end)
  end, "Enter a tuplet: 3, 5, 5:4, 2:3 (off for plain values)")

  -- Suggestions (`paw.complete`) shown as ghost notes: Tab takes them.
  local function accept(count)
    local cur = paw.complete and paw.complete.current()
    local clip = view:clip()
    if not (cur and clip and cur.clip == clip.id and cur.item) then return false end
    local onsets, finish = {}, view.beat
    for _, n in ipairs(cur.item.notes) do
      local key = string.format("%.6f", n.start)
      if not onsets[key] then
        onsets[#onsets + 1] = n.start
        onsets[key] = true
      end
    end
    local limit = count and onsets[count + 1] or math.huge
    for _, n in ipairs(cur.item.notes) do
      if n.start < limit - 1e-9 then finish = math.max(finish, n.start + n.length) end
    end
    if count then
      for _ = 1, count do
        if not paw.complete.accept(true) then break end
      end
    else
      paw.complete.accept()
    end
    view:set(nil, finish)
    return true
  end
  imap("<Tab>", function() accept() end, "Take the suggestion shown")
  nmap("<Tab>", function(ctx)
    if not accept(ctx.count) then paw.cmd("view.next") end
  end, "Take the suggestion shown (a count: so many notes or chords), else the next view")
end

if paw.ui.keybar then
  paw.ui.keybar.set("notation", "n", {
    -- `+` `-` as in every view (docs/reference/keys.md); `Ctrl-a` `Ctrl-x` are the same with a count.
    { "i", "enter" }, { "<CR>", "note" }, { "x", "delete" }, { "+", "sharp" }, { "-", "flat" },
    { "<A-l>", "longer" }, { "<A-h>", "shorter" }, { "g5", "quarter" }, { "gd", "dot" }, { "<localleader>n", "back" },
  })
  paw.ui.keybar.set("notation", "i", {
    { "c", "C..B", "a-g" }, { "C", "chord", "A-G" }, { "<A-3>", "+3rd", "Alt-2…8" }, { "5", "value", "2-7" }, { ".", "dot" },
    { "t", "triplets" }, { "~", "tie" }, { "R", "again" }, { "r", "rest" }, { "+", "sharp" }, { "-", "flat" },
    { "'", "8va" }, { ",", "8vb" }, { "<BS>", "back" },
  })
  paw.ui.keybar.set("notation", "x", {
    { "x", "delete" }, { "+", "sharp" }, { "-", "flat" }, { "}", "8va" }, { "{", "8vb" },
    { "g>", "accent" }, { "g(", "slur" }, { "<A-l>", "longer" }, { "<A-h>", "shorter" }, { "<Esc>", "done" },
  })
end

return {}
