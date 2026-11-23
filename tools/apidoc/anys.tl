-- The `any` of the Teal declarations that tools/apidoc.lua writes, and their
-- allow-list, runtime/types/any-allowed.txt: each name with the count of
-- `any` (and `Untyped`) that it may have, and the reason. The count only
-- goes down (docs/explanation/about-teal.md).
local record anys
  --- The allow-list's file.
  PATH: string

  --- The `any` that the writers of a run wrote, by the name of what has
  --- them (`paw.api.part_get`, `paw.Untyped`).
  record Counts
    by_name: {string: integer}
  end

  --- An entry of the allow-list.
  record Allowed
    count: integer
    why: string
  end
end

anys.PATH = "runtime/types/any-allowed.txt"

--- How many times `text` says `any` or `Untyped`.
function anys.words(text: string): integer
  local n = 0
  for _ in text:gmatch("%f[%w_]any%f[^%w_]") do
    n = n + 1
  end
  for _ in text:gmatch("%f[%w_]Untyped%f[^%w_]") do
    n = n + 1
  end
  return n
end

--- A count that starts with `first` (the records of the kernel's data).
function anys.new(first: {string: integer}): anys.Counts
  local by_name: {string: integer} = {}
  for name, n in pairs(first) do
    by_name[name] = n
  end
  return {by_name = by_name}
end

--- Count the `any` of a line of a declaration under `name`, and give the line.
function anys.count(counts: anys.Counts, name: string, text: string): string
  local n = anys.words(text)
  if n > 0 then
    counts.by_name[name] = (counts.by_name[name] or 0) + n
  end
  return text
end

-- A line of the allow-list: an entry (`name`, `count`, `why`), or a
-- comment or an empty line, which has no `name`.
local record Line
  text: string
  name: string
  count: integer
  why: string
end

local function lines_of(text: string): {Line}
  local out: {Line} = {}
  for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
    local name, n, why = line:match("^(%S+)%s+(%d+)%s+(.*)$")
    if name and not name:match("^#") then
      out[#out + 1] = {text = line, name = name, count = math.tointeger(tonumber(n)), why = why}
    else
      out[#out + 1] = {text = line}
    end
  end
  return out
end

--- The allow-list's entries by name.
function anys.allowed(text: string): {string: anys.Allowed}
  local out: {string: anys.Allowed} = {}
  for _, line in ipairs(lines_of(text)) do
    if line.name then
      out[line.name] = {count = line.count, why = line.why}
    end
  end
  return out
end

--- The `any` that the allow-list `text` does not allow: a list of lines.
function anys.problems(counts: anys.Counts, text: string): {string}
  local allowed = anys.allowed(text)
  local out: {string} = {}
  for name, n in pairs(counts.by_name) do
    local a = allowed[name]
    if not a then
      out[#out + 1] = "new any: " .. name .. " (" .. n .. "): give it a type in its doc comment"
    elseif n > a.count then
      out[#out + 1] = "more any: " .. name .. " (" .. n .. ", allowed " .. a.count .. ")"
    end
  end
  table.sort(out)
  return out
end

--- The allow-list `text` with each count lowered to what the declarations
--- have. Nothing is added or raised here: only by hand, with the reason. So
--- the count only goes down.
function anys.lowered(counts: anys.Counts, text: string): string
  local out: {string} = {}
  for _, line in ipairs(lines_of(text)) do
    if line.name then
      local now = math.min(line.count, counts.by_name[line.name] or 0)
      if now > 0 then
        out[#out + 1] = line.name .. " " .. now .. " " .. line.why
      end
    else
      out[#out + 1] = line.text
    end
  end
  while out[#out] == "" do
    out[#out] = nil
  end
  return table.concat(out, "\n") .. "\n"
end

return anys
