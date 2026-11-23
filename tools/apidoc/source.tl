-- The files of the source tree as the readers of tools/apidoc.lua read them:
-- the text, or its lines, from the top of the checkout.
local record source
end

--- The text of a file, or nil when it is not there.
function source.read(path: string): string
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  return text
end

--- The lines of a file, or nil when it is not there.
function source.lines(path: string): {string}
  local text = source.read(path)
  if not text then
    return nil
  end
  local out: {string} = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    out[#out + 1] = line
  end
  return out
end

-- The lines of each file read once in a run, by its path.
local kept: {string: {string}} = {}

--- The lines of a file, read once in a run: a file that is not there has
--- no lines. A path that ends in `.lua` and is not there is read as the
--- `.tl` beside it: a runtime that tools/dev-runtime.sh makes loads the Lua
--- that Teal made, on the same lines, and the doc comments are in the `.tl`.
function source.kept(path: string): {string}
  kept[path] = kept[path] or source.lines(path) or source.lines((path:gsub("%.lua$", ".tl"))) or {}
  return kept[path]
end

--- The `---` lines over line `at` of `lines`, in order, without the dashes.
function source.doc_over(lines: {string}, at: integer): {string}
  local doc: {string} = {}
  local n = at - 1
  while n > 0 and lines[n] and lines[n]:match("^%s*%-%-%-") do
    table.insert(doc, 1, (lines[n]:gsub("^%s*%-%-%- ?", "")))
    n = n - 1
  end
  return doc
end

--- The file of module `name` in the runtime (`paw.harmony.read`) with the
--- first of `exts` that is there (`.tl`, `/init.tl`), or nil.
function source.module_file(name: string, exts: {string}): string
  local base = "runtime/lua/" .. name:gsub("%.", "/")
  for _, ext in ipairs(exts) do
    if source.read(base .. ext) then
      return base .. ext
    end
  end
end

return source
