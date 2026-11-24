-- `paw.meta`: the keys that modules keep in `meta`, the `meta` family of
-- `paw.kinds`. A part, a clip, a note and the project each have a `meta`
-- table, where a module or an extension keeps its own data. The module
-- declares each key that it keeps:
--
--   paw.meta.define("utau", { title = "The voice of a note: phonemes, tuning", version = 2 })
--
-- so `K` names the owner of the key, and the owner can move data of an
-- older version. A key that no loaded module declares stays as it is,
-- saved with the project: `:checkhealth meta` lists it, with the files
-- that hold it.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local registry = require("paw.registry")
local kinds = require("paw.kinds")

local record M
  --- A key of `meta` that no loaded module declares, and where it is.
  record Undeclared
    key: string
    --- The things that hold it: `part Bass`, `clip verse`, `note of clip
    --- verse`, `project`.
    places: {string}
    --- The files of the project folder that hold it, sorted.
    files: {string}
  end

  --- The declared keys by name, with the extension that declared each.
  keys: registry.Registry<contracts.MetaKey>
end

M.keys = registry.new(
  "meta_keys",
  "keys of meta",
  {
    changed = function(key: string, spec: contracts.MetaKey)
      kinds.mirror(
        "meta", key, spec and {title = spec.title, version = spec.version, schema = spec.schema}, M.keys:owner(key)
      )
    end,
  }
)

kinds.family(
  "meta",
  {
    define = function(key: string, given: contracts.Kind): contracts.Kind
      local spec = given as contracts.MetaKey
      local version = spec.version or 1
      if math.type(version) ~= "integer" or version < 1 then
        error(string.format("meta key `%s`: its version is a whole number from 1", key), 3)
      end
      spec.name, spec.version = key, version
      spec.title = spec.title or key
      kinds.put(M.keys, key, spec)
      return spec
    end,
    remove = function(key: string) M.keys:remove(key) end,
    get = function(key: string): contracts.Kind return M.keys:get(key) end,
    owner = function(key: string): string return M.keys:owner(key) end,
  }
)

--- Declare the key `key` of `meta` (`paw.kinds.define("meta", key, spec)`).
--- `spec.title` says what it holds, and `spec.version` (1 if not given)
--- is the version of its data.
function M.define(key: string, spec: contracts.MetaKey): contracts.MetaKey
  return kinds.define("meta", key, spec) as contracts.MetaKey
end

--- Who keeps the key `key`: the extension that declared it, `paw` for a
--- key of the core, `the user's config` for a key that the config
--- declared, or nil for a key that no loaded module declares.
function M.owner(key: string): string
  if not M.keys:get(key) then
    return nil
  end
  return M.keys:owner(key) or (kinds.builtin("meta", key) and "paw" or "the user's config")
end

--- Each key of `meta` in the project that no loaded module declares,
--- sorted by key, with the things and the files that hold it.
function M.undeclared(): {M.Undeclared}
  local found: {string: M.Undeclared} = {}
  local seen: {string: {string: boolean}} = {}
  local file_of: {string: string} = {}
  for _, f in ipairs(api.project_files()) do
    if f.clip then
      file_of["clip" .. f.clip] = f.path
    elseif f.part then
      file_of["part" .. f.part] = file_of["part" .. f.part] or f.path
    end
  end
  local function note(meta: types.Meta, place: string, file: string)
    for key in pairs(meta or {}) do
      if not M.keys:get(key) then
        local entry = found[key] or {key = key, places = {}, files = {}}
        found[key], seen[key] = entry, seen[key] or {}
        if #entry.places < 3 then
          entry.places[#entry.places + 1] = place
        end
        if file and not seen[key][file] then
          seen[key][file] = true
          entry.files[#entry.files + 1] = file
        end
      end
    end
  end
  note(api.project_get().meta, "project", "meta.json")
  for _, id in ipairs(api.part_list({all = true})) do
    local part = api.part_get(id)
    note(part.meta, "part " .. part.name, file_of["part" .. id])
    for _, clip in ipairs(api.clip_list(id)) do
      local file = file_of["clip" .. clip.id] or file_of["part" .. id]
      note(clip.meta, "clip " .. clip.name, file)
      if clip.kind == "midi" then
        for _, n in ipairs((api.clip_notes(clip.id))) do
          note(n.meta, "a note of clip " .. clip.name, file)
        end
      end
    end
  end
  local out: {M.Undeclared} = {}
  for _, entry in pairs(found) do
    table.sort(entry.files)
    out[#out + 1] = entry
  end
  table.sort(out, function(a: M.Undeclared, b: M.Undeclared): boolean return a.key < b.key end)
  return out
end

--- The keys that the core keeps, each declared by the module that keeps it.
local CORE: {{string, string}} = {
  {"group_head", "the part is a group (paw.groups)"},
  {"group_link", "the faders of the group are linked (paw.groups)"},
  {"takes", "the takes of a part or a clip (paw.takes)"},
  {"vca", "the faders that a VCA moves (paw.vca)"},
  {"vcas", "the VCAs that move the fader (paw.vca)"},
  {"frozen", "the frozen audio of a part (paw.freeze)"},
  {"channel", "the MIDI channel of a note (paw.midifile)"},
  {"articulation", "the articulations of a note (paw.query)"},
  {"comment", "a comment on a note (paw.query)"},
}
for _, entry in ipairs(CORE) do
  kinds.core("meta", entry[1])
  M.define(entry[1], {title = entry[2]})
end

return M
