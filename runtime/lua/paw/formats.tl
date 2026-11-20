-- `paw.formats`: the files of other programs that paw opens, brings in and
-- writes, each a format that one call registers, from the core, an
-- extension or a configuration:
--
--   paw.formats.register({
--     name = "rpp", desc = "REAPER projects", extensions = { "rpp" },
--     project = true,                          -- a whole project: `:e` and `:w` use it too
--     detect = function(path) return ... end,  -- optional: else by the extension
--     import = function(path, opts) ... end,   -- optional: opts.merge, opts.args
--     export = function(path, opts) ... end,   -- optional: opts.args
--   })
--
-- `:import song.rpp` brings the file in (`opts.merge` is true: its tracks
-- are added to the project), `:open song.rpp` and `:edit song.rpp` open it
-- in place of the project (`opts.merge` false), `:export song.rpp` writes
-- the project to it, and so does `:write song.rpp` for a format that is a
-- `project`. `opts.args` holds the words of the command after the path
-- (`instrument=synth` is `args.instrument`). A side can be left out: a
-- format that is read only, or written only.
--
-- `import` and `export` return what to say: text, or `{ said, lost }`,
-- where `lost` is a list of lines of what did not carry over, shown on a
-- page. An error is said as the error. `paw.formats.list()` gives the
-- formats, `:help formats` lists them.
--
-- An extension in Teal gives its format the type `paw.formats.Format`, so
-- the checker checks its fields.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.

local type Untyped = require("paw.untyped")

-- The `paw` global, for its parts still written in Lua. This module is a
-- part of the global's types, so it takes the global as `Untyped`.
local paw = (_G as {string:Untyped}).paw

local record M
  --- A word of a command line after the path: `key=value` words by their
  --- key (`true` and `false` as booleans), the others by their place.
  type Arg = string | boolean | number

  --- What `import` and `export` of a format take: `merge` (import only)
  --- is true for `:import`, false for `:open` and `:edit`; `args` holds
  --- the words of the command after the path.
  record Options
    merge: boolean
    args: {string | integer: Arg}
  end

  --- What `import` and `export` return when they say more than text: what
  --- they did, and the lines of what did not carry over (shown on a page).
  record Said
    said: string
    lost: {string}
  end

  --- What `import` and `export` return: what to say (text, or a `Said`),
  --- false to say nothing, or nil to say what paw says by default.
  type Result = string | Said | boolean

  --- The side of a format: it reads files, or writes them.
  enum Side
    "import"
    "export"
  end

  --- A format of files, as `register` takes it.
  record Format
    --- The name of the format: `rpp`.
    name: string
    --- What the files are, for the list of `:help formats`.
    desc: string
    --- The endings of its files: `{ "rpp" }`.
    extensions: {string}
    --- True when a file holds a whole project: then `:w song.rpp` writes one too.
    project: boolean
    --- Optional: true when the file is of this format, whatever its ending.
    detect: function(path: string): boolean
    --- Optional: read the file.
    import: function(path: string, opts: Options): Result
    --- Optional: write the project to the file.
    export: function(path: string, opts: Options): Result
  end

  --- The formats, by name.
  registry: {string:Format}
end

local type Format = M.Format
local type Options = M.Options

M.registry = {}

local function lower(list: {string}): {string}
  local out: {string} = {}
  for i, e in ipairs(list or {}) do out[i] = (tostring(e):lower():gsub("^%.", "")) end
  return out
end

-- `paw.help` (written in Lua) makes its page of the formats again when
-- they change.
local record Help
  dirty: boolean
end

local function help_changed()
  if paw.help then (paw.help as Help).dirty = true end
end

--- Register a format of files (see the top of paw/formats.tl). A format
--- of the same name is replaced. Returns the name.
function M.register(spec: Format): string
  assert(type(spec) == "table" and type(spec.name) == "string" and spec.name ~= "", "a format has a name")
  assert(spec.import or spec.export, "a format reads files (`import`), writes them (`export`), or both")
  local f: Format = {
    name = spec.name, desc = spec.desc, extensions = lower(spec.extensions), project = spec.project,
    detect = spec.detect, import = spec.import, export = spec.export,
  }
  M.registry[spec.name] = f
  help_changed()
  return spec.name
end

--- Take a format away again.
function M.unregister(name: string)
  M.registry[name] = nil
  help_changed()
end

--- The format of a name, or nil.
function M.get(name: string): Format return M.registry[name] end

--- The formats, by name: `{ name, desc, extensions, project, import, export }` each.
function M.list(): {Format}
  local out: {Format} = {}
  for _, f in pairs(M.registry) do out[#out + 1] = f end
  table.sort(out, function(a: Format, b: Format): boolean return a.name < b.name end)
  return out
end

--- The format that takes `path` for `side` ("import" or "export"): one
--- whose `detect` says yes, else one of the file's extension. Nil when
--- none does.
function M.for_path(path: string, side: M.Side): Format
  if type(path) ~= "string" or path == "" then return nil end
  local ext = (path:match("%.([^./]+)$") or ""):lower()
  local by_ext: Format
  for _, f in ipairs(M.list()) do
    if f[side] then
      if f.detect then
        local ok, yes = pcall(f.detect, path)
        if ok and yes then return f end
      end
      if not by_ext then
        for _, e in ipairs(f.extensions) do
          if e == ext then by_ext = f end
        end
      end
    end
  end
  return by_ext
end

--- The extensions of the files that a side takes, for lists and completion.
function M.extensions(side: M.Side): {string}
  local out: {string} = {}
  local seen: {string:boolean} = {}
  for _, f in ipairs(M.list()) do
    if f[side] then
      for _, e in ipairs(f.extensions) do
        if not seen[e] then seen[e], out[#out + 1] = true, e end
      end
    end
  end
  table.sort(out)
  return out
end

--- The path at the start of a command line and the `key=value` words at
--- its end: `song.rpp instrument=synth` is `"song.rpp", { instrument = "synth" }`.
function M.split_args(line: string): string, {string:M.Arg}
  local path = tostring(line or "")
  local args: {string:M.Arg} = {}
  while true do
    local rest, key, value = path:match("^(.-)%s+([%w_]+)=(%S*)%s*$")
    if not rest then break end
    args[key] = value == "true" and true or value == "false" and false or value
    path = rest
  end
  return (path:gsub("^%s+", ""):gsub("%s+$", "")), args
end

--- Say what a side of a format did: its text, and its lost lines on a page.
local function say(f: Format, result: M.Result, default: string): M.Result
  if result is string then
    paw.notify(result)
    return result
  end
  local said: M.Said = result is M.Said and result or {}
  local lost = said.lost
  if lost and #lost > 0 then
    paw.notify((said.said or default) .. "; see the list of what was not carried over", "warn")
    pcall(paw.ui.page, f.desc or f.name, lost)
  else
    paw.notify(said.said or default)
  end
  return said
end

local function run(f: Format, side: M.Side, path: string, opts: Options): M.Result
  opts.args = opts.args or {}
  local ok, result = pcall(f[side], path, opts)
  if not ok then
    paw.notify((side == "import" and "could not read " or "could not write ") .. path .. ": "
      .. tostring(result):gsub("^[^:]*:%d+: ", ""):gsub("\n.*", ""), "error")
    return nil
  end
  if result == false then return nil end
  return say(f, result, (side == "import" and "read " or "wrote ") .. path)
end

--- Bring a file in with its format: `opts.merge` adds to the project,
--- else it opens in place of the project. Says what it did; returns what
--- the format returned, or nil when it could not.
function M.import(path: string, opts?: Options): M.Result
  local f = M.for_path(path, "import")
  if not f then
    paw.notify("no format reads " .. path .. ": `:help formats` lists them", "warn")
    return nil
  end
  return run(f, "import", path, opts or {})
end

--- Write the project with the format of a file. Says what it did.
function M.export(path: string, opts?: Options): M.Result
  local f = M.for_path(path, "export")
  if not f then
    paw.notify("no format writes " .. path .. ": `:help formats` lists them", "warn")
    return nil
  end
  return run(f, "export", path, opts or {})
end

--- The page of `:help formats`, in Markdown: what each format reads and
--- writes, and how to add one.
function M.help_text(): string
  local lines = { "# File formats", "",
    "paw opens, brings in and writes the files of other programs in these formats.",
    "The ending of the file selects the format.", "",
    "- `:import file` adds what the file holds to the project.",
    "- `:open file` and `:edit file` open the file in place of the project.",
    "- `:export file` writes the project to the file. `:write file` does too, for a format of whole projects.", "",
    "| Format | Files | Reads | Writes |", "| --- | --- | --- | --- |" }
  for _, f in ipairs(M.list()) do
    local ext: {string} = {}
    for i, e in ipairs(f.extensions) do ext[i] = "`." .. e .. "`" end
    lines[#lines + 1] = string.format("| %s (%s) | %s | %s | %s |", f.desc or f.name, f.name, table.concat(ext, " "),
      f.import and "yes" or "no", f.export and (f.project and "yes, also with `:write`" or "yes") or "no")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "An extension or your configuration adds a format with `paw.formats.register`. See"
  lines[#lines + 1] = "[Write an importer or exporter](../how-to/write-an-importer-or-exporter.md)."
  return table.concat(lines, "\n") .. "\n"
end

return M
