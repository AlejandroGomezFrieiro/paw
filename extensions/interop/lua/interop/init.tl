-- What the formats of other programs' projects share: the list of what did
-- not carry over, finding the plugins and devices of a file among those
-- installed, gain in decibels, tempo maps in seconds, the state of a VST3
-- plugin, and registering a format. REAPER (interop.rpp) and DAWproject
-- (interop.dawproject) are made with it; a new format can be too.
--
--   local interop = require("interop")
--   local report = interop.report.new("Not carried over from song.xyz:")
--   report:add("Plugins", "Reverb (not installed here)")
--   interop.find_plugin({ format = "vst3", id = class, name = "Reverb", vendor = "Acme" })
--   interop.register({ name = "xyz", desc = "XYZ projects", extensions = { "xyz" }, module = "myext.xyz" })
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local reports = require("interop.report")
local type types = require("paw.types")
local type formats = require("paw.formats")
local type zip = require("paw.zip")
local type rpp_format = require("interop.rpp.format")

local api = paw.api

local record M
  --- What an import or an export of a format takes. `merge` and the words
  --- of the command line come from `paw.formats`; each format reads the
  --- fields it knows and leaves the others.
  record Options
    --- Add to the current project (import).
    merge: boolean
    --- Where the file was read from (import).
    path: string
    --- The folder of the file (rpp): media paths are relative to it.
    dir: string
    --- The name of the file, for the title of the report (export).
    name: string
    --- A device kind for MIDI parts left without an instrument (rpp import).
    instrument: string
    --- Where the audio of a DAWproject file goes (import).
    media_dir: string
    --- False: refer to audio files where they are (DAWproject export).
    embed: boolean
    --- The seed of the GUIDs and the time stamp of the file (rpp export).
    seed: integer
    timestamp: integer
    --- The version of paw that wrote the file (DAWproject export).
    version: string
  end

  --- What an import or an export gives: `report`, what it made, and what
  --- `said` adds for `paw.formats`.
  record Result
    report: reports.Report
    --- Import: the new parts, and the counts of clips and plugins.
    parts: {integer}
    clips: integer
    devices: integer
    --- Import of an rpp file: the tempo the project plays at.
    tempo: number
    --- Export of an rpp file: the document written.
    doc: rpp_format.Node
    --- Export of a DAWproject file: the files of the archive.
    files: {zip.Entry}
    --- What `paw.formats` says, and the lines of what did not carry over.
    said: string
    lost: {string}
  end

  --- What `register` takes: a format of `paw.formats` whose `module` has
  --- `import` and `export`. `import = false` or `export = false` leaves
  --- that side out.
  record Spec
    name: string
    desc: string
    extensions: {string}
    project: boolean
    detect: function(path: string): boolean
    module: string
    import: boolean
    export: boolean
  end

  --- A marker or a region as `paw.markers` keeps it (`project.meta.markers`),
  --- in beats; a region has a length.
  record Marker
    id: integer
    beat: number
    name: string
    color: string
    length: number
  end

  --- A song section as the sections extension gives it, in beats.
  record Section
    start: number
    finish: number
    name: string
  end

  --- The module of a format (`spec.module`).
  record Module
    import: function(path: string, opts?: Options): Result
    export: function(path: string, opts?: Options): Result
  end

  report: reports
  tempo_from_seconds: function(
    tempos: {types.TempoSecondsPoint}, signatures?: {types.SigSecondsPoint}
  ): types.TempoMapInSeconds
  vst3_split: function(raw: string): string, string
  vst3_join: function(component: string, controller: string): string
end

local type Options = M.Options
local type Result = M.Result

--- Lists of what did not carry over, by group (`new`, `add`, `count`,
--- `empty`, `lines`, `data`): see interop/report.tl.
M.report = reports

-- Decibels from a gain as `paw.dsp.db` makes them (the same arithmetic,
-- so the same numbers): a gain under 6.3e-8 is silence, -144 dB.
local LN10_20 = math.log(10) / 20

--- A gain as decibels, kept from -120 to 24 (what a fader takes).
function M.db(gain?: number): number
  local g: number = math.abs(gain or 0)
  local db = g < 6.3e-8 and -144 or math.log(g) / LN10_20
  return paw.util.clamp(db, -120, 24)
end

--- A gain in decibels as an amplitude: silence at -120 dB and below.
function M.amp(db: number): number
  if db <= -120 then
    return 0
  end
  return 10 ^ (db / 20)
end

--- The markers and regions of the project (`project.meta.markers`).
function M.markers(): {M.Marker}
  local meta = api.project_get().meta or {}
  return type(meta.markers) == "table" and meta.markers as {M.Marker} or {}
end

--- Add markers and regions after those of the project, with new ids.
function M.add_markers(list: {M.Marker})
  local meta = api.project_get().meta or {}
  local all: {M.Marker} = type(meta.markers) == "table" and meta.markers as {M.Marker} or {}
  local top = 0
  for _, m in ipairs(all) do
    top = math.max(top, math.floor(tonumber(m.id) or 0))
  end
  for i, m in ipairs(list) do
    m.id = top + i
    all[#all + 1] = m
  end
  meta.markers = all
  api.project_set({meta = meta})
end

--- The part of the sections extension that a format reads.
local record Sections
  list: function(): {M.Section}
end

--- The song sections, when the sections extension is there; none when
--- it is not.
function M.sections(): {M.Section}
  local ok, sections = pcall(require as (function(string): Sections), "sections") as (boolean, Sections)
  return ok and sections.list() or {}
end

--- The kind of device installed here that is `kind`, or nil.
function M.installed(kind: string): types.DeviceType
  return api.device_find({kind = kind})
end

--- The plugin installed here that a file names: by its own id (a VST3
--- class id in either case, a CLAP id), else by name and vendor, else by
--- name in any case; `query` is `{ format, id, name, vendor }`.
function M.find_plugin(query: types.DeviceQuery): types.DeviceType
  return api.device_find(query)
end

--- The kinds of device by kind, each looked up the first time it is met:
--- `types[kind]` is its entry of `paw.api.device_types`, or nil when it is
--- not installed here.
function M.device_types(): {string: types.DeviceType}
  -- The kinds that are not installed, so that each is looked up once.
  local missing: {string: boolean} = {}
  local meta: metatable<{string: types.DeviceType}> = {
    __index = function(t: {string: types.DeviceType}, kind: string): types.DeviceType
      if missing[kind] then
        return nil
      end
      local v = api.device_find({kind = kind})
      if v then
        rawset(t, kind, v)
      else
        missing[kind] = true
      end
      return v
    end,
  }
  return setmetatable({}, meta)
end

--- A tempo map from points in seconds: see `paw.api.tempo_from_seconds`.
M.tempo_from_seconds = api.tempo_from_seconds

--- The parts of a VST3 plugin's state as paw keeps it, and back
--- (`paw.bytes.vst3_split`, `vst3_join`).
M.vst3_split, M.vst3_join = paw.bytes.vst3_split, paw.bytes.vst3_join

--- What an import or an export says (`paw.formats`): `said`, and what did
--- not carry over (`lost`, the lines of `result.report`), with the rest of
--- `result`.
function M.said(result: Result, text: string): Result
  result.said = text
  if result.report and not result.report:empty() then
    result.lost = result.report:lines(30)
  end
  return result
end

--- The words of a command line as options: `embed=false` typed on a
--- command line is a word, and so the boolean false.
local function words(args: {string | integer: formats.Arg}): Options
  local out: {string: formats.Arg} = {}
  for k, v in pairs(args or {}) do
    if k is string then
      if v == "false" then
        v = false
      elseif v == "true" then
        v = true
      end
      out[k] = v
    end
  end
  -- The words are the user's: each format reads the fields it knows.
  return out as Options
end

--- Register a format whose module (`spec.module`) has `import(path,
--- opts)` and `export(path, opts)` that return `{ report, ... }`: `import`
--- says how many parts, clips and plugins came in, `export` that the file
--- was written. `opts.merge` and `opts.args` are as `paw.formats` gives them.
function M.register(spec: M.Spec): string
  local function module(): M.Module
    return (require as function(string): M.Module)(spec.module)
  end
  local f: formats.Format = {
    name = spec.name,
    desc = spec.desc,
    extensions = spec.extensions,
    project = spec.project,
    detect = spec.detect,
  }
  if spec.import ~= false then
    f.import = function(path: string, opts: formats.Options): formats.Result
      local o = words(opts.args)
      if opts.merge ~= nil then
        o.merge = opts.merge
      end
      local result = module().import(path, o)
      return M.said(
        result,
        string.format(
          "%s %s: %d parts, %d clips, %d plugins",
          opts.merge and "imported" or "opened",
          path,
          #result.parts,
          result.clips,
          result.devices
        )
      ) as formats.Said
    end
  end
  if spec.export ~= false then
    f.export = function(path: string, opts: formats.Options): formats.Result
      return M.said(module().export(path, words(opts.args)), "wrote " .. path) as formats.Said
    end
  end
  return paw.formats.register(f)
end

return M
