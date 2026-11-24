-- The pickers that come with the runtime. Each is a table of the fields
-- `paw.pick` takes, with a `desc`, or a function that returns one; add your
-- own with `paw.pick.sources:put(name, source)`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua. paw/pick.tl
-- calls this module with itself: `require("paw.pick.sources")(pick)`.
local api = require("paw.api")
local util = require("paw.util")
local options = require("paw.options")
local project = require("paw.pick.project")
local preview = require("paw.pick.preview")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type UiModule = require("paw.ui")
local type PanesModule = require("paw.panes")
local type objects = require("paw.objects")
local type CommandsModule = require("paw.commands")
local type CursorModule = require("paw.cursor")
local type HelpModule = require("paw.help")
local type AuditionModule = require("paw.audition")
local type MidifileModule = require("paw.midifile")
local type MusicModule = require("paw.music")
local type AddressModule = require("paw.address")
local type FrontendModule = require("paw.frontend")

local opt = options.opt

--- What these pickers call of `paw.pick` (paw/pick.tl, which requires this
--- module): its sources, hearing a file, and opening a picker by name.
local interface Pick is project.Pick
  metamethod __call: function(self: Pick, name: string, extra?: contracts.PickExtra)
end

--- The built-in pickers by name, which paw/pick.tl puts in `paw.pick.sources`.
local type Sources = project.Sources

--- A key mapping (paw/keymap.tl).
local type Map = KeymapModule.Map

--- A mapping with what kind of key it is, as `paw.keymap.all` gives it.
local type KeyAll = KeymapModule.KeyAll

--- What a register holds: keys (a macro), parts, a stretch of time,
--- notes or a device.
local record Register is KeymapModule.Register
  record Named
    name: string
  end
  record Device
    kind: string
  end
  keys: string
  parts: {Named}
  rows: {{integer}}
  length: number
  notes: {types.Note}
  device: Device
end

--- The parts in scope (paw/scope.tl): what this module calls of it.
local record Scope
  parts: function(): {integer}
end

--- A device that can be added, as paw/fx.lua lists it: a device type,
--- whether it is a favourite, and the extension it came with.
local record DeviceInfo
  kind: string
  name: string
  category: string
  format: string
  vendor: string
  params: {types.ParamInfo}
  favourite: boolean
  recent: integer
  from: string
end

--- What `paw.fx.add` and `added` take besides the part and the kind.
local record AddOptions
  query: string
end

--- The devices (paw/fx.lua, in Lua): what this module calls of them.
local record Fx
  preferred: function(part_id: integer): string
  device_list: function(wanted: string): {DeviceInfo}
  device_line: function(info: DeviceInfo): string
  rank: function(info: DeviceInfo, query: string, line: string, wanted: string): number
  add: function(part: objects.Part, kind: string, opts?: AddOptions): objects.Device
  place: function(part: objects.Part, kind: string): types.Device
  added: function(device: types.Device, kind: string, opts?: AddOptions)
  toggle_favourite: function(kind: string)
end

--- The inspector (paw/views/inspector.lua, in Lua): what this module calls of it.
local record DevicesView
  show: function(self: DevicesView, device: integer, key?: string): integer
end

--- A message of the program (`paw.ui.messages`).
local record Message
  level: string
  text: string
end

local type InputOptions = UiModule.InputOptions

local record Paw is partial.Paw
  keymap: KeymapModule
  ui: UiModule
  commands: CommandsModule
  cursor: CursorModule
  help: HelpModule
  audition: AuditionModule
  midifile: MidifileModule
  music: MusicModule
  address: AddressModule
  time: objects.Time
  project: objects.Project
  frontend: FrontendModule
  scope: Scope
  panes: PanesModule
  fx: Fx
  open: function(path: string)
  state: {string: util.Data}
end
local paw = (_G as {string: Paw}).paw
local keymap = paw.keymap

--- A line of the picker of pickers.
local record PickerLine
  name: string
  desc: string
end

--- A key of the keys picker: its mapping and kind, how it is written, what
--- it does and where (`tag`), and the view it belongs to when that is not
--- the focused one (`other`).
local record KeyLine
  map: Map
  kind: string
  other: string
  human: string
  desc: string
  tag: string
  humans: {string: boolean}
end

--- A part of the parts picker.
local record PartLine
  id: integer
  index: integer
  name: string
end

--- A clip of the clips picker.
local record ClipLine
  id: integer
  part: integer
  part_name: string
  name: string
  start: number
  length: number
  kind: types.ClipKind
end

--- A device on the part.
local record DeviceLine
  id: integer
  index: integer
  name: string
  kind: string
  bypass: boolean
end

--- A mark: its name, its view and where it is.
local record MarkLine
  name: string
  view: string
  where: string
end

--- A register: its name and what it holds.
local record RegisterLine
  name: string
  value: Register
end

--- A file under the current directory: a project, audio or MIDI.
local record FileLine
  path: string
  kind: string
end

--- A key with the place it had among the keys of a command, to sort them.
local record Numbered
  key: string
  n: integer
end

local record M
  type Pick = Pick
  type Sources = Sources
  type Map = Map
  type KeyAll = KeyAll
  type DeviceInfo = DeviceInfo
  type PickerLine = PickerLine
  type KeyLine = KeyLine
  type PartLine = PartLine
  type ClipLine = ClipLine
  type DeviceLine = DeviceLine
  type MarkLine = MarkLine
  type RegisterLine = RegisterLine
  type FileLine = FileLine
  --- The project, audio and MIDI files under a directory, walking at
  --- most `limit` entries: what the files picker lists.
  walk: function(root: string, limit: integer, depth?: integer): {FileLine}
  metamethod __call: function(self: M, pick: Pick): Sources
end

local function need_part(): objects.Part
  local part = paw.cursor.part()
  if not part then
    paw.notify("no part selected", "warn")
  end
  return part
end

local function plural(n: integer, word: string): string
  return n .. " " .. word .. (n == 1 and "" or "s")
end

-- The command a mapping runs, when it runs one.
local function command_of(map: Map): string
  local rhs = map.rhs
  if rhs is string then
    return rhs:match("^(%S+)")
  end
  return nil
end

-- A key as its human name, without the view in brackets.
local function human_of(key: string): string
  return keymap.human((key:gsub(" %(.*%)$", "")))
end

--- Every key that runs a command, by the command's name: lists of
--- `lhs` strings, with the view in brackets for a view's own.
local function key_index(): {string: {string}}
  local index: {string: {string}} = {}
  local held: {string: {string: boolean}} = {}
  for _, mode in ipairs({"n", "x"} as {KeymapModule.Mode}) do
    for _, scope in ipairs({paw.ui.focused, "arrange", "pianoroll", "devices", "mixer"}) do
      for _, map in ipairs(keymap.list(mode, scope)) do
        local name = command_of(map)
        if name then
          local key = map.lhs .. (map.scope ~= "global" and " (" .. map.scope .. ")" or "")
          local list = index[name] or {}
          index[name] = list
          local has = held[name] or {}
          held[name] = has
          if not has[key] then
            has[key] = true
            list[#list + 1] = key
          end
        end
      end
    end
  end
  -- The shortest key first: `u` before `Ctrl-z`.
  for _, list in pairs(index) do
    local numbered: {Numbered} = {}
    for i, key in ipairs(list) do
      numbered[i] = {key = key, n = i}
    end
    table.sort(
      numbered,
      function(a: Numbered, b: Numbered): boolean
        local la, lb = #human_of(a.key), #human_of(b.key)
        if la ~= lb then
          return la < lb
        end
        return a.n < b.n
      end
    )
    for i, entry in ipairs(numbered) do
      list[i] = entry.key
    end
  end
  return index
end

local keys_now: {string: {string}} = {}

--- Keys that run a command, as `lhs` strings.
local function keys_for(name: string): {string}
  return keys_now[name] or {}
end

--- The commands the focused view has keys of its own for, by name.
local function view_commands(): {string: boolean}
  local out: {string: boolean} = {}
  local view = paw.ui.focused
  for _, mode in ipairs({"n", "x"} as {KeymapModule.Mode}) do
    for _, map in ipairs(keymap.list(mode, view)) do
      local name = command_of(map)
      if map.scope == view and name then
        out[name] = true
      end
    end
  end
  return out
end

local view_set: {string: boolean} = {}

local function edit_command(spec: CommandsModule.Spec)
  local opts: InputOptions = {prompt = ":", history = "cmdline", text = spec.name .. " "}
  paw.ui.input(
    opts,
    function(line: string)
      if line:match("%S") then
        paw.state.last_cmdline = line
        paw.commands.used(line:match("^%s*:?(%S+)"))
      end
      paw.commands.exec(line)
    end
  )
end

-- Key mappings -------------------------------------------------------------------

-- What a key is for, in a few letters: where it works and what kind it is.
local kind_tags: {string: string} = {
  motion = "motion", operator = "operator", object = "object", visual = "visual", insert = "insert"
}

local function key_tag(entry: KeyLine): string
  if entry.other then
    return entry.other .. " view"
  end
  local where = entry.map.scope == "global" and "global" or entry.map.scope:gsub("^%a+%.", "")
  local kind = kind_tags[entry.kind]
  return kind and where .. " " .. kind or where
end

--- Run a mapping chosen in the keys picker, as if its keys were typed.
local function run_key(entry: KeyLine)
  local map = entry.map
  if entry.other then
    paw.ui.focus(entry.other)
    return paw.notify(keymap.human(map.lhs) .. " is a key of the " .. entry.other .. " view, which has the keys now")
  end
  if entry.kind == "object" then
    return paw.notify(
      keymap.human(map.lhs) .. " names a region: type it after an operator such as `d` or `y`, or in a selection"
    )
  end
  if entry.kind == "insert" then
    return paw.notify(keymap.human(map.lhs) .. " works in insert mode: `i` first")
  end
  if entry.kind == "visual" and keymap.mode ~= "x" then
    return paw.notify(keymap.human(map.lhs) .. " acts on a selection: `v` or `V` first")
  end
  keymap.normal(map.lhs)
end

-- Parts and clips ---------------------------------------------------------------

local function part_name(id: integer): string
  local ok, t = pcall(api.part_get, id) as (boolean, types.Part)
  return ok and t.name or "?"
end

-- The arrange view, centred on the cursor when it can be.
local function center()
  local arrange = paw.ui.views:get("arrange") as contracts.ArrangeView
  if arrange.center then
    arrange:center()
  end
end

-- Devices ------------------------------------------------------------------------

--- What a register holds, in a line.
local function describe(value: Register): string
  if value.kind == "keys" then
    return "macro   " .. value.keys
  end
  if value.kind == "parts" then
    local list: {string} = {}
    for i, t in ipairs(value.parts) do
      list[i] = t.name
    end
    return "parts  " .. table.concat(list, ", ")
  end
  if value.kind == "range" then
    local clips = 0
    for _, row in ipairs(value.rows) do
      clips = clips + #row
    end
    return string.format("time    %g beats on %s, %s", value.length, plural(#value.rows, "part"), plural(clips, "clip"))
  end
  if value.kind == "notes" then
    return string.format("notes   %d over %g beats", #value.notes, value.length)
  end
  if value.kind == "device" then
    return "device  " .. tostring(value.device.kind)
  end
  return tostring(value.kind)
end

-- Files --------------------------------------------------------------------------

local audio_ext: {string: boolean} = {
  wav = true, wave = true, aif = true, aiff = true, flac = true, mp3 = true, ogg = true
}
local function is_project(path: string): boolean
  local file = io.open(path, "rb")
  if not file then
    return false
  end
  local head = file:read(200) or ""
  file:close()
  return head:find('"version"', 1, true) ~= nil and head:find('"project"', 1, true) ~= nil
end

--- Names that `.gitignore` of `root` gives as plain names: `build`, `out/`.
--- Patterns with a slash in the middle or a wildcard are left out: a cheap
--- reading, not git's.
local function ignored_by(root: string): {string: boolean}
  local out: {string: boolean} = {}
  local file = io.open(root .. "/.gitignore", "r")
  if not file then
    return out
  end
  for line in file:lines() do
    local name = line:match("^/?([^/*?%[!#%s][^/*?%[%s]*)/?%s*$")
    if name then
      out[name] = true
    end
  end
  file:close()
  return out
end

--- A folder waiting to be read: where it is, the prefix of its files, its depth.
local record WalkDir
  dir: string
  prefix: string
  depth: integer
end

--- A walk of the project, audio and MIDI files under `root`, in slices:
--- `step(ms)` reads directories, level by level, until `ms` pass, and
--- returns the files found and whether the walk is over. `stopped` is the
--- option of the limit that stopped it, or nil.
local record Walk
  step: function(ms: number): {FileLine}, boolean
  stopped: string
  seen: integer
end

--- Start a walk. `depth` is how many folders deep it goes, `limit` how many
--- entries it reads, `skip` the folder names it leaves out; it leaves out
--- the names a `.gitignore` of `root` gives too.
local function start_walk(root: string, limit: integer, depth: integer, skip: {string | number}): Walk
  local leave: {string: boolean} = ignored_by(root)
  for _, name in ipairs(skip) do
    leave[tostring(name)] = true
  end
  local queue: {WalkDir} = {{dir = root, prefix = root == "." and "" or root .. "/", depth = 0}}
  local head, tail = 1, 1
  local w: Walk = {seen = 0}
  w.step = function(ms: number): {FileLine}, boolean
    local out: {FileLine} = {}
    -- A budget of work: on the wall clock.
    local deadline = api.real_ms() + ms
    while head <= tail do
      local item = queue[head]
      queue[head] = nil
      head = head + 1
      for _, entry in ipairs(api.read_dir(item.dir)) do
        w.seen = w.seen + 1
        if w.seen > limit then
          w.stopped = "files_limit"
          return out, true
        end
        local name = entry.name
        local path = item.prefix .. name
        if entry.is_dir then
          if name:sub(1, 1) ~= "." and not leave[name] then
            if item.depth < depth then
              tail = tail + 1
              queue[tail] = {dir = item.dir .. "/" .. name, prefix = path .. "/", depth = item.depth + 1}
            else
              w.stopped = w.stopped or "files_depth"
            end
          end
        else
          local ext = (name:match("%.([^.]+)$") or ""):lower()
          if audio_ext[ext] then
            out[#out + 1] = {path = path, kind = "audio"}
          elseif paw.midifile.is_midi_file(name) then
            out[#out + 1] = {path = path, kind = "midi"}
          elseif ext == "json" and is_project(item.dir .. "/" .. name) then
            out[#out + 1] = {path = path, kind = "project"}
          end
        end
      end
      if api.real_ms() >= deadline then
        return out, false
      end
    end
    return out, true
  end
  return w
end

--- Project and audio files under `root`, all at once (a test or a script
--- wants the whole list): at most `limit` entries, `depth` folders deep.
local function walk(root: string, limit: integer, depth?: integer): {FileLine}
  local w = start_walk(root, limit, depth or 8, opt.files_skip)
  local out: {FileLine} = {}
  repeat
    local more, done = w.step(1e9)
    for _, f in ipairs(more) do
      out[#out + 1] = f
    end
  until done
  return out
end

-- Messages -----------------------------------------------------------------------

local levels: {string: string} = {info = "Normal", warn = "Warn", error = "Error"}

--- The pickers, for `pick`.
local function make(pick: Pick): Sources
  local S: Sources = {}

  -- Pickers ------------------------------------------------------------------------

  local pickers: contracts.PickSource<PickerLine> = {
    desc = "Every picker",
    title = "Pickers",
    items = function(): {PickerLine}
      local out: {PickerLine} = {}
      for name, source in pairs(pick.sources:entries()) do
        if name ~= "pickers" and not name:match("^_") then
          local desc = ""
          if source is contracts.PickInfo then
            desc = source.desc or source.title
          end
          out[#out + 1] = {name = name, desc = desc}
        end
      end
      table.sort(out, function(a: PickerLine, b: PickerLine): boolean return a.name < b.name end)
      return out
    end,
    format = function(s: PickerLine): string return string.format("%-14s %s", s.name, s.desc) end,
    on_choose = function(s: PickerLine) pick(s.name) end,
  }
  S.pickers = pickers

  -- Commands -----------------------------------------------------------------------

  local commands: contracts.PickSource<CommandsModule.Spec> = {
    desc = "Run a command",
    title = "Commands",
    items = function(): {CommandsModule.Spec}
      keys_now = key_index()
      view_set = view_commands()
      return paw.commands.list()
    end,
    format = function(spec: CommandsModule.Spec): string
      local keys = keys_for(spec.alias_of or spec.name)
      local key = keys[1] and human_of(keys[1]) or ""
      return string.format("%-24s %-10s %s", spec.name, key, spec.alias_of and "→ " .. spec.alias_of or spec.desc)
    end,
    primary = function(spec: CommandsModule.Spec): string return spec.name end,
    -- Commands used before come first, and those the focused view has keys for.
    boost = function(spec: CommandsModule.Spec): number
      local name = spec.alias_of or spec.name
      return math.min(paw.commands.uses(name), 10) * 8 + (view_set[name] and 40 or 0)
    end,
    on_choose = function(spec: CommandsModule.Spec)
      paw.state.last_cmdline = spec.name
      paw.commands.used(spec.name)
      paw.commands.run(spec.name)
    end,
    actions = {
      ["<C-e>"] = {
        fn = function(spec: CommandsModule.Spec)
          if spec then
            edit_command(spec)
          end
        end,
        desc = "edit arguments",
      },
      ["<C-]>"] = {
        fn = function(spec: CommandsModule.Spec)
          if spec then
            paw.help.for_command(spec.alias_of or spec.name)
          end
        end,
        desc = "help",
      },
    },
    preview = function(spec: CommandsModule.Spec): {string | contracts.PageLine}
      local lines: {string | contracts.PageLine} = {{text = spec.name, style = "Title"}, ""}
      for line in (spec.desc ~= "" and spec.desc or "(no description)"):gmatch("[^\n]+") do
        lines[#lines + 1] = line
      end
      if spec.alias_of then
        lines[#lines + 1] = "Another name for " .. spec.alias_of
      end
      local keys = keys_for(spec.alias_of or spec.name)
      if #keys > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = {text = "Keys", style = "HelpSection"}
        for _, key in ipairs(keys) do
          local lhs, where = key:match("^(.-)( %(.*%))$")
          lines[#lines + 1] = "  " .. keymap.human(lhs or key) .. (where or "")
        end
      end
      lines[#lines + 1] = ""
      lines[#lines + 1] = {text = "C-e types it on the command line, for arguments", style = "Dim"}
      return lines
    end,
  }
  S.commands = commands

  S.keys = function(_: contracts.PickExtra): contracts.PickInfo
    local view = paw.ui.focused
    -- The picker is as wide as the screen allows, the list on the left
    -- and, beside it, the help of the key chosen.
    -- (A window's main area is wider than the screen the kernel keeps for it.)
    local cells = paw.panes.cells()
    local total = math.min(150, math.max((api.ui_size()), cells and cells.w as integer or 0) - 4)
    local list_w = math.floor(total * 0.6)
    local preview_w = total - list_w - 3
    local cols = {key = 8, tag = 4, desc = 10}
    local keys: contracts.PickSource<KeyLine> = {
      desc = "Every key that works in the focused view",
      title = "Keys · " .. tostring(view),
      empty = "No keys are mapped here.",
      width = total,
      choose = "run",
      -- The view's own keys before the global ones, and those before the keys of other views.
      boost = function(entry: KeyLine): number
        return entry.other and 0 or entry.map.scope == "global" and 20 or 40
      end,
      items = function(): {KeyLine}
        -- Ranked rather than alphabetical: what the view itself adds, then
        -- what works everywhere; plain keys before motions, operators and
        -- the rest; short keys before long ones.
        local rank: {string: integer} = {key = 1, operator = 2, motion = 3, object = 4, visual = 5, insert = 6}
        local out: {KeyLine} = {}
        local seen: {string: KeyLine} = {}
        for _, given in ipairs(keymap.all(view)) do
          local map = given.map
          local rhs = map.rhs
          local entry: KeyLine = {
            map = map,
            kind = given.kind,
            human = keymap.human(map.lhs),
            desc = map.desc or (rhs is string and rhs) or "(no description)",
          }
          entry.tag = key_tag(entry)
          -- Keys that do the same thing in the same place are one line.
          local same = entry.tag .. "\t" .. entry.desc .. "\t" .. tostring(map.rhs)
          local first = seen[same]
          if first then
            if not first.humans[entry.human] then
              first.humans[entry.human] = true
              first.human = first.human .. ", " .. entry.human
            end
          else
            entry.humans = {[entry.human] = true}
            seen[same] = entry
            out[#out + 1] = entry
          end
        end
        table.sort(
          out,
          function(a: KeyLine, b: KeyLine): boolean
            local ga, gb = a.map.scope == "global" and 1 or 0, b.map.scope == "global" and 1 or 0
            if ga ~= gb then
              return ga < gb
            end
            if rank[a.kind] ~= rank[b.kind] then
              return (rank[a.kind] or 9) < (rank[b.kind] or 9)
            end
            if #a.map.keys ~= #b.map.keys then
              return #a.map.keys < #b.map.keys
            end
            local la, lb = a.map.lhs:match("^%a") and 0 or 1, b.map.lhs:match("^%a") and 0 or 1
            if la ~= lb then
              return la < lb
            end
            return a.map.lhs:lower() .. a.map.lhs < b.map.lhs:lower() .. b.map.lhs
          end
        )
        -- After them, the keys of the other views, so that a search for what
        -- a key does finds it wherever it works: `send` in the mixer finds
        -- the arrange view's `<leader>ts`.
        local names: {string} = {}
        for name, v in pairs(paw.ui.views:entries()) do
          if name ~= view and v.focusable ~= false and not v.modal then
            names[#names + 1] = name
          end
        end
        table.sort(names)
        for _, name in ipairs(names) do
          for _, map in ipairs(keymap.list("n", name)) do
            if map.scope == name and not map.motion and map.desc then
              local entry: KeyLine = {
                map = map, kind = "key", other = name, human = keymap.human(map.lhs), desc = map.desc
              }
              entry.tag = key_tag(entry)
              out[#out + 1] = entry
            end
          end
        end
        -- The columns are as wide as what they hold, the description
        -- keeping what the others leave.
        local longest = 0
        cols.key, cols.tag = 8, 4
        for _, e in ipairs(out) do
          cols.key = math.max(cols.key, math.min(14, api.str_width(e.human)))
          cols.tag = math.max(cols.tag, api.str_width(e.tag))
          longest = math.max(longest, api.str_width(e.desc))
        end
        cols.desc = math.max(10, math.min(longest, list_w - 3 - cols.key - cols.tag - 2))
        return out
      end,
      format = function(e: KeyLine): string
        return util.fit(e.human, cols.key) .. " " .. util.fit(e.desc, cols.desc) .. " " .. e.tag
      end,
      -- What the manual says of the key, or what it is for.
      preview = function(e: KeyLine): {string | contracts.PageLine}
        local excerpt = paw.help.excerpt_for_map(e.map, preview_w, 24)
        if excerpt then
          return excerpt as {string | contracts.PageLine}
        end
        return {
          {text = e.human, style = "HelpKey"},
          "",
          e.desc,
          "",
          {text = "the manual has nothing on it yet", style = "Dim"},
        }
      end,
      primary = function(e: KeyLine): string return e.human end,
      -- The whole description, not the part that the width leaves.
      search = function(e: KeyLine): string return e.human .. " " .. e.desc .. " " .. e.tag end,
      on_choose = run_key,
      actions = {
        ["<C-]>"] = {
          fn = function(e: KeyLine)
            if e then
              paw.help.for_map(e.map)
            end
          end,
          desc = "help",
        },
      },
    }
    return keys
  end

  -- Parts and clips ---------------------------------------------------------------

  local parts: contracts.PickSource<PartLine> = {
    desc = "Go to a part",
    title = "Parts",
    items = function(): {PartLine}
      local out: {PartLine} = {}
      for i, id in ipairs(paw.scope.parts()) do
        out[#out + 1] = {id = id, index = i, name = part_name(id)}
      end
      return out
    end,
    format = function(t: PartLine): string return string.format("%2d  %s", t.index, t.name) end,
    location = function(t: PartLine): string return paw.address.part(t.id) end,
    on_choose = function(t: PartLine) keymap.push_jump(); paw.cursor.set_part(t.id); center() end,
    delete = function(list: {PartLine})
      api.undo_label(#list == 1 and "Remove the part" or "Remove parts")
      for _, t in ipairs(list) do
        if pcall(api.part_get, t.id) then
          api.part_remove(t.id)
        end
      end
    end,
    -- What the part plays around the cursor, heard when asked for.
    audition_key = "parts",
    audition_default = false,
    audition = function(t: PartLine): string return t.name .. " · " .. paw.audition.through(t.id) end,
    preview = function(t: PartLine): {string | contracts.PageLine}
      local info = api.part_get(t.id)
      local lines: {string | contracts.PageLine} = {{text = info.name, style = "Title"}, ""}
      lines[#lines + 1] = string.format(
        "volume %+.1f dB, pan %+.2f%s%s",
        info.volume,
        info.pan,
        info.mute and ", muted" or "",
        info.solo and ", solo" or ""
      )
      lines[#lines + 1] = "output  " .. (info.output and part_name(info.output) or "Master")
      for i, id in ipairs(info.devices) do
        lines[#lines + 1] = string.format("%d. %s", i, api.device_get(id).name)
      end
      local clips = api.clip_list(t.id)
      lines[#lines + 1] = ""
      lines[#lines + 1] = plural(#clips, "clip")
      for _, c in ipairs(clips) do
        lines[#lines + 1] = string.format("  %-10s %s", paw.time.format(c.start), c.name)
      end
      return lines
    end,
  }
  S.parts = parts

  local clips: contracts.PickSource<ClipLine> = {
    desc = "Go to a clip",
    title = "Clips",
    items = function(): {ClipLine}
      local out: {ClipLine} = {}
      for _, id in ipairs(paw.scope.parts()) do
        local name = part_name(id)
        for _, c in ipairs(api.clip_list(id)) do
          out[#out + 1] = {
            id = c.id, part = id, part_name = name, name = c.name, start = c.start, length = c.length, kind = c.kind
          }
        end
      end
      return out
    end,
    format = function(c: ClipLine): string
      return string.format("%-20s %-14s %s", c.name, c.part_name, paw.time.format(c.start))
    end,
    location = function(c: ClipLine): string return paw.address.clip(c.id) end,
    on_choose = function(c: ClipLine)
      keymap.push_jump()
      paw.ui.focus("arrange")
      paw.cursor.set_part(c.part)
      paw.cursor.set_beat(c.start)
      local arrange = paw.ui.views:get("arrange") as contracts.ArrangeView
      arrange:center()
    end,
    delete = function(list: {ClipLine})
      api.undo_label(#list == 1 and "Remove the clip" or "Remove clips")
      for _, c in ipairs(list) do
        if pcall(api.clip_get, c.id) then
          api.clip_remove(c.id)
        end
      end
    end,
    -- A MIDI clip's notes drawn as a small piano roll, an audio clip's sound.
    preview = function(c: ClipLine, width: integer, height: integer): {string | contracts.PageLine}
      local info = api.clip_get(c.id)
      local lines: {string | contracts.PageLine} = {
        {text = info.name, style = "Title"},
        "part   " .. c.part_name,
        string.format(
          "from    %s to %s, %g beats%s",
          paw.time.format(info.start),
          paw.time.format(info.start + info.length),
          info.length,
          info.muted and ", muted" or ""
        ),
        info.kind == "midi" and plural(info.note_count, "note") or "audio   " .. tostring(info.file),
        "",
      }
      local drawn = preview.clip(c.id, width or 40, math.max(4, (height or 20) - #lines - 3))
      for _, line in ipairs(drawn) do
        lines[#lines + 1] = line
      end
      return lines
    end,
    -- Heard: an audio clip's file; a MIDI clip's first bars through its part.
    audition_key = "clips",
    audition = function(c: ClipLine): string
      local info = api.clip_get(c.id)
      if info.kind == "audio" then
        paw.audition.file(info.file)
        return info.name
      end
      local length = math.min(info.length, paw.time.bar(info.start) * 2)
      local notes: {AuditionModule.PhraseNote} = {}
      local all = api.clip_notes(c.id)
      for _, n in ipairs(all) do
        if n.start >= 0 and n.start < length then
          notes[#notes + 1] = {pitch = n.pitch, start = n.start, length = n.length, velocity = n.velocity}
        end
      end
      paw.audition.phrase(c.part, notes, {length = length, label = info.name, key = "clip" .. c.id})
      return string.format("%s · %g beats on %s", info.name, length, c.part_name)
    end,
  }
  S.clips = clips

  -- Devices ------------------------------------------------------------------------

  local typed: string -- what was typed in the device picker, remembered with the choice
  local wanted: string -- the kind of device the part most likely needs, listed first
  local devices: contracts.PickSource<DeviceInfo> = {
    desc = "Add a device or plugin to the part",
    title = "Add a device",
    -- Favourites first, then the ones used last; `@instrument`, `@clap`,
    -- `@fav` or `@<vendor>` typed filter (see `paw.fx.rank`).
    items = function(): {DeviceInfo}
      wanted = paw.fx.preferred(paw.cursor.part_id())
      return paw.fx.device_list(wanted)
    end,
    format = function(info: DeviceInfo): string return paw.fx.device_line(info) end,
    rank = function(info: DeviceInfo, query: string, line: string): number
      typed = query
      return paw.fx.rank(info, query, line, wanted)
    end,
    on_choose = function(info: DeviceInfo)
      local part = need_part()
      if not part then
        return
      end
      api.undo_label("add " .. info.name .. " to " .. part.name)
      paw.fx.add(part, info.kind, {query = typed})
      paw.notify("added " .. info.name .. " to " .. part.name)
    end,
    -- Heard on the part, with what it plays around the cursor: added as a
    -- trial, taken away again unless chosen. A plugin is made apart, so
    -- the selection rests on it longer first.
    audition = function(info: DeviceInfo): string | contracts.Hearing<DeviceInfo>
      local part = paw.cursor.part()
      if not part then
        return "no part to try it on"
      end
      local device = paw.audition.try(function(): types.Device return paw.fx.place(part, info.kind) end)
      local hearing: contracts.Hearing<DeviceInfo> = {
        label = info.name .. " · " .. paw.audition.through(part.id),
        loading = function(): boolean
          local ok, d = pcall(api.device_get, device.id) as (boolean, types.Device)
          return ok and d.status == "loading"
        end,
        keep = function()
          api.undo_label("add " .. info.name .. " to " .. part.name)
          paw.fx.added(device, info.kind, {query = typed})
          paw.notify("added " .. info.name .. " to " .. part.name)
        end,
      }
      return hearing
    end,
    audition_delay = function(info: DeviceInfo, ms: number): number
      return info.format ~= "builtin" and math.max(ms, 600) or ms
    end,
    actions = {
      ["<C-f>"] = {
        desc = "favourite",
        fn = function(info: DeviceInfo, query: string)
          if info then
            paw.fx.toggle_favourite(info.kind)
          end
          pick("devices", {query = query})
        end,
      },
      ["<C-t>"] = {
        desc = "instruments/effects",
        fn = function(_: DeviceInfo, query: string)
          -- Step the filter: none, instruments, effects.
          local q = query:gsub("%s*@instrument", ""):gsub("%s*@effect", "")
          local was = query:find("@instrument") and 1 or query:find("@effect") and 2 or 0
          local tag = ({[0] = " @instrument", [1] = " @effect", [2] = ""} as {integer: string})[was]
          pick("devices", {query = ((q .. tag):gsub("^%s+", ""))})
        end,
      },
    },
    preview = function(info: DeviceInfo): {string | contracts.PageLine}
      local lines: {string | contracts.PageLine} = {
        {text = info.name, style = "Title"},
        "",
        "kind     " .. info.kind,
        "format   " .. info.format .. (info.category and info.category ~= "" and ", " .. info.category or ""),
      }
      if info.favourite then
        lines[#lines + 1] = "a favourite (Ctrl-f)"
      end
      if info.vendor and info.vendor ~= "" then
        lines[#lines + 1] = "vendor   " .. info.vendor
      end
      local params = info.params or {}
      if #params > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = {text = plural(#params, "parameter"), style = "HelpSection"}
        for i, p in ipairs(params) do
          if i > 30 then
            break
          end
          lines[#lines + 1] = "  " .. p.name
        end
      end
      return lines
    end,
  }
  S.devices = devices

  local part_devices: contracts.PickSource<DeviceLine> = {
    desc = "Devices on the part: show one in the device panel",
    title = "Devices on the part",
    empty = "No devices on this part. `<leader>da` adds one.",
    items = function(): {DeviceLine}
      local part = paw.cursor.part()
      local out: {DeviceLine} = {}
      for i, device in ipairs(part and part:devices() or {}) do
        local d = device:get()
        out[#out + 1] = {id = d.id, index = i, name = d.name, kind = d.kind, bypass = d.bypass}
      end
      return out
    end,
    format = function(d: DeviceLine): string
      return string.format("%d. %s%s", d.index, d.name, d.bypass and "  (bypassed)" or "")
    end,
    on_choose = function(d: DeviceLine)
      local inspector = paw.ui.views:get("inspector") as DevicesView
      paw.ui.focus("inspector")
      inspector:show(d.id)
      api.ui_redraw()
    end,
    actions = {
      ["<C-e>"] = {
        fn = function(d: DeviceLine)
          if d then
            api.device_editor(d.id)
          end
        end,
        desc = "plugin window",
      },
    },
    preview = function(d: DeviceLine): {string | contracts.PageLine}
      local info = api.device_get(d.id)
      local lines: {string | contracts.PageLine} = {{text = info.name, style = "Title"}, "", "kind   " .. info.kind, ""}
      for i, p in ipairs(info.param_info) do
        if i > 40 then
          break
        end
        lines[#lines + 1] = string.format("%-18s %s", p.name, paw.frontend.format_value(p, info.params[p.key]))
      end
      return lines
    end,
  }
  S.part_devices = part_devices

  -- Marks and registers ------------------------------------------------------------

  local marks: contracts.PickSource<MarkLine> = {
    desc = "Go to a mark",
    title = "Marks",
    empty = "No marks. `ma` sets mark a at the cursor.",
    items = function(): {MarkLine}
      local out: {MarkLine} = {}
      for _, view in ipairs({"arrange", "pianoroll"}) do
        local list = keymap.marks(view)
        local names: {string} = {}
        for name in pairs(list) do
          names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
          local pos = list[name]
          local where: string
          if view == "arrange" then
            local ok, t = pcall(api.part_get, pos.part) as (boolean, types.Part)
            where = paw.time.format(pos.beat) .. "  " .. (ok and t.name or "(part gone)")
          else
            where = paw.music.name(math.floor(pos[1] as number)) .. "  beat " .. (pos[2] as number) + 1
          end
          out[#out + 1] = {name = name, view = view, where = where}
        end
      end
      return out
    end,
    format = function(m: MarkLine): string return string.format("%s  %-10s %s", m.name, m.view, m.where) end,
    on_choose = function(m: MarkLine)
      if paw.ui.focused ~= m.view then
        paw.ui.focus(m.view)
      end
      keymap.goto_mark(m.name)
    end,
  }
  S.marks = marks

  local registers: contracts.PickSource<RegisterLine> = {
    desc = "Paste a register, or play a macro",
    title = "Registers",
    empty = "Nothing yanked or recorded yet.",
    items = function(): {RegisterLine}
      local out: {RegisterLine} = {}
      for name, value in pairs(keymap.registers) do
        out[#out + 1] = {name = name, value = value as Register}
      end
      table.sort(out, function(a: RegisterLine, b: RegisterLine): boolean return a.name < b.name end)
      return out
    end,
    format = function(r: RegisterLine): string return string.format('"%s  %s', r.name, describe(r.value)) end,
    on_choose = function(r: RegisterLine)
      if r.value.kind == "keys" then
        return keymap.play(r.name)
      end
      keymap.normal('"' .. r.name .. "P")
    end,
  }
  S.registers = registers

  -- Messages -----------------------------------------------------------------------

  local messages: contracts.PickSource<Message> = {
    desc = "Earlier messages, newest first",
    title = "Messages",
    empty = "No messages yet.",
    items = function(): {Message}
      local out: {Message} = {}
      local list = paw.ui.messages as {Message}
      for i = #list, 1, -1 do
        out[#out + 1] = list[i]
      end
      return out
    end,
    format = function(m: Message): string return string.format("%-5s %s", m.level, m.text:match("^[^\n]*")) end,
    on_choose = function(m: Message) paw.ui.page("Message", {{text = m.text, style = levels[m.level]}}) end,
    preview = function(m: Message): {string | contracts.PageLine}
      return {{text = m.text, style = levels[m.level]}}
    end,
  }
  S.messages = messages

  -- Files --------------------------------------------------------------------------

  local files_walk: Walk
  local files: contracts.PickSource<FileLine> = {
    desc = "Open a project, or import audio or MIDI at the cursor",
    title = "Files",
    empty = "No project, audio or MIDI files under this directory.",
    -- The walk goes on in slices after the picker opens, so that keys stay
    -- quick in a large folder; the query line says when it stops at a limit.
    items = function(): {FileLine}
      files_walk = start_walk(".", opt.files_limit, opt.files_depth, opt.files_skip)
      return {}
    end,
    more = function(ms: number): {FileLine}, boolean, string
      local out, done = files_walk.step(ms)
      if not done then
        return out, false, "reading…"
      end
      local why = files_walk.stopped
      if why == "files_limit" then
        return out, true, string.format("stopped at %d entries (files_limit)", opt.files_limit)
      elseif why == "files_depth" then
        return out, true, string.format("stopped at depth %d (files_depth)", opt.files_depth)
      end
      return out, true, nil
    end,
    format = function(f: FileLine): string return f.path end,
    on_choose = function(f: FileLine)
      if f.kind == "project" then
        if not paw.project.guard("open") then
          return
        end
        paw.open(f.path)
        return paw.notify("opened " .. f.path)
      end
      if f.kind == "midi" then
        paw.commands.run("import", {f.path})
        return
      end
      local part = need_part()
      if not part then
        return
      end
      part:add_clip({start = paw.cursor.beat, file = f.path})
    end,
    audition_key = "files",
    audition = function(f: FileLine): string return pick.hear_file(f.path) end,
    preview = function(f: FileLine): {string | contracts.PageLine}
      if f.kind == "project" then
        return {{text = f.path, style = "Title"}, "", "A project.", "Enter opens it in place of this one."}
      end
      if f.kind == "midi" then
        return {
          {text = f.path, style = "Title"},
          "",
          "A MIDI file.",
          "Enter brings its parts in at " .. paw.time.format(paw.cursor.beat) .. "; `:open` opens it as a project.",
        }
      end
      local part = paw.cursor.part()
      return {
        {text = f.path, style = "Title"},
        "",
        "Audio.",
        "Enter adds it at " .. paw.time.format(paw.cursor.beat) .. (part and " on " .. part.name or ""),
      }
    end,
  }
  S.files = files

  -- Options ------------------------------------------------------------------------

  local option_picker: contracts.PickSource<options.Info> = {
    desc = "Set an option",
    title = "Options",
    items = function(): {options.Info} return options.list() end,
    format = function(o: options.Info): string return string.format("%-14s %s", o.name, tostring(opt[o.name])) end,
    on_choose = function(o: options.Info)
      local value = opt[o.name]
      if value is boolean then
        opt[o.name] = not value
        return paw.notify(o.name .. " = " .. tostring(not value))
      end
      local input: InputOptions = {prompt = o.name .. " = ", text = tostring(value)}
      paw.ui.input(
        input,
        function(text: string)
          if text == "" then
            return
          end
          local read, err = options.read(o.name, text)
          if read == nil then
            return paw.notify(err, "error")
          end
          opt[o.name] = read
          paw.notify(o.name .. " = " .. tostring(opt[o.name]))
        end
      )
    end,
    preview = function(o: options.Info): {string | contracts.PageLine}
      return {
        {text = o.name, style = "Title"},
        "",
        "now       " .. tostring(opt[o.name]),
        "default   " .. tostring(o.default),
        "",
        {text = type(o.default) == "boolean" and "Enter switches it" or "Enter asks for a new value", style = "Dim"},
      }
    end,
  }
  S.options = option_picker

  project(pick, S)
  return S
end

M.walk = walk

return setmetatable(M, {__call = function(_: M, pick: Pick): Sources return make(pick) end} as metatable<M>)
