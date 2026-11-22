-- Commands and keys of the UTAU extension. Everything here uses the public
-- `paw` module, like runtime/lua/paw/defaults/ does.
local api = paw.api
local utau = require("utau")
local notes = require("utau.notes")
local lyrics = require("utau.lyrics")
local batch = require("utau.batch")
local ui = require("utau.editor")
local editor, sheet, picker = ui.editor, ui.sheet, ui.picker
local command, map = paw.command, paw.keymap.set

--- The vocal track the cursor is on, or a warning.
local function vocal_track()
  local id = paw.cursor.track_id()
  if id and utau.device_of(id) then return id end
  paw.notify("not a vocal track: `:utau.track` adds one, `:utau.voice` makes this one sing", "warn")
end

--- The clip to act on: the editor's, else the vocal clip under the cursor.
local function vocal_clip()
  local clip = sheet:clip()
  if not clip then paw.notify("no vocal clip: open one with Enter on a vocal track", "warn") end
  return clip
end

local function set_singer(track, words)
  if #words == 0 then return picker:open(track) end
  local query = table.concat(words, " ")
  local s = utau.choose_singer(track, query)
  if s then
    paw.notify("singer: " .. s.name)
  elseif #utau.singers > 0 then
    paw.notify("no singer matches `" .. query .. "`", "warn")
  end
end

-- A vocal track is a kind of track (`paw.track_kinds`): `:track.add vocal`,
-- `:track.new`, the window's menus that make a track, the header's `V`, `K`
-- and Enter on its clips all come from here.
paw.track_kinds.define("vocal", {
  title = "Vocal track",
  letter = "V",
  desc = "sung by a singer of OpenUtau's",
  -- The singing device first, then the singer: the words after the kind
  -- (`track.add vocal Katyusha`), or chosen from a list (not with `ask = false`).
  create = function(track, args)
    if not utau.device_of(track.id) then track:add_device(utau.DEVICE, nil, { index = 1 }) end
    utau.sync()
    if args.ask ~= false then set_singer(track.id, args.words or {}) end
  end,
  editor = function(clip)
    if clip:get().kind ~= "midi" then return false end
    editor:edit(clip.id)
    return true
  end,
  describe = function(id)
    local config = utau.config(id)
    local singer = config.singer and utau.find_singer(config.singer)
    local words = singer and singer.name or config.singer or "no singer yet"
    if utau.frozen(id) then words = words .. ", frozen" end
    return words
  end,
  -- Vocal tracks made before there were kinds of track have the device.
  is = function(id) return utau.device_of(id) ~= nil end,
})

command("utau.track", function(ctx)
  local args = { kind = "vocal", name = ctx.args.name or "Vocal" }
  for i, word in ipairs(ctx.args) do
    args[i] = word
  end
  paw.cmd("track.add", args)
end, { desc = "Add a vocal track, with a singer: `utau.track Katyusha` (as `track.add vocal Katyusha`)" })

command("utau.voice", function()
  local track = paw.cursor.track()
  if not track then return paw.notify("no track selected", "warn") end
  if utau.device_of(track.id) then return paw.notify("already a vocal track") end
  paw.track_kinds.set(track, "vocal", { ask = false })
end, { desc = "Make the cursor track a vocal track" })

command("utau.singer", function(ctx)
  local track = vocal_track()
  if track then set_singer(track, ctx.args) end
end, { desc = "Choose the singer of the vocal track; with no name, from a list" })

for _, field in ipairs({ "phonemizer", "renderer", "resampler" }) do
  command("utau." .. field, function(ctx)
    local track = vocal_track()
    if not track then return end
    local value = ctx.args[1]
    if not value then
      return paw.notify(string.format("%s: %s", field, utau.config(track)[field] or "(the singer's default)"))
    end
    if field == "phonemizer" then
      for _, p in ipairs(utau.phonemizers) do
        if p.id:lower():find(tostring(value):lower(), 1, true) or p.name:lower() == tostring(value):lower() then
          value = p.id
          break
        end
      end
    end
    utau.configure(track, { [field] = value == "default" and false or value })
  end, { desc = "Set the vocal track's " .. field .. " (`default` for the singer's own)" })
end

command("utau.color", function(ctx)
  local track = vocal_track()
  if track then utau.configure(track, { voice_color = ctx.args[1] or false }) end
end, { desc = "Set the vocal track's voice colour (a subbank name), or clear it" })

command("utau.edit", function()
  local clip = paw.cursor.clip()
  if not clip then return paw.notify("no clip under the cursor", "warn") end
  editor:edit(clip.id)
end, { desc = "Open the clip under the cursor in the vocal editor" })

command("utau.sheet", function() paw.ui.toggle("utau_lyrics") end, { desc = "Show or hide the lyric sheet" })

command("utau.lyric", function(ctx)
  local _, index = editor:note()
  if not index then return paw.notify("no note under the editor's cursor", "warn") end
  notes.set_lyric(editor.clip_id, index, ctx.args[1] or "")
end, { desc = "Set the lyric of the note under the editor's cursor", raw = true })

command("utau.lyrics", function(ctx)
  local clip = vocal_clip()
  if not clip then return end
  local _, index = editor:note()
  local changed, words = lyrics.apply(clip.id, ctx.args[1] or "", { first = index or 1, per_kana = sheet.per_kana })
  paw.notify(string.format("%d words, %d lyrics changed", words, changed))
end, { desc = "Give the notes from the editor's cursor on these words: `utau.lyrics la la la`", raw = true })

command("utau.lyrics_file", function(ctx)
  local clip = vocal_clip()
  local path = ctx.args[1]
  if not clip or not path then return paw.notify("usage: utau.lyrics_file <text file>", "warn") end
  local file = io.open(path, "rb")
  if not file then return paw.notify("cannot read " .. path, "error") end
  local text = file:read("*a"):gsub("^\239\187\191", "")
  file:close()
  local changed, words = lyrics.apply(clip.id, text, { per_kana = sheet.per_kana })
  paw.notify(string.format("%d words, %d lyrics changed", words, changed))
end, { desc = "Give the clip's notes the words of a text file", raw = true })

--- Notes the editor's cursor is on, for batch edits: one note, or all.
local function which(ctx)
  if ctx.args.note then
    local _, index = editor:note()
    return index and { [index] = true } or {}
  end
end

command("utau.batch", function(ctx)
  local id = ctx.args[1]
  if not id then
    local names = {}
    for _, op in ipairs(batch.OPS) do
      names[#names + 1] = op.id .. ": " .. op.name
    end
    return paw.notify(table.concat(names, "\n"))
  end
  local clip = vocal_clip()
  if not clip then return end
  local count = batch.run(id, clip.id, ctx.args, which(ctx))
  paw.notify(string.format("%s: %d notes changed", id, count))
end, {
  desc = "Run a batch edit on the vocal clip (`note=1` for the note under the cursor); no name lists them",
  complete = function()
    local out = {}
    for _, op in ipairs(batch.OPS) do
      out[#out + 1] = op.id
    end
    return out
  end,
})

command("utau.preset", function(ctx)
  local id = ctx.args[1]
  if not id then
    local names = {}
    for _, p in ipairs(batch.PRESETS) do
      names[#names + 1] = p.id .. ": " .. p.name
    end
    return paw.notify(table.concat(names, "\n"))
  end
  local clip = vocal_clip()
  if not clip then return end
  paw.notify(id .. ": " .. table.concat(batch.preset(id, clip.id, which(ctx)), ", "))
end, {
  desc = "Apply a tuning preset to the vocal clip (`note=1` for one note); no name lists them",
  complete = function()
    local out = {}
    for _, p in ipairs(batch.PRESETS) do
      out[#out + 1] = p.id
    end
    return out
  end,
})

command("utau.vibrato", function()
  local _, index = editor:note()
  if not index then return paw.notify("no note under the editor's cursor", "warn") end
  notes.change_props(editor.clip_id, function(p)
    p.vb = not p.vb and { 75, 175, 25, 10, 10, 0, 0, 0 } or nil
    return true
  end, { [index] = true })
end, { desc = "Turn vibrato on or off for the note under the editor's cursor" })

command("utau.tuning", function(ctx)
  local _, index = editor:note()
  if not index then return paw.notify("no note under the editor's cursor", "warn") end
  notes.change_props(editor.clip_id, function(p)
    local tu = math.floor((p.tu or 0) + (ctx.args.by or 0) + 0.5)
    if ctx.args[1] then tu = math.floor(tonumber(ctx.args[1]) or 0) end
    p.tu = tu ~= 0 and tu or nil
    return true
  end, { [index] = true })
end, { desc = "Tune the note under the cursor in cents: `utau.tuning 20`, `utau.tuning by=-5`" })

command(
  "utau.bend",
  function(ctx) editor:bend((tonumber(ctx.args[1]) or 10) * (ctx.count or 1)) end,
  { desc = "Bend the sung pitch at the editor's cursor by some cents: `utau.bend -20`" }
)

command(
  "utau.flatten",
  function(ctx) editor:flatten(ctx.args.clip) end,
  { desc = "Remove pitch bends under the note at the cursor (`clip=1`: the whole clip)" }
)

command("utau.render", function()
  local track = vocal_track()
  if not track then return end
  utau.engine.send(require("utau.proto").encode.invalidate(tostring(track), ""))
end, { desc = "Render the vocal track again from scratch" })

command("utau.import", function(ctx)
  local path = ctx.args[1]
  if not path then return paw.notify("usage: utau.import <file.ustx|.ust|.vsqx|.svp|.mid|.musicxml>", "warn") end
  local ok, result = pcall(require("utau.import").file, path, { at = paw.cursor.beat })
  if not ok then return paw.notify("utau.import: " .. tostring(result), "error") end
  paw.notify(string.format("imported %d vocal tracks from %s", #result, path))
end, { desc = "Import an OpenUtau, UTAU or other singing project as vocal tracks", raw = true, complete = "files" })

-- Getting the work out ----------------------------------------------------------------

local function args_tracks(ctx)
  if ctx.args.all then return nil end
  local track = vocal_track()
  return track and { track } or false
end

command("utau.export", function(ctx)
  local path = ctx.args[1]
  if not path then return paw.notify("usage: utau.export <file.ustx|.ust|.mid> [all=1] [clip=1]", "warn") end
  local opts = {}
  if ctx.args.clip then
    local clip = paw.cursor.clip()
    if not clip or not utau.device_of(api.clip_get(clip.id).track) then
      return paw.notify("no vocal clip under the cursor", "warn")
    end
    opts.clip = clip.id
  else
    opts.tracks = args_tracks(ctx)
    if opts.tracks == false then return end
  end
  local ok, files = pcall(require("utau.export").write, tostring(path), opts)
  if not ok then return paw.notify("utau.export: " .. tostring(files), "error") end
  paw.notify("exported " .. table.concat(files, ", "))
end, {
  desc = "Export the vocal track to OpenUtau (.ustx), UTAU (.ust) or MIDI with lyrics (.mid); `all=1` every vocal track, `clip=1` the clip",
})

command("utau.openutau", function()
  local ok, path, argv = pcall(require("utau.export").open)
  if not ok then return paw.notify("utau.openutau: " .. tostring(path), "error") end
  paw.notify("opening " .. path .. " in OpenUtau (" .. argv[1] .. ")")
end, { desc = "Write the vocal tracks to a .ustx beside the project and open it in OpenUtau" })

-- Freezing ---------------------------------------------------------------------------------

command("utau.freeze", function()
  local track = vocal_track()
  if not track then return end
  local ok, audio = pcall(require("utau.freeze").freeze, track)
  if not ok then return paw.notify("utau.freeze: " .. tostring(audio), "warn") end
  paw.notify(
    api.track_get(track, "name")
      .. " is frozen: it plays as audio on "
      .. audio.name
      .. "; `:utau.unfreeze` to sing it again"
  )
end, { desc = "Render the vocal track to audio on a track below it, and stop singing it" })

command("utau.unfreeze", function()
  local id = paw.cursor.track_id()
  -- On the audio track of a frozen track too.
  for _, vocal in ipairs(utau.vocal_tracks()) do
    if require("utau.freeze").audio(vocal.track) == id then id = vocal.track end
  end
  if not id or not utau.device_of(id) then return paw.notify("not a vocal track", "warn") end
  local ok, err = pcall(require("utau.freeze").unfreeze, id)
  if not ok then return paw.notify("utau.unfreeze: " .. tostring(err), "warn") end
  paw.cursor.set_track(id)
end, { desc = "Sing the frozen vocal track again, and remove its audio" })

-- Singer presets -------------------------------------------------------------------------

local presets = require("utau.singer_presets")

command("utau.singer_save", function(ctx)
  local track = vocal_track()
  if not track then return end
  local name = table.concat(ctx.args, " ")
  if name == "" then return paw.notify("usage: utau.singer_save <name>", "warn") end
  local ok, path = pcall(presets.save, track, name)
  if not ok then return paw.notify("utau.singer_save: " .. tostring(path), "error") end
  paw.notify("saved the voice as `" .. name .. "` (" .. path .. ")")
end, { desc = "Save the vocal track's voice as a singer preset: `utau.singer_save Soft Kitane`" })

local function preset_line(p)
  local options = {}
  for k, v in pairs(p.options or {}) do
    options[#options + 1] = k .. "=" .. tostring(v)
  end
  table.sort(options)
  return {
    tostring(p.name),
    "singer: " .. tostring(p.singer),
    "phonemizer: " .. (p.phonemizer ~= "" and p.phonemizer or "default"),
    "renderer: " .. (p.renderer ~= "" and p.renderer or "default"),
    "resampler: " .. (p.resampler ~= "" and p.resampler or "default"),
    "options: " .. (#options > 0 and table.concat(options, " ") or "none"),
  }
end

paw.pick.sources.utau_presets = {
  desc = "Give the vocal track a saved singer preset",
  title = "Singer presets",
  items = function() return presets.list() end,
  format = function(p) return string.format("%s  (%s)", p.name, p.singer ~= "" and p.singer or "no singer") end,
  preview = preset_line,
  empty = "no singer presets yet: `:utau.singer_save <name>` saves one",
  on_choose = function(p)
    local track = vocal_track()
    if track then
      presets.apply(track, p)
      paw.notify("voice: " .. p.name)
    end
  end,
}

command("utau.singer_preset", function(ctx)
  local track = vocal_track()
  if not track then return end
  local name = table.concat(ctx.args, " ")
  if name == "" then return paw.pick("utau_presets") end
  local ok, p = pcall(presets.apply, track, name)
  if not ok then return paw.notify("utau.singer_preset: " .. tostring(p), "warn") end
  paw.notify("voice: " .. p.name)
end, {
  desc = "Give the vocal track a singer preset; with no name, from a list",
  complete = function()
    local out = {}
    for _, p in ipairs(presets.list()) do
      out[#out + 1] = p.name
    end
    return out
  end,
})

command("utau.singer_delete", function(ctx)
  local name = table.concat(ctx.args, " ")
  if name == "" then return paw.notify("usage: utau.singer_delete <name>", "warn") end
  paw.notify(
    presets.delete(name) and ("deleted the singer preset `" .. name .. "`") or ("no singer preset `" .. name .. "`")
  )
end, { desc = "Delete a singer preset" })

-- Installing singers -----------------------------------------------------------------------

local install = require("utau.install")

command("utau.install", function(ctx)
  local path = ctx.args[1]
  if not path then
    return paw.notify("usage: utau.install <voicebank.zip|.rar|.7z|.uar|.vogeon|.oudep|folder>", "warn")
  end
  paw.notify("installing " .. tostring(path) .. " into " .. install.target() .. " ...")
  api.ui_redraw()
  local ok, installed = pcall(install.install, tostring(path))
  if not ok then return paw.notify("utau.install: " .. tostring(installed), "error") end
  local lines = {}
  for _, x in ipairs(installed) do
    lines[#lines + 1] = x.path .. " (" .. x.kind .. ")"
  end
  paw.notify("installed " .. table.concat(lines, ", "))
end, {
  desc = "Install a voicebank archive, Vogen singer, dependency package or voicebank folder for OpenUtau",
  raw = true,
})

paw.pick.sources.utau_singers = {
  desc = "The installed singers; choosing one gives it to the vocal track",
  title = "Installed singers",
  items = function()
    if #utau.singers == 0 and utau.engine.state == "off" then utau.sync() end
    return install.installed()
  end,
  format = function(s) return string.format("%s  [%s]", s.name, s.type or "?") end,
  preview = function(s)
    return { s.name, "type: " .. tostring(s.type), "author: " .. tostring(s.author or ""), tostring(s.path or "") }
  end,
  empty = "no singers installed: `:utau.install <voicebank.zip>` installs one",
  on_choose = function(s)
    local track = paw.cursor.track_id()
    if track and utau.device_of(track) and s.id then
      utau.configure(track, { singer = s.id })
      paw.notify("singer: " .. s.name)
    end
  end,
}

command(
  "utau.singers",
  function() paw.pick("utau_singers") end,
  { desc = "List the installed singers (choosing one gives it to the vocal track)" }
)

-- Harmony and doubling ---------------------------------------------------------------------

local harmony = require("utau.harmony")

command("utau.harmony", function(ctx)
  local track = vocal_track()
  if not track then return end
  local ok, made, info = pcall(harmony.create, track, {
    interval = ctx.args[1] or "3up",
    key = ctx.args.key,
    preset = ctx.args.preset,
  })
  if not ok then return paw.notify("utau.harmony: " .. tostring(made), "warn") end
  paw.cursor.set_track(made)
  paw.notify(
    string.format(
      "%s: %d notes, a %s in %s (%s)",
      made.name,
      info.notes,
      info.interval.name,
      harmony.key_name(info.key),
      info.key_source
    )
  )
end, {
  desc = "Add a harmony track under the vocal track: `utau.harmony 3up` (3up 3down 5up 4down 6down 8up 8down), `key=Dm`, `key=F#_major`, `preset=name`",
  complete = function()
    local out = {}
    for _, iv in ipairs(harmony.INTERVALS) do
      out[#out + 1] = iv.id
    end
    return out
  end,
})

command("utau.double", function(ctx)
  local track = vocal_track()
  if not track then return end
  local ok, made, info = pcall(harmony.create, track, {
    interval = "double",
    take = tonumber(ctx.args.take) or 1,
    preset = ctx.args.preset,
  })
  if not ok then return paw.notify("utau.double: " .. tostring(made), "warn") end
  paw.cursor.set_track(made)
  paw.notify(string.format("%s: %d notes with their own timing and tuning", made.name, info.notes))
end, {
  desc = "Add a double of the vocal track: the same notes, a little apart in timing and tuning (`take=2` for another)",
})

-- What depends on the renderer -------------------------------------------------------------

local renderer = require("utau.renderer")

local function on_off(value, current)
  if value == nil then return not current end
  value = tostring(value):lower()
  return value == "on" or value == "true" or value == "1"
end

command("utau.ai_pitch", function(ctx)
  local track = vocal_track()
  if not track then return end
  local on = on_off(ctx.args[1], renderer.option(track, "pitchmode") ~= "manual")
  renderer.ai_pitch(track, on)
  paw.notify(
    "AI pitch "
      .. (on and "on (the renderer's pitch model sings, drawn pitch on top)" or "off (the notes and drawn pitch alone)")
  )
end, { desc = "AI pitch on or off for the vocal track (DiffSinger and other renderers with a pitch model)" })

local function take_notes(ctx)
  if ctx.args.note then
    local _, index = editor:note()
    return index and { [index] = true } or {}
  end
end

command("utau.retake", function(ctx)
  local clip = vocal_clip()
  if not clip then return end
  local action = ctx.args[1] or "new"
  local id = renderer.retake(clip.id, action, {
    kind = ctx.args.kind or "pitch",
    notes = take_notes(ctx),
    whole = ctx.args.whole and true or nil,
    index = tonumber(ctx.args.index),
  })
  if not id then return paw.notify("the singing engine is not connected", "warn") end
end, {
  desc = "AI takes of the vocal clip: `utau.retake` a new one, `prev`, `next`, `info`; `kind=timbre` for timbre takes; `note=1` the note under the cursor",
  complete = function() return { "new", "prev", "next", "info", "select" } end,
})

command("utau.timing", function(ctx)
  local clip = vocal_clip()
  if not clip then return end
  local take = tonumber(ctx.args[1]) or 1
  local n = renderer.timing(clip.id, take, take_notes(ctx))
  paw.notify(
    take > 0 and string.format("timing take %d on %d notes", take, n) or string.format("timing reset on %d notes", n)
  )
end, { desc = "A timing take of the vocal clip: note onsets humanized, `utau.timing 2` another, `utau.timing 0` back" })

--- Show a curve under the notes of the vocal editor, by its key or a part
--- of its name. True if there is such a curve.
local function show_curve(want)
  for _, c in ipairs(editor:curves()) do
    if c.key == want or c.name:lower():find(tostring(want):lower(), 1, true) then
      editor.curve = c.key
      api.ui_redraw()
      return true
    end
  end
  return false
end

command("utau.curve", function(ctx)
  local track = vocal_track()
  if not track then return end
  local abbr = ctx.args[1]
  local list = renderer.extra_expressions(track)
  if not abbr then
    local names, drawn = {}, {}
    for _, c in ipairs(editor:curves()) do
      names[#names + 1] = c.key .. ": " .. c.name
    end
    for _, x in ipairs(utau.extra_curves(track)) do
      drawn[#drawn + 1] = x.abbr .. " on " .. x.key
    end
    for _, e in ipairs(list) do
      names[#names + 1] = string.format("%s: %s (%g to %g), the renderer's own", e.abbr, e.name, e.min, e.max)
    end
    return paw.notify(table.concat(names, "\n") .. (#drawn > 0 and ("\ndrawn: " .. table.concat(drawn, ", ")) or ""))
  end
  if ctx.args.off then
    return paw.notify(
      renderer.remove_curve(track, abbr) and (abbr .. " is no longer drawn") or ("no curve " .. abbr),
      "info"
    )
  end
  for _, e in ipairs(list) do
    if e.abbr == abbr then
      local ok, slot = pcall(renderer.add_curve, track, e)
      if not ok then return paw.notify("utau.curve: " .. tostring(slot), "warn") end
      show_curve(slot)
      return paw.notify(string.format("%s (%s) is drawn on the device's `%s` lane", e.name, abbr, slot))
    end
  end
  if show_curve(abbr) then return end
  paw.notify("no curve `" .. abbr .. "`; `:utau.curve` lists them", "warn")
end, {
  desc = "Show a curve under the notes of the vocal editor: `utau.curve dyn`. One of the renderer's own (energy, voice colour blends...) is given a lane first; `off=1` takes it away; no name lists them",
  complete = function()
    local out = {}
    for _, c in ipairs(editor:curves()) do
      out[#out + 1] = c.key
    end
    local track = paw.cursor.track()
    for _, e in ipairs(track and renderer.extra_expressions(track.id) or {}) do
      out[#out + 1] = e.abbr
    end
    return out
  end,
})

command("utau.unison", function(ctx)
  local track = vocal_track()
  if not track then return end
  local voices = tonumber(ctx.args[1]) or 1
  renderer.unison(track, voices, {
    spacing = ctx.args.spacing,
    pitch = ctx.args.pitch,
    timing = ctx.args.timing,
    level = ctx.args.level,
  })
  paw.notify(voices >= 2 and ("unison: " .. voices .. " voices") or "unison off")
end, {
  desc = "Sing the vocal track with several voices: `utau.unison 4 spacing=60 pitch=8 timing=20 level=0`, `utau.unison 1` off",
})

command(
  "utau.shift",
  function(ctx)
    local track = vocal_track()
    if not track then return end
    renderer.shift(track, tonumber(ctx.args[1]) or 0, tonumber(ctx.args.cents) or 0)
  end,
  { desc = "Sing the vocal track higher or lower without moving its notes: `utau.shift 12`, `utau.shift 0 cents=-20`" }
)

command("utau.restart", function()
  utau.engine.stop()
  utau.sync()
end, { desc = "Restart the singing engine" })

command("utau.status", function()
  local e = utau.engine
  local lines = { string.format("engine: %s%s", e.state, e.reason and (" (" .. e.reason .. ")") or "") }
  if e.info then
    lines[#lines + 1] = string.format("paw-utau-engine %s, OpenUtau %s", e.info.engine, e.info.openutau)
  end
  lines[#lines + 1] = string.format("%d singers; log: %s", #utau.singers, e.log_path())
  for _, vocal in ipairs(utau.vocal_tracks()) do
    local state, counts = utau.status(vocal.track)
    local parts = {}
    for name, n in pairs(counts) do
      parts[#parts + 1] = n .. " " .. name
    end
    lines[#lines + 1] = string.format("%s: %s %s", api.track_get(vocal.track, "name"), state, table.concat(parts, ", "))
  end
  paw.notify(table.concat(lines, "\n"))
end, { desc = "Show what the singing engine is doing" })

-- Keys ------------------------------------------------------------------------------------

-- Enter on a clip of a vocal track opens the vocal editor; elsewhere it does
-- what it always did.
map("<CR>", function()
  local clip = paw.cursor.clip()
  if clip and utau.device_of(api.clip_get(clip.id).track) and clip.kind == "midi" then return editor:edit(clip.id) end
  paw.cmd("clip.edit")
end, { view = "arrange", desc = "Edit the clip's notes" })
-- In the arrange view's insert mode, `u` inserts a vocal clip on a vocal
-- track, and Enter after it opens the vocal editor (paw.insert).
paw.insert.add("u", {
  kind = "midi",
  desc = "A vocal clip, to sing; Enter opens the vocal editor",
  order = 15,
  tracks = { "vocal" },
  name = "Vocal %d",
  open = function(_, item) editor:edit(item.id) end,
})
-- From every view, on the leader.
paw.keymap.group("<leader>u", "utau")
map("<leader>ut", "utau.track", { desc = "Add a vocal track" })
map("<leader>uv", "utau.voice", { desc = "Make the cursor track a vocal track" })
map("<leader>us", "utau.singer", { desc = "Choose the vocal track's singer" })
map("<leader>ue", "utau.edit", { desc = "Open the clip under the cursor in the vocal editor" })
map("<leader>ul", "utau.sheet", { desc = "Show or hide the lyric sheet" })
map("<leader>ur", "utau.render", { desc = "Render the vocal track again from scratch" })
map("<leader>uf", "utau.freeze", { desc = "Render the vocal track to audio, and stop singing it" })
map("<leader>uF", "utau.unfreeze", { desc = "Sing the frozen vocal track again" })
map("<leader>uo", "utau.openutau", { desc = "Open the vocal tracks in OpenUtau" })
map("<leader>ui", "utau.status", { desc = "What the singing engine is doing" })
paw.keymap.group("<localleader>V", "vocal", { view = "arrange" })
map("<localleader>Vt", "utau.track", { view = "arrange", desc = "Add a vocal track" })
map("<localleader>Vs", "utau.singer", { view = "arrange", desc = "Choose the vocal track's singer" })

-- The editor is a piano roll, and takes the same grammar: motions, the
-- operators below with any of them, text objects, visual mode, registers,
-- counts and `.`. Notes carry their lyrics and tuning wherever they go.
local keymap, edit = paw.keymap, paw.edit
local motion, linewise = { motion = true }, { motion = true, linewise = true }
local function emap(lhs, rhs, desc, opts) map(lhs, rhs, paw.util.merge({ view = "utau", desc = desc }, opts)) end
local function move(dbeat, dpitch)
  return function(ctx)
    local n = ctx.count or 1
    editor:move(dbeat * n * paw.opt.note_grid, dpitch * n)
  end
end
local function steps(dir)
  return function(ctx)
    for _ = 1, ctx.count or 1 do
      editor:step_note(dir)
    end
  end
end
emap("h", move(-1, 0), "Left one step", motion)
emap("l", move(1, 0), "Right one step", motion)
emap("j", move(0, -1), "Down a semitone", linewise)
emap("k", move(0, 1), "Up a semitone", linewise)
emap("<Left>", move(-1, 0), "Left one step", motion)
emap("<Right>", move(1, 0), "Right one step", motion)
emap("<Down>", move(0, -1), "Down a semitone", linewise)
emap("<Up>", move(0, 1), "Up a semitone", linewise)
emap("<C-d>", move(0, -12), "Down an octave", linewise)
emap("<C-u>", move(0, 12), "Up an octave", linewise)
paw.keymap.classic("J", move(0, -12), { view = "utau", desc = "Down an octave", motion = true, linewise = true })
paw.keymap.classic("K", move(0, 12), { view = "utau", desc = "Up an octave", motion = true, linewise = true })
emap("w", steps(1), "Next note", motion)
emap("b", steps(-1), "Previous note", motion)
emap("<Tab>", steps(1), "Next note", motion)
emap("<S-Tab>", steps(-1), "Previous note", motion)
emap("0", function() editor:move(-editor.beat, 0) end, "Start of the clip", motion)
emap("$", function()
  local clip = editor:clip()
  if clip then editor:move(clip.length - editor.beat, 0) end
end, "End of the clip", motion)
emap("W", function(ctx)
  local clip = editor:clip()
  if not clip then return end
  local bar = paw.time.bar()
  local to = (math.floor((clip.start + editor.beat) / bar + 1e-9) + (ctx.count or 1)) * bar - clip.start
  editor:move(to - editor.beat, 0)
end, "Next bar", motion)
emap("B", function(ctx)
  local clip = editor:clip()
  if not clip then return end
  local bar = paw.time.bar()
  local to = (math.ceil((clip.start + editor.beat) / bar - 1e-9) - (ctx.count or 1)) * bar - clip.start
  editor:move(to - editor.beat, 0)
end, "Previous bar", motion)

local function eobject(lhs, fn, desc) keymap.textobject(lhs, fn, { view = "utau", desc = desc }) end
for _, lhs in ipairs({ "in", "an" }) do
  eobject(lhs, function()
    local note = editor:note()
    if note then
      return {
        view = "utau",
        kind = "block",
        r0 = note.pitch,
        r1 = note.pitch,
        c0 = note.start,
        c1 = note.start + note.length,
      }
    end
  end, "The note under the cursor")
end
for _, lhs in ipairs({ "ib", "ab" }) do
  eobject(lhs, function(ctx)
    local clip = editor:clip()
    if not clip then return end
    local bar = paw.time.bar()
    local c0 = math.floor((clip.start + editor.beat) / bar + 1e-9) * bar - clip.start
    return {
      view = "utau",
      kind = "char",
      r0 = editor.pitch,
      r1 = editor.pitch,
      c0 = c0,
      c1 = c0 + bar * (ctx.count or 1),
    }
  end, "This bar, or N bars from it")
end
for _, lhs in ipairs({ "ic", "ac", "ie", "ae" }) do
  eobject(lhs, function()
    local clip = editor:clip()
    if clip then
      return { view = "utau", kind = "char", r0 = editor.pitch, r1 = editor.pitch, c0 = 0, c1 = clip.length }
    end
  end, "Every note of the clip")
end

local function eop(lhs, fn, desc)
  keymap.operator(lhs, function(region, ctx)
    if editor.clip_id and editor:clip() then return fn(paw.clip(editor.clip_id), region, ctx) end
  end, { view = "utau", desc = desc })
end
eop("d", function(clip, region, ctx) keymap.setreg(edit.roll.delete(clip, region), ctx.register) end, "Delete")
eop("y", function(clip, region, ctx)
  local value = edit.roll.yank(clip, region)
  keymap.setreg(value, ctx.register, true)
  paw.notify(#value.notes == 1 and "yanked 1 note" or "yanked " .. #value.notes .. " notes")
end, "Yank")
local function shift(clip, region, by)
  by = math.max(by * paw.opt.note_grid, region.kind == "line" and -math.huge or -region.c0)
  edit.roll.each(clip, region, function(n) n.start = math.max(0, n.start + by) end)
  if region.kind ~= "line" then editor:move(by, 0) end
end
eop(">", function(clip, region, ctx) shift(clip, region, region.visual and ctx.count or 1) end, "Move notes later")
eop(
  "<lt>",
  function(clip, region, ctx) shift(clip, region, -(region.visual and ctx.count or 1)) end,
  "Move notes earlier"
)
eop("gl", function(clip, region)
  local c0, c1 = region.c0, region.c1
  if region.kind == "line" then
    c0, c1 = 0, clip.length
  end
  paw.cmd("transport.loop_beats", { clip.start + c0, clip.start + c1 })
end, "Set the playback loop to this and turn looping on")
local function paste(before)
  return function(ctx)
    if not (editor.clip_id and editor:clip()) then return end
    local clip, at = paw.clip(editor.clip_id), editor.beat
    local note = not before and editor:note()
    if note then at = note.start + note.length end
    local start = at
    for _ = 1, ctx.count or 1 do
      start = at
      at = edit.roll.paste(clip, keymap.getreg(ctx.register), editor.pitch, at)
      if not at then return end
    end
    editor:move(start - editor.beat, 0)
  end
end
emap("p", paste(false), "Paste after the note")
emap("P", paste(true), "Paste at the cursor")
emap("gp", "transport.to_cursor", "Playhead to the cursor")
for lhs, fn in pairs({
  x = function(clip, region, ctx) keymap.setreg(edit.roll.delete(clip, region), ctx.register) end,
  ["<C-a>"] = function(clip, region, ctx)
    edit.roll.each(clip, region, function(n) n.pitch = math.min(127, n.pitch + (ctx.count or 1)) end)
  end,
  ["<C-x>"] = function(clip, region, ctx)
    edit.roll.each(clip, region, function(n) n.pitch = math.max(0, n.pitch - (ctx.count or 1)) end)
  end,
  ["+"] = function(clip, region, ctx)
    edit.roll.each(clip, region, function(n) n.pitch = math.min(127, n.pitch + (ctx.count or 1)) end)
  end,
  ["-"] = function(clip, region, ctx)
    edit.roll.each(clip, region, function(n) n.pitch = math.max(0, n.pitch - (ctx.count or 1)) end)
  end,
}) do
  map(lhs, nil, {
    view = "utau",
    mode = "x",
    desc = lhs == "x" and "Delete" or "Transpose",
    operator = function(region, ctx)
      if editor.clip_id and editor:clip() then fn(paw.clip(editor.clip_id), region, ctx) end
    end,
  })
end
emap("i", function() editor:toggle_note() end, "Add or remove a note")
emap("x", function()
  local selected = editor:selected()
  if #selected > 0 then
    editor:clear_selection()
    return paw.clip(editor.clip_id):edit_notes({ remove = selected })
  end
  if editor:note() then editor:toggle_note() end
end, "Remove the selected notes, or the note")
emap("c", function() editor:edit_lyric() end, "Type the note's lyric (Tab moves on to the next note)")
emap("<CR>", function()
  if editor:note() then
    editor:edit_lyric()
  else
    editor:toggle_note()
  end
end, "Type the lyric of the note, or add a note")
-- These work on the selected notes, else the note under the cursor.
-- A note's main value is its pitch, as in the piano roll; its length is
-- `Alt-h` `Alt-l`, as a clip's is in the arrange view.
local function lengthen()
  editor:change_targets(function(n) n.length = n.length + paw.opt.note_grid end)
end
local function shorten()
  editor:change_targets(function(n) n.length = math.max(paw.opt.note_grid, n.length - paw.opt.note_grid) end)
end
local function transpose(sign)
  return function(ctx)
    local by = sign * (ctx.count or 1)
    editor:change_targets(function(n) n.pitch = math.max(0, math.min(127, n.pitch + by)) end)
    editor:move(0, by)
  end
end
emap("+", transpose(1), "Up a semitone", { role = "main+" })
emap("-", transpose(-1), "Down a semitone", { role = "main-" })
emap("<C-a>", transpose(1), "Up a semitone for each of the count", { role = "main+" })
emap("<C-x>", transpose(-1), "Down a semitone for each of the count", { role = "main-" })
emap("<A-l>", lengthen, "Lengthen the notes")
emap("<A-h>", shorten, "Shorten the notes")
paw.keymap.classic("+", lengthen, { view = "utau", desc = "Lengthen the notes" })
paw.keymap.classic("-", shorten, { view = "utau", desc = "Shorten the notes" })
emap("L", function()
  editor:change_targets(function(n) n.start = n.start + paw.opt.note_grid end)
end, "Move the notes right")
emap("H", function()
  local indices, list = editor:targets()
  local step = paw.opt.note_grid
  for _, i in ipairs(indices) do
    step = math.min(step, list[i].start)
  end
  if step > 0 then editor:change_targets(function(n) n.start = n.start - step end) end
end, "Move the notes left")
-- The chosen curve (`gc`): the pitch in 10 cents, the others in steps of their own.
local function raise(dir)
  return function(ctx)
    local info = editor:curve_info()
    editor:raise_curve(dir * (info and info.step or 10) * (ctx.count or 1))
  end
end
emap("}", raise(1), "Raise the curve here (the pitch 10 cents)")
emap("{", raise(-1), "Lower the curve here (the pitch 10 cents)")
-- `=` is an operator in every view: here it puts the chosen curve back over
-- what it covers (`=in` under the note, `==` the whole clip).
eop("=", function(_, region)
  local clip, device = editor:clip(), editor:device()
  if not device then return end
  local c0, c1 = region.c0, region.c1
  if region.kind == "line" then
    c0, c1 = 0, clip.length
  end
  notes.reset(clip.track, device, editor.curve, clip.start + c0, clip.start + c1)
end, "Put the curve back")
emap("~", "utau.vibrato", "Vibrato on or off")
emap("S", "utau.singer", "Choose the singer")
emap("s", "utau.sheet", "Show or hide the lyric sheet")
emap("r", "utau.render", "Render the track again")
-- Escape cancels and stays, as in every view (docs/reference/key-rule.md): it lets go of the selection.
emap("<Esc>", function()
  if next(editor.sel) then return editor:clear_selection() end
  paw.keymap.escape_hint()
end, "Forget the selection", { repeatable = false })
paw.keymap.classic("<Esc>", function()
  if next(editor.sel) then return editor:clear_selection() end
  paw.layout.back()
end, { view = "utau", desc = "Forget the selection, else back to the window before" })

local function smap(lhs, rhs, desc, opts) map(lhs, rhs, paw.util.merge({ view = "utau_lyrics", desc = desc }, opts)) end
smap("j", function(ctx)
  sheet.line = sheet.line + (ctx.count or 1)
  api.ui_redraw()
end, "Next line", motion)
smap("k", function(ctx)
  sheet.line = math.max(1, sheet.line - (ctx.count or 1))
  api.ui_redraw()
end, "Previous line", motion)
smap("c", function() sheet:edit_line() end, "Retype the line")
smap("<CR>", function() sheet:edit_line() end, "Retype the line")
-- `~` switches a setting of the sheet, as it switches a clip's mute; `K`
-- describes, as in every view.
smap("~", function()
  sheet.per_kana = not sheet.per_kana
  api.ui_redraw()
end, "Split Japanese into one kana per note, or not")
smap("q", function() paw.ui.hide("utau_lyrics") end, "Close the lyric sheet")
paw.keymap.classic(
  "<Esc>",
  function() paw.ui.hide("utau_lyrics") end,
  { view = "utau_lyrics", desc = "Close the lyric sheet" }
)

return {}
