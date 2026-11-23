-- The default commands and keys: clips. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local command = paw.command
local cursor = paw.cursor
local keymap, edit = paw.keymap, paw.edit
local roll = paw.ui.views:get("pianoroll")
local common = require("paw.defaults.common")
local need_track, need_clip, plain_folder = common.need_track, common.need_clip, common.plain_folder

command("clip.add", function(ctx)
  local track = need_track()
  if not track then return end
  if ctx.args[1] ~= nil then
    error("clip.add puts a clip at the cursor and takes length= and name=: `clip.add length=8`", 0)
  end
  local length = ctx.args.length == nil and paw.opt.clip_length or tonumber(ctx.args.length)
  if not length or not (length > 0 and length < math.huge) then
    error("a clip's length is a number of beats above 0, not " .. tostring(ctx.args.length), 0)
  end
  local clip = track:add_clip({ start = cursor.beat, length = length * (ctx.count or 1), name = ctx.args.name })
  return clip
end, { desc = "Add an empty MIDI clip at the cursor" })
command("clip.import", function(ctx)
  local track = need_track()
  if not track then return end
  local file = ctx.args[1]
  if not file then return paw.notify("usage: clip.import <file.wav>", "warn") end
  if paw.midifile.is_midi_file(file) then
    -- A MIDI file is one clip of all its notes, on this track.
    return paw.midifile.import(tostring(file), { track = track }).clips[1]
  end
  return track:add_clip({ start = cursor.beat, file = tostring(file) })
end, {
  desc = "Add an audio or MIDI file at the cursor: `clip.import take.wav`, `clip.import riff.mid`",
  complete = { "audio_files" },
})
-- Sound files this program reads.
local audio_extensions = { "wav", "wave", "aif", "aiff", "flac", "mp3", "ogg", "oga" }

--- True if a path names a sound file, from its file ending.
function paw.is_audio_file(path)
  local ext = (tostring(path):match("%.([^./]+)$") or ""):lower()
  for _, known in ipairs(audio_extensions) do
    if ext == known then return true end
  end
  return false
end

--- Bring a sound file into the project: on a new track named after the
--- file (or on `opts.track`), at the cursor (or `opts.start`). Returns the clip.
function paw.import_audio(path, opts)
  opts = opts or {}
  local name = (path:match("([^/]+)$") or path):gsub("%.[^.]+$", "")
  local made
  -- With `paw.opt.copy_imports`, the project plays a copy in its own `media` folder.
  if paw.opt.copy_imports then path = api.media_adopt(path) end
  local track = opts.track and paw.track(opts.track)
  if not track then
    track = paw.add_track({ name = name, index = cursor.index() and cursor.index() + 1 or nil })
    made = track
  end
  local ok, clip = pcall(track.add_clip, track, { start = opts.start or cursor.beat, file = path, name = name })
  if not ok then
    if made then made:remove() end
    error((tostring(clip):gsub("^[^:]*:%d+: ", ""):gsub("^runtime error: ", ""):match("^[^\n]*")), 0)
  end
  cursor.set_track(track)
  return clip
end

--- True if a path names a chain file of devices: a `devices.json`.
function paw.is_chain_file(path) return tostring(path):match("devices%.json$") ~= nil end

-- The chain file open alone, if one is: `{ path, track }` (see `open_chain`).
paw.chain_document = nil

--- Open a chain file (a `devices.json`) alone, as a new project with no
--- file: one track with its devices, and the device panel on it. `:w`
--- writes the chain back to its file. Returns the track.
function paw.open_chain(path)
  local name = (path:gsub("/devices%.json$", ""):match("([^/]+)$") or path):gsub("%.json$", "")
  api.project_new()
  api.project_set("name", name)
  local track = paw.add_track({ name = name })
  api.track_chain_file(track.id, path, false)
  api.undo_reset()
  paw.chain_document = { path = path, track = track.id, opening = true }
  cursor.set_track(track)
  pcall(paw.ui.show, "devices")
  return track
end

paw.on("project.loaded", function()
  if paw.chain_document and paw.chain_document.opening then
    paw.chain_document.opening = nil
  else
    paw.chain_document = nil
  end
end)

--- Open what a path names: a folder that is no project as a list of its
--- files, a sound file as a new track, anything else as a project, with
--- plugins offline as `opts` says (see `paw.loading.open`).
function paw.open(path, opts)
  if plain_folder(path) then return paw.files.open(path, { here = true }) end
  if paw.is_audio_file(path) then return paw.import_audio(path, { start = 0 }) end
  if paw.is_chain_file(path) then return paw.open_chain(path) end
  if paw.midifile.is_clip_file(path) then return paw.midifile.open_clip(path) end
  if paw.formats.for_path(path, "import") then
    return paw.formats.import(path, { merge = false, args = opts and opts.args or {} })
  end
  return paw.loading.open(path, opts)
end

--- What a MIDI file brought in or opened came to, said.
local function midi_said(path, done)
  local name = path:match("([^/]+)$") or path
  local text =
    string.format("%s: %d notes on %d track%s", name, done.notes, #done.tracks, #done.tracks == 1 and "" or "s")
  if done.skipped then text = text .. "; left out: " .. done.skipped end
  return text
end

-- Standard MIDI files, a format as any other (paw/formats.tl). `:import`
-- puts the file's tracks at the cursor (`tempo=yes`: its tempo map too),
-- `:open` makes a new project of it; `:export song.mid clip` or
-- `selection` writes less than the whole project.
paw.formats.register({
  name = "midi",
  desc = "Standard MIDI files",
  extensions = paw.midifile.extensions,
  import = function(path, opts)
    if not opts.merge then
      return "opened " .. midi_said(path, paw.midifile.open(path)) .. " (`:w` asks where to save it)"
    end
    local tempo = opts.args.tempo
    return "imported "
      .. midi_said(path, paw.midifile.import(path, { tempo = tempo == true or tempo == "yes" or tempo == "on" }))
  end,
  export = function(path, opts)
    local what = opts.args[2] and tostring(opts.args[2])
    local midi_opts = {}
    if what == "clip" then
      local clip = cursor.clip()
      if not clip or clip.kind ~= "midi" then error("no MIDI clip at the cursor", 0) end
      midi_opts.clips = { clip.id }
    elseif what == "selection" then
      local region = paw.keymap.selection()
      if not region then error("nothing is selected", 0) end
      midi_opts.tracks = edit.arrange.tracks(region)
    elseif what then
      error("export what: `clip`, `selection`, or nothing for the whole project", 0)
    end
    local notes = paw.midifile.export(path, midi_opts)
    local lost = paw.midifile.lost_text()
    return string.format("exported %d notes to %s%s", notes, path, lost and "; MIDI 1.0 " .. lost or "")
  end,
})

command("import", function(ctx)
  local args
  local function bring(path)
    -- A track folder (one with a track.json): a track that refers to it.
    local folder = path:gsub("/+$", ""):gsub("/track%.json$", "")
    if paw.files.is_dir(folder) and io.open(folder .. "/track.json") then
      local ok, id = pcall(api.track_import_folder, folder, cursor.index() and cursor.index() + 1 or nil)
      if not ok then
        return paw.notify("could not import " .. path .. ": " .. tostring(id):gsub("^[^:]*:%d+: ", ""), "error")
      end
      local track = paw.track(id)
      cursor.set_track(track)
      return paw.notify(
        string.format(
          "imported the track “%s” from %s; it refers to the folder until you edit it",
          track.name,
          folder
        )
      )
    end
    -- A chain file: the devices of the track at the cursor.
    if paw.is_chain_file(path) then
      local track = cursor.track_id() and paw.track(cursor.track_id())
      if not track then return paw.notify("put the cursor on a track first: the chain goes on it", "warn") end
      local ok, n = pcall(api.track_chain_file, track.id, path, true)
      if not ok then
        return paw.notify("could not import " .. path .. ": " .. tostring(n):gsub("^[^:]*:%d+: ", ""), "error")
      end
      return paw.notify(
        string.format(
          "the chain of %s (%d device%s) is on track “%s”; it refers to the file until you edit it",
          path,
          n,
          n == 1 and "" or "s",
          track.name
        )
      )
    end
    if paw.midifile.is_clip_file(path) then
      local track = cursor.track_id() and paw.track(cursor.track_id())
      if not track or track.id == 0 then
        track = paw.add_track({ name = (path:match("([^/]+)$") or path):gsub("%.[^.]+$", "") })
      end
      local ok, clip = pcall(paw.midifile.import_clip, path, track, cursor.beat)
      if not ok then
        return paw.notify("could not import " .. path .. ": " .. tostring(clip):gsub("^[^:]*:%d+: ", ""), "error")
      end
      return paw.notify(
        string.format(
          "imported %s: %d notes on track “%s”; it refers to the file until you edit it",
          path:match("([^/]+)$") or path,
          clip.note_count or #clip:notes(),
          track.name
        )
      )
    end
    -- A file of another program: its format (paw/formats.tl).
    if paw.formats.for_path(path, "import") then return paw.formats.import(path, { merge = true, args = args }) end
    local ok, clip = pcall(paw.import_audio, path, { track = ctx.args.track })
    if not ok then return paw.notify("could not import " .. path .. ": " .. tostring(clip), "error") end
    paw.notify(
      string.format(
        "imported %s: %.1f beats on track “%s”",
        path:match("([^/]+)$") or path,
        clip.length,
        clip:track().name
      )
    )
  end
  -- `tempo=yes` and other `key=value` words at the end of the line, the
  -- path being the rest.
  local path
  path, args = paw.formats.split_args(ctx.args[1])
  for k, v in pairs(ctx.args) do
    if type(k) == "string" then args[k] = v end
  end
  if path ~= "" then return bring(paw.files.path(path)) end
  local endings = {}
  for _, list in ipairs({ audio_extensions, paw.formats.extensions("import") }) do
    for _, ext in ipairs(list) do
      endings[#endings + 1] = ext
    end
  end
  paw.pick.file({ title = "Import", extensions = endings, on_choose = bring })
end, {
  desc = "Bring a file in: a sound file on a new track, a MIDI file's tracks at the cursor, a project of another program's tracks (`:help formats`): `import take.mp3`, `import song.mid`, `import song.mid tempo=yes` (its tempo map too); alone, choose it from a list",
  raw = true,
  complete = "importable",
})

command("open", function(ctx)
  local force = paw.project.discarding()
  local args = {}
  for k, v in pairs(ctx.args) do
    if type(k) == "string" then args[k] = v end
  end
  local function go(path)
    if not paw.is_audio_file(path) and not paw.project.guard("open", force) then return end
    -- A file of another program says itself what it opened (paw/formats.tl).
    if paw.formats.for_path(path, "import") then return paw.formats.import(path, { merge = false, args = args }) end
    local ok, err = pcall(paw.open, path)
    if not ok then
      return paw.notify("could not open " .. path .. ": " .. tostring(err):gsub("^[^:]*:%d+: ", ""), "error")
    end
    if paw.midifile.is_clip_file(path) then
      return paw.notify(
        "opened " .. (path:match("([^/]+)$") or path) .. " alone: `:w` writes it back, `:w song` saves a project of it"
      )
    end
    if paw.is_chain_file(path) then
      return paw.notify("opened the chain " .. path .. " alone: `:w` writes it back, `:w song` saves a project of it")
    end
    paw.notify("opened " .. path)
  end
  local path = ctx.args[1]
  -- `key=value` words at the end are for the format of the file.
  if path and path ~= "" and not plain_folder(path) and not paw.files.is_dir(path) then
    local words
    path, words = paw.formats.split_args(path)
    for k, v in pairs(words) do
      args[k] = v
    end
  end
  if plain_folder(path) then return paw.files.open(path, { here = true }) end
  if path and path ~= "" then return go(paw.files.path(path)) end
  paw.pick.file({ title = "Open", on_choose = go })
end, {
  desc = "Open a project, a MIDI file or a project of another program as a new project (`:help formats`), or a sound file on a new track: `open song`, `open song.mid`, `open take.wav`; alone, choose it from a list",
  raw = true,
  complete = "files",
})

command("export", function(ctx)
  local path = ctx.args[1] and tostring(ctx.args[1])
  if not path or not paw.formats.for_path(path, "export") then
    local ends = table.concat(paw.formats.extensions("export"), " .")
    return paw.notify("usage: export <file> (." .. ends .. "); `:render` makes sound files", "warn")
  end
  return paw.formats.export(paw.files.path(path), { args = ctx.args })
end, {
  desc = "Write the project to a file of another program, its ending choosing the format (`:help formats`): `export song.mid`, `export riff.mid clip`, `export part.mid selection` (a MIDI file of the clip at the cursor, or of the selection's tracks)",
  complete = { "exportable", function() return { "clip", "selection" } end },
})

command("set", function(ctx)
  local name, value = ctx.args[1], ctx.args[2]
  for key, v in pairs(ctx.args) do
    if type(key) == "string" then
      name, value = key, v
    end
  end
  if not name then return paw.pick("options") end
  name = tostring(name)
  -- `set plugins+=Surge` and `set plugins-=Surge` add to a list and take
  -- from it, as in Vim.
  local list_name, how, item = name:match("^([%w_]+)([%+%-])=(.*)$")
  if list_name then
    if type(paw.opt[list_name]) ~= "table" then
      return paw.notify(list_name .. " is not a list option: `set " .. list_name .. "=value`", "warn")
    end
    local out = {}
    for _, v in ipairs(paw.opt[list_name]) do
      if not (how == "-" and tostring(v) == item) then out[#out + 1] = v end
    end
    if how == "+" then out[#out + 1] = tonumber(item) or item end
    local value, err = paw.option.read(list_name, out)
    if value == nil then return paw.notify(err, "error") end
    paw.opt[list_name] = value
    return paw.notify(list_name .. " = " .. paw.option.show(paw.opt[list_name]))
  end
  -- `set follow?` shows an option; a name that is none is an error, as in Vim.
  local ask = name:match("^(.-)%?$")
  if ask then
    name, value = ask, nil
  end
  -- A short name stands for its option: `set rnu` is `set relativenumber`.
  local function known(n)
    n = paw.option.full(n)
    for _, o in ipairs(paw.option.list()) do
      if o.name == n then return true end
    end
    return false
  end
  -- The true/false forms of Vim: `set follow!` and `set invfollow` flip
  -- it, `set nofollow` sets it false, `set follow` alone sets it true.
  local flip = name:match("^(.-)!$")
  local off = not flip and not ask and not known(name) and name:match("^no(.+)$")
  local inv = not flip and not ask and not off and not known(name) and name:match("^inv(.+)$")
  local base = flip or off or inv or name
  if not known(base) then return paw.notify("E518: Unknown option: " .. (flip or name), "error") end
  base = paw.option.full(base)
  if not (flip or off or inv) then name = base end
  local boolean = type(paw.opt[base]) == "boolean"
  if flip or off or inv then
    name = base
    if not boolean then return paw.notify(name .. " is not a true/false option", "warn") end
    if value ~= nil then
      return paw.notify("E474: Invalid argument: " .. tostring(ctx.args[1]) .. " takes no value", "error")
    end
    if off then
      value = false
    else
      value = not paw.opt[name]
    end
  elseif value == nil and boolean and not ask then
    value = true
  end
  if value == nil then return paw.notify(name .. " = " .. paw.option.show(paw.opt[name])) end
  local err
  value, err = paw.option.read(name, value)
  if value == nil then return paw.notify(err, "error") end
  paw.opt[name] = value
  paw.notify(name .. " = " .. paw.option.show(paw.opt[name]))
end, {
  desc = "Show or set an option: `set zoom 4`, `set zoom=4`, `set zoom?` shows it, `set follow` and `set nofollow` turn it on and off, `set follow!` flips it, a list `set plugins=a,b`, `+=c`, `-=a`; `set` alone lists them",
  complete = { "options" },
})

command("clip.remove", function()
  local clip = need_clip()
  if clip then clip:remove() end
end, { desc = "Remove the clip under the cursor" })
command("clip.duplicate", function(ctx)
  local clip = need_clip()
  if not clip then return end
  -- A count makes that many copies, one after the other: `4&`.
  local copy = clip
  for _ = 1, math.max(1, ctx.count or 1) do
    copy = copy:duplicate()
  end
  cursor.set_beat(copy.start)
end, { desc = "Repeat the clip right after itself, as many times as the count" })
command("clip.link", function()
  local clip = need_clip()
  if not clip then return end
  local copy = paw.clip(api.clip_link(clip.id)):get()
  cursor.set_beat(copy.start)
  paw.notify(string.format("linked copy of %s: %s, %d clips", copy.name, copy.link, copy.link_count))
end, { desc = "Put a linked copy after the clip: the clips of a link share their notes" })
command("clip.unlink", function()
  local clip = need_clip()
  if not clip then return end
  local link = clip:get().link
  if not link then return paw.notify("the clip is not linked", "warn") end
  api.clip_unlink(clip.id)
  paw.notify(string.format("unlinked %s from %s", clip.name, link))
end, { desc = "Take the clip out of its link: it keeps its notes, and edits of it stay its own" })
command("clip.override", function(ctx)
  local clip = need_clip()
  if not clip then return end
  if clip.kind ~= "midi" then return paw.notify("only MIDI clips have overrides", "warn") end
  -- `clear` first, so that `clear transpose=2` keeps the transpose.
  local patch, given = {}, ctx.args[1] == "clear"
  if given then
    patch.transpose, patch.velocity = 0, 0
  end
  for key, value in pairs(ctx.args) do
    if key == 1 and given then
      -- `clear`, done.
    elseif key == "transpose" or key == "velocity" then
      patch[key], given = tonumber(value), true
      if not patch[key] then error(key .. " is a whole number, not " .. tostring(value), 0) end
    else
      error("usage: clip.override transpose=<semitones> velocity=<change>, or clip.override clear", 0)
    end
  end
  -- Both in one edit: one undo step.
  if given then api.clip_set(clip.id, patch) end
  local c = clip:get()
  paw.notify(c.name .. ": " .. (common.overrides_text(c) or "no overrides"))
end, {
  desc = "Play the clip transposed or louder without a change of its notes: `clip.override transpose=3`",
  complete = { "clear", "transpose=", "velocity=" },
})
command("clip.mute", function()
  local clip = need_clip()
  if clip then clip.muted = not clip.muted end
end, { desc = "Mute or unmute the clip" })
command("clip.move", function(ctx)
  local clip = need_clip()
  if not clip then return end
  local by = (ctx.args.by or 1) * (ctx.count or 1) * paw.opt.grid
  clip.start = math.max(0, clip.start + by)
  cursor.set_beat(math.max(0, cursor.beat + by))
end, { desc = "Move the clip by grid steps: `clip.move by=-1`" })
command("clip.resize", function(ctx)
  local clip = need_clip()
  if not clip then return end
  local length = clip.length + (ctx.args.by or 1) * (ctx.count or 1) * paw.opt.grid
  if length > 0 then clip.length = length end
end, { desc = "Lengthen or shorten the clip by grid steps: `clip.resize by=-1`" })
command("clip.split", function()
  -- Clips chosen with the pointer are split together.
  if paw.frontend.act.split_clips() then return end
  local clip = need_clip()
  if not clip then return end
  local c = clip:get()
  local at = cursor.beat - c.start
  if at <= 0 or at >= c.length then return end
  -- A linked clip leaves its link first: the cut changes its notes, and
  -- the other clips of the link keep theirs.
  if c.link then api.clip_unlink(clip.id) end
  -- A MIDI clip's right half keeps its overrides (nil for audio).
  local right = {
    start = cursor.beat,
    length = c.length - at,
    name = c.name,
    kind = c.kind,
    transpose = c.transpose,
    velocity = c.velocity,
  }
  -- The right half plays as the clip does: stretched, shifted, looped.
  local moved = paw.stretch.carry(c, right, at)
  if c.kind == "midi" and c.loop then
    -- Each half of a looped clip repeats the whole loop, from where it begins.
    right.notes = clip:notes()
    for _, note in ipairs(right.notes) do
      note.start = note.start + moved.shift
    end
    if c.control_count > 0 then
      right.controls = clip:controls()
      for _, control in ipairs(right.controls) do
        control.start = control.start + moved.shift
      end
    end
  elseif c.kind == "midi" then
    local keep, move = {}, {}
    for _, note in ipairs(clip:notes()) do
      if note.start < at then
        note.length = math.min(note.length, at - note.start)
        keep[#keep + 1] = note
      else
        note.start = note.start - at
        move[#move + 1] = note
      end
    end
    clip:set_notes(keep)
    right.notes = move
    -- Controller moves go to the half they happen in.
    if c.control_count > 0 then
      local stay, go = {}, {}
      for _, control in ipairs(clip:controls()) do
        if control.start < at then
          stay[#stay + 1] = control
        else
          control.start = control.start - at
          go[#go + 1] = control
        end
      end
      clip:set_controls(stay)
      right.controls = go
    end
  else
    right.file, right.gain = c.file, c.gain
    right.offset = moved.offset
    -- The fade out goes with the end, which the right half now has.
    right.fade_out = math.min(c.fade_out, right.length)
    clip.fade_out = 0
    clip.fade_in = math.min(c.fade_in, at)
  end
  -- Both halves keep every take, lined up.
  local takes = paw.takes.piece(c, cursor.beat, c.start + c.length, c.loop and moved.shift)
  if takes then right.meta = { takes = takes } end
  clip.length = at
  clip:track():add_clip(right)
end, { desc = "Split the clip at the cursor" })
--- The clips over a clip (a take over it), and over those, on its track.
local function clips_over(clip)
  local from, to = clip.start, clip.start + clip.length
  local found = { [clip.id] = true }
  local list = clip:track():clips()
  local grew = true
  while grew do
    grew = false
    for _, other in ipairs(list) do
      if not found[other.id] and other.start < to - 1e-9 and other.start + other.length > from + 1e-9 then
        found[other.id], grew = true, true
        from, to = math.min(from, other.start), math.max(to, other.start + other.length)
      end
    end
  end
  return found, from, to
end

command("clip.join", function()
  local clip = need_clip()
  if not clip then return end
  local track = clip:track().id
  -- Clips over each other first, as `:j` joins them; else the next one.
  local over, from, to = clips_over(clip)
  if next(over, next(over)) then
    edit.arrange.join(track, from, to, over)
    return paw.notify("joined the clips over each other")
  end
  local finish, next_clip = clip.start + clip.length, nil
  for _, other in ipairs(clip:track():clips()) do
    if other.start >= finish - 1e-9 and (not next_clip or other.start < next_clip.start) then next_clip = other end
  end
  if not next_clip then return paw.notify("no clip after this one, or over it, to join it with", "warn") end
  edit.arrange.join(track, clip.start, next_clip.start + next_clip.length)
end, { desc = "Join the clip with the clips over it (a take over it), or else with the next one on the track" })
command("clip.rename", function(ctx)
  local clip = need_clip()
  if not clip then return end
  if ctx.args[1] then
    clip.name = tostring(ctx.args[1])
  else
    paw.ui.input({ prompt = "Clip name: ", text = clip.name }, function(name)
      if name ~= "" then clip.name = name end
    end)
  end
end, { desc = "Rename the clip" })
command("clip.transpose", function(ctx)
  local clip, row = need_clip(), cursor.index()
  if not clip then return end
  edit.arrange.transpose(
    { kind = "char", r0 = row, r1 = row, c0 = clip.start, c1 = clip.start + clip.length },
    (ctx.args.by or tonumber(ctx.args[1]) or 1) * (ctx.count or 1)
  )
end, { desc = "Move the clip's notes by semitones: `clip.transpose 12`, `clip.transpose by=-1`" })
command("clip.insert", function()
  local track = need_track()
  if not track then return end
  local clip = cursor.clip()
  if clip and clip.kind ~= "midi" then return paw.notify("notes cannot be entered in an audio clip", "warn") end
  clip = clip or track:add_clip({ start = cursor.beat, length = paw.opt.clip_length })
  local at = cursor.beat - clip.start
  roll:edit(clip)
  roll:set(nil, math.floor(at / paw.opt.note_grid + 1e-9) * paw.opt.note_grid)
  keymap.set_mode("i")
end, { desc = "Enter notes at the cursor from the keyboard, in a new clip if there is none" })
command("clip.fade", function(ctx)
  local clip = need_clip()
  if not clip then return end
  if clip.kind ~= "audio" then return paw.notify("only audio clips fade", "warn") end
  local fade_in, fade_out = tonumber(ctx.args["in"]), tonumber(ctx.args.out)
  if ctx.args[1] then
    fade_in, fade_out = tonumber(ctx.args[1]), tonumber(ctx.args[2] or ctx.args[1])
    -- `:adjust` changes one end and keeps the other as the first line gave it.
    ctx.args = { ["in"] = fade_in, out = fade_out }
  end
  if not fade_in and not fade_out then
    -- Alone, it asks: one number for both ends, or two.
    return paw.ui.input({
      prompt = string.format("Fade %s in and out, in beats (now %g %g): ", clip.name, clip.fade_in, clip.fade_out),
      label = "Fade the clip",
    }, function(text)
      local a, b = text:match("^%s*([%d%.]+)%s*([%d%.]*)%s*$")
      if not a then return paw.notify("type one length for both ends, or two: `1 2`", "warn") end
      paw.commands.run("clip.fade", { tonumber(a), tonumber(b) or tonumber(a) })
    end)
  end
  if fade_in then clip.fade_in = math.min(math.max(0, fade_in), clip.length) end
  if fade_out then clip.fade_out = math.min(math.max(0, fade_out), clip.length) end
  paw.notify(string.format("%s fades in over %g beats and out over %g", clip.name, clip.fade_in, clip.fade_out))
end, {
  desc = "Fade an audio clip in and out, in beats: `clip.fade in=1 out=2`, `clip.fade 0.5`, `clip.fade 0`; alone, it asks",
  adjust = { { name = "in", min = 0, step = 0.25 }, { name = "out", min = 0, step = 0.25 } },
})
command("clip.fade.cursor", function(ctx)
  local which = tostring(ctx.args[1] or "")
  if which ~= "in" and which ~= "out" then return paw.notify("usage: clip.fade.cursor in|out", "warn") end
  local clip = need_clip()
  if not clip then return end
  if clip.kind ~= "audio" then return paw.notify("only audio clips fade", "warn") end
  -- A count is the length in beats; else the fade reaches the cursor.
  local beats = ctx.count
  if not beats then beats = which == "in" and cursor.beat - clip.start or clip.start + clip.length - cursor.beat end
  beats = math.min(math.max(0, beats), clip.length)
  if which == "in" then
    clip.fade_in = beats
  else
    clip.fade_out = beats
  end
  if beats == 0 then return paw.notify(string.format("%s has no fade-%s", clip.name, which)) end
  paw.notify(string.format("%s fades %s over %g beat%s", clip.name, which, beats, beats == 1 and "" or "s"))
end, {
  desc = "Fade the audio clip in from its start to the cursor (`in`), or out from the cursor to its end (`out`); a count gives the beats",
  label = "Fade the clip",
})
command("clip.crossfade", function(ctx)
  local clip = need_clip()
  if not clip then return end
  local finish, next_clip = clip.start + clip.length, nil
  for _, other in ipairs(clip:track():clips()) do
    if other.id ~= clip.id and other.start > clip.start and (not next_clip or other.start < next_clip.start) then
      next_clip = other
    end
  end
  if not next_clip or clip.kind ~= "audio" or next_clip.kind ~= "audio" then
    return paw.notify("a crossfade needs an audio clip here and another after it", "warn")
  end
  -- Let this clip run on under the start of the next for as long as its
  -- file has sound, and fade the two across each other there.
  local beats = tonumber(ctx.args[1]) or ctx.count or paw.opt.grid
  local overlap = math.min(beats, next_clip.length)
  local file_end = clip.start + api.clip_source_length(clip.id)
  local reach = math.min(next_clip.start + overlap, file_end)
  if reach > finish then clip.length = reach - clip.start end
  overlap = clip.start + clip.length - next_clip.start
  if overlap <= 0 then return paw.notify("the clips do not meet: move them together first", "warn") end
  clip.fade_out, next_clip.fade_in = overlap, overlap
end, { desc = "Fade this audio clip into the next one over some beats: `clip.crossfade 1`" })
-- Stretching, pitch shifting and looping: `paw.stretch`.
local function stretch_run(f, ...)
  local ok, err = pcall(f, ...)
  if not ok then paw.notify((tostring(err):gsub("^[^:]*:%d+: ", ""):gsub("^runtime error: ", "")), "warn") end
  return ok
end
command("clip.stretch", function(ctx)
  local clip = need_clip()
  if not clip then return end
  if clip.kind ~= "audio" then return paw.notify("only audio clips are stretched", "warn") end
  local word, to = ctx.args[1], tonumber(ctx.args.to)
  local ok
  if to then
    ok = stretch_run(paw.stretch.to, clip.id, to)
  elseif word == "selection" or word == "loop" then
    local from, finish = require("paw.render").ranges[word]()
    if not from then return paw.notify(finish, "warn") end
    ok = stretch_run(paw.stretch.fit, clip.id, from, finish)
  elseif word == "reset" then
    ok = stretch_run(paw.stretch.reset, clip.id)
  elseif tonumber(word) then
    ok = stretch_run(paw.stretch.set, clip.id, tonumber(word))
  else
    return paw.ui.input(
      { prompt = string.format("Stretch %s to (now ×%g): ", clip.name, clip.stretch), label = "Stretch the clip" },
      function(text) paw.commands.run("clip.stretch", { tonumber(text) or text }) end
    )
  end
  if ok then paw.notify(string.format("%s plays ×%g as long as its file", clip.name, clip.stretch)) end
end, {
  desc = "Stretch an audio clip, keeping its pitch: `clip.stretch 1.5` (times as long), `clip.stretch to=8` (beats), `clip.stretch selection`, `clip.stretch loop`, `clip.stretch reset`",
})
command("clip.pitch", function(ctx)
  local clip = need_clip()
  if not clip then return end
  if clip.kind ~= "audio" then
    return paw.notify("only audio clips are shifted: transpose a MIDI clip's notes", "warn")
  end
  local semitones = tonumber(ctx.args[1])
  if not semitones then
    return paw.ui.input(
      { prompt = string.format("Shift %s by semitones (now %+g): ", clip.name, clip.pitch), label = "Shift the pitch" },
      function(text)
        if tonumber(text) then paw.commands.run("clip.pitch", { tonumber(text) }) end
      end
    )
  end
  if stretch_run(paw.stretch.pitch, clip.id, semitones) then
    paw.notify(string.format("%s plays %+g semitones from its file", clip.name, semitones))
  end
end, {
  desc = "Shift an audio clip's pitch by semitones, keeping its length: `clip.pitch 3`, `clip.pitch -0.5`, `clip.pitch 0`",
})
command("clip.tempo", function(ctx)
  local clip = need_clip()
  if not clip then return end
  local word = ctx.args[1]
  if word == "off" then
    stretch_run(paw.stretch.follow, clip.id, false)
    return paw.notify(clip.name .. " keeps its length in seconds")
  end
  if stretch_run(paw.stretch.follow, clip.id, tonumber(word)) then
    paw.notify(string.format("%s follows the tempo; its sound is at %g BPM", clip.name, clip.source_tempo))
  end
end, {
  desc = "Make an audio clip keep its beats when the tempo changes, stretched to fit: `clip.tempo 120` (its sound's tempo), `clip.tempo` (as it plays now), `clip.tempo off`",
})
command("clip.stretch_mode", function(ctx)
  local clip = need_clip()
  if not clip then return end
  local mode = ctx.args[1]
  if mode then stretch_run(function() clip.stretch_mode = mode end) end
  paw.notify(clip.name .. " is stretched as " .. tostring(clip.stretch_mode))
end, {
  desc = "How an audio clip is stretched: `clip.stretch_mode tonal` (held notes), `percussive` (drums, speech), `auto`",
  complete = { "auto", "tonal", "percussive" },
})
command("clip.warp", function(ctx)
  local clip = need_clip()
  if not clip then return end
  if clip.kind ~= "audio" then return paw.notify("only audio clips have warp markers", "warn") end
  local word, beat = ctx.args[1] or "add", cursor.beat
  local index = tonumber(ctx.args[2])
  local function say(i)
    local m = api.clip_get(clip.id).warp[i]
    paw.notify(string.format("warp marker %d: %.3f s into the file, at %s", i, m.source, paw.time.format(m.beat)))
  end
  local i
  if word == "add" then
    if stretch_run(function() i = paw.stretch.warp_add(clip.id, index or beat) end) then say(i) end
  elseif word == "remove" or word == "move" then
    index = index or paw.stretch.warp_near(clip, beat)
    if not index then return paw.notify(clip.name .. " has no warp markers", "warn") end
    if word == "remove" then
      if stretch_run(paw.stretch.warp_remove, clip.id, index) then
        paw.notify("warp marker " .. index .. " taken off")
      end
    elseif stretch_run(function() i = paw.stretch.warp_move(clip.id, index, tonumber(ctx.args[3]) or beat) end) then
      say(i)
    end
  elseif word == "snap" then
    if stretch_run(paw.stretch.warp_snap, clip.id) then paw.notify(clip.name .. "'s warp markers are on the grid") end
  elseif word == "clear" then
    if stretch_run(function() clip.warp = {} end) then paw.notify(clip.name .. " has no warp markers now") end
  else
    paw.notify("clip.warp add, remove, move, snap or clear", "warn")
  end
end, {
  desc = "Warp markers: `clip.warp` pins the sound at the cursor; `clip.warp move` pulls the nearest marker to the cursor (`move 2`: marker 2, `move 2 8.5`: to beat 8.5); `clip.warp remove`, `snap` (all onto the grid), `clear`",
  complete = { "add", "remove", "move", "snap", "clear" },
})
command("clip.formants", function(ctx)
  local clip = need_clip()
  if not clip then return end
  if clip.kind ~= "audio" then return paw.notify("only audio clips are shifted", "warn") end
  local word = ctx.args[1]
  local on = word == "on" or (word ~= "off" and not clip.formants)
  if stretch_run(function() clip.formants = on end) then
    paw.notify(clip.name .. (on and " keeps its formants when shifted" or " shifts its formants with its pitch"))
  end
end, {
  desc = "Keep an audio clip's formants when its pitch is shifted, so that a voice keeps its size: `clip.formants on`, `off`, or turn it over",
  complete = { "on", "off" },
})
command("clip.repeat", function(ctx)
  local clip = need_clip()
  if not clip then return end
  local word = ctx.args[1]
  if word == "off" or (word == nil and clip.loop) then
    stretch_run(paw.stretch.loop, clip.id, false)
    return paw.notify(clip.name .. " no longer repeats")
  end
  if stretch_run(paw.stretch.loop, clip.id, true, tonumber(word)) then
    paw.notify(string.format("%s repeats every %g beats: drag its end out to repeat it", clip.name, clip.loop_length))
  end
end, {
  desc = "Make a clip repeat its notes or sound when you make it longer. `clip.repeat` turns it on or off, `clip.repeat 4` repeats the first 4 beats, `clip.repeat off` turns it off. It is not the playback loop (`transport.loop`)",
})
command("clip.edit", function()
  local clip = need_clip()
  if not clip then return end
  -- A subproject's clip: the window enters the subproject, as `znn` does.
  local nest = paw.scope.of_clip(clip.id)
  if nest then
    local ok, err = pcall(paw.scope.enter, nest)
    if not ok then return paw.notify(tostring(err), "warn") end
    return paw.notify(paw.scope.describe() .. " · `zw` goes back")
  end
  -- An extension with an editor of its own for this clip opens it, as it
  -- does for a double click in a graphical frontend.
  for _, opener in ipairs(paw.frontend.openers) do
    if opener(clip) then return end
  end
  paw.ui.views:get("pianoroll"):edit(clip)
end, {
  desc = "Open the clip in its editor: the piano roll, or one an extension has for it; a subproject's clip enters the subproject",
})
