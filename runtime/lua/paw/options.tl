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

local record M
  type Value = Value
  type Spec = Spec
  type Definition = Definition
  type Info = Info
  type Opt = Opt
  type Option<T> = Option<T>
  opt: Opt
end

--- The payload of `option.changed`.
local record Changed
  name: string
  value: Value
  old: Value
end

-- What this module reads of `paw`, which paw/init.lua makes. A module of the
-- runtime in Teal does not see the global `paw`: runtime/types/paw.d.tl
-- declares it from these modules.
local record Paw
  emit: function(string, Changed)
end
local paw = (_G as {string:Paw}).paw

local defaults: {string:Value} = {
  leader = " ",            -- what `<leader>` means in key mappings: Space
  localleader = "\\",      -- what `<localleader>` means: the leader of one view's own keys (the notation popovers)
  timeoutlen = 800,        -- ms to wait for the rest of a key sequence
  hint_delay = 500,        -- ms before the keys that can follow are listed; 0 for at once
  hints = true,            -- list the keys that can follow a half-typed command
  -- "classic" keeps the keys each view had before they all kept to one rule
  -- (docs/reference/key-rule.md), for a while.
  keys = "default",
  keybar = true,           -- show the keys worth knowing first on the bottom line
  ripple = false,          -- deleting time closes the gap, pasting makes room
  -- Seconds between safety copies of unsaved work; 0 for none. Off when
  -- started with --clean, which is how tests and experiments run.
  autosave = api.env().clean and 0 or 60,
  reopen_last = false,     -- start with the project that was open last, when none is named
  threads = 0,            -- threads to process tracks on; 0 for one per core
  files_limit = 20000,     -- the files picker reads at most this many directory entries
  files_depth = 8,         -- and goes this many folders deep
  -- Folders the files picker does not enter (it leaves out hidden ones and
  -- those a .gitignore at its root names too).
  files_skip = { "target", "node_modules", "result", "build", "dist", "__pycache__", "vendor" },
  device_sleep = true,     -- devices at rest sleep through silence; the sound is the same
  octave = 4,              -- where note entry in insert mode starts: `a` is C of this octave
  grid = 1,                -- arrange cursor step and snap, in beats
  zoom = 2,                -- arrange columns per beat
  track_height = "auto",   -- arrange rows per track; "auto" fits the tracks to the screen, 3 to 4
  header_width = "auto",   -- arrange columns for the track headers; "auto" by the screen's width
  -- The track column at the left of the track headers, as Neovim's
  -- 'number', 'relativenumber' and 'statuscolumn': each track's number,
  -- or how many `j` or `k` reach it, and the parts shown (paw/trackcolumn.tl).
  number = true,
  relativenumber = false,
  trackcolumn = { "number", "signs", "fold" },
  -- The ruler's bar labels: how many `W` or `B` reach each bar, and the
  -- parts of each label shown (paw/ruler.tl).
  relativebar = false,
  barlabel = { "number" },
  -- The keys of the arrange view's insert mode, in the order the hints
  -- show them: what each inserts at the cursor (paw/insert.tl).
  insertkeys = { "m", "a", "r", "'", "f" },
  termcolors = "auto",     -- "true" for 24-bit colour, "256", or "auto" to ask the environment
  ascii = false,           -- draw with plain ASCII characters only
  braille = true,          -- false draws curves with lines, whatever curve_glyphs says
  curve_glyphs = "sextant", -- curves in cells: "sextant" (a connected line), "braille" (dots) or "line"
  wave_scale = "linear",   -- audio clips in cells: "linear" shows hits, "db" shows quiet sound too
  mouse = true,            -- the terminal reports the pointer; false leaves it to the terminal's own selection
  graphics = true,         -- views that paint show pixels where the terminal shows images; false keeps cells
  follow = true,           -- scroll to keep the playhead in view
  fps = 60,                -- the most frames a second while something moves; frames come only when a cell changes
  clip_length = 4,         -- beats, for new MIDI clips
  count_in = 0,            -- bars the metronome counts before recording from a stop; 0 for none
  pre_roll = 0,            -- bars a take punched in from a stop plays before the punch in
  pre_roll_seconds = 0,    -- and seconds more, before those bars
  -- A MIDI take over a clip: "new" is a clip of its own on top, "merge"
  -- joins its notes into the clips under it (overdub).
  midi_record = "new",
  click_level = 0,         -- dB, the metronome's level against its own
  click_accent = true,     -- the first beat of a bar clicks higher
  click_output = 0,        -- the first output channel of the pair the click plays on; 0 for with the song
  velocity = 100,          -- for notes entered by hand
  send_level = -12,        -- dB a new send starts at
  -- The selected track plays the MIDI keyboard while no track is armed, as
  -- if its input were monitored; false: only an armed or monitored track.
  midi_follows_selection = true,
  note_grid = 0.25,        -- piano roll step and snap, in beats
  note_snap = true,        -- the pointer's notes land on the piano roll's grid
  note_zoom = 8,           -- piano roll columns per beat
  phrase_rest = 0.5,       -- beats: a longer rest ends a phrase (`ip`, `(` `)` in the piano roll)
  message_time = 4000,     -- ms a message stays on the command line
  -- A sound file whose decoded audio is larger than this many megabytes is
  -- played from the disk instead of being held in memory; 0 holds every
  -- file in memory. And how many gigabytes of decoded sound are kept in the
  -- cache between runs, so that long files are decoded once.
  media_stream = 64,
  media_cache = 16,
  ffmpeg = "ffmpeg",       -- what renders to MP3, Ogg and Opus run: a name on the PATH, or a path
  -- How many steps the undo history keeps, and about how many megabytes of
  -- what they changed; past either its oldest steps are let go.
  undo_steps = 1000,
  undo_memory = 1024,
}

-- What an option takes besides its default's type (M.Spec).
local specs: {string:Spec} = {
  timeoutlen = { min = 0, max = 10000 },
  hint_delay = { min = 0, max = 10000 },
  threads = { min = 0, max = 256, integer = true },
  octave = { min = -1, max = 9, integer = true },
  grid = { min = 1 / 128, max = 64 },
  zoom = { min = 0.125, max = 64 },
  track_height = { type = { "number", "string" }, min = 1, max = 12, integer = true, values = { "auto" } },
  header_width = { type = { "number", "string" }, min = 8, max = 60, integer = true, values = { "auto" } },
  termcolors = { type = { "string", "number" } },
  curve_glyphs = { values = { "sextant", "braille", "line" } },
  wave_scale = { values = { "linear", "db" } },
  fps = { min = 1, max = 240 },
  clip_length = { min = 1 / 128, max = 100000 },
  count_in = { min = 0, max = 16, integer = true },
  pre_roll = { min = 0, max = 64, integer = true },
  pre_roll_seconds = { min = 0, max = 60 },
  files_limit = { min = 100, max = 10000000, integer = true },
  files_depth = { min = 1, max = 64, integer = true },
  click_level = { min = -60, max = 12 },
  midi_record = { values = { "new", "merge" } },
  click_output = { min = 0, max = 63, integer = true },
  velocity = { min = 1, max = 127, integer = true },
  send_level = { min = -150, max = 24 },
  note_grid = { min = 1 / 128, max = 64 },
  note_zoom = { min = 0.125, max = 64 },
  phrase_rest = { min = 0, max = 64 },
  message_time = { min = 0, max = 600000 },
  media_stream = { min = 0 },
  media_cache = { min = 0 },
  autosave = { min = 0 },
  undo_steps = { min = 10, max = 1000000, integer = true },
  undo_memory = { min = 16, max = 1048576 },
}

local function has<T>(list: {T}, value: T): boolean
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

local function show(value: Value): string
  return value is string and string.format("%q", value) or tostring(value)
end

local function types_of(name: string): {string}
  local spec: Spec = specs[name] or {}
  local t = spec.type
  if t is {string} then return t end
  return { t or type(defaults[name]) }
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
  for _, v in ipairs(spec.values or {}) do words[#words + 1] = show(v) end
  return table.concat(words, ", or ")
end

--- Tells if option `name` accepts `value`: true, or nil and an error that
--- tells what it accepts. An option with no default accepts any value.
function M.check(name: string, value: Value): boolean, string
  if defaults[name] == nil or value == nil then return true end
  local spec: Spec = specs[name] or {}
  local ok = has(types_of(name), type(value))
  if ok and value is number then
    ok = value == value and value > -math.huge and value < math.huge
      and (not spec.min or value >= spec.min) and (not spec.max or value <= spec.max)
      and (not spec.integer or value % 1 == 0)
  elseif ok and spec.values and (value is string or value is boolean) then
    ok = has(spec.values, value as string | boolean)
  end
  if ok then return true end
  return nil, string.format("%s takes %s, not %s", name, takes(name), show(value))
end

--- A list typed as text: `Surge, Vital` is { "Surge", "Vital" }, and a
--- number in it is a number.
local function list_of(text: Value): {string | number}
  local out: {string | number} = {}
  for part in tostring(text):gmatch("[^,]+") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then out[#out + 1] = tonumber(part) or part end
  end
  return out
end

--- An option's value as text: a list is its items with commas between.
function M.show(value: Value): string
  if not value is {string | number} then return tostring(value) end
  local parts: {string} = {}
  for i, v in ipairs(value) do parts[i] = tostring(v) end
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
  if not M.check(name, value) and M.check(name, tostring(text)) then value = tostring(text) end
  -- An option that takes a list reads text with commas, or nothing, or
  -- what it takes in no other form, as one.
  if not text is {string | number} and has(types_of(name), "table")
    and (tostring(text):find(",", 1, true) or tostring(text) == "" or not M.check(name, value)) then
    value = list_of(text)
  end
  local ok, err = M.check(name, value)
  if not ok then return nil, err end
  return value
end

--- Short names, as Vim's: `:set nu` is `:set number`.
local aliases: {string:string} = { nu = "number", rnu = "relativenumber", rbar = "relativebar" }

--- The full name of option `name`: itself, or what its short name stands for.
function M.full(name: string): string
  return aliases[name] or name
end

local values: {string:Value} = {}
-- What `M.define` was given, by name.
local definitions: {string:Definition} = {}

local opt: Opt = setmetatable({} as Opt, {
  __index = function(_: Opt, name: string): Value
    name = aliases[name] or name
    local v = values[name]
    if v == nil then return defaults[name] end
    return v
  end,
  __newindex = function(self: Opt, name: string, value: Value)
    name = aliases[name] or name
    local ok, err = M.check(name, value)
    if not ok then error(err, 2) end
    local old = self[name]
    values[name] = value
    if old ~= value then
      paw.emit("option.changed", { name = name, value = value, old = old })
      api.ui_redraw()
    end
  end,
})

--- Give an option a default, for extensions that add their own options. The
--- option then accepts values of the type of the default. `spec` adds more rules:
---   paw.option.define("lanes", 4, { min = 1, max = 16, integer = true })
---   paw.option.define("look", "plain", { values = { "plain", "fancy" } })
---   paw.option.define("size", "auto", { type = { "number", "string" }, min = 1, values = { "auto" } })
--- It gives a handle with the type of the default: `get()` and `set(value)`.
function M.define<T>(name: string, default: T, spec?: Spec): Option<T>
  defaults[name] = default as Value
  specs[name] = spec or specs[name]
  definitions[name] = { default = default as Value, spec = specs[name] }
  return {
    name = name,
    get = function(_: Option<T>): T return opt[name] as T end,
    set = function(_: Option<T>, value: T) opt[name] = value as Value end,
  }
end

--- Each option given a default by `paw.option.define`, by name: what it
--- was given, `{ default, spec }`, the same table until defined again.
function M.definitions(): {string:Definition}
  local out: {string:Definition} = {}
  for name, d in pairs(definitions) do out[name] = d end
  return out
end

--- Remove the definition of an option and its value (the extension that
--- defined it unloaded). `paw.opt[name]` is nil again. With `was`, the
--- value that `paw.option.definitions` gave before, that definition
--- returns, and the value stays.
function M.undefine(name: string, was?: Definition)
  if was then
    defaults[name], specs[name], definitions[name] = was.default, was.spec, was
    return
  end
  local old = opt[name]
  defaults[name], specs[name], definitions[name], values[name] = nil, nil, nil, nil
  if old ~= nil then
    paw.emit("option.changed", { name = name, old = old })
    api.ui_redraw()
  end
end

--- What option `name` takes besides its default's type (`min`, `max`,
--- `integer`, `type`, `values`), or nil.
function M.spec(name: string): Spec
  return specs[name]
end

--- Every option that has a default, by name: { name, default }.
function M.list(): {Info}
  local out: {Info} = {}
  for name, default in pairs(defaults) do out[#out + 1] = { name = name, default = default, takes = takes(name) } end
  table.sort(out, function(a: Info, b: Info): boolean return a.name < b.name end)
  return out
end

M.opt = opt
return M
