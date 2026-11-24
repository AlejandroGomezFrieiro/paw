-- What paw keeps of your editing across restarts, as Neovim's ShaDa does.
--
-- `shada.json` in the state directory holds what is yours: the history of
-- each prompt, the last search, and the registers `a` to `z` and `0`. The
-- state directory of a project (`paw.loading.project_dir`) holds a
-- `shada.json` of its own, with the marks, the jump list, the places of
-- the edits and the last cursor. Nothing goes in the project folder.
--
-- paw reads them at the start and when a project opens, and writes them
-- when it quits and when a project closes. A file that another paw wrote
-- meanwhile is merged by time, so no entry is lost. `paw.opt.shada = false`,
-- `--clean` and a script keep and read nothing.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local type registry = require("paw.registry")
local kernel = require("paw.events.kernel")
local util = require("paw.util")
local options = require("paw.options")
local cursor = require("paw.cursor")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
local type SeatsModule = require("paw.seats")

local type Data = util.Data

--- One line of a history in the file.
local record Row
  t: string
  time: number
end

--- A register in the file.
local record Kept
  time: number
  value: Data
end

--- Where the cursor was in a project.
local record Place
  part: integer
  beat: number
  lane: integer
  view: string
end

--- The file of the user's state.
local record UserFile
  version: integer
  search: string
  histories: {string: {Row}}
  registers: {string: Kept}
end

--- What belongs to the user in the keymap.
local type UserState = KeymapModule.UserState

--- The file of a project's state: what belongs to it in the keymap (the
--- marks and the places, by view), and where the cursor was.
local record ProjectFile is KeymapModule.ProjectPlaces
  version: integer
  cursor: Place
end

-- What this module reads of the modules in Lua (their functions are in
-- paw/views/cmdline.lua).
local record Cmdline
  histories: function(): {string: {string}}
  set_history: function(name: string, lines: {string})
end
local record Ui
  focused: string
  views: registry.Registry<{string: boolean}>
  focus: function(name: string)
end
local record Paw is partial.Paw
  keymap: KeymapModule
  seats: SeatsModule
  ui: Ui
end
local paw = (_G as {string: Paw}).paw

local record M
end

local env = api.env()

--- The size above which a register is not kept.
local MAX_REGISTER = 1024 * 1024

local user_file = env.state_dir .. "/shada.json"
local enabled = not env.clean and not env.scripted

-- The times of what was read, so that a write can tell what is new.
local history_times: {string: {number}} = {}
local record Stamp
  time: number
  text: string
end
local register_stamp: {string: Stamp} = {}

--- Keep the files in `file` (and the project files where they always are),
--- and keep for all start options, for tests. `use()` sets all back.
function M.use(file?: string)
  if file then
    user_file, enabled = file, true
  else
    user_file, enabled = env.state_dir .. "/shada.json", not env.clean and not env.scripted
  end
  -- The times of what was read from the file before are of that file.
  history_times, register_stamp = {}, {}
end

local function active(): boolean
  return enabled and options.opt.shada ~= false
end

-- The project whose state is in memory, and where its cursor was last.
local current: string
local last: Place

--- A file as the table that it holds, which the caller checks.
local function read_json(path: string): any
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local text = handle:read("*a")
  handle:close()
  local ok, data = pcall(api.json_decode, text)
  return ok and data or nil
end

local function write_json<T>(path: string, data: T)
  pcall(api.fs_mkdir, path:match("^(.*)/[^/]*$") or ".")
  local handle = io.open(path .. ".tmp", "wb")
  if not handle then
    return
  end
  handle:write(api.json_encode(data, true))
  handle:close()
  os.rename(path .. ".tmp", path)
end

local function read_user_file(): UserFile
  local data = read_json(user_file) as UserFile
  if type(data) ~= "table" then
    return {histories = {}, registers = {}}
  end
  data.histories = type(data.histories) == "table" and data.histories or {}
  data.registers = type(data.registers) == "table" and data.registers or {}
  return data
end

local function project_file_of(path: string): string
  return require("paw.loading").project_dir(path) .. "/shada.json"
end

local function read_project_file(path: string): ProjectFile
  if not path or path == "" then
    return {}
  end
  local data = read_json(project_file_of(path)) as ProjectFile
  return type(data) == "table" and data or {}
end

local function limit(): integer
  return math.floor(tonumber(options.opt.history) or 200)
end

--- A value that a file can hold: text, numbers, booleans and tables of
--- them, not too deep.
local function plain(value: Data, depth: integer): boolean
  if value is {Data: Data} then
    if depth > 20 then
      return false
    end
    for k, v in pairs(value) do
      if not (k is string or k is number) or not plain(v, depth + 1) then
        return false
      end
    end
    return true
  end
  return value is string or value is number or value is boolean
end

local function in_local(fn: function())
  paw.seats.within(0, fn)
end

local function keymap(): KeymapModule
  return (require as function(string): KeymapModule)("paw.keymap")
end

local function cmdline(): Cmdline
  return (require as function(string): Cmdline)("paw.views.cmdline")
end

-- What is yours -----------------------------------------------------------------

local record Entry
  text: string
  time: number
  seq: integer
end

--- The lines of a history as a file holds them.
local function history_entries(list: {Row}): {Entry}
  local out: {Entry} = {}
  for _, row in ipairs(list or {}) do
    if type(row) == "table" and type(row.t) == "string" then
      out[#out + 1] = {text = row.t, time = tonumber(row.time) or 0, seq = 0}
    end
  end
  return out
end

--- Entries in time order, the same text once (its latest), at most `max`.
local function merged(entries: {Entry}, max: integer): {Entry}
  for i, e in ipairs(entries) do
    e.seq = i
  end
  table.sort(
    entries,
    function(a: Entry, b: Entry): boolean
      if a.time ~= b.time then
        return a.time < b.time
      end
      return a.seq < b.seq
    end
  )
  local seen: {string: boolean} = {}
  local out: {Entry} = {}
  for i = #entries, 1, -1 do
    local e = entries[i]
    if not seen[e.text] and #out < max then
      seen[e.text] = true
      table.insert(out, 1, e)
    end
  end
  return out
end

--- Merge the histories in memory with those in `disk`, and give the lot as
--- the file holds them. Memory takes the result too.
local function merge_histories(disk: {string: {Row}}): {string: {Row}}
  local lines = cmdline()
  local now = os.time()
  local out: {string: {Row}} = {}
  local names: {string: boolean} = {}
  for name in pairs(disk) do
    names[name] = true
  end
  for name in pairs(lines.histories()) do
    names[name] = true
  end
  for name in pairs(names) do
    local entries = history_entries(disk[name])
    local mine = lines.histories()[name] or {}
    local times = history_times[name] or {}
    for i, text in ipairs(mine) do
      entries[#entries + 1] = {text = text, time = times[i] or now, seq = 0}
    end
    local kept = merged(entries, limit())
    local rows: {Row} = {}
    local texts: {string} = {}
    local stamps: {number} = {}
    for i, e in ipairs(kept) do
      rows[i] = {t = e.text, time = e.time}
      texts[i], stamps[i] = e.text, e.time
    end
    if #rows > 0 then
      out[name] = rows
      lines.set_history(name, texts)
      history_times[name] = stamps
    end
  end
  return out
end

local function register_name(name: string): boolean
  return name:match("^[a-z0]$") ~= nil
end

local function merge_registers(mine: {string: Data}, disk: {string: Kept}): {string: Kept}
  local out: {string: Kept} = {}
  for name, item in pairs(disk) do
    if register_name(name) and type(item) == "table" and item.value ~= nil then
      out[name] = item
    end
  end
  local now = os.time()
  for name, value in pairs(mine) do
    if register_name(name) and value is {Data: Data} and plain(value, 0) then
      local text = api.json_encode(value)
      if #text <= MAX_REGISTER then
        local stamp = register_stamp[name]
        local time = stamp and stamp.text == text and stamp.time or now
        local theirs = out[name]
        if not (theirs and theirs.time > time) then
          out[name] = {time = time, value = value}
          register_stamp[name] = {time = time, text = text}
        end
      end
    end
  end
  return out
end

local function read_user()
  local disk = read_user_file()
  in_local(
    function()
      local data: UserState = {search = type(disk.search) == "string" and disk.search or nil, registers = {}}
      for name, item in pairs(disk.registers) do
        if register_name(name) and type(item) == "table" and item.value ~= nil then
          data.registers[name] = item.value as KeymapModule.Register
          register_stamp[name] = {time = tonumber(item.time) or 0, text = api.json_encode(item.value)}
        end
      end
      for name, list in pairs(disk.histories) do
        local kept = merged(history_entries(list), limit())
        local texts: {string} = {}
        local times: {number} = {}
        for i, e in ipairs(kept) do
          texts[i], times[i] = e.text, e.time
        end
        cmdline().set_history(name, texts)
        history_times[name] = times
      end
      keymap().shada_set_user(data)
    end
  )
end

local function write_user()
  local disk = read_user_file()
  in_local(
    function()
      local mine = keymap().shada_user()
      local out: UserFile = {version = 1}
      out.search = mine.search or disk.search
      out.histories = merge_histories(disk.histories)
      out.registers = merge_registers(mine.registers as {string: Data}, disk.registers)
      write_json(user_file, out)
    end
  )
end

-- What is a project's -----------------------------------------------------------

local function write_project(path: string)
  if not path or path == "" then
    return
  end
  in_local(
    function()
      local out = keymap().shada_project() as ProjectFile
      out.version = 1
      out.cursor = last
      write_json(project_file_of(path), out)
    end
  )
end

local function restore_cursor(place: Place)
  if type(place) ~= "table" or type(place.part) ~= "number" then
    return
  end
  pcall(cursor.set_part, math.floor(place.part), place.lane)
  if type(place.beat) == "number" then
    cursor.set_beat(place.beat)
  end
  if type(place.view) == "string" and paw.ui.views:get(place.view) and paw.ui.focused ~= place.view then
    pcall(paw.ui.focus, place.view)
  end
end

local function read_project(path: string)
  -- A project with no file has nothing kept, and starts with no marks.
  local data = read_project_file(path)
  in_local(function() keymap().shada_set_project(data); restore_cursor(data.cursor) end)
end

-- Entry points --------------------------------------------------------------------

--- Read what is kept: yours, and the current project's.
function M.read()
  if not active() then
    return
  end
  read_user()
  read_project(current)
end

--- Write what is kept: yours, and the current project's.
function M.write()
  if not active() then
    return
  end
  write_user()
  write_project(current)
end

events.on(
  cursor.changed,
  function(place: cursor.Place)
    if place.part then
      last = {part = place.part, beat = place.beat, lane = place.lane, view = paw.ui.focused}
    end
  end
)

events.on(
  kernel.project_loaded,
  function(p: kernel.Loaded)
    if not active() then
      current = p.path
      return
    end
    -- The project that closes writes first, and the user's file with it.
    if current then
      write_user()
      write_project(current)
    end
    current, last = p.path, nil
    read_project(current)
  end
)

events.on(
  events.exit,
  function()
    if active() then
      local part = cursor.part_id()
      if part then
        last = {part = part, beat = cursor.beat, lane = nil, view = paw.ui.focused}
      end
      M.write()
    end
  end
)

-- At the start: yours. The project that is open already is read when the
-- kernel says that it loaded.
if active() then
  read_user()
end

return M
