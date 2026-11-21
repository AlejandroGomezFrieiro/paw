-- Stems by group: one file for each group (or each track) of the song, or
-- of the group a narrowed tab shows, named after it. `:render stems` shows
-- what it would write first, and renders on `y`.
--
--   paw.stems.plan({ dir = "out", format = "flac" })   -- what would be written
--   paw.stems.plan({ tracks = true })                  -- one per track instead
--   paw.stems.plan({ group = strings })                -- that group alone
--   paw.stems.render(plan, opts)                       -- write it: the files
--
-- A stem is its track as when it is soloed: with what its sound passes
-- through on the way to the master (a reverb its sends reach among them),
-- so that the stems add up to the mix.
local api = paw.api
local M = {}

local groups = paw.groups

local function name_of(id) return api.track_get(id, "name") end

--- Whether a track or anything inside it has clips.
local function sounds(id)
  if #api.clip_list(id) > 0 then return true end
  for _, member in ipairs(groups.members(id)) do
    if sounds(member) then return true end
  end
  return false
end

--- The tracks a stem of `id` holds that have clips, by name.
local function holds(id)
  local out = {}
  for _, other in ipairs(api.track_list()) do
    if other ~= id and paw.scope.contains(other, id) and #api.clip_list(other) > 0 then out[#out + 1] = name_of(other) end
  end
  return out
end

--- What the stems would be: a list of `{ id, name, file, holds }`, in the
--- order of the track list. `opts`: `dir` (where; `stems` in the renders
--- folder by default, see `paw.render.renders_dir`), `format` ("wav", the default, "flac",
--- "mp3", "ogg", "opus"), `tracks` (one per track, not per group), `group`
--- (that group, or track, alone). In a narrowed tab, the parts of its group.
function M.plan(opts)
  opts = opts or {}
  local scope = paw.scope.group()
  local ext = opts.format or "wav"
  local dir = opts.dir
  if not dir then
    local renders = require("paw.render").renders_dir() or "."
    dir = opts.group and renders or (renders .. "/stems")
  end
  local ids = {}
  if opts.group then
    ids[1] = opts.group
  else
    for _, id in ipairs(paw.scope.tracks()) do
      local t = api.track_get(id)
      local wanted
      if opts.tracks then
        wanted = not groups.is_group(id) or #t.clips > 0
      else
        -- The top of each branch: the parts of the scope's group, or of the song.
        local parent = groups.of(id)
        wanted = scope and parent == scope or (not scope and parent == nil)
      end
      if wanted and not t.mute and not paw.vca.is_vca(id) and sounds(id) then ids[#ids + 1] = id end
    end
  end
  local out, used = {}, {}
  for _, id in ipairs(ids) do
    local name = name_of(id):gsub("[^%w%-_ ]", "_")
    -- Two of one name get a number each.
    used[name] = (used[name] or 0) + 1
    if used[name] > 1 then name = name .. " " .. used[name] end
    out[#out + 1] = { id = id, name = name_of(id), file = string.format("%s/%s.%s", dir, name, ext), holds = holds(id) }
  end
  return out, dir
end

--- Write the stems of a plan, with `paw.render`'s options (`background`
--- renders them one after another). Returns the files.
function M.render(plan, opts)
  opts = opts or {}
  local files = {}
  for _, stem in ipairs(plan) do
    local dir = stem.file:match("^(.*)/[^/]*$")
    if dir then pcall(paw.api.fs_mkdir, dir) end
    local ext = stem.file:match("%.(%w+)$")
    -- A lossy stem is titled after its track, unless the options say otherwise.
    local lossy = ext ~= "wav" and ext ~= "flac"
    local tags = paw.util.merge(lossy and { title = stem.name } or {}, opts.tags or {})
    paw.render(stem.file, paw.util.merge(opts, { tracks = { stem.id }, format = false, tags = tags }))
    files[#files + 1] = stem.file
  end
  return files
end

-- The plan, to confirm -------------------------------------------------------------------

local FOOTER = "y or Enter: render · n or Esc: back"
local confirm = { modal = true, focusable = true, window = false, scroll = 0, lines = {} }
paw.seats.fields("render.plan", confirm, { "scroll", "lines", "plan", "opts" }, { scroll = 0, lines = {} })

function confirm:render(canvas)
  local h = canvas.height - 1
  self.scroll = paw.util.clamp(self.scroll, 0, math.max(0, #self.lines - h))
  for row = 0, h - 1 do
    local line = self.lines[row + 1 + self.scroll]
    if line then canvas:text(1, row, paw.util.fit(line, canvas.width - 2), "Normal") end
  end
  canvas:fill(0, canvas.height - 1, canvas.width, 1, " ", "FloatFooter")
  canvas:text(1, canvas.height - 1, FOOTER, "FloatFooter")
end

function confirm:on_key(key)
  if key == "y" or key == "<CR>" then
    local plan, opts = self.plan, self.opts
    self.plan, self.opts, self.lines = nil, nil, {}
    paw.ui.close()
    local files = M.render(plan or {}, opts)
    paw.notify(string.format("rendering %d stem%s", #files, #files == 1 and "" or "s"))
  elseif key == "n" or key == "q" or key == "<Esc>" or key == "<C-c>" then
    self.plan, self.opts, self.lines = nil, nil, {}
    paw.ui.close()
  elseif key == "j" or key == "<Down>" then
    self.scroll = self.scroll + 1
  elseif key == "k" or key == "<Up>" then
    self.scroll = self.scroll - 1
  end
  api.ui_redraw()
end

paw.ui.view("render.plan", confirm)

--- Show a plan and render it on `y`.
function M.confirm(plan, dir, opts)
  if #plan == 0 then return paw.notify("nothing to render: no group or track here has clips", "warn") end
  local lines, w = {}, api.str_width(FOOTER) + 4
  for _, stem in ipairs(plan) do
    local file = stem.file:match("([^/]+)$")
    local line = string.format("%-24s %s", file, #stem.holds > 0 and table.concat(stem.holds, ", ") or stem.name)
    lines[#lines + 1] = line
    w = math.max(w, api.str_width(line) + 4)
  end
  confirm.plan, confirm.opts, confirm.lines, confirm.scroll = plan, opts, lines, 0
  paw.ui.open("render.plan", { title = string.format("Render %d stem%s into %s", #plan, #plan == 1 and "" or "s", dir),
    width = math.min(w, 110), height = math.min(#lines + 3, 30) })
end

--- What `:render stems` and `:render <group>` do with the command's options.
function M.command(ctx, opts)
  local a = ctx.args
  local how = { format = a.format, tracks = a[2] == "tracks" or nil }
  if a[1] == "stems" then
    local dir = a[2] ~= "tracks" and a[2] or a[3]
    how.dir = dir and paw.files.path(tostring(dir)) or nil
  else
    how.group = paw.scope.find(a[1])
  end
  local plan, dir = M.plan(how)
  M.confirm(plan, dir, opts)
end

--- True if `:render <word>` names a group to render alone, and not a file:
--- the name of a group, with no file ending.
function M.names_group(word)
  return type(word) == "string" and not word:find("[./]") and paw.scope.find(word) ~= nil
end

return M
