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
local M = {
  -- The formats, by name.
  registry = {},
}

local function lower(list)
  local out = {}
  for i, e in ipairs(list or {}) do out[i] = (tostring(e):lower():gsub("^%.", "")) end
  return out
end

--- Register a format of files (see the top of paw/formats.lua). A format
--- of the same name is replaced. Returns the name.
function M.register(spec)
  assert(type(spec) == "table" and type(spec.name) == "string" and spec.name ~= "", "a format has a name")
  assert(spec.import or spec.export, "a format reads files (`import`), writes them (`export`), or both")
  local f = {}
  for k, v in pairs(spec) do f[k] = v end
  f.extensions = lower(spec.extensions)
  M.registry[spec.name] = f
  if paw.help then paw.help.dirty = true end
  return spec.name
end

--- Take a format away again.
function M.unregister(name)
  M.registry[name] = nil
  if paw.help then paw.help.dirty = true end
end

--- The format of a name, or nil.
function M.get(name) return M.registry[name] end

--- The formats, by name: `{ name, desc, extensions, project, import, export }` each.
function M.list()
  local out = {}
  for _, f in pairs(M.registry) do out[#out + 1] = f end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- The format that takes `path` for `side` ("import" or "export"): one
--- whose `detect` says yes, else one of the file's extension. Nil when
--- none does.
function M.for_path(path, side)
  if type(path) ~= "string" or path == "" then return nil end
  local ext = (path:match("%.([^./]+)$") or ""):lower()
  local by_ext
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
function M.extensions(side)
  local out, seen = {}, {}
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
function M.split_args(line)
  local path, args = tostring(line or ""), {}
  while true do
    local rest, key, value = path:match("^(.-)%s+([%w_]+)=(%S*)%s*$")
    if not rest then break end
    args[key] = value == "true" and true or value == "false" and false or value
    path = rest
  end
  return (path:gsub("^%s+", ""):gsub("%s+$", "")), args
end

--- Say what a side of a format did: its text, and its lost lines on a page.
local function say(f, result, default)
  if type(result) == "string" then
    paw.notify(result)
    return result
  end
  result = type(result) == "table" and result or {}
  local lost = result.lost
  if lost and #lost > 0 then
    paw.notify((result.said or default) .. "; see the list of what was not carried over", "warn")
    pcall(paw.ui.page, f.desc or f.name, lost)
  else
    paw.notify(result.said or default)
  end
  return result
end

local function run(f, side, path, opts)
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
function M.import(path, opts)
  local f = M.for_path(path, "import")
  if not f then
    paw.notify("no format reads " .. path .. ": `:help formats` lists them", "warn")
    return nil
  end
  return run(f, "import", path, opts or {})
end

--- Write the project with the format of a file. Says what it did.
function M.export(path, opts)
  local f = M.for_path(path, "export")
  if not f then
    paw.notify("no format writes " .. path .. ": `:help formats` lists them", "warn")
    return nil
  end
  return run(f, "export", path, opts or {})
end

--- The page of `:help formats`, in Markdown: what each format reads and
--- writes, and how to add one.
function M.help_text()
  local lines = { "# File formats", "",
    "paw opens, brings in and writes the files of other programs in these formats.",
    "The ending of the file selects the format.", "",
    "- `:import file` adds what the file holds to the project.",
    "- `:open file` and `:edit file` open the file in place of the project.",
    "- `:export file` writes the project to the file. `:write file` does too, for a format of whole projects.", "",
    "| Format | Files | Reads | Writes |", "| --- | --- | --- | --- |" }
  for _, f in ipairs(M.list()) do
    local ext = {}
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
