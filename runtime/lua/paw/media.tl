-- The project's sound files: listing what is missing, relinking it, and
-- copying files from elsewhere into the project's own `media` folder.
-- The work is in the kernel (crates/paw-core/src/session/media.rs).
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local commands = require("paw.commands")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type objects = require("paw.objects")
local type CursorModule = require("paw.cursor")

--- A clip: its id, or the clip (`paw.clip`, `paw.cursor.clip`).
local type ClipRef = integer | objects.Clip

--- The payload of `option.changed`, as far as this module reads it.
local record OptionChanged
  name: string
  value: options.Value
end

-- What this module reads of `paw`, which paw/init.lua makes, and of the
-- modules in Lua that it calls: their parts that it uses.
--- What `paw.pick.file` takes (paw/pick.tl).
local record FileOptions
  title: string
  directory: boolean
  extensions: {string}
  on_choose: function(path: string)
end
--- The parts of `paw.pick` (paw/pick.tl) that this module calls.
local record Pick
  open: function<T>(spec: contracts.PickSource<T>)
  file: function(opts: FileOptions)
end
local type UiModule = require("paw.ui")
local record Paw is partial.Paw
  ui: UiModule
  cursor: CursorModule
  pick: Pick
end
local paw = (_G as {string:Paw}).paw

local type Context = commands.Context
local type Result = commands.Result

local record M
  type ClipRef = ClipRef
end

options.define("copy_imports", false) -- importing copies the file into `media` beside the project

-- Long files are played from the disk, not held in memory: see the
-- options `media_stream` and `media_cache`.
api.media_store(tonumber(options.opt.media_stream) or 0, tonumber(options.opt.media_cache) or 16)
local option_changed: events.Event<OptionChanged> = events.event("option.changed")
events.on(option_changed, function(e: OptionChanged)
  if e.name == "media_stream" then api.media_store(tonumber(e.value) or 0) end
end)

local function name_of(path: string): string return tostring(path):match("([^/]+)$") or tostring(path) end

--- Files the project's clips play that are not there, once each.
function M.missing(): {string} return api.media_missing() end

--- Every file the project plays: `{ path, missing, inside }`.
function M.list(): {types.MediaFile} return api.media_list() end

--- Make the clips that play `from` play the file `to`, and find the other
--- files that paw cannot find in the folder of `to`. One undo step. Returns
--- `{ clips, found, missing }`.
function M.relink(from: string, to: string): types.MediaFound return api.media_relink(from, to) end

--- Find in a directory tree each file that paw cannot find. One undo step.
--- Returns `{ found, missing }`.
function M.search(dir: string): types.MediaFound return api.media_search(dir) end

--- Copy every file from outside the project's folder into `media` beside
--- it and point the clips at the copies. One undo step. Returns `{ copied, missing, dir }`.
function M.collect(): types.MediaCollected return api.media_collect() end

local function still(result: types.MediaFound): string
  local n = #(result.missing or {})
  return n == 0 and "nothing is missing now" or string.format("%d still missing", n)
end

--- An entry of the list of `M.relink_pick`.
local record Missing
  label: string
  search: boolean
  path: string
end

--- Select a file for a file that paw cannot find, or a directory where paw finds all of them.
function M.relink_pick()
  local missing = api.media_missing()
  if #missing == 0 then return paw.notify("no media is missing") end
  local items: {Missing} = { { label = "Search a directory for all of them…", search = true } }
  for _, path in ipairs(missing) do items[#items + 1] = { label = name_of(path) .. "  " .. path, path = path } end
  paw.pick.open({
    title = string.format("Missing media (%d)", #missing),
    items = items,
    format = function(item: Missing): string return item.label end,
    on_choose = function(item: Missing)
      if item.search then
        return paw.pick.file({
          title = "Search for missing media", directory = true,
          on_choose = function(dir: string)
            local result = api.media_search(dir)
            paw.notify(string.format("found %d file%s; %s", result.found, result.found == 1 and "" or "s", still(result)))
          end,
        })
      end
      local ext = item.path:match("%.([^./]+)$")
      paw.pick.file({
        title = "Find " .. name_of(item.path),
        extensions = ext and { ext } or nil,
        on_choose = function(path: string)
          local ok, result = pcall(api.media_relink, item.path, path)
          if not ok then return paw.notify(tostring(result), "error") end
          local found = result as types.MediaFound
          paw.notify(string.format("%s: %d clip%s relinked, %d other file%s found; %s", name_of(path),
            found.clips, found.clips == 1 and "" or "s", found.found, found.found == 1 and "" or "s", still(found)))
        end,
      })
    end,
  })
end

commands.define("media.relink", function(ctx: Context): Result
  local a, b = ctx.args[1], ctx.args[2]
  if a and b then
    local result = api.media_relink(tostring(a), tostring(b))
    return paw.notify(string.format("%d clip%s relinked; %s", result.clips, result.clips == 1 and "" or "s", still(result)))
  elseif a then
    local result = api.media_search(tostring(a))
    return paw.notify(string.format("found %d file%s; %s", result.found, result.found == 1 and "" or "s", still(result)))
  end
  M.relink_pick()
end, { desc = "Find missing media: alone, choose a file or a directory; `media.relink <dir>` searches it; `media.relink <old> <new>`" })

commands.define("media.collect", function(): Result
  local result = api.media_collect()
  local n = #result.missing
  paw.notify(string.format("copied %d file%s into %s%s", result.copied, result.copied == 1 and "" or "s", result.dir,
    n > 0 and string.format(" (%d missing, not copied)", n) or ""))
end, { desc = "Copy every sound file from outside the project's folder into its `media` folder" })

commands.define("collect", function(): Result
  if not api.project_get().path then return paw.notify("the project has no folder yet: `:w song` saves it first", "warn") end
  local tracks, chains = api.track_collect()
  local clips = api.clip_collect()
  local result = api.media_collect()
  local n = #result.missing
  local parts: {string} = {}
  if tracks > 0 then parts[#parts + 1] = string.format("%d track%s, ", tracks, tracks == 1 and "" or "s") end
  if chains > 0 then parts[#parts + 1] = string.format("%d chain%s, ", chains, chains == 1 and "" or "s") end
  paw.notify(string.format("%s%d clip%s and %d sound file%s are now the project's own%s; `:w` writes them into its folder",
    table.concat(parts), clips, clips == 1 and "" or "s", result.copied, result.copied == 1 and "" or "s",
    n > 0 and string.format(" (%d missing, not copied)", n) or ""))
end, { desc = "Copy every file from outside the project's folder into it: tracks, chains of devices, MIDI clip files and sound files" })

--- A path with the home folder as `~`.
local function tilde(path: string): string
  local home = os.getenv("HOME")
  if home and path:sub(1, #home + 1) == home .. "/" then return "~" .. path:sub(#home + 1) end
  return path
end

-- The first edit of a clip that refers to a file outside the project.
events.on(kernel.clip_copied, function(e: kernel.ClipCopied)
  paw.notify(string.format("%s is now this project's own copy (was %s)", e.name, tilde(tostring(e.origin))))
end)
-- The first edit of a track or a chain from outside the project.
events.on(kernel.track_copied, function(e: kernel.TrackCopied)
  paw.notify(string.format("the track %s is now this project's own copy (was %s)", e.name, tilde(tostring(e.origin))))
end)
events.on(kernel.chain_copied, function(e: kernel.TrackCopied)
  paw.notify(string.format("the devices of %s are now this project's own copy (was %s)", e.name, tilde(tostring(e.origin))))
end)

commands.define("media.missing", function(): Result
  local missing = api.media_missing()
  if #missing == 0 then return paw.notify("no media is missing") end
  local names: {string} = {}
  for i, path in ipairs(missing) do names[i] = name_of(path) end
  paw.notify(string.format("%d missing: %s; :media.relink finds them", #missing, table.concat(names, ", ")), "warn")
end, { desc = "List the sound files the project plays that are not there" })

-- Audio clip operations that leave the source file alone ---------------------

local function need_audio_clip(): objects.Clip
  local clip = paw.cursor.clip()
  if not clip then paw.notify("no clip under the cursor", "warn") return nil end
  if clip.kind ~= "audio" then paw.notify("not an audio clip", "warn") return nil end
  return clip
end

local function id_of(clip: ClipRef): integer
  if clip is objects.Clip then return clip.id end
  return clip
end

--- Play an audio clip backwards: a `reverse` in its edit list, which leaves
--- its file as it is (a second reverse takes it away). Returns `{ edits }`.
function M.reverse(clip: ClipRef): types.ClipEdits return api.clip_reverse(id_of(clip)) end

--- A gain of `db` on a part of an audio clip, from `from` to `to` seconds
--- of what it plays, in its edit list. Returns how many edits it has.
function M.gain_part(clip: ClipRef, from: number, to: number, db: number): integer
  return api.clip_edit_add(id_of(clip), { kind = "gain", from = from, to = to, db = db })
end

--- Samples drawn over an audio clip's (a pencil fix), from `at` seconds of
--- what it plays, in one channel (0 or 1) or both, in its edit list.
--- Returns how many edits it has.
function M.pencil(clip: ClipRef, at: number, values: {number}, channel?: integer): integer
  return api.clip_edit_add(id_of(clip), { kind = "pencil", at = at, values = values, channel = channel })
end

--- An audio clip's edit list: `{ { kind, ... } }`.
function M.edits(clip: ClipRef): {types.AudioEdit} return api.clip_edits(id_of(clip)) end

--- Take away an audio clip's edit list. Returns how many edits it had.
function M.clear_edits(clip: ClipRef): integer return api.clip_edits_clear(id_of(clip)) end

--- Bring the loudest sample an audio clip plays to `level` dB (0) by its gain.
--- Returns the new gain.
function M.normalize(clip: ClipRef, level?: number): number return api.clip_normalize(id_of(clip), level) end

--- Join audio clips of one track into one clip that plays a new file: the
--- clips of the list, by id or as clips. A list of one clip joins it and
--- each audio clip that touches or overlaps it. Lua can also give one clip
--- without a list. Returns { id, file, glued }.
function M.glue(clips: {ClipRef}): types.ClipGlued
  -- One clip given without a list (from Lua): a clip has an id, a list has none.
  local list = clips
  if type(clips) ~= "table" or (clips as objects.Clip).id ~= nil then list = { clips as ClipRef } end
  local ids: {integer} = {}
  for i, c in ipairs(list) do ids[i] = id_of(c) end
  return api.clip_glue(ids)
end

commands.define("clip.reverse", function(): Result
  local clip = need_audio_clip()
  if not clip then return end
  local done = M.reverse(clip)
  paw.notify(string.format("reversed %s (%d edit%s in its list; the file stays as it is)", clip.name, done.edits, done.edits == 1 and "" or "s"))
end, { desc = "Play the audio clip under the cursor backwards: an edit in its list; the file stays as it is" })

commands.define("clip.gain", function(ctx: Context): Result
  local clip = need_audio_clip()
  if not clip then return end
  local from, to, db = tonumber(ctx.args[1]), tonumber(ctx.args[2]), tonumber(ctx.args[3])
  if not (from and to and db) then return paw.notify("usage: clip.gain <from> <to> <dB>, in seconds of the clip: `clip.gain 1.2 1.3 -12`", "warn") end
  local ok, n = pcall(M.gain_part, clip, from, to, db)
  if not ok then return paw.notify((tostring(n):gsub("^[^:]*:%d+: ", "")), "error") end
  paw.notify(string.format("%s: %+g dB from %g s to %g s (%d edit%s in its list)", clip.name, db, from, to, n, n == 1 and "" or "s"))
end, { desc = "A gain on a part of the audio clip under the cursor, in seconds of the clip: `clip.gain 1.2 1.3 -12`" })

commands.define("clip.edits", function(): Result
  local clip = need_audio_clip()
  if not clip then return end
  local list = M.edits(clip)
  if #list == 0 then return paw.notify(clip.name .. " has no edits: it plays its file") end
  local lines: {string} = {}
  for i, e in ipairs(list) do
    if e.kind == "reverse" then
      lines[i] = string.format("%d. backwards", i)
    elseif e.kind == "gain" then
      lines[i] = string.format("%d. %+g dB from %.3f s to %.3f s of the sound", i, e.db, e.from, e.to)
    else
      lines[i] = string.format("%d. %d samples drawn at %.3f s%s", i, #e.values, e.at, e.channel and (" in channel " .. e.channel) or "")
    end
  end
  paw.ui.page("Edits of " .. clip.name, lines)
end, { desc = "List the edit list of the audio clip under the cursor" })

commands.define("clip.edits.clear", function(): Result
  local clip = need_audio_clip()
  if not clip then return end
  local n = M.clear_edits(clip)
  paw.notify(n == 0 and (clip.name .. " has no edits") or string.format("%s plays its file again (%d edit%s taken away)", clip.name, n, n == 1 and "" or "s"))
end, { desc = "Take away the edit list of the audio clip under the cursor: it plays its file again" })

commands.define("clip.normalize", function(ctx: Context): Result
  local clip = need_audio_clip()
  if not clip then return end
  local gain = M.normalize(clip, tonumber(ctx.args[1]) or 0)
  paw.notify(string.format("%s: clip gain %+.1f dB", clip.name, gain))
end, { desc = "Bring the audio clip's loudest sample to a level by its gain: `clip.normalize -1`" })

commands.define("clip.glue", function(): Result
  local clip = need_audio_clip()
  if not clip then return end
  local result = M.glue({ clip })
  paw.notify(string.format("glued %d clips into %s", result.glued, name_of(result.file)))
end, { desc = "Join the audio clip under the cursor and those touching it into one clip (a new file)" })

return M
