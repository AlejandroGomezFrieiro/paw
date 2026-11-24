-- More pickers: what the project holds (markers, notes, media, its text),
-- its history, and what the program knows (help, extensions, the Lua API).
-- Each has a location where it can, so that `Ctrl-v`, `Ctrl-x`, `Ctrl-t`
-- and `Ctrl-q` work in it (see paw/pick.tl, "Keys every picker has").
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local A = require("paw.address")
local util = require("paw.util")
local preview = require("paw.pick.preview")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type UiModule = require("paw.ui")
local type LayoutModule = require("paw.layout")
local type objects = require("paw.objects")
local type HelpModule = require("paw.help")
local type MarkersModule = require("paw.markers")
local type QueryModule = require("paw.query")
local type LazyModule = require("paw.lazy")
local type GrepModule = require("paw.grep")
local type QfModule = require("paw.qf")
local type MusicModule = require("paw.music")
local type CursorModule = require("paw.cursor")
local type AuditionModule = require("paw.audition")
local type CommandsModule = require("paw.commands")
local type registry = require("paw.registry")

--- What these pickers call of `paw.pick` (paw/pick.tl, which requires this
--- module): its sources, and hearing a file.
local interface Pick
  sources: registry.Registry<contracts.PickEntry>
  hear_file: function(path: string): string
end

--- The built-in pickers by name, which paw/pick.tl puts in `paw.pick.sources`.
local type Sources = {string: contracts.PickEntry}

--- What `paw.layout.split` takes.
local record SplitOptions
  vertical: boolean
  view: string
  buf: integer
end

--- The layout (paw/layout.tl): what this module calls of it.
local record Layout
  buf_create: function(type: string, target: string): contracts.LayoutBuffer
  tab_new: function(name?: string, view?: string)
  current: function(): contracts.Window
  show_in: function(win: contracts.Window, view: string, buf: integer): contracts.Window
  split: function(opts: SplitOptions): contracts.Window, string
end

--- An extension as `paw.ext.list()` gives it.
local record ExtInfo
  name: string
  path: string
  ok: boolean
  error: string
end

--- The extensions (paw/ext.lua, in Lua): what this module calls of them.
local record Ext
  list: function(): {ExtInfo}
  bundled_dir: function(): string
  bundled: function(): {string}
  load_bundled: function(name: string, why?: string): contracts.ExtEntry, string
  lazy: LazyModule
end

--- The devices' presets (paw/fx.lua, in Lua): the picker of the device under the cursor.
local record Fx
  pick: function()
end

local type InputOptions = UiModule.InputOptions

local record Paw is partial.Paw
  keymap: KeymapModule
  ui: UiModule
  layout: LayoutModule
  help: HelpModule
  markers: MarkersModule
  query: QueryModule
  grep: GrepModule
  qf: QfModule
  music: MusicModule
  cursor: CursorModule
  time: objects.Time
  clip: function(id: integer): objects.Clip
  audition: AuditionModule
  commands: CommandsModule
  fx: Fx
end
local paw = (_G as {string: Paw}).paw
local ext = paw.ext as Ext
local keymap = paw.keymap

--- A sound file that the project uses, and the clips that play it.
local record MediaItem
  path: string
  clips: {types.Clip}
end

--- An entry of the quickfix list, and its place in the list.
local record QfLine
  index: integer
  entry: QfModule.Entry
end

--- An extension: loaded or not, and whether it loaded well.
local record ExtLine
  name: string
  path: string
  loaded: boolean
  ok: boolean
  error: string
  --- What loads it, for one that waits for its first use.
  waits: {string}
end

--- A key of a table of the `paw` global: a name, or a place in a list.
local type Key = string | number

--- A value of the `paw` global, as the picker of the Lua API walks it.
local type Member = string | number | boolean | function | {Key: Member}

--- A function of the Lua API: its name, the function, and its signature.
local record Symbol
  name: string
  fn: function
  text: string
end

local record M
  type Pick = Pick
  type Sources = Sources
  type MediaItem = MediaItem
  type QfLine = QfLine
  type ExtLine = ExtLine
  type Symbol = Symbol
  metamethod __call: function(self: M, pick: Pick, S: Sources)
end

local function plural(n: integer, word: string): string
  return n .. " " .. word .. (n == 1 and "" or "s")
end

-- Help ---------------------------------------------------------------------------

local help: contracts.PickSource<HelpModule.Tag> = {
  desc = "Go to a help tag",
  title = "Help",
  items = function(): {HelpModule.Tag} return paw.help.index().list end,
  format = function(tag: HelpModule.Tag): string return string.format("%-34s %s", tag.name, tag.source.name) end,
  primary = function(tag: HelpModule.Tag): string return tag.name end,
  on_choose = function(tag: HelpModule.Tag) paw.help.jump(tag) end,
  location = function(tag: HelpModule.Tag): contracts.Location
    return {uri = "paw://help/" .. tag.source.name, selector = {line = tag.row, col = tag.col}}
  end,
  -- A page shown in a window split off this one, or in a tab of its own.
  open = function(tag: HelpModule.Tag, how: string)
    local L = paw.layout as Layout
    local buf = L.buf_create("textbuf", "help://" .. tag.source.name)
    if how == "tab" then
      L.tab_new(nil, "empty")
      L.show_in(L.current(), "textbuf", buf.id)
    else
      local made, why = L.split({vertical = how == "vsplit", view = "textbuf", buf = buf.id})
      if not made then
        paw.notify(why, "warn")
      end
    end
    paw.help.show(tag.source, tag.row, tag.col)
  end,
  preview = function(tag: HelpModule.Tag, _: integer, height: integer): {string | contracts.PageLine}
    local lines: {string | contracts.PageLine} = {}
    local doc = tag.source.doc and tag.source.doc.lines or {}
    for row = tag.row, math.min(#doc, tag.row + (height or 20)) do
      local line = doc[row]
      lines[#lines + 1] = {text = line.text, style = row == tag.row and "Title" or nil}
    end
    return lines
  end,
}

-- Markers and regions ----------------------------------------------------------

--- A picker of the markers (`kind` "marker") or of the regions ("region").
local function marker_source(kind: string): contracts.PickSource<MarkersModule.Marker>
  local region = kind == "region"
  return {
    desc = region and "Go to a region" or "Go to a marker",
    title = region and "Regions" or "Markers",
    empty = region and "No regions. `" .. keymap.human("<leader>rn") .. "` makes one over the selection or the loop."
      or "No markers. `" .. keymap.human("<leader>rm") .. "` puts one at the cursor.",
    items = function(): {MarkersModule.Marker}
      local out: {MarkersModule.Marker} = {}
      if region then
        -- As a tree: each region, then the regions inside it.
        for _, node in ipairs(paw.markers.walk()) do
          out[#out + 1] = node.region
        end
        return out
      end
      for _, m in ipairs(paw.markers.list()) do
        if not m.length then
          out[#out + 1] = m
        end
      end
      return out
    end,
    format = function(m: MarkersModule.Marker): string
      local where = paw.time.format(m.beat)
      local indent = ""
      if m.length then
        where = where .. " – " .. paw.time.format(m.beat + m.length)
        indent = string.rep("  ", (paw.markers.depth(m.id) or 1) - 1)
      end
      return string.format("%-24s %s", indent .. paw.markers.label(m), where)
    end,
    primary = function(m: MarkersModule.Marker): string return paw.markers.label(m) end,
    -- What is typed finds a name, not a number of the time: `Chorus 2`.
    search = function(m: MarkersModule.Marker): string return paw.markers.label(m) end,
    location = function(m: MarkersModule.Marker): contracts.Location
      return {uri = A.marker(m.id), selector = {time = {m.beat, m.beat}}}
    end,
    on_choose = function(m: MarkersModule.Marker)
      keymap.push_jump()
      paw.ui.focus("arrange")
      paw.cursor.set_beat(m.beat)
      local arrange = paw.ui.views:get("arrange") as contracts.ArrangeView
      if arrange.center then
        arrange:center()
      end
    end,
    delete = function(list: {MarkersModule.Marker})
      api.undo_label(region and "Remove regions" or "Remove markers")
      for _, m in ipairs(list) do
        paw.markers.remove(m.id)
      end
    end,
    preview = function(m: MarkersModule.Marker): {string | contracts.PageLine}
      local lines: {string | contracts.PageLine} = {
        {text = paw.markers.label(m), style = "Title"},
        "",
        (m.length and "region from " or "marker at ") .. paw.time.format(m.beat),
      }
      if m.length then
        lines[#lines + 1] = string.format("to %s, %g beats", paw.time.format(m.beat + m.length), m.length)
        -- Where it is in the tree of regions: `Song › Chorus 2 › Verse A`.
        lines[#lines + 1] = "in Song › " .. (paw.markers.pathname(m):gsub("/", " › "))
      end
      -- What plays there: the clips that start within a bar of it.
      lines[#lines + 1] = ""
      for _, id in ipairs(api.part_list()) do
        for _, c in ipairs(api.clip_list(id)) do
          if c.start <= m.beat + (m.length or 0) and c.start + c.length > m.beat then
            lines[#lines + 1] = string.format("  %-16s %s", api.part_get(id).name, c.name)
          end
        end
      end
      return lines
    end,
  }
end

-- Notes ------------------------------------------------------------------------

-- A note's line: pitch, velocity, lyric and articulations, where it is.
local function note_line(node: QueryModule.Node): string
  local n = node.data as types.Note
  local words: {string} = {}
  if n.lyric and n.lyric ~= "" then
    words[#words + 1] = "“" .. n.lyric .. "”"
  end
  for _, art in ipairs(paw.query.articulations(node)) do
    words[#words + 1] = art
  end
  local clip = node.parent.data as types.Clip
  return string.format(
    "%-4s %3d %-18s %-14s %s",
    paw.music.name(n.pitch),
    n.velocity,
    table.concat(words, " "),
    util.fit(clip.name, 14),
    paw.time.format(clip.start + n.start)
  )
end

local notes: contracts.PickSource<QueryModule.Node> = {
  desc = "Find a note by pitch, lyric or articulation",
  title = "Notes",
  empty = "No notes in the project.",
  items = function(): {QueryModule.Node} return paw.query.run("note") end,
  format = note_line,
  location = function(node: QueryModule.Node): contracts.Location return node.location end,
  on_choose = function(node: QueryModule.Node) keymap.push_jump(); paw.qf.go({location = node.location}) end,
  delete = function(nodes: {QueryModule.Node})
    local by_clip: {integer: {integer}} = {}
    local order: {integer} = {}
    for _, node in ipairs(nodes) do
      if not by_clip[node.clip] then
        by_clip[node.clip] = {}
        order[#order + 1] = node.clip
      end
      local list = by_clip[node.clip]
      list[#list + 1] = node.place
    end
    api.undo_label("Remove notes")
    for _, id in ipairs(order) do
      paw.clip(id):edit_notes({remove = by_clip[id]})
    end
    paw.notify("removed " .. plural(#nodes, "note"))
  end,
  preview = function(node: QueryModule.Node, width: integer, height: integer): {string | contracts.PageLine}
    local n = node.data as types.Note
    local lines: {string | contracts.PageLine} = {{text = note_line(node), style = "Title"}, ""}
    for _, line in ipairs(preview.roll(node.clip, width or preview.width(), math.max(4, (height or 20) - 4), n.id)) do
      lines[#lines + 1] = line
    end
    return lines
  end,
  -- Heard through its part: the note, with the others that start with it.
  audition_key = "notes",
  audition = function(node: QueryModule.Node): string
    local n = node.data as types.Note
    local heard: {AuditionModule.PhraseNote} = {}
    local all = api.clip_notes(node.clip)
    for _, other in ipairs(all) do
      if math.abs(other.start - n.start) < 1e-9 then
        heard[#heard + 1] = {
          pitch = other.pitch, start = 0, length = math.min(other.length, 2), velocity = other.velocity
        }
      end
    end
    paw.audition.phrase(
      node.part,
      heard,
      {
        length = math.min(n.length, 2) + 0.5,
        loop = false,
        label = paw.music.name(n.pitch),
        key = "note" .. node.clip .. ":" .. tostring(n.id),
      }
    )
    return paw.music.name(n.pitch) .. " · " .. paw.audition.through(node.part)
  end,
}

-- Media ----------------------------------------------------------------------------

local media: contracts.PickSource<MediaItem> = {
  desc = "Sound files the project uses",
  title = "Media",
  empty = "The project uses no sound files.",
  items = function(): {MediaItem}
    local out: {MediaItem} = {}
    local users: {string: {types.Clip}} = {}
    for _, id in ipairs(api.part_list()) do
      for _, c in ipairs(api.clip_list(id)) do
        if c.file then
          local key = tostring(c.file)
          users[key] = users[key] or {}
          table.insert(users[key], c)
        end
      end
    end
    local seen: {string: boolean} = {}
    for _, entry in ipairs(api.media_list()) do
      local path = tostring(entry.path)
      if not seen[path] then
        seen[path] = true
        out[#out + 1] = {path = path, clips = users[path] or {}}
      end
    end
    for path, clips in pairs(users) do
      if not seen[path] then
        out[#out + 1] = {path = path, clips = clips}
      end
    end
    table.sort(out, function(a: MediaItem, b: MediaItem): boolean return a.path < b.path end)
    return out
  end,
  format = function(f: MediaItem): string
    return string.format("%-40s %s", f.path:match("[^/]*$"), plural(#f.clips, "clip"))
  end,
  location = function(f: MediaItem): contracts.Location return f.clips[1] and {uri = A.clip(f.clips[1].id)} or nil end,
  on_choose = function(f: MediaItem)
    local part = paw.cursor.part()
    if not part then
      return paw.notify("no part selected", "warn")
    end
    part:add_clip({start = paw.cursor.beat, file = f.path})
  end,
  choose = "add at the cursor",
  audition_key = "files",
  preview = function(f: MediaItem): {string | contracts.PageLine}
    local lines: {string | contracts.PageLine} = {{text = f.path:match("[^/]*$"), style = "Title"}, f.path, ""}
    for _, c in ipairs(f.clips) do
      lines[#lines + 1] = string.format("  %-16s %s", c.name, paw.time.format(c.start))
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = {text = "Enter adds it at the cursor; Ctrl-v shows the first clip that plays it", style = "Dim"}
    return lines
  end,
}

-- Text: a live grep -----------------------------------------------------------------

-- The records come in slices after the picker opens: the notes of every
-- clip are read for their lyrics and articulations.
local grep_read: function(ms: number): {GrepModule.Found}, boolean
local grep: contracts.PickSource<GrepModule.Found> = {
  desc = "Find any text in the project: names, lyrics, articulations, comments",
  title = "Text in the project",
  empty = "The project has no text in it yet.",
  mode = "exact",
  items = function(): {GrepModule.Found} grep_read = paw.grep.reader(); return {} end,
  more = function(ms: number): {GrepModule.Found}, boolean, string
    local found, done = grep_read(ms)
    return found, done, not done and "reading…" or nil
  end,
  format = function(r: GrepModule.Found): string
    return string.format("%-8s %-28s %s", r.field, util.fit(r.where or "", 28), r.text)
  end,
  primary = function(r: GrepModule.Found): string return r.text end,
  location = function(r: GrepModule.Found): contracts.Location return r.location end,
  on_choose = function(r: GrepModule.Found) keymap.push_jump(); paw.qf.go({location = r.location}) end,
  preview = function(r: GrepModule.Found, width: integer, height: integer): {string | contracts.PageLine}
    local lines: {string | contracts.PageLine} = {
      {text = r.text, style = "Title"}, "", r.field .. " · " .. tostring(r.where or ""), ""
    }
    local parsed = r.location and A.parse(r.location.uri)
    if parsed and parsed.clip then
      local focus = parsed.kind == "note" and parsed.note or nil
      for _, line in ipairs(
        preview.clip(parsed.clip, width or preview.width(), math.max(4, (height or 20) - 5), focus)
      ) do
        lines[#lines + 1] = line
      end
    end
    return lines
  end,
}

-- The quickfix list ------------------------------------------------------------------

local quickfix: contracts.PickSource<QfLine> = {
  desc = "The entries of the quickfix list",
  title = "Quickfix",
  empty = "The quickfix list is empty.",
  items = function(): {QfLine}
    local list = paw.qf.current()
    local out: {QfLine} = {}
    for i, e in ipairs(list and list.entries or {}) do
      out[i] = {index = i, entry = e}
    end
    return out
  end,
  format = function(x: QfLine): string
    local e = x.entry
    return string.format("%-24s %s%s", util.fit(paw.qf.where(e), 24), e.level and e.level .. ": " or "", e.text)
  end,
  location = function(x: QfLine): contracts.Location return x.entry.location end,
  on_choose = function(x: QfLine) paw.qf.jump(x.index) end,
}

-- Undo states ---------------------------------------------------------------------

local function ago(t: number): string
  local s = math.max(0, os.time() - (tonumber(t) or os.time()))
  if s < 60 then
    return s .. " s ago"
  end
  if s < 3600 then
    return math.floor(s / 60) .. " min ago"
  end
  return os.date("%H:%M", math.floor(t))
end

local undo: contracts.PickSource<types.UndoState> = {
  desc = "Go to a state of the undo history",
  title = "Undo history",
  items = function(): {types.UndoState}
    local tree = api.undo_tree()
    local out: {types.UndoState} = {}
    for _, s in ipairs(tree.states) do
      out[#out + 1] = s
    end
    table.sort(out, function(a: types.UndoState, b: types.UndoState): boolean return a.id > b.id end)
    return out
  end,
  format = function(s: types.UndoState): string
    local mark = s.current and "●" or s.saved and "S" or " "
    local label = s.name or s.label or (s.parent and "edit" or "the project as opened")
    return string.format("%s #%-4d %-34s %s", mark, s.id, util.fit(tostring(label), 34), ago(s.time))
  end,
  choose = "go there",
  on_choose = function(s: types.UndoState) api.undo_goto(s.id); paw.notify("at state #" .. s.id) end,
  preview = function(s: types.UndoState): {string | contracts.PageLine}
    local current = api.undo_current()
    local lines: {string | contracts.PageLine} = {
      {text = string.format("#%d  %s", s.id, tostring(s.name or s.label or "")), style = "Title"}
    }
    if s.keys and s.keys ~= "" then
      lines[#lines + 1] = "keys    " .. s.keys
    end
    lines[#lines + 1] = ""
    if s.id == current then
      lines[#lines + 1] = {text = "the state the project is in", style = "Dim"}
      return lines
    end
    local ok, diff = pcall(api.undo_diff, current, s.id) as (boolean, types.UndoDiff)
    if ok and diff then
      lines[#lines + 1] = {text = "going there changes:", style = "HelpSection"}
      for _, item in ipairs(diff.items or {}) do
        lines[#lines + 1] = {
          text = item, style = item:sub(1, 1) == "+" and "Info" or item:sub(1, 1) == "-" and "Warn" or nil
        }
      end
    end
    return lines
  end,
}

-- Extensions ----------------------------------------------------------------------

local function readme(path: string, rows: integer): {string}
  local file = path and io.open(path .. "/README.md", "rb")
  if not file then
    return {}
  end
  local out: {string} = {}
  for line in file:lines() do
    if #out >= rows then
      break
    end
    out[#out + 1] = line
  end
  file:close()
  return out
end

local extensions: contracts.PickSource<ExtLine> = {
  desc = "Extensions: loaded, and those that come with the program",
  title = "Extensions",
  items = function(): {ExtLine}
    local out: {ExtLine} = {}
    local seen: {string: boolean} = {}
    for _, e in ipairs(ext.list()) do
      seen[e.name] = true
      out[#out + 1] = {name = e.name, path = e.path, loaded = true, ok = e.ok, error = e.error}
    end
    for _, w in ipairs(ext.lazy.list()) do
      if not seen[w.name] then
        seen[w.name] = true
        out[#out + 1] = {name = w.name, path = w.path, loaded = false, waits = ext.lazy.describe(w.name)}
      end
    end
    local dir = ext.bundled_dir()
    for _, name in ipairs(ext.bundled()) do
      if not seen[name] then
        out[#out + 1] = {name = name, path = dir and dir .. "/" .. name, loaded = false}
      end
    end
    return out
  end,
  format = function(e: ExtLine): string
    local state = e.waits and "waits for " .. table.concat(e.waits, ", ")
      or not e.loaded and "not loaded"
      or e.ok and "loaded"
      or "failed"
    return string.format("%-14s %s", e.name, state)
  end,
  primary = function(e: ExtLine): string return e.name end,
  choose = "help, or load",
  on_choose = function(e: ExtLine)
    if e.loaded then
      paw.help.open(e.name)
      return
    end
    local entry, why: contracts.ExtEntry, string
    if e.waits then
      entry = ext.lazy.load(e.name, "the extension picker")
    else
      entry, why = ext.load_bundled(e.name, "the extension picker")
    end
    if not entry then
      return paw.notify(why, "warn")
    end
    paw.notify(entry.ok and "loaded " .. e.name or e.name .. " failed to load", entry.ok and "info" or "error")
  end,
  preview = function(e: ExtLine, _: integer, height: integer): {string | contracts.PageLine}
    local lines: {string | contracts.PageLine} = {{text = e.name, style = "Title"}, tostring(e.path or ""), ""}
    if e.error then
      lines[#lines + 1] = {text = tostring(e.error):match("^[^\n]*"), style = "Error"}
    end
    for _, line in ipairs(readme(e.path, (height or 20) - #lines)) do
      lines[#lines + 1] = line
    end
    return lines
  end,
}

-- The Lua API -------------------------------------------------------------------------

local files: {string: {string}} = {}

--- The lines of a source file, read once; none when it does not open.
local function lines_of(path: string): {string}
  local lines = files[path]
  if not lines then
    lines = {}
    local file = io.open(path, "rb")
    if file then
      for line in file:lines() do
        lines[#lines + 1] = line
      end
      file:close()
    end
    files[path] = lines
  end
  return lines
end

--- The comment right above a function's definition, from its source file.
local function doc_of(fn: function): {string}, string, integer
  local info = debug.getinfo(fn, "S")
  local path = info and info.source and info.source:match("^@(.+)$")
  if not path or info.linedefined < 1 then
    return nil
  end
  -- The Lua that Teal makes has no comments, and keeps the lines of the .tl.
  -- The built runtime gives the .tl as the source. A runtime that
  -- tools/dev-runtime.sh makes loads the .lua, with the .tl beside it.
  local teal = path:gsub("%.lua$", ".tl")
  if teal ~= path and #lines_of(teal) > 0 then
    path = teal
  end
  local lines = lines_of(path)
  local out: {string} = {}
  local row = info.linedefined - 1
  while row >= 1 and lines[row] and lines[row]:match("^%s*%-%-") do
    table.insert(out, 1, (lines[row]:gsub("^%s*%-%-%-?%s?", "")))
    row = row - 1
  end
  return out, path:match("runtime/lua/(.*)$") or path, info.linedefined
end

--- `name(a, b)`: a function with the names of its parameters.
local function signature(name: string, fn: function): string
  local params: {string} = {}
  for i = 1, 16 do
    local ok, p = pcall(debug.getlocal, fn, i) as (boolean, string)
    if not ok or not p then
      break
    end
    params[#params + 1] = p
  end
  local info = debug.getinfo(fn, "u")
  if info and info.isvararg then
    params[#params + 1] = "..."
  end
  return name .. "(" .. table.concat(params, ", ") .. ")"
end

local SKIP: {string: boolean} = {_kernel = true, state = true, opt = true}

local symbols: contracts.PickSource<Symbol> = {
  desc = "The Lua API: every function of `paw`",
  title = "Lua API",
  items = function(): {Symbol}
    local out: {Symbol} = {}
    local function add(name: string, fn: function)
      out[#out + 1] = {name = name, fn = fn, text = signature(name, fn)}
    end
    -- The global as Lua has it: each value of it, by name.
    local global = paw as {Key: Member}
    local names: {string} = {}
    for k in pairs(global) do
      if k is string and not SKIP[k] then
        names[#names + 1] = k
      end
    end
    table.sort(names)
    for _, k in ipairs(names) do
      local v = rawget(global, k) as Member
      if v is function then
        add("paw." .. k, v)
      elseif v is {Key: Member} then
        local inner: {string} = {}
        for k2, v2 in pairs(v) do
          if k2 is string and v2 is function and k2:sub(1, 1) ~= "_" then
            inner[#inner + 1] = k2
          end
        end
        table.sort(inner)
        for _, k2 in ipairs(inner) do
          add("paw." .. k .. "." .. k2, v[k2] as function)
        end
      end
    end
    return out
  end,
  format = function(s: Symbol): string return s.text end,
  primary = function(s: Symbol): string return s.name end,
  choose = "help",
  on_choose = function(s: Symbol)
    local tag = paw.help.lookup(s.name)
    if tag and tag.name:find(s.name, 1, true) then
      paw.help.jump(tag)
      return
    end
    local doc, where, line = doc_of(s.fn)
    local lines: {string | contracts.PageLine} = {{text = s.text, style = "Title"}, ""}
    for _, l in ipairs(doc or {"(no comment above it)"}) do
      lines[#lines + 1] = l
    end
    if where then
      lines[#lines + 1] = ""
      lines[#lines + 1] = {text = where .. ":" .. line, style = "Dim"}
    end
    paw.ui.page(s.name, lines)
  end,
  insert = function(s: Symbol)
    local opts: InputOptions = {prompt = ":", history = "cmdline", text = "lua " .. s.name .. "("}
    paw.ui.input(
      opts,
      function(line: string)
        if line:match("%S") then
          paw.commands.exec(line)
        end
      end
    )
  end,
  preview = function(s: Symbol): {string | contracts.PageLine}
    local lines: {string | contracts.PageLine} = {{text = s.text, style = "Title"}, ""}
    local doc, where, line = doc_of(s.fn)
    if not doc then
      lines[#lines + 1] = {text = "a function of the kernel (docs/reference/api.md)", style = "Dim"}
      return lines
    end
    for _, l in ipairs(#doc > 0 and doc or {"(no comment above it)"}) do
      lines[#lines + 1] = l
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = {text = where .. ":" .. line, style = "Dim"}
    return lines
  end,
}

--- Add the pickers of this module to `S`, the sources of `pick`.
local function add(pick: Pick, S: Sources)
  -- Heard, from the picker's own module: a sound file, or a MIDI file's first bars.
  media.audition = function(f: MediaItem): string return pick.hear_file(f.path) end
  S.help = help
  S.markers = marker_source("marker")
  S.regions = marker_source("region")
  S.notes = notes
  S.media = media
  S.grep = grep
  S.quickfix = quickfix
  S.undo = undo
  S.extensions = extensions
  S.symbols = symbols
  -- The presets of the device under the cursor, as `:preset` opens them.
  S.presets = function(_: contracts.PickExtra): contracts.PickInfo paw.fx.pick(); return nil end
end

return setmetatable({} as M, {__call = function(_: M, pick: Pick, S: Sources) add(pick, S) end} as metatable<M>)
