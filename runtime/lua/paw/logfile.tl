-- The log of paw in the runtime: `:log`, `:log!` and `:log dump`, the
-- option `loglevel`, and the part of the start header that only the
-- runtime knows. The kernel writes the file and keeps the flight recorder
-- (crates/paw-core/src/logging, ADR 0043).
--
--   options.opt.loglevel = "info,plugin=debug"   -- the levels of the file
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local command = require("paw.command")
local events = require("paw.events")
local options = require("paw.options")
local type contracts = require("paw.contracts")
local type TextbufModule = require("paw.textbuf")

-- The global `paw` (runtime/types/paw.d.tl): no module of the global
-- requires this one, so it sees the global's types.
local layout = paw.layout
local textbuf = paw.textbuf

--- An extension that paw/ext.lua loaded, as far as this module reads it.
local record Loaded
  name: string
end

--- paw/ext.lua (Lua), as far as this module calls it.
local record Ext
  list: function(): {Loaded}
end
local ext = (require as function(string): Ext)("paw.ext")

local record M
  header: function()
  open: function(which: string)
end

--- A line of the log in its text buffer.
local record LogLine is contracts.TextItem
  text: string
end

--- The lines of the file at `path`, after `into`. Nothing when it cannot
--- be read.
local function read_lines(path: string, into: {LogLine})
  local file = path and io.open(path, "r")
  if not file then
    return
  end
  for line in file:lines() do
    into[#into + 1] = {id = #into + 1, text = line}
  end
  file:close()
end

--- The file that `which` ("current" or "previous") names, or nil and why
--- not.
local function path_of(which: string): string, string
  local files = api.log_files()
  if not files.current then
    return nil, "this run writes no log file: a script writes its warnings to the standard error"
  end
  if which == "previous" then
    local file = io.open(files.previous, "r")
    if not file then
      return nil, "no log of the run before: this is the first run that wrote one"
    end
    file:close()
    return files.previous
  end
  return files.current
end

textbuf.kind(
  "log",
  {
    pattern = "^paw://log/(%a+)$",
    readonly = "the log cannot be changed here: paw writes it",
    gutter = false,
    static = true,
    read = function(ctx?: contracts.TextContext): {LogLine}, string
      local which = ctx.args[1] as string
      local path, why = path_of(which)
      if not path then
        return nil, why
      end
      local items: {LogLine} = {}
      read_lines(path, items)
      -- This run's log ends with what other code printed so far: the next
      -- start adds it to the file of this run.
      if which == "current" then
        local stderr: {LogLine} = {}
        read_lines(api.log_files().stderr, stderr)
        if #stderr > 0 then
          items[#items + 1] = {
            id = #items + 1, text = "---- stderr.log so far: what plugins, libraries and other programs printed ----"
          }
          for _, line in ipairs(stderr) do
            items[#items + 1] = {id = #items + 1, text = line.text}
          end
        end
      end
      return items
    end,
    format = function(item: LogLine): {string} return {item.text} end,
    parse = function(): {string: string}, string return {} end,
    title = function(ctx?: contracts.TextContext): string
      return ctx.args[1] == "previous" and "Log of the run before" or "Log of this run"
    end,
    hint = ":log! the run before · :log dump writes the flight recorder · :q closes",
  }
)

--- Show the log of this run ("current") or of the run before
--- ("previous") in the window in front, with the cursor on its last line.
function M.open(which: string)
  local _, why = path_of(which)
  if why then
    return paw.notify(why, "warn")
  end
  local buf = layout.buf_create("textbuf", "paw://log/" .. which)
  textbuf.reload(buf as TextbufModule.TextBuffer)
  layout.show_in(layout.current(), "textbuf", buf.id)
  local _, _, text, cursor = textbuf.here()
  if text then
    cursor.row = text:count()
  end
  api.ui_redraw()
end

command.define(
  "log",
  function(ctx: contracts.CommandContext): contracts.CommandResult
    local word = ctx.args[1]
    if word == nil then
      M.open("current")
    elseif word == "dump" then
      local count = api.log_dump()
      if not count then
        paw.notify("this run writes no log file: a script writes its warnings to the standard error", "warn")
      else
        paw.notify(string.format("the flight recorder wrote %d events to the log", count))
      end
    else
      paw.notify(
        "`:log` opens the log, `:log!` the log of the run before, `:log dump` writes the flight recorder", "warn"
      )
    end
  end,
  {
    desc = "Open the log of this run; `:log dump` writes the flight recorder to it",
    complete = function(): {string} return {"dump"} end,
  }
)

command.define(
  "log!", function(): contracts.CommandResult M.open("previous") end, {desc = "Open the log of the run before"}
)

-- `paw.opt.loglevel` takes what the kernel can read, and sets it.
options.checks.loglevel = function(value: options.Value): string
  return api.log_level_check(tostring(value)) and "a level, or levels per target such as \"info,plugin=debug\"" or nil
end

events.on(
  options.changed,
  function(e: options.Changed)
    if e.name ~= "loglevel" or e.value == nil then
      return
    end
    local kept = api.log_level(tostring(e.value))
    if kept then
      paw.notify(
        "PAW_LOG sets the levels of the log for this run (" .. kept .. "): loglevel applies at the next start", "warn"
      )
    end
  end
)

--- The part of the start header that the runtime knows: the sound, the
--- extensions, the plugins and the options that differ from their
--- default. The kernel writes the version and the terminal.
function M.header()
  local engine = api.engine_get()
  api.log(
    string.format(
      "sound: %s, device %s, %d Hz, block %d",
      tostring(engine.backend),
      engine.device ~= "" and engine.device or "none",
      engine.sample_rate or 0,
      engine.buffer_size or 0
    )
  )
  local names: {string} = {}
  for _, entry in ipairs(ext.list()) do
    names[#names + 1] = entry.name
  end
  api.log("extensions: " .. (#names > 0 and table.concat(names, ", ") or "none"))
  local plugins: {string: integer} = {}
  for _, kind in ipairs(api.device_types()) do
    if kind.format ~= "builtin" then
      plugins[kind.format] = (plugins[kind.format] or 0) + 1
    end
  end
  local counts: {string} = {}
  for format, count in pairs(plugins) do
    counts[#counts + 1] = string.format("%d %s", count, format)
  end
  table.sort(counts)
  api.log("devices besides the built-in ones: " .. (#counts > 0 and table.concat(counts, ", ") or "none"))
  local changed: {string} = {}
  for _, info in ipairs(options.list()) do
    local value = options.opt[info.name] as options.Value
    if options.show(value) ~= options.show(info.default) then
      changed[#changed + 1] = info.name .. "=" .. options.show(value)
    end
  end
  api.log("options that differ from their default: " .. (#changed > 0 and table.concat(changed, ", ") or "none"))
end

return M
