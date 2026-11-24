-- Options: `paw.opt.zoom = 4`. Any name can be set; the ones the runtime
-- reads are defined below. Changing one emits `option.changed`.
--
-- A defined option takes values of its default's type, and a number in its
-- range (`specs` below, or what `paw.option.define` was given): a value
-- that is not is refused with an error that says what it takes, and the
-- option keeps what it had.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local registry = require("paw.registry")

--- What an option holds: text, a number, true or false, or a list.
local type Value = string | number | boolean | {string | number}

--- What an option takes besides its default's type: `type` (a type or
--- a list of them), `min` and `max` for a number, `integer`, and
--- `values`, the only strings or booleans it takes.
local record Spec
  type: string | {string}
  min: number
  max: number
  integer: boolean
  values: {string | boolean}
end

--- What `paw.option.define` was given.
local record Definition
  default: Value
  spec: Spec
end

--- An option in `paw.option.list`.
local record Info
  name: string
  default: Value
  takes: string
end

--- The options that were set, as `paw.option.snapshot` gives them.
local record Snapshot
  values: {string: Value}
end

--- `paw.opt`: the options the runtime defines, by their types, and any
--- other by its name. tools/apidoc.lua makes the record from the options
--- that the runtime defines (`runtime/types/paw/opts.d.tl`).
local type Opt = require("paw.opts")

--- An option that an extension defines, by the type of its default:
--- `local lanes = paw.option.define("lanes", 4)`, then `lanes:get()` is an
--- integer and `lanes:set(8)` takes one.
local record Option<T>
  name: string
  get: function(self: Option<T>): T
  set: function(self: Option<T>, value: T)
end

--- The payload of `option.changed`: the name of the option, its value and
--- the value before. `value` is nil when an extension that defined the
--- option unloaded.
local record Changed
  name: string
  value: Value
  old: Value
end

local record M
  type Value = Value
  type Spec = Spec
  type Definition = Definition
  type Info = Info
  type Opt = Opt
  type Option<T> = Option<T>
  type Snapshot = Snapshot
  type Changed = Changed
  opt: Opt
  --- The event `option.changed`: an option got a different value.
  changed: events.Event<Changed>
  --- What `define` was given, by the name of the option, with the
  --- extension that defined it. A definition over another one keeps it:
  --- when the extension unloads, the definition below comes back, and the
  --- value stays. With none below, the option goes with its value.
  defined: registry.Registry<Definition>
  --- Checks of a value beyond its spec, by the name of the option: what
  --- the option takes, in words, when it does not take the value, else
  --- nil. A module above sets one: paw/timegrid.tl, for the grid settings.
  checks: {string: function(value: Value): string}
end

M.checks = {}

M.changed = events.event("option.changed")

local defaults: {string: Value} = {
  leader = " ", -- what `<leader>` means in key mappings: Space
  localleader = "\\", -- what `<localleader>` means: the leader of one view's own keys (the notation popovers)
  timeoutlen = 800, -- ms to wait for the rest of a key sequence
  hint_delay = 500, -- ms before the keys that can follow are listed; 0 for at once
  hints = true, -- list the keys that can follow a half-typed command
  -- "classic" keeps the keys each view had before they all kept to one rule
  -- (docs/reference/key-rule.md), for a while.
  keys = "default",
  keybar = true, -- show the keys worth knowing first on the bottom line
  ripple = false, -- deleting time closes the gap, pasting makes room
  -- Seconds between safety copies of unsaved work; 0 for none. Off when
  -- started with --clean, which is how tests and experiments run.
  autosave = api.env().clean and 0 or 60,
  reopen_last = false, -- start with the project that was open last, when none is named
  threads = 0, -- threads to process parts on; 0 for one per core
  files_limit = 20000, -- the files picker reads at most this many directory entries
  files_depth = 8, -- and goes this many folders deep
  -- Folders the files picker does not enter (it leaves out hidden ones and
  -- those a .gitignore at its root names too).
  files_skip = {"target", "node_modules", "result", "build", "dist", "__pycache__", "vendor"},
  device_sleep = true, -- devices at rest sleep through silence; the sound is the same
  -- "edit" lowers the costly settings of the built-in devices while paw
  -- plays live, such as the oversampling of a saturation. Renders, exports,
  -- stems, freezes and bounces always play at "full".
  quality = "full",
  -- The grid of the time views and of the note editors: a number of
  -- beats, or text such as "1/8t", "bar" or "500ms" (paw/timegrid.tl).
  grid = 1,
  zoom = 2, -- arrange columns per beat
  part_height = "auto", -- arrange rows per part; "auto" fits the parts to the screen, 1 to 3
  header_width = "auto", -- arrange columns for the part headers; "auto" by the screen's width
  -- The part column at the left of the part headers, as Neovim's
  -- 'number', 'relativenumber' and 'statuscolumn': each part's number,
  -- or how many `j` or `k` reach it, and the components shown (paw/partcolumn.tl).
  number = true,
  relativenumber = false,
  partcolumn = {"number", "signs", "fold"},
  -- The ruler's bar labels: how many `W` or `B` reach each bar, and the
  -- parts of each label shown (paw/ruler.tl).
  relativebar = false,
  barlabel = {"number"},
  -- The keys of the arrange view's insert mode, in the order the hints
  -- show them: what each inserts at the cursor (paw/insert.tl).
  insertkeys = {"m", "a", "r", "'", "f"},
  termcolors = "auto", -- "true" for 24-bit colour, "256", or "auto" to ask the environment
  ascii = false, -- draw with plain ASCII characters only
  braille = true, -- false draws curves with lines, whatever curve_glyphs says
  curve_glyphs = "sextant", -- curves in cells: "sextant" (a connected line), "braille" (dots) or "line"
  wave_scale = "linear", -- audio clips in cells: "linear" shows hits, "db" shows quiet sound too
  mouse = true, -- the terminal reports the pointer; false leaves it to the terminal's own selection
  graphics = true, -- views that paint show pixels where the terminal shows images; false keeps cells
  follow = true, -- scroll to keep the playhead in view
  jumpview = "left", -- where a jump that lands off screen puts its target: "left" (near the left edge) or "center"
  jumpmargin = 6, -- columns between the left edge and the target of a jump with jumpview "left"
  fps = 60, -- the most frames a second while something moves; frames come only when a cell changes
  check_stamps = false, -- draw the windows that the screen keeps (a view's `stamp`), and fail when they differ
  clip_length = 4, -- beats, for new MIDI clips
  -- Where play and record start from a stop: "cursor" (the cursor of the
  -- view with the keys, the playhead goes there) or "playhead" (the old way).
  play_from = "cursor",
  count_in = 0, -- bars the metronome counts before recording from a stop; 0 for none
  pre_roll = 0, -- bars a take punched in from a stop plays before the punch in
  pre_roll_seconds = 0, -- and seconds more, before those bars
  -- A MIDI take over a clip: "new" is a clip of its own on top, "merge"
  -- joins its notes into the clips under it (overdub).
  midi_record = "new",
  click_level = 0, -- dB, the metronome's level against its own
  click_accent = true, -- the first beat of a bar clicks higher
  click_output = 0, -- the first output channel of the pair the click plays on; 0 for with the song
  velocity = 100, -- for notes entered by hand
  send_level = -12, -- dB a new send starts at
  -- The selected part plays the MIDI keyboard while no part is armed, as
  -- if its input were monitored; false: only an armed or monitored part.
  midi_follows_selection = true,
  note_grid = 0.25, -- the grid of the note editors, as grid
  swing = 50, -- percent: each second line of a bar of the grid moves later, from 50 (none) to 75
  snap = true, -- a press of the pointer goes to a grid line, and what it drags moves by lines
  note_zoom = 8, -- piano roll columns per beat
  phrase_rest = 0.5, -- beats: a longer rest ends a phrase (`ip`, `(` `)` in the piano roll)
  message_time = 4000, -- ms a message stays on the command line
  -- A sound file whose decoded audio is larger than this many megabytes is
  -- played from the disk instead of being held in memory; 0 holds every
  -- file in memory. And how many gigabytes of decoded sound are kept in the
  -- cache between runs, so that long files are decoded once.
  media_stream = 64,
  media_cache = 16,
  ffmpeg = "ffmpeg", -- what renders to MP3, Ogg and Opus run: a name on the PATH, or a path
  -- How many steps the undo history keeps, and about how many megabytes of
  -- what they changed; past either its oldest steps are let go.
  undo_steps = 1000,
  undo_memory = 1024,
  -- Keep the undo tree after a save, in the state directory, so that a
  -- project opened again can undo past its last save; about how many
  -- megabytes for one project. Off when started with --clean.
  undofile = not api.env().clean,
  undofile_mb = 256,
  -- What paw keeps across restarts (paw/shada.tl): on or off, and how many
  -- lines each prompt's history holds.
  shada = true,
  history = 200,
}

-- What an option takes besides its default's type (M.Spec).
local specs: {string: Spec} = {
  timeoutlen = {min = 0, max = 10000},
  hint_delay = {min = 0, max = 10000},
  threads = {min = 0, max = 256, integer = true},
  grid = {type = {"number", "string"}, min = 1 / 128, max = 64},
  zoom = {min = 0.125, max = 64},
  part_height = {type = {"number", "string"}, min = 1, max = 12, integer = true, values = {"auto"}},
  header_width = {type = {"number", "string"}, min = 8, max = 60, integer = true, values = {"auto"}},
  termcolors = {type = {"string", "number"}},
  curve_glyphs = {values = {"sextant", "braille", "line"}},
  wave_scale = {values = {"linear", "db"}},
  quality = {values = {"full", "edit"}},
  jumpview = {values = {"left", "center"}},
  jumpmargin = {min = 0, max = 200, integer = true},
  fps = {min = 1, max = 240},
  clip_length = {min = 1 / 128, max = 100000},
  count_in = {min = 0, max = 16, integer = true},
  pre_roll = {min = 0, max = 64, integer = true},
  pre_roll_seconds = {min = 0, max = 60},
  files_limit = {min = 100, max = 10000000, integer = true},
  files_depth = {min = 1, max = 64, integer = true},
  click_level = {min = -60, max = 12},
  midi_record = {values = {"new", "merge"}},
  play_from = {values = {"cursor", "playhead"}},
  click_output = {min = 0, max = 63, integer = true},
  velocity = {min = 1, max = 127, integer = true},
  send_level = {min = -150, max = 24},
  note_grid = {type = {"number", "string"}, min = 1 / 128, max = 64},
  swing = {min = 50, max = 75},
  note_zoom = {min = 0.125, max = 64},
  phrase_rest = {min = 0, max = 64},
  message_time = {min = 0, max = 600000},
  media_stream = {min = 0},
  media_cache = {min = 0},
  autosave = {min = 0},
  undo_steps = {min = 10, max = 1000000, integer = true},
  undo_memory = {min = 16, max = 1048576},
  undofile_mb = {min = 1, max = 1048576},
  history = {min = 1, max = 100000, integer = true},
}

local function has<T>(list: {T}, value: T): boolean
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

local function show(value: Value): string
  return value is string and string.format("%q", value) or tostring(value)
end

local function types_of(name: string): {string}
  local spec: Spec = specs[name] or {}
  local t = spec.type
  if t is {string} then
    return t
  end
  return {t or type(defaults[name])}
end

--- What an option takes, in words: `a whole number from 1 to 12, or "auto"`.
local function takes(name: string): string
  local spec: Spec = specs[name] or {}
  local words: {string} = {}
  for _, t in ipairs(types_of(name)) do
    if t == "number" then
      local what = spec.integer and "a whole number" or "a number"
      if spec.min and spec.max then
        what = string.format("%s from %g to %g", what, spec.min, spec.max)
      elseif spec.min then
        what = string.format("%s from %g up", what, spec.min)
      end
      words[#words + 1] = what
    elseif t == "boolean" and not spec.values then
      words[#words + 1] = "true or false"
    elseif t == "string" and not spec.values then
      words[#words + 1] = "text"
    elseif t == "table" then
      words[#words + 1] = "a list"
    end
  end
  for _, v in ipairs(spec.values or {}) do
    words[#words + 1] = show(v)
  end
  return table.concat(words, ", or ")
end

--- Tells if option `name` accepts `value`: true, or nil and an error that
--- tells what it accepts. An option with no default accepts any value.
function M.check(name: string, value: Value): boolean, string
  if defaults[name] == nil or value == nil then
    return true
  end
  local spec: Spec = specs[name] or {}
  local ok = has(types_of(name), type(value))
  if ok and value is number then
    ok = value == value
      and value > -math.huge
      and value < math.huge
      and (not spec.min or value >= spec.min)
      and (not spec.max or value <= spec.max)
      and (not spec.integer or value % 1 == 0)
  elseif ok and spec.values and (value is string or value is boolean) then
    ok = has(spec.values, value as string | boolean)
  end
  local check = M.checks[name]
  local why = ok and check and check(value)
  if ok and not why then
    return true
  end
  return nil, string.format("%s takes %s, not %s", name, why or takes(name), show(value))
end

--- A list typed as text: `Surge, Vital` is { "Surge", "Vital" }, and a
--- number in it is a number.
local function list_of(text: Value): {string | number}
  local out: {string | number} = {}
  for part in tostring(text):gmatch("[^,]+") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then
      out[#out + 1] = tonumber(part) or part
    end
  end
  return out
end

--- An option's value as text: a list is its items with commas between.
function M.show(value: Value): string
  if not (value is {string | number}) then
    return tostring(value)
  end
  local parts: {string} = {}
  for i, v in ipairs(value) do
    parts[i] = tostring(v)
  end
  return table.concat(parts, ",")
end

--- The value typed text stands for in option `name` (`true`, `off`, a
--- number, the text, or a list for an option that takes one: `a,b`), or
--- nil and an error that says what it takes. A value that is not text is
--- checked as it is.
function M.read(name: string, text: Value): Value, string
  local value = text
  if text == "true" or text == "on" then
    value = true
  elseif text == "false" or text == "off" then
    value = false
  elseif text is string then
    value = tonumber(text) or text
  end
  -- `set ffmpeg=7` keeps the text, for an option that takes text.
  if not M.check(name, value) and M.check(name, tostring(text)) then
    value = tostring(text)
  end
  -- An option that takes a list reads text with commas, or nothing, or
  -- what it takes in no other form, as one.
  if
    not (text is {string | number})
    and has(types_of(name), "table")
    and (tostring(text):find(",", 1, true) or tostring(text) == "" or not M.check(name, value))
  then
    value = list_of(text)
  end
  local ok, err = M.check(name, value)
  if not ok then
    return nil, err
  end
  return value
end

--- Short names, as Vim's: `:set nu` is `:set number`.
local aliases: {string: string} = {nu = "number", rnu = "relativenumber", rbar = "relativebar"}

--- The full name of option `name`: itself, or what its short name stands for.
function M.full(name: string): string
  return aliases[name] or name
end

local values: {string: Value} = {}

local opt: Opt = setmetatable(
  {} as Opt,
  {
    __index = function(_: Opt, name: string): Value
      name = aliases[name] or name
      local v = values[name]
      if v == nil then
        return defaults[name]
      end
      return v
    end,
    __newindex = function(self: Opt, name: string, value: Value)
      name = aliases[name] or name
      local ok, err = M.check(name, value)
      if not ok then
        error(err, 2)
      end
      local old = self[name]
      values[name] = value
      if old ~= value then
        events.emit(M.changed, {name = name, value = value, old = old})
        api.ui_redraw()
      end
    end,
  }
)

M.defined = registry.new(
  "options",
  "options",
  {
    changed = function(name: string, d: Definition)
      if d then
        defaults[name], specs[name] = d.default, d.spec
        return
      end
      local old = opt[name]
      defaults[name], specs[name], values[name] = nil, nil, nil
      if old ~= nil then
        events.emit(M.changed, {name = name, old = old})
        api.ui_redraw()
      end
    end,
  }
)

--- Give an option a default, for extensions that add their own options. The
--- option then accepts values of the type of the default. `spec` adds more rules:
---   paw.option.define("lanes", 4, { min = 1, max = 16, integer = true })
---   paw.option.define("look", "plain", { values = { "plain", "fancy" } })
---   paw.option.define("size", "auto", { type = { "number", "string" }, min = 1, values = { "auto" } })
--- It gives a handle with the type of the default: `get()` and `set(value)`.
function M.define<T>(name: string, default: T, spec?: Spec): Option<T>
  M.defined:put(name, {default = default as Value, spec = spec or specs[name]})
  return {
    name = name,
    get = function(_: Option<T>): T return opt[name] as T end,
    set = function(_: Option<T>, value: T) opt[name] = value as Value end,
  }
end

--- Each option given a default by `paw.option.define`, by name: what it
--- was given, `{ default, spec }`, the same table until defined again.
function M.definitions(): {string: Definition}
  return M.defined:entries()
end

--- What option `name` takes besides its default's type (`min`, `max`,
--- `integer`, `type`, `values`), or nil.
function M.spec(name: string): Spec
  return specs[name]
end

--- Every option that has a default, by name: { name, default }.
function M.list(): {Info}
  local out: {Info} = {}
  for name, default in pairs(defaults) do
    out[#out + 1] = {name = name, default = default, takes = takes(name)}
  end
  table.sort(out, function(a: Info, b: Info): boolean return a.name < b.name end)
  return out
end

--- A copy of a value: a list is copied, so that a later change to the
--- list does not reach the copy.
local function copy(value: Value): Value
  if value is {string | number} then
    local out: {string | number} = {}
    for i, v in ipairs(value) do
      out[i] = v
    end
    return out
  end
  return value
end

--- True if two values are the same, a list item by item.
local function same(a: Value, b: Value): boolean
  if a is {string | number} and b is {string | number} then
    if #a ~= #b then
      return false
    end
    for i = 1, #a do
      if a[i] ~= b[i] then
        return false
      end
    end
    return true
  end
  return a == b
end

--- The value of each option that was set, to give back later with
--- `paw.option.restore`. An option that was not set keeps its default.
function M.snapshot(): Snapshot
  local out: {string: Value} = {}
  for name, value in pairs(values) do
    out[name] = copy(value)
  end
  return {values = out}
end

--- Give each option the value it had in `snapshot`, and an option set
--- after it its default again. Each option that changes emits
--- `option.changed`. Gives the names of the options that changed, sorted.
function M.restore(snapshot: Snapshot): {string}
  local names: {string} = {}
  local seen: {string: boolean} = {}
  for _, list in ipairs({values, snapshot.values}) do
    for name in pairs(list) do
      if not seen[name] then
        seen[name] = true
        names[#names + 1] = name
      end
    end
  end
  table.sort(names)
  local changed: {string} = {}
  for _, name in ipairs(names) do
    local want = snapshot.values[name]
    if not same(values[name], want) then
      local old = opt[name]
      values[name] = copy(want)
      changed[#changed + 1] = name
      if not same(old, opt[name]) then
        events.emit(M.changed, {name = name, value = opt[name], old = old})
        api.ui_redraw()
      end
    end
  end
  return changed
end

M.opt = opt
return M
