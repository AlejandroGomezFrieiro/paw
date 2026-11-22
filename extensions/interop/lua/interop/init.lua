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
local api = paw.api

local M = {}

--- Lists of what did not carry over, by group (`new`, `add`, `count`,
--- `empty`, `lines`, `data`): see interop/report.lua.
M.report = require("interop.report")

--- A gain as decibels, kept from -120 to 24 (what a fader takes).
function M.db(gain) return paw.util.clamp(require("paw.dsp").db(gain or 0), -120, 24) end

--- The kind of device installed here that is `kind`, or nil.
function M.installed(kind) return api.device_find({ kind = kind }) end

--- The plugin installed here that a file names: by its own id (a VST3
--- class id in either case, a CLAP id), else by name and vendor, else by
--- name in any case; `query` is `{ format, id, name, vendor }`.
function M.find_plugin(query) return api.device_find(query) end

--- The kinds of device by kind, each looked up the first time it is met:
--- `types[kind]` is its entry of `paw.api.device_types`, or false.
function M.device_types()
  return setmetatable({}, {
    __index = function(t, kind)
      local v = api.device_find({ kind = kind }) or false
      rawset(t, kind, v)
      return v
    end,
  })
end

--- A tempo map from points in seconds: see `paw.api.tempo_from_seconds`.
M.tempo_from_seconds = api.tempo_from_seconds

--- The parts of a VST3 plugin's state as paw keeps it, and back
--- (`paw.bytes.vst3_split`, `vst3_join`).
M.vst3_split, M.vst3_join = paw.bytes.vst3_split, paw.bytes.vst3_join

--- What an import or an export says (`paw.formats`): `said`, and what did
--- not carry over (`lost`, the lines of `result.report`), with the rest of
--- `result`.
function M.said(result, text)
  result.said = text
  if result.report and not result.report:empty() then result.lost = result.report:lines(30) end
  return result
end

--- Register a format whose module (`spec.module`) has `import(path,
--- opts)` and `export(path, opts)` that return `{ report, ... }`: `import`
--- says how many tracks, clips and plugins came in, `export` that the file
--- was written. `opts.merge` and `opts.args` are as `paw.formats` gives them.
function M.register(spec)
  local mod = spec.module
  -- `embed=false` typed on a command line is a word: false.
  local function words(args)
    local out = {}
    for k, v in pairs(args or {}) do
      if type(k) == "string" then
        if v == "false" then
          v = false
        elseif v == "true" then
          v = true
        end
        out[k] = v
      end
    end
    return out
  end
  local f = {}
  for k, v in pairs(spec) do
    f[k] = v
  end
  f.module = nil
  if spec.import ~= false then
    f.import = function(path, opts)
      local result = require(mod).import(path, paw.util.merge(words(opts.args), { merge = opts.merge }))
      return M.said(
        result,
        string.format(
          "%s %s: %d tracks, %d clips, %d plugins",
          opts.merge and "imported" or "opened",
          path,
          #result.tracks,
          result.clips,
          result.devices
        )
      )
    end
  end
  if spec.export ~= false then
    f.export = function(path, opts) return M.said(require(mod).export(path, words(opts.args)), "wrote " .. path) end
  end
  return paw.formats.register(f)
end

return M
