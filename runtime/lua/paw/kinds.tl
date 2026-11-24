-- `paw.kinds`: the kinds of each family, by one function. A family is a
-- set of kinds of one thing: `stream` (what a lane carries), `clip` (what
-- a clip holds), `part` (what a part is for) and `meta` (a key that a
-- module keeps in `meta`). The core and extensions define kinds:
--
--   paw.kinds.define("stream", "video", { title = "Video", time = "seconds", records = true })
--   paw.kinds.define("clip", "film", { gives = "video", serialize = ..., deserialize = ... })
--   paw.kinds.define("part", "vocal", { title = "Vocal part", create = ... })
--   paw.kinds.define("meta", "utau", { title = "Phonemes of a note", version = 1 })
--
-- Each family keeps its kinds in a `paw.registry`, so each kind has the
-- extension that defined it, and the kind comes back when an extension
-- that replaced it unloads. The kernel keeps a copy of the kind on top
-- (`paw.api.kinds_put`): it checks a clip of a kind, a stream type, and
-- gives the kinds with their schema to a tool (`paw.api.kinds_list`).
--
-- The module of a family (paw/clip_kinds.tl, paw/part_kinds.tl,
-- paw/meta.tl) gives it to `paw.kinds.family`. This module defines the
-- stream family and the built-in kinds of clip.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local registry = require("paw.registry")

local record M
  --- A family as its module gives it to `paw.kinds.family`.
  record Family
    --- Check `spec`, complete it, and make it the kind `name`. An error
    --- says what is wrong with it.
    define: function(name: string, spec: contracts.Kind): contracts.Kind
    --- Take away the kind `name` on top, so that the one below comes back.
    remove: function(name: string)
    --- The kind `name` as defined, or nil.
    get: function(name: string): contracts.Kind
    --- The extension that defined the kind `name`, or nil for the core
    --- and the user.
    owner: function(name: string): string
  end

  --- The families by name.
  families: {string: Family}
  --- The stream kinds by name.
  streams: registry.Registry<contracts.StreamKind>
end
M.families = {}

--- The feature of the core that puts the built-in kinds of a family.
local CORE: {string: string} = {
  stream = "paw.streams",
  clip = "paw.clips",
  part = "paw.parts",
  meta = "paw.meta",
}

--- The names of the kinds that the core put, by family.
local builtin: {string: {string: boolean}} = {stream = {}, clip = {}, part = {}, meta = {}}

--- Give the kind `name` of `family` to the kernel: the fields that it
--- keeps, and its owner. A nil `fields` takes the kind away.
function M.mirror(family: string, name: string, fields: types.KindSpec, owner: string)
  if fields and not owner and builtin[family][name] then
    owner = CORE[family]
  end
  api.kinds_put(family, name, fields, owner)
end

--- Put `spec` at `name` in `reg`, the registry of a family. When the
--- kernel refuses the kind, the registry is as it was, and the error says
--- why.
function M.put<T>(reg: registry.Registry<T>, name: string, spec: T)
  local ok, err = pcall(function() reg:put(name, spec) end) as (boolean, string)
  if not ok then
    if reg:get(name) == spec then
      reg:remove(name)
    end
    error((tostring(err):gsub("^[^:]*:%d+: ", ""):gsub("^runtime error: ", "")), 0)
  end
end

--- Give `family` to `paw.kinds`: `define` then reaches it.
function M.family(name: string, family: M.Family)
  M.families[name] = family
end

--- The family `name`, or an error that lists the families.
local function family_of(name: string, level: integer): M.Family
  local family = M.families[name]
  if not family then
    local names: {string} = {}
    for key in pairs(M.families) do
      names[#names + 1] = key
    end
    table.sort(names)
    error(string.format("`%s` is no family of kinds: there are %s", tostring(name), table.concat(names, ", ")), level)
  end
  return family
end

--- True when `name` names a kind: lowercase words joined by dots
--- (`band`, `drums.transient`), at most 64 bytes, as the kernel takes it.
local function valid(name: string): boolean
  if type(name) ~= "string" or #name == 0 or #name > 64 then
    return false
  end
  for word in (name .. "."):gmatch("([^.]*)%.") do
    if not word:match("^[a-z][a-z0-9_%-]*$") then
      return false
    end
  end
  return true
end

--- Define the kind `name` of `family` (`stream`, `clip`, `part` or
--- `meta`) with `spec`. `name` is a lowercase word, or words joined by
--- dots. Defining a kind again replaces it, and an extension's kind goes
--- when the extension unloads. Gives the spec as the family completed it.
function M.define(family: string, name: string, spec: contracts.Kind): contracts.Kind
  local fam = family_of(family, 3)
  if not valid(name) then
    error(
      string.format(
        "`%s` is not a name of a kind: say lowercase words joined by dots, as `band` or `drums.transient`",
        tostring(name)
      ),
      2
    )
  end
  if type(spec) ~= "table" then
    error(string.format("paw.kinds.define(%q, %q, spec): the spec is a table", family, name), 2)
  end
  -- A built-in kind of clip has content of its own, and an extension
  -- does not replace a built-in kind of another family.
  local by_extension = registry.owner ~= nil and registry.owner() ~= nil
  if builtin[family][name] and (family == "clip" or by_extension) then
    error(string.format("`%s` is a built-in %s kind: it is not defined again", name, family), 2)
  end
  return fam.define(name, spec)
end

--- Take away the kind `name` of `family`: things of the kind that the
--- project holds keep it, and the kind below comes back if there is one.
function M.remove(family: string, name: string)
  family_of(family, 3).remove(name)
end

--- The kind `name` of `family` as defined, or nil.
function M.get(family: string, name: string): contracts.Kind
  return family_of(family, 3).get(name)
end

--- The kinds of `family` (of every family when nil) as the kernel keeps
--- them, sorted by family and name, each with its owner and the schema of
--- its data.
function M.list(family?: string): {types.KindInfo}
  return api.kinds_list(family)
end

-- The stream family -------------------------------------------------------------

--- The fields of a stream kind that the kernel keeps.
local function stream_fields(spec: contracts.StreamKind): types.KindSpec
  return spec
    and {
      title = spec.title,
      time = spec.time,
      records = spec.records,
      control = spec.control,
      props = spec.props,
      schema = spec.schema,
    }
end

M.streams = registry.new(
  "stream_kinds",
  "stream kinds",
  {
    changed = function(name: string, spec: contracts.StreamKind)
      M.mirror("stream", name, stream_fields(spec), M.streams:owner(name))
    end,
  }
)

local TIMES: {string: boolean} = {samples = true, beats = true, seconds = true}

M.family(
  "stream",
  {
    define = function(name: string, given: contracts.Kind): contracts.Kind
      local spec = given as contracts.StreamKind
      if spec.time ~= nil and not TIMES[spec.time as string] then
        error(string.format("stream kind `%s`: its time is `samples`, `beats` or `seconds`", name), 3)
      end
      spec.name = name
      spec.title = spec.title or name
      M.put(M.streams, name, spec)
      return spec
    end,
    remove = function(name: string) M.streams:remove(name) end,
    get = function(name: string): contracts.Kind return M.streams:get(name) end,
    owner = function(name: string): string return M.streams:owner(name) end,
  }
)

--- The stream kinds of the core: what the lanes of a project carry.
local STREAMS: {{string, contracts.StreamKind}} = {
  {
    "midi",
    {
      title = "MIDI",
      time = "beats",
      records = true,
      props = {
        lyrics = {type = "boolean", default = false},
      },
    },
  },
  {"audio", {title = "Audio", time = "samples"}},
  {"curve", {title = "Curve", time = "beats", records = true, control = true}},
  {"state", {title = "State", time = "beats", records = true, control = true}},
}
for _, entry in ipairs(STREAMS) do
  builtin.stream[entry[1]] = true
  M.define("stream", entry[1], entry[2])
end

--- The kinds of clip of the core, and the stream that each gives. Their
--- clips have content of their own, so they are not in the registry of
--- `paw.clip_kinds`: the kernel keeps them, and `paw.kinds.list` gives
--- them.
local CLIPS: {{string, string, string}} = {
  {"midi", "MIDI clip", "midi"},
  {"audio", "Audio clip", "audio"},
  {"nest", "Subproject clip", "audio"},
  {"curve", "Curve clip", "curve"},
}
for _, entry in ipairs(CLIPS) do
  builtin.clip[entry[1]] = true
  M.mirror("clip", entry[1], {title = entry[2], gives = entry[3]}, CORE.clip)
end

--- Mark the kind `name` of `family` as the core's, before the core
--- defines it: the kernel then names the core as its owner (`paw.meta`).
function M.core(family: string, name: string)
  builtin[family][name] = true
end

--- True when `name` is a kind of `family` that the core defines.
function M.builtin(family: string, name: string): boolean
  return builtin[family] ~= nil and builtin[family][name] == true
end

return M
