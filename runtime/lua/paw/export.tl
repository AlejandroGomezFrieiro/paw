-- Exports of sound: the words of `:export` turned into a plan of renders,
-- the plan float, the queue that renders the plan one file at a time, and
-- the message at the end. `paw.render` (paw/render.tl) renders each file.
--
--   paw.export.plan("stems format=flac")               -- the plan: what would be written
--   paw.export.plan("bridge.wav", paw.ex.range("17,32"))
--   paw.export.run(plan)                                -- write it, in the background
--   paw.export.last()                                   -- what the last export wrote
--
-- The grammar is `:[tracks] [time] export[!] [preset] [target] [word=value ...]`.
-- The range gives what is heard (tracks) and when (time). `each=` makes one
-- render for each group, track, region or clip. The target names the files,
-- with fields such as `{group}`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local commands = require("paw.commands")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local render = require("paw.render")
local util = require("paw.util")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type ScopeModule = require("paw.scope")
local type GroupsModule = require("paw.groups")
local type VcaModule = require("paw.vca")
local type MarkersModule = require("paw.markers")
local type FormatsModule = require("paw.formats")
local type SeatsModule = require("paw.seats")
local type UiModule = require("paw.ui")

--- `paw.files` (paw/views/files.lua): a path from the folder `:cd` set.
local record Files
  path: function(name: string): string
end
local record Paw is partial.Paw
  scope: ScopeModule
  groups: GroupsModule
  vca: VcaModule
  markers: MarkersModule
  formats: FormatsModule
  seats: SeatsModule
  ui: UiModule
end
local paw = (_G as {string: Paw}).paw

local type Range = contracts.CommandRange
local type Args = commands.Args

--- What `channels=` takes: two channels, one, or one when both sides are
--- equal (the kernel's `render::Channels`).
local type Channels = types.RenderChannels

--- What `each=` takes: one render for each of these.
local enum Each
  "group"
  "track"
  "region"
  "clip"
end

--- A preset: a name for a set of export words. `target` names the files,
--- relative to the renders folder; `words` are the other words.
local record Preset
  desc: string
  target: string
  words: {string: string}
end

--- One file of a plan, and what paw renders into it.
local record Render
  --- The file, a full path.
  file: string
  --- The tracks that it holds, or nil for the mix.
  tracks: {integer}
  --- What it holds, in words: the names of the tracks.
  holds: string
  --- Where it starts and ends, in beats of the song. No start: the start
  --- of the song. No end: the end of the last clip.
  from: number
  to: number
  --- When, in words: "song", "bars 17-32", a region's name.
  when: string
  tap: types.RenderTap
  channels: Channels
  --- The title of a lossy file of one stem: the name of the stem.
  title: string
  --- True when the file is there and is not in the renders folder.
  replaces: boolean
end

--- A plan of files to write. `paw.export.run` writes it.
local record Plan
  renders: {Render}
  --- What the plan leaves out, and why: "Gtr 2, muted".
  left_out: {string}
  --- What the user should know: "the master has a compressor: ...".
  notes: {string}
  --- The words of the file that are the same for each render (tail, bits, tags).
  options: render.Options
  --- True when the plan is to be shown before paw writes it: more than one
  --- file, or a file outside the renders folder that is there.
  confirm: boolean
  --- True with `wait=true`: render in the foreground.
  wait: boolean
end

--- A file that an export could not write, and why.
local record Failure
  file: string
  error: string
end

--- What the last export did: `paw.export.last()`.
local record Last
  plan: Plan
  --- How many files it was to write.
  total: integer
  --- What each file came to, in the order of the plan.
  results: {types.RenderResult}
  failed: {Failure}
  cancelled: boolean
  --- The message that paw gave at the end.
  message: string
end

local record M
  type Plan = Plan
  type Render = Render
  type Preset = Preset
  type Last = Last
  type Channels = Channels
  type Each = Each
  --- The presets by name: `:export stems` takes the words of `stems`.
  --- `paw.export.presets.mine = { target = "mine/{track}.flac", words = { each = "track" } }`
  --- adds one.
  presets: {string: Preset}
  --- The words that `:export` takes, for its completion: `{ key, values, what }`.
  words: {{string | {string}}}
  is_dynamics: function(device: types.Device): boolean
  preset_names: function(): {string}
  plan_args: function(args: commands.Args, range?: contracts.CommandRange): Plan
  plan: function(words?: string, range?: contracts.CommandRange): Plan
  run: function(plan: Plan)
  cancel: function(): boolean
  last: function(): Last
  running: function(): boolean
  lines: function(plan: Plan): {string}
  confirm: function(plan: Plan)
  again: function(): boolean
end

M.presets = {
  mix = {desc = "the song, through the master", target = "{project}.wav", words = {}},
  review = {
    desc = "an MP3 to listen to or send",
    target = "{project}.mp3",
    words = {quality = "high", loudness = "-14"},
  },
  stems = {
    desc = "one file for each group, for a mastering engineer",
    target = "stems/{group}.wav",
    words = {each = "group", tap = "master", channels = "auto"},
  },
  tracks = {
    desc = "one file for each track, for a mixing engineer",
    target = "tracks/{track}.wav",
    words = {each = "track", tap = "post", channels = "auto"},
  },
  regions = {desc = "one file for each region", target = "regions/{n} {region}.wav", words = {each = "region"}},
}

M.words = {
  {"each=", {"group", "track", "region", "clip", "region,group"}, "one file for each"},
  {"tap=", {"master", "groups", "post", "pre"}, "where in the sound the render listens"},
  {"channels=", {"stereo", "mono", "auto"}, "auto: mono when both sides are equal"},
  {"in=", {"loop"}, "the loop, or a region by name"},
  {"format=", {"wav", "flac", "mp3", "ogg", "opus"}, "the format, when the target has no ending"},
  {"tail=", {"0", "1", "2", "4"}, "seconds after the end"},
  {"rate=", {"44100", "48000", "96000"}, "sample rate"},
  {"bits=", {"16", "24", "32"}, "sample size; 32 is float"},
  {"dither=", {"true"}, "dither at 16 or 24 bits"},
  {"quality=", {"low", "medium", "high", "best"}, "of an MP3, Ogg or Opus file"},
  {"bitrate=", {"128", "192", "256", "320"}, "kbit/s of an MP3, Ogg or Opus file"},
  {"normalize=", {"-1", "-0.3"}, "peak level in dB"},
  {"loudness=", {"-14", "-16", "-23"}, "integrated loudness in LUFS"},
  {"level=", {"1", "2", "leaves"}, "with each=region: the regions of a level"},
  {"wait=", {"true"}, "export in the foreground"},
}

-- The kinds of the built-in devices that change their level by the level that they hear.
local DYNAMICS: {string: boolean} = {compressor = true, limiter = true, gate = true}

--- True for a device that changes its level by the level that it hears: a
--- compressor, a limiter or a gate, built in or a plugin with such a name.
--- Such a device on a group or on the master that several files of an
--- export pass makes the files differ a little from the mix. Replace it to
--- name other devices.
function M.is_dynamics(device: types.Device): boolean
  if DYNAMICS[device.kind] then
    return true
  end
  local name = ((device.plugin and device.plugin.name) or device.name or ""):lower()
  return name:find("compress", 1, true) ~= nil
    or name:find("limit", 1, true) ~= nil
    or name:find("gate", 1, true) ~= nil
    or name:find("dynamic", 1, true) ~= nil
end

-- The words ----------------------------------------------------------------------------

--- Each word that `:export` knows, by its name.
local KNOWN: {string: boolean} = {}
for _, w in ipairs(M.words) do
  KNOWN[(w[1] as string):sub(1, -2)] = true
end
for _, tag in ipairs(render.tag_names) do
  KNOWN[tag] = true
end

-- The values of `tap=`.
local TAPS: {string: boolean} = {pre = true, post = true, groups = true, master = true}

--- The formats paw writes sound in, by their endings.
local function sound_endings(): {string: boolean}
  local out: {string: boolean} = {}
  for _, f in ipairs(api.render_formats()) do
    for _, e in ipairs(f.extensions) do
      out[e] = true
    end
  end
  return out
end

--- The ending of a file name, in lower case, or nil.
local function ending(name: string): string
  local e = name:match("%.([%w]+)$")
  return e and e:lower()
end

--- True when a word is the target of another format than sound (a MIDI
--- file, a project of another program): `paw.formats` writes it.
local function other_format(word: string): boolean
  local e = ending(word)
  return e ~= nil and not sound_endings()[e] and paw.formats.for_path(word, "export") ~= nil
end

--- A word of the command line as text, or nil.
local function text_of(v: commands.Arg): string
  if v == nil then
    return nil
  end
  return tostring(v)
end

-- The tracks ---------------------------------------------------------------------------

--- The name of a track.
local function name_of(id: integer): string
  return api.track_get(id).name
end

--- True when a track or a track inside it has clips.
local function sounds(id: integer): boolean
  if #api.clip_list(id) > 0 then
    return true
  end
  for _, member in ipairs(paw.groups.members(id)) do
    if sounds(member) then
      return true
    end
  end
  return false
end

--- The names of the tracks with clips that a render of `id` holds: the
--- track, or the tracks inside the group.
local function holds_of(id: integer): {string}
  if not paw.groups.is_group(id) then
    return {name_of(id)}
  end
  local out: {string} = {}
  for _, other in ipairs(api.track_list()) do
    if other ~= id and paw.scope.contains(other, id) and #api.clip_list(other) > 0 then
      out[#out + 1] = name_of(other)
    end
  end
  return out
end

--- True when a group in `set` holds the track `id`.
local function inside(id: integer, set: {integer: boolean}): boolean
  local parent = paw.groups.of(id)
  while parent do
    if set[parent] then
      return true
    end
    parent = paw.groups.of(parent)
  end
  return false
end

--- The tracks of a range without those that a group of the range holds:
--- `t/Drums/` names the group Drums and the track Drums 2 inside it, and
--- renders the group.
local function outermost(ids: {integer}): {integer}
  local set: {integer: boolean} = {}
  for _, id in ipairs(ids) do
    set[id] = true
  end
  local out: {integer} = {}
  for _, id in ipairs(ids) do
    if not inside(id, set) then
      out[#out + 1] = id
    end
  end
  return out
end

--- A unit that a render holds: a track, or a group with its tracks.
local record Unit
  id: integer
  name: string
end

--- The units of the range or of the scope, for `each=group` or `each=track`.
--- Muted tracks and VCAs are left out, the muted ones named in `left_out`.
local function units(kind: Each, given: {integer}, left_out: {string}): {Unit}
  local ids: {integer} = {}
  if given then
    if kind == "track" then
      -- Each track that sounds, the tracks inside a group of the range too.
      for _, id in ipairs(given) do
        if paw.groups.is_group(id) then
          for _, other in ipairs(api.track_list()) do
            if paw.scope.contains(other, id) and other ~= id and not paw.groups.is_group(other) then
              ids[#ids + 1] = other
            end
          end
        else
          ids[#ids + 1] = id
        end
      end
    else
      ids = given
    end
  else
    local scope = paw.scope.group()
    for _, id in ipairs(paw.scope.tracks()) do
      local wanted: boolean
      if kind == "track" then
        wanted = not paw.groups.is_group(id) or #api.clip_list(id) > 0
      else
        -- The top of each branch: the parts of the scope's group, or of the song.
        wanted = paw.groups.of(id) == scope
      end
      if wanted then
        ids[#ids + 1] = id
      end
    end
  end
  local out: {Unit} = {}
  for _, id in ipairs(ids) do
    if paw.vca.is_vca(id) or not sounds(id) then
      -- A VCA and a track with nothing to play make no file.
    elseif api.track_get(id).mute then
      left_out[#left_out + 1] = name_of(id) .. ", muted"
    else
      out[#out + 1] = {id = id, name = name_of(id)}
    end
  end
  return out
end

-- The time -----------------------------------------------------------------------------

--- A stretch of time of a render, with its name.
local record Span
  from: number
  to: number
  when: string
  --- The fields of the name that the stretch gives: `{region}`.
  region: string
end

--- The words for a range of bars: "bars 17-32", "bar 5".
local function bars_text(r: Range): string
  local b = r.bars
  if not b then
    return "the selection"
  end
  if b[1] == b[2] then
    return "bar " .. b[1]
  end
  return string.format("bars %d-%d", b[1], b[2])
end

--- The path of a region by its node: "Chorus 2 - Verse A".
local function region_path(node: MarkersModule.Node): string
  local parts: {string} = {}
  while node do
    table.insert(parts, 1, paw.markers.label(node.region))
    node = node.parent
  end
  return table.concat(parts, " - ")
end

--- When the plan plays: the Ex range, or `in=`, or the song.
local function span_of(range: Range, word: string): Span
  local timed = range and range.from and not range.whole
  if word and timed then
    error("in= and a range of time say the same: give one", 0)
  end
  if timed then
    return {from = range.from, to = range.to, when = bars_text(range)}
  end
  if word and word ~= "song" then
    local resolve = render.ranges[word]
    if not resolve then
      error(string.format("in=%s: no loop or region of that name", word), 0)
    end
    local from, to = resolve()
    if not from then
      error(to as string, 0)
    end
    local region = paw.markers.region(word)
    return {
      from = from,
      to = to as number,
      when = word,
      region = region and paw.markers.label(region) or word,
    }
  end
  return {when = "song"}
end

--- The regions to render one by one, inside the span when it has an end.
local function region_spans(level: string, span: Span): {Span}
  local depth = level and math.tointeger(tonumber(level))
  if level and level ~= "leaves" and not (depth and depth >= 1) then
    error("level= is a level from 1, or leaves", 0)
  end
  local out: {Span} = {}
  for _, node in ipairs(paw.markers.walk()) do
    local r = node.region
    local start, finish = r.beat, r.beat + r.length
    local at_level = not level or node.depth == depth or (level == "leaves" and #node.children == 0)
    local overlaps = not span.to or (finish > (span.from or 0) and start < span.to)
    if at_level and overlaps then
      local path = region_path(node)
      out[#out + 1] = {from = start, to = finish, when = path, region = path}
    end
  end
  if #out == 0 then
    error(
      level and "there are no regions at that level" or "there are no regions to export: `:region name` makes one", 0
    )
  end
  return out
end

-- The names ----------------------------------------------------------------------------

--- The fields of a file name, and what each holds for one render.
local FIELDS: {string: boolean} = {
  project = true,
  track = true,
  group = true,
  tracks = true,
  region = true,
  n = true,
  date = true,
}

--- The fields that tell the files of one kind of `each=` apart.
local NAMED: {Each: {string}} = {
  group = {"{group}", "{track}"},
  track = {"{track}", "{group}"},
  region = {"{region}"},
  clip = {"{n}"},
}

--- True when a target names the files of one kind of `each=` apart.
local function names_kind(target: string, kind: Each): boolean
  for _, field in ipairs(NAMED[kind]) do
    if target:find(field, 1, true) then
      return true
    end
  end
  return false
end

--- The field that `each=` adds to a target that has none.
local ADDED: {Each: string} = {group = "{group}", track = "{track}", region = "{n} {region}", clip = "{track} {n}"}

--- A name that is safe in a file name: no folder separator and no control
--- character.
local function safe(text: string): string
  return (text:gsub("[/\\%c]", "_"))
end

--- The name of the project, or "render" before it has one.
local function project_name(): string
  local name = api.project_get().name
  return (name and name ~= "") and name or "render"
end

--- The target with its fields filled in.
local function fill(target: string, values: {string: string}): string
  return (
    target:gsub(
      "{(%w+)}",
      function(field: string): string
        if not FIELDS[field] then
          error(
            string.format(
              "{%s}: not a field of a name; use {project} {track} {group} {tracks} {region} {n} {date}", field
            ),
            0
          )
        end
        return safe(values[field] or "")
      end
    )
  )
end

--- True when `path` is in the renders folder, which paw owns.
local function in_renders(path: string): boolean
  local dir = render.renders_dir()
  return dir ~= nil and path:sub(1, #dir + 1) == dir .. "/"
end

--- Where a target goes: a name that the user typed without a folder, and
--- each name of a preset, go into the renders folder; a path with a folder
--- goes there.
local function place(target: string, typed: boolean): string
  if typed and (target:find("/", 1, true) or target:sub(1, 1) == "~") then
    return (paw.files as Files).path(target)
  end
  local dir = render.renders_dir()
  if not dir then
    return (paw.files as Files).path(target)
  end
  return dir .. "/" .. target
end

-- The plan -----------------------------------------------------------------------------

--- An item of `each=`: a render's tracks, or its time, and the fields of
--- its name.
local record Item
  unit: Unit
  span: Span
end

--- The items of one kind of `each=`.
local function items_of(kind: Each, given: {integer}, span: Span, level: string, left_out: {string}): {Item}
  local out: {Item} = {}
  if kind == "group" or kind == "track" then
    for _, u in ipairs(units(kind, given, left_out)) do
      out[#out + 1] = {unit = u}
    end
  elseif kind == "region" then
    for _, s in ipairs(region_spans(level, span)) do
      out[#out + 1] = {span = s}
    end
  else
    -- Each clip of the tracks, inside the span, plays alone on its track.
    local tracks = given or paw.scope.tracks()
    for _, id in ipairs(tracks) do
      for _, c in ipairs(api.clip_list(id)) do
        local inside_span = not span.to or (c.start + c.length > (span.from or 0) and c.start < span.to)
        if inside_span and not c.muted then
          out[#out + 1] = {
            unit = {id = id, name = name_of(id)},
            span = {from = c.start, to = c.start + c.length, when = c.name ~= "" and c.name or "clip " .. c.id},
          }
        end
      end
    end
  end
  return out
end

--- The words of `each=`, in order: `each=region,group`.
local function each_list(word: string): {Each}
  if not word then
    return {}
  end
  local out: {Each} = {}
  for part in word:gmatch("[^,%s]+") do
    if not ADDED[part as Each] then
      error(string.format("each=%s: use group, track, region or clip, or two joined: each=region,group", part), 0)
    end
    out[#out + 1] = part as Each
  end
  if #out > 2 then
    error("each= joins two at most: each=region,group", 0)
  end
  return out
end

--- The devices of a track that change the level by the level they hear, by name.
local function dynamics_of(id: integer): {string}
  local out: {string} = {}
  for _, d in ipairs(api.track_get(id).devices or {}) do
    local device = api.device_get(d)
    if device and not device.bypass and M.is_dynamics(device) then
      out[#out + 1] = device.name or device.kind
    end
  end
  return out
end

--- The id of the master, which `api.track_get` takes.
local MASTER = 0

--- A note for each group or master that several renders of the plan pass
--- and that has a compressor or the like on it: there, the stems differ
--- from the mix.
local function dynamics_notes(renders: {Render}): {string}
  local passes: {integer: integer} = {}
  local order: {integer} = {}
  local function pass(id: integer)
    if not passes[id] then
      order[#order + 1] = id
    end
    passes[id] = (passes[id] or 0) + 1
  end
  for _, r in ipairs(renders) do
    if r.tracks and (r.tap == "groups" or r.tap == "master") then
      local seen: {integer: boolean} = {}
      for _, id in ipairs(r.tracks) do
        local parent = paw.groups.of(id)
        while parent do
          if not seen[parent] then
            seen[parent] = true
            pass(parent)
          end
          parent = paw.groups.of(parent)
        end
      end
      if r.tap == "master" then
        pass(MASTER)
      end
    end
  end
  local notes: {string} = {}
  for _, id in ipairs(order) do
    local found = passes[id] > 1 and dynamics_of(id) or {}
    if #found > 0 then
      local where = id == MASTER and "the master" or name_of(id)
      notes[#notes + 1] = string.format(
        "%s has %s: it hears each file alone, so the files differ a little from the mix",
        where,
        table.concat(found, ", ")
      )
    end
  end
  return notes
end

--- The positional words: the preset (if the first word names one) and the
--- target.
local function preset_and_target(args: Args): Preset, string
  local first, second = text_of(args[1]), text_of(args[2])
  if args[3] ~= nil then
    error("`" .. tostring(args[3]) .. "`: one target only; words take a value: tail=2", 0)
  end
  -- `./stems` is a path, `stems` the preset.
  local preset = first and M.presets[first]
  if preset then
    return preset, second
  end
  if second then
    error(
      string.format("`%s`: no preset of that name; the presets are %s", first, table.concat(M.preset_names(), ", ")), 0
    )
  end
  return nil, first
end

--- The names of the presets, in order.
function M.preset_names(): {string}
  local out: {string} = {}
  for name in pairs(M.presets) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

--- The words of `:export`: the preset's, then the words typed, which win.
--- Gives the preset, the target that the user typed, and the words.
local function read_words(args: Args): Preset, string, {string: string}
  local preset, typed = preset_and_target(args)
  local words: {string: string} = {}
  for k, v in pairs(preset and preset.words or {}) do
    words[k] = v
  end
  for k, v in pairs(args as {string | integer: commands.Arg}) do
    if k is string then
      if not KNOWN[k] then
        error(string.format("%s=: not a word of :export; <Tab> after :export lists them", k), 0)
      end
      words[k] = v == true and "true" or tostring(v)
    end
  end
  return preset, typed, words
end

--- The tracks of the range without the muted ones, which go into
--- `left_out`; nil with no range.
local function heard(range: Range, left_out: {string}): {integer}
  if not (range and range.tracks) then
    return nil
  end
  local given: {integer} = {}
  for _, id in ipairs(outermost(range.tracks)) do
    if api.track_get(id).mute then
      left_out[#left_out + 1] = name_of(id) .. ", muted"
    else
      given[#given + 1] = id
    end
  end
  if #given == 0 then
    error(string.format("%s holds only muted tracks: nothing to export", range.text or "the range"), 0)
  end
  return given
end

--- True when `each=` makes renders of single tracks or groups.
local function per_track(kinds: {Each}): boolean
  for _, kind in ipairs(kinds) do
    if kind ~= "region" then
      return true
    end
  end
  return false
end

--- The items of the plan: one for each item of `each=`, or for each pair
--- of two joined (`each=region,group`), with the number of each in its set.
local function items_and_numbers(
  kinds: {Each}, given: {integer}, span: Span, level: string, left_out: {string}
): {Item}, {integer}
  local items: {Item} = {{}}
  local nth: {integer} = {1}
  for depth, kind in ipairs(kinds) do
    local list = items_of(kind, given, span, level, left_out)
    local joined: {Item} = {}
    local numbers: {integer} = {}
    for i, outer in ipairs(items) do
      for k, inner in ipairs(list) do
        joined[#joined + 1] = {unit = inner.unit or outer.unit, span = inner.span or outer.span}
        -- `{n}` counts the items of the first kind.
        numbers[#numbers + 1] = depth == 1 and k or nth[i]
      end
    end
    items, nth = joined, numbers
  end
  if #items == 0 then
    error(
      #left_out > 0 and ("nothing to export: " .. table.concat(left_out, "; "))
        or "nothing to export: no group or track here has clips",
      0
    )
  end
  return items, nth
end

--- The target of the files, with the fields that `each=` needs and its
--- ending: the target typed, the preset's, or the default. Gives the
--- target and its ending.
local function target_of(
  typed: string, preset: Preset, given: {integer}, words: {string: string}, kinds: {Each}
): string, string
  local target = typed or (preset and preset.target) or (given and "{tracks}.wav" or "{project}.wav")
  local format = words.format and words.format:lower()
  local endings = sound_endings()
  if format and not endings[format] then
    error("format=" .. format .. ": paw writes sound as wav, flac, mp3, ogg or opus", 0)
  end
  local folder = target:sub(-1) == "/"
  local ext = not folder and ending(target)
  if ext and typed and format and format ~= ext then
    error(string.format("%s and format=%s say two formats: give one", target, format), 0)
  end
  if ext and not endings[ext] then
    error(string.format("%s: paw writes sound as .wav, .flac, .mp3, .ogg or .opus", target), 0)
  end
  -- The ending of a preset's target gives way to format=.
  local stem = ext and target:sub(1, -#ext - 2) or target
  ext = format or ext or "wav"
  -- With each= and a target without its field, paw adds the field.
  local added: {string} = {}
  for _, kind in ipairs(kinds) do
    if not names_kind(stem, kind) then
      added[#added + 1] = ADDED[kind]
    end
  end
  if #added > 0 then
    stem = stem .. ((folder or stem == "") and "" or " ") .. table.concat(added, " - ")
  end
  -- A format that needs an encoder that paw does not have is refused
  -- before anything is rendered.
  local why = api.render_check(project_name() .. "." .. ext, options.opt.ffmpeg)
  if why then
    error(why, 0)
  end
  return stem .. "." .. ext, ext
end

--- The options of `paw.render` that the words give, the same for each file.
local function file_options(words: {string: string}): render.Options
  local tags: {string: string} = {}
  for _, key in ipairs(render.tag_names) do
    if words[key] and words[key] ~= "true" then
      tags[key] = words[key]
    end
  end
  return {
    tail = tonumber(words.tail) or 2,
    rate = tonumber(words.rate) as integer,
    bits = tonumber(words.bits) as integer,
    dither = words.dither == "true" or nil,
    quality = words.quality,
    bitrate = tonumber(words.bitrate) as integer,
    normalize = tonumber(words.normalize),
    loudness = tonumber(words.loudness),
    tags = next(tags) ~= nil and tags as types.RenderTags or nil,
  }
end

--- The names of tracks, joined with `+`.
local function joined_names(ids: {integer}): string
  local names: {string} = {}
  for _, id in ipairs(ids) do
    names[#names + 1] = name_of(id)
  end
  return table.concat(names, "+")
end

--- The plan of the words of `:export`, as `commands.parse` gives them, and
--- a range. See `M.plan`.
function M.plan_args(args: Args, range?: Range): Plan
  local preset, typed, words = read_words(args)
  local left_out: {string} = {}
  -- WHAT, WHEN, WHERE in the signal, HOW the file is, HOW MANY files.
  local given = heard(range, left_out)
  local span = span_of(range, words["in"])
  local tap = (words.tap or "master") as types.RenderTap
  if not TAPS[tap] then
    error("tap=" .. tostring(tap) .. ": use pre, post, groups or master", 0)
  end
  local kinds = each_list(words.each)
  -- The mix of a window narrowed to a group is the mix of the group.
  local scope = paw.scope.group()
  if not given and scope and not per_track(kinds) then
    given = {scope}
  end
  if (tap == "pre" or tap == "post") and not given and not per_track(kinds) then
    error("tap=" .. tap .. " is the sound of tracks: give them, as in :t2export tap=" .. tap .. ", or each=track", 0)
  end
  local channels = (words.channels or "stereo") as Channels
  if channels ~= "stereo" and channels ~= "mono" and channels ~= "auto" then
    error("channels=" .. tostring(channels) .. ": use stereo, mono or auto", 0)
  end
  local items, nth = items_and_numbers(kinds, given, span, words.level, left_out)
  local target, ext = target_of(typed, preset, given, words, kinds)

  -- One render for each item, with its file.
  local renders: {Render} = {}
  local used: {string: integer} = {}
  local date = os.date("%Y-%m-%d") as string
  local tracks_name = given and joined_names(given) or project_name()
  for i, item in ipairs(items) do
    local tracks = item.unit and {item.unit.id} or given
    local s = item.span or span
    local unit_name = item.unit and item.unit.name or tracks_name
    local fields = {
      project = project_name(),
      track = unit_name,
      group = unit_name,
      tracks = tracks_name,
      region = s.region or s.when,
      n = string.format("%02d", nth[i]),
      date = date,
    }
    local file = place(fill(target, fields), typed ~= nil)
    -- Two files of one name get a number each.
    used[file] = (used[file] or 0) + 1
    if used[file] > 1 then
      file = file:sub(1, -#ext - 2) .. " " .. used[file] .. "." .. ext
    end
    local holds: {string} = {}
    for _, id in ipairs(tracks or {}) do
      for _, n in ipairs(holds_of(id)) do
        holds[#holds + 1] = n
      end
    end
    renders[i] = {
      file = file,
      tracks = tracks,
      holds = tracks and table.concat(holds, ", ") or "the mix",
      from = s.from,
      to = s.to,
      when = s.when,
      -- The mix is always heard through the master (tap=groups leaves out its devices).
      tap = (tracks or tap == "groups") and tap or "master",
      channels = channels,
      title = item.unit and item.unit.name or nil,
      replaces = io.open(file) ~= nil and not in_renders(file),
    }
  end
  local confirm = #renders > 1
  for _, r in ipairs(renders) do
    confirm = confirm or r.replaces
  end
  return {
    renders = renders,
    left_out = left_out,
    notes = #renders > 1 and dynamics_notes(renders) or {},
    options = file_options(words),
    confirm = confirm,
    wait = words.wait == "true",
  }
end

--- The plan of an export: the words as typed after `:export`, and the
--- range of tracks and time before it (`paw.ex.range("t2,t4 17,32")`, or
--- nil for the song). Gives `{ renders, left_out, notes, options, confirm }`.
--- Each render has its `file`, `tracks` (nil for the mix), `from`, `to`,
--- `when`, `tap` and `channels`. A plan that cannot be is an error with a
--- clear message.
function M.plan(words?: string, range?: Range): Plan
  local _, args = commands.parse("export " .. (words or ""))
  return M.plan_args(args, range)
end

-- The queue ----------------------------------------------------------------------------

--- A file of the queue, with the plan that it comes from.
local record Step
  plan: Plan
  render: Render
end

--- The export that runs: its first plan, the files of the queue (an export
--- started while it runs adds its own), the one that renders now, and what
--- the renders came to so far. Nil when no export runs.
local record Job
  plan: Plan
  queue: {Step}
  index: integer
  results: {types.RenderResult}
  failed: {Failure}
  cancelled: boolean
end
local job: Job
local last: Last

--- The options of `paw.render` for one render of a plan.
local function render_options(plan: Plan, r: Render): render.Options
  local opts: render.Options = {}
  for k, v in pairs(plan.options as {string: util.Data}) do
    (opts as {string: util.Data})[k] = v
  end
  opts.start, opts["end"] = r.from, r.to
  opts.tracks, opts.tap, opts.channels = r.tracks, r.tap, r.channels
  -- A lossy file of one stem has its name as its title, unless the words say another.
  local e = ending(r.file)
  if r.title and e ~= "wav" and e ~= "flac" then
    local tags = util.merge({title = r.title} as {string: string}, (opts.tags or {}) as {string: string})
    opts.tags = tags as types.RenderTags
  end
  return opts
end

--- Render one file of a plan, in the folder that its name gives, which
--- paw makes when it is not there.
local function write(file: string, opts: render.Options): types.RenderResult
  local dir = file:match("^(.*)/[^/]+$")
  if dir then
    pcall(api.fs_mkdir, dir)
  end
  return render.render(file, opts)
end

--- "1:42": a length in minutes and seconds.
local function length(seconds: number): string
  local s = math.floor(seconds + 0.5)
  return string.format("%d:%02d", s // 60, s % 60)
end

--- A path as the user sees it: from the folder of the project.
local function shown(path: string): string
  local dir = render.renders_dir()
  local project = dir and (dir:match("^(.*)/renders$") or dir)
  if project and path:sub(1, #project + 1) == project .. "/" then
    return path:sub(#project + 2)
  end
  return path
end

--- The message at the end of an export: what it wrote, how long, how loud.
local function summary(done: Last): string, string
  local results, n = done.results, #done.results
  local peak = 0.0
  local shortest, longest = math.huge, 0.0
  for _, r in ipairs(results) do
    peak = math.max(peak, r.peak or 0)
    shortest, longest = math.min(shortest, r.seconds), math.max(longest, r.seconds)
  end
  local db = 20 * math.log10(math.max(peak, 1e-6))
  local how: string
  if n == 1 then
    local r = results[1]
    local lufs = done.plan.options.loudness and r.loudness and string.format(", %.1f LUFS", r.loudness) or ""
    how = string.format("wrote %s (%s%s, peak %+.1f dB)", shown(r.path), length(r.seconds), lufs, db)
  elseif n > 1 then
    local dir = shown(results[1].path):match("^(.*)/[^/]+$") or "."
    for _, r in ipairs(results) do
      if (shown(r.path):match("^(.*)/[^/]+$") or ".") ~= dir then
        dir = nil
        break
      end
    end
    local each = length(shortest) == length(longest) and (length(longest) .. " each")
      or (length(shortest) .. " to " .. length(longest))
    how = string.format("wrote %d files%s (%s, peak %+.1f dB)", n, dir and (" to " .. dir) or "", each, db)
  end
  local level = "info"
  if how and db > 0 then
    how, level = how .. " (clips)", "warn"
  end
  local parts: {string} = {}
  for _, f in ipairs(done.failed) do
    parts[#parts + 1] = (f.file:match("([^/]+)$") or f.file) .. ": " .. f.error
    level = "error"
  end
  if done.cancelled then
    parts[#parts + 1] = string.format("export cancelled; %d of %d files written", n, done.total)
    level = "info"
  elseif #parts > 0 then
    parts[#parts + 1] = string.format("%d file%s written", n, n == 1 and "" or "s")
  end
  -- A failure or a cancel says what happened in place of the files.
  if #parts > 0 then
    return table.concat(parts, "; "), level
  end
  return how or "nothing exported", level
end

--- End the export that runs: say what it wrote, and keep it for `M.last`.
local function finish()
  local done = job
  job, render.batch = nil, nil
  last = {
    plan = done.plan,
    total = #done.queue,
    results = done.results,
    failed = done.failed,
    cancelled = done.cancelled,
  }
  local text, level = summary(last)
  last.message = text
  paw.notify(text, level)
  api.ui_redraw()
end

--- Start the next render of the export that runs, or end it.
local function start_next()
  if not job then
    return
  end
  if job.cancelled then
    return finish()
  end
  job.index = job.index + 1
  local step = job.queue[job.index]
  if not step then
    return finish()
  end
  local r = step.render
  render.batch = {index = job.index, total = #job.queue}
  local opts = render_options(step.plan, r)
  opts.background, opts.quiet = true, true
  local ok, err = pcall(write, r.file, opts) as (boolean, string)
  if not ok then
    job.failed[#job.failed + 1] = {file = r.file, error = tostring(err)}
    return start_next()
  end
end

--- True when the render of `path` is the one of the export that runs.
local function ours(path: string): boolean
  local step = job and job.queue[job.index]
  return step ~= nil and step.render.file == path
end

events.on(
  kernel.render_done,
  function(info: types.RenderResult)
    if ours(info.path) then
      job.results[#job.results + 1] = info
      start_next()
    end
  end
)
events.on(
  kernel.render_failed,
  function(e: kernel.RenderEnd)
    if ours(e.path) then
      job.failed[#job.failed + 1] = {file = e.path, error = tostring(e.error)}
      start_next()
    end
  end
)
events.on(
  kernel.render_cancelled,
  function(e: kernel.RenderEnd)
    if ours(e.path) then
      job.cancelled = true
      finish()
    end
  end
)

--- Write the files of a plan, one render at a time, on the render thread:
--- the status line shows how far it is, and one message at the end says
--- what it wrote. A plan with `wait` renders in the foreground. When an
--- export runs, the files of this one wait after it.
function M.run(plan: Plan)
  if #plan.renders == 0 then
    error("nothing to export", 0)
  end
  local steps: {Step} = {}
  for i, r in ipairs(plan.renders) do
    steps[i] = {plan = plan, render = r}
  end
  if job then
    for _, step in ipairs(steps) do
      job.queue[#job.queue + 1] = step
    end
    if render.batch then
      render.batch.total = #job.queue
    end
    return
  end
  job = {plan = plan, queue = steps, index = 0, results = {}, failed = {}}
  if not plan.wait then
    local n = #plan.renders
    paw.notify(
      (n == 1 and ("exporting " .. shown(plan.renders[1].file)) or string.format("exporting %d files", n))
        .. " · Esc cancels"
    )
    return start_next()
  end
  for i, r in ipairs(plan.renders) do
    render.batch = {index = i, total = #plan.renders}
    local ok, info = pcall(write, r.file, render_options(plan, r)) as (boolean, types.RenderResult)
    if ok then
      job.results[#job.results + 1] = info
    else
      job.failed[#job.failed + 1] = {file = r.file, error = tostring(info)}
    end
  end
  finish()
end

--- Stop the export that runs, and the files that wait after it. Returns
--- true if an export ran.
function M.cancel(): boolean
  if not job then
    return false
  end
  job.cancelled = true
  -- The kernel says when the render stops; with none running, it ends now.
  if not render.cancel() then
    finish()
  end
  return true
end

--- What the last export did: `{ plan, results, failed, cancelled, message }`.
--- `results` holds what `paw.render` gives for each file written. Nil
--- before the first export ends.
function M.last(): Last
  return last
end

--- True while an export runs.
function M.running(): boolean
  return job ~= nil
end

-- The plan float -------------------------------------------------------------------------

local FOOTER = "y or Enter: export · n or Esc: back · j k: scroll"

--- The float that shows a plan before paw writes it.
local record Confirm is contracts.View
  scroll: integer
  lines: {string}
  plan: Plan
end
local confirm: Confirm = {modal = true, focusable = true, window = false, scroll = 0, lines = {}}
paw.seats.fields(
  "export.plan",
  confirm as {string: util.Data},
  {"scroll", "lines", "plan"},
  {scroll = 0, lines = {}} as {string: util.Data}
)

function confirm:render(canvas: contracts.Buf, _: contracts.RenderContext)
  local h = canvas.height - 1
  self.scroll = math.tointeger(util.clamp(self.scroll, 0, math.max(0, #self.lines - h)))
  for row = 0, h - 1 do
    local at = row + 1 + self.scroll
    local line = self.lines[at]
    if line then
      -- The heads of the columns, the files, then what is left out and the notes.
      local style = at == 1 and "Dim" or (line:match("^left out") or line:match("^note")) and "Warn" or "Normal"
      canvas:text(1, row, util.fit(line, canvas.width - 2), style)
    end
  end
  canvas:fill(0, canvas.height - 1, canvas.width, 1, " ", "FloatFooter")
  canvas:text(1, canvas.height - 1, FOOTER, "FloatFooter")
end

function confirm:on_key(key: string): boolean
  if key == "y" or key == "<CR>" then
    local plan = self.plan
    self.plan, self.lines = nil, {}
    paw.ui.close()
    if plan then
      M.run(plan)
    end
  elseif key == "n" or key == "q" or key == "<Esc>" or key == "<C-c>" then
    self.plan, self.lines = nil, {}
    paw.ui.close()
  elseif key == "j" or key == "<Down>" then
    self.scroll = self.scroll + 1
  elseif key == "k" or key == "<Up>" then
    self.scroll = self.scroll - 1
  end
  api.ui_redraw()
end

paw.ui.view("export.plan", confirm)

--- The lines of a plan, as the float shows them: one for each file, with
--- what it holds, when, where it listens and its channels; then what it
--- leaves out, and the notes.
function M.lines(plan: Plan): {string}
  local rows: {{string}} = {{"file", "holds", "when", "tap", "channels"}}
  for _, r in ipairs(plan.renders) do
    rows[#rows + 1] = {
      shown(r.file) .. (r.replaces and " (replaces it)" or ""),
      r.holds,
      r.when,
      r.tap,
      r.channels,
    }
  end
  -- Each column as wide as its widest text; the last one as it is.
  local widths: {integer} = {}
  for _, row in ipairs(rows) do
    for c = 1, #row - 1 do
      widths[c] = math.max(widths[c] or 0, api.str_width(row[c]))
    end
  end
  local out: {string} = {}
  for _, row in ipairs(rows) do
    local parts: {string} = {}
    for c, text in ipairs(row) do
      parts[c] = c < #row and (text .. string.rep(" ", widths[c] - api.str_width(text))) or text
    end
    out[#out + 1] = table.concat(parts, "  ")
  end
  if #plan.left_out > 0 then
    out[#out + 1] = "left out: " .. table.concat(plan.left_out, "; ")
  end
  for _, note in ipairs(plan.notes) do
    out[#out + 1] = "note: " .. note
  end
  return out
end

--- Show a plan in a float; `y` writes it.
function M.confirm(plan: Plan)
  local lines = M.lines(plan)
  local w = api.str_width(FOOTER) + 4
  for _, line in ipairs(lines) do
    w = math.max(w, api.str_width(line) + 4)
  end
  confirm.plan, confirm.lines, confirm.scroll = plan, lines, 0
  local n = #plan.renders
  paw.ui.open(
    "export.plan",
    {
      title = n == 1 and ("Export " .. shown(plan.renders[1].file)) or string.format("Export %d files", n),
      width = math.min(w, 120),
      height = math.min(#lines + 3, 30),
    }
  )
end

-- The command ----------------------------------------------------------------------------

--- The words of a command as text again: `stems format=flac`.
local function unparse(args: Args): string
  local out: {string} = {}
  for _, v in ipairs(args) do
    out[#out + 1] = tostring(v)
  end
  local keys: {string} = {}
  for k in pairs(args as {string | integer: commands.Arg}) do
    if k is string then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = tostring(args[k])
    out[#out + 1] = k .. "=" .. (v:find("%s") and ('"' .. v .. '"') or v)
  end
  return table.concat(out, " ")
end

--- The last `:export` line, which `<leader>ee` runs again.
local last_line: string

--- Run `:export` again as it was last typed. Returns false when there was none.
function M.again(): boolean
  if not last_line then
    return false
  end
  commands.exec(last_line)
  return true
end

local function export(ctx: commands.Context, bang: boolean): commands.Result
  local args = ctx.args
  local range = ctx.range
  -- A file of another program (a MIDI file, a project): its format writes it.
  local target = M.presets[text_of(args[1]) or ""] and text_of(args[2]) or text_of(args[1])
  if target and other_format(target) then
    -- `:` in visual mode types `'<,'>`: the word `selection` says what to write.
    if range and not range.selection then
      error(
        target .. ": a range is for sound files; `:export " .. target .. " selection` writes the selected tracks", 0
      )
    end
    return paw.formats.export((paw.files as Files).path(target), {args = args as {string | integer: commands.Arg}})
      as commands.Result
  end
  last_line = (range and range.text or "") .. "export" .. (bang and "! " or " ") .. unparse(args)
  local plan = M.plan_args(args, range)
  if plan.confirm and not bang then
    return M.confirm(plan)
  end
  M.run(plan)
end

--- Complete the words of `:export`: the presets, the files of other
--- programs, `clip` and `selection` after a MIDI file, then the words and
--- their values.
local function complete(rest: string): {string}
  local before, word = rest:match("^(.-)(%S*)$")
  local out: {string} = {}
  local key = word:match("^(%w+)=")
  if before == "" and not key then
    for _, name in ipairs(M.preset_names()) do
      out[#out + 1] = name
    end
    local files = commands.completers:get("exportable")
    for _, item in ipairs(files and files(word) or {}) do
      out[#out + 1] = item.text
    end
  end
  local first = before:match("^(%S+)%s+$")
  if first and other_format(first) and not key then
    out[#out + 1] = before .. "clip"
    out[#out + 1] = before .. "selection"
  end
  for _, w in ipairs(M.words) do
    local name = w[1] as string
    if key and name == key .. "=" then
      for _, v in ipairs(w[2] as {string}) do
        out[#out + 1] = before .. name .. v
      end
    elseif not key then
      out[#out + 1] = before .. name
    end
  end
  return out
end

for _, bang in ipairs({"", "!"}) do
  commands.define(
    "export" .. bang,
    function(ctx: commands.Context): commands.Result return export(ctx, bang == "!") end,
    {
      desc = bang == ""
        and "Export the song or a part of it to sound files, or to a file of another program by its ending: `export`, `export song.flac`, `export stems`, `:17,32export bridge.wav`, `:t/Drums/export drums.wav`, `export song.mid`" or "Export and replace files without the plan first: `export! stems`",
      range = true,
      complete = complete,
    }
  )
end

commands.define(
  "export.cancel",
  function(): commands.Result
    if not M.cancel() and not render.cancel() then
      paw.notify("nothing is being exported")
    end
  end,
  {desc = "Stop the export that runs, and the files that wait after it; it leaves no file of the render that runs"}
)

-- `Esc` in normal mode stops a render (paw/render.tl): the kernel then says
-- that the render was cancelled, and the export ends with it.

return M
