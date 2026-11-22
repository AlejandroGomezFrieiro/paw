-- MusicXML files and the project: scores brought in and taken out.
--
--   :open song.musicxml            -- a new project: a track and a MIDI clip for each part
--   :import song.mxl               -- the parts on new tracks below the cursor's, at the cursor
--   :import song.mxl tempo=yes     -- and its tempo marks and time signatures from there on
--   :notation.import song.xml      -- the same as :import
--   :notation.export song.musicxml -- the clip's score (`all`: every track's), `.mxl` zipped, `.ly` LilyPond
--
-- A file opens as `paw.midifile` opens a MIDI file: a project of its own
-- with no file (saving asks for a name, never writing over the score), the
-- song's tempo map from the tempo marks (each mark's `sound tempo`), its
-- time signatures from the bars, a marker at each rehearsal mark, the
-- title and composer in the project's `meta`, and the key. A part on
-- channel 10 or in a percussion clef gets the drum kit; a part's MIDI
-- program goes in its clip as a program change. What could not be kept is
-- counted and said.
local api = paw.api
local util = paw.util
local view = require("notation")
local D = require("notation.doc")
local mx = require("notation.musicxml")

local F = {}

local EPS = 1e-6

local function stem(path) return ((path:match("([^/]+)$") or path):gsub("%.[^.]+$", "")) end

--- The tempo marks of every part (each tick once), in ticks from measure 1.
local function tempos_of(file)
  local seen, out = {}, {}
  for _, part in ipairs(file.parts) do
    for _, t in ipairs(part.tempos) do
      local key = math.floor(t.t + 0.5)
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = t
      end
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  return out
end

--- The song's tempo map from the file's, from beat `at` on; the project's
--- before it.
local function put_tempo_map(file, at)
  local sc = file.parts[1].score
  local f = D.frame(sc)
  local tempos, signatures = {}, {}
  for _, t in ipairs(tempos_of(file)) do tempos[#tempos + 1] = { beat = at + t.t / D.Q, bpm = math.max(1, math.min(960, t.bpm)) } end
  for i, m in ipairs(sc.measures) do
    if i == 1 or m.meter then
      local mt = f.meters[i]
      signatures[#signatures + 1] = { beat = at + f.starts[i] / D.Q, num = mt[1], den = mt[2] }
    end
  end
  local keep_t, keep_s = {}, {}
  for _, t in ipairs(paw.tempo.points()) do
    if t.beat < at - EPS then keep_t[#keep_t + 1] = { beat = t.beat, bpm = t.bpm, ramp = t.ramp } end
  end
  for _, s in ipairs(paw.tempo.signatures()) do
    if s.beat < at - EPS then keep_s[#keep_s + 1] = { beat = s.beat, num = s.num, den = s.den } end
  end
  if not tempos[1] or tempos[1].beat > at + EPS then table.insert(tempos, 1, { beat = at, bpm = paw.tempo.at(at) }) end
  for _, t in ipairs(tempos) do keep_t[#keep_t + 1] = t end
  for _, s in ipairs(signatures) do keep_s[#keep_s + 1] = s end
  paw.tempo.set_points(keep_t, keep_s)
end

--- A track for each part below `index` (nil: at the end), each with a
--- MIDI clip of what the part plays whose first bar starts at beat `at`,
--- with what its score says kept as notation data. The track keeps the
--- part's staves (its clef, or a grand staff). Returns the tracks and how
--- many notes they play.
local function add_parts(file, at, index, name)
  local tracks, notes = {}, 0
  for i, part in ipairs(file.parts) do
    local sc = part.score
    local f = D.frame(sc)
    local origin = D.origin(sc)
    local track = paw.add_track({ name = part.name, index = index and index + i or nil })
    if part.drums then track:add_device("drums") end
    local meta = track.meta or {}
    meta.notation = util.merge(type(meta.notation) == "table" and meta.notation or {},
      { clef = #sc.staves == 2 and "grand" or sc.staves[1].clef })
    track.meta = meta
    local controls = part.program and { { start = 0, type = "program", program = part.program, value = 0 } } or nil
    local clip = track:add_clip({ start = at - origin / D.Q, length = math.max(1, (origin + f.finish) / D.Q),
      name = #file.parts == 1 and name or part.name, controls = controls })
    view.store(clip, view.score_of(clip:get()), sc)
    notes = notes + #clip:notes()
    tracks[#tracks + 1] = track
  end
  view.cache = nil
  return tracks, notes
end

--- A marker in the song at each rehearsal mark (each place once).
local function add_markers(file, at)
  local markers, seen = require("paw.markers"), {}
  for _, part in ipairs(file.parts) do
    for _, r in ipairs(part.rehearsals) do
      local beat = at + r.t / D.Q
      local key = string.format("%.6f", beat)
      if not seen[key] then
        seen[key] = true
        markers.add(beat, r.name)
      end
    end
  end
end

local function read(path)
  local file, why = mx.read(path)
  if not file then error(why, 0) end
  return file
end

--- Open a MusicXML file as a new project with no file of its own (see
--- the top of this file). Returns { tracks, notes, skipped }; errors when
--- the file cannot be read, leaving the open project alone.
function F.open(path)
  local file = read(path)
  api.project_new()
  api.project_set("name", stem(path))
  local meta = api.project_get().meta or {}
  meta.title, meta.composer = file.title, file.composer
  api.project_set("meta", meta)
  local first = file.parts[1].score.measures[1]
  if first and first.key and first.key.name then pcall(paw.harmony.set_key, first.key.name) end
  put_tempo_map(file, 0)
  local tracks, notes = add_parts(file, 0, nil, stem(path))
  add_markers(file, 0)
  -- It opens as a project file does: nothing to undo, nothing changed yet.
  api.undo_reset()
  if tracks[1] then paw.cursor.set_track(tracks[1]) end
  return { tracks = tracks, notes = notes, skipped = mx.skipped_text(file) }
end

--- Bring a MusicXML file into the project: its parts on new tracks below
--- the cursor's, the first bar at the cursor (or `opts.start`). The tempo
--- map is left alone unless `opts.tempo`. Returns { tracks, clips, notes, skipped }.
function F.import(path, opts)
  opts = opts or {}
  local file = read(path)
  local at = opts.start or paw.cursor.beat
  if opts.tempo then put_tempo_map(file, at) end
  local tracks, notes = add_parts(file, at, paw.cursor.index(), stem(path))
  add_markers(file, at)
  local clips = {}
  for _, t in ipairs(tracks) do clips[#clips + 1] = t:clips()[1] end
  if tracks[1] then paw.cursor.set_track(tracks[1]) end
  return { tracks = tracks, clips = clips, notes = notes, skipped = mx.skipped_text(file) }
end

--- What a file brought in or opened came to, said.
function F.said(path, done)
  local name = path:match("([^/]+)$") or path
  local text = string.format("%s: %d notes on %d track%s", name, done.notes, #done.tracks, #done.tracks == 1 and "" or "s")
  if done.skipped then text = text .. "; left out: " .. done.skipped end
  return text
end

-- Taking scores out ---------------------------------------------------------------------------

--- The score of a clip: what its notes are written as.
local function score_of_clip(clip) return view.score_of(clip:get()) end

--- Whether a track plays the drum kit.
local function drums(track)
  for _, d in ipairs(track:devices()) do
    if d.kind == "drums" or d.kind == "sampler" then return true end
  end
  return false
end

--- The MIDI program a clip's controls set first, or nil.
local function program(clip)
  if (clip:get().control_count or 0) == 0 then return nil end
  for _, k in ipairs(clip:controls()) do
    if k.type == "program" then return k.program end
  end
end

--- Parts for the clips (one a track), on one timeline: a part whose first
--- bar starts later than the first part's has empty bars before it, and
--- every part as many bars as the longest. Returns the parts, and how
--- many bars could not be lined up.
function F.parts(clips)
  local fifths = view.key()
  local _, stored = view.key()
  local key_name = stored and stored.root and (stored.root .. " " .. (stored.scale or "major")) or nil
  local parts, first = {}, math.huge
  for _, clip in ipairs(clips) do
    local c = clip:get()
    local sc = D.copy(score_of_clip(clip))
    local beat = c.start + D.origin(sc) / D.Q
    parts[#parts + 1] = { name = clip:track().name, score = sc, beat = beat, fifths = fifths, key_name = key_name,
      program = program(clip), drums = drums(clip:track()) }
    first = math.min(first, beat)
  end
  local most, off = 0, 0
  for _, p in ipairs(parts) do
    local sc = p.score
    local f = D.frame(sc)
    local bar = f.lengths[1] or D.W
    local pad = math.floor((p.beat - first) * D.Q / bar + EPS)
    if math.abs((p.beat - first) * D.Q - pad * bar) > 1 then off = off + 1 end
    if pad > 0 then
      -- The empty bars take the first bar's time signature and key.
      local m1 = sc.measures[1]
      local meter = f.meters[1]
      for _ = 1, pad do table.insert(sc.measures, 1, { id = D.id(sc, "m"), voices = {}, v = D.token() }) end
      local head = sc.measures[1]
      head.meter, head.groups, head.meter_symbol, head.key = { meter[1], meter[2] }, meter.groups, m1.meter_symbol, m1.key
      m1.meter, m1.groups, m1.meter_symbol, m1.key = nil, nil, nil, nil
      sc._frame = nil
    end
    most = math.max(most, #sc.measures)
  end
  for _, p in ipairs(parts) do
    D.ensure(p.score, most)
    p.score._frame = nil
  end
  return parts, off
end

--- Write the clips as a MusicXML (or .mxl, or LilyPond) file. `opts`:
--- `title`, `composer`. Returns how many parts went in.
function F.export(path, clips, opts)
  opts = opts or {}
  local parts = F.parts(clips)
  local ext = (path:match("%.(%w+)$") or ""):lower()
  local text
  if ext == "ly" then
    text = require("notation.lilypond").write(parts, opts)
  else
    text = mx.write(parts, opts)
    if ext == "mxl" then text = mx.mxl(text, stem(path)) end
  end
  local f, err = io.open(path, "wb")
  if not f then error((tostring(err):gsub("^[^:]*: ", "")), 0) end
  f:write(text)
  f:close()
  return #parts
end

--- The clips `:notation.export … all` writes: on each track, its first
--- MIDI clip with notes.
function F.all_clips()
  local out = {}
  for _, track in ipairs(paw.tracks()) do
    for _, clip in ipairs(track:clips()) do
      local c = clip:get()
      if c.kind == "midi" and c.note_count > 0 then
        out[#out + 1] = clip
        break
      end
    end
  end
  return out
end

-- Commands ---------------------------------------------------------------------------------------

local function import_command(path, tempo)
  local ok, done = pcall(F.import, path, { tempo = tempo == true or tempo == "yes" or tempo == "on" })
  if not ok then return paw.notify("could not import " .. path .. ": " .. tostring(done):gsub("^[^:]*:%d+: ", ""), "error") end
  paw.notify("imported " .. F.said(path, done))
  return done
end

--- The path of a raw command line, and a `tempo=` at its end.
local function path_and_tempo(line)
  local path, tempo = tostring(line or ""), nil
  local rest, word = path:match("^(.-)%s+tempo=(%S+)%s*$")
  if rest then path, tempo = rest, word end
  return (path:gsub("^~", os.getenv("HOME") or "~")), tempo
end

paw.command("notation.import", function(ctx)
  local path, tempo = path_and_tempo(ctx.args[1])
  if path == "" then return paw.notify("usage: notation.import <score.musicxml|.mxl> [tempo=yes]", "warn") end
  return import_command(path, tempo or ctx.args.tempo)
end, { raw = true, desc = "Bring a MusicXML score in: a track for each part at the cursor, each a MIDI clip with its notation: `notation.import song.musicxml`, `song.mxl tempo=yes` (its tempo marks and time signatures too)", complete = "files" })

-- MusicXML is a format of `paw.formats`: `:import song.musicxml` brings
-- its parts in at the cursor (`tempo=yes`: its tempo marks too), `:open`
-- makes a new project of it, `:export song.musicxml` writes the first
-- clip of each track. LilyPond is written only.
local function heading() return require("notation.page").heading(paw.project.get().name or "score") end

paw.formats.register({
  name = "musicxml", desc = "MusicXML scores (MuseScore, Dorico, Sibelius, Finale)", extensions = mx.extensions,
  import = function(path, opts)
    local tempo = opts.args.tempo
    if opts.merge then return "imported " .. F.said(path, F.import(path, { tempo = tempo == true or tempo == "yes" or tempo == "on" })) end
    return "opened " .. F.said(path, F.open(path)) .. " (`:w` asks where to save it)"
  end,
  export = function(path)
    local title, composer = heading()
    local n = F.export(path, F.all_clips(), { title = title, composer = composer })
    return string.format("wrote %d part%s to %s", n, n == 1 and "" or "s", path)
  end,
})

paw.formats.register({
  name = "lilypond", desc = "LilyPond scores", extensions = { "ly" },
  export = function(path)
    local title, composer = heading()
    local n = F.export(path, F.all_clips(), { title = title, composer = composer })
    return string.format("wrote %d part%s to %s", n, n == 1 and "" or "s", path)
  end,
})

view.files = F
return F
